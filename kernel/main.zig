const std = @import("std");
const drivers = @import("drivers");
const exception = @import("exception.zig");
const sched = @import("sched.zig");
const shell = @import("shell.zig");
const initrd = @import("fs/initrd.zig");
const heap = @import("lib/heap.zig");
const dtb = @import("lib/dtb.zig");
const thread = @import("thread.zig");
const uart = drivers.uart;
const mailbox = drivers.mailbox;

const PageAllocator = heap.PageAllocator(.{ .verbose_log = false });
const DynamicAllocator = heap.DynamicAllocator(.{ .verbose_log = false });

pub const std_options: std.Options = .{
    .log_level = .info,
    .logFn = uart.miniUARTLogFn,
};

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    std.log.err("!KERNEL PANIC!", .{});
    std.log.err("{s}", .{msg});

    if (error_return_trace) |trace| {
        for (trace.instruction_addresses, 0..) |address, level| {
            if (address == 0) {
                break;
            }
            std.log.err("#{}: 0x{X}", .{ level, address });
        }
    }

    while (true) {
        asm volatile ("nop");
    }
}

// Singleton instance
var allocator: std.mem.Allocator = undefined;
pub fn getSingletonAllocator() std.mem.Allocator {
    return allocator;
}

// Main function for the kernel
export fn main(dtb_address: usize) void {
    drivers.init();

    const board_revision = mailbox.getBoardRevision() catch {
        @panic("Cannot obtain board revision from mailbox.");
    };
    const arm_memory = mailbox.getArmMemory() catch {
        @panic("Cannot obtain ARM memory information from mailbox.");
    };
    const mem: []allowzero u8 = @as([*]allowzero u8, @ptrFromInt(arm_memory.@"0"))[0..arm_memory.@"1"];

    const buffer_len = mem.len >> 7;
    const buffer_addr = std.mem.alignForward(usize, @intFromPtr(&_flash_img_end), 1 << heap.log2_page_size);
    const buffer: []u8 = @as([*]u8, @ptrFromInt(buffer_addr))[0..buffer_len];
    var fba = std.heap.FixedBufferAllocator.init(buffer);
    const startup_allocator = fba.allocator();

    const dtb_size = dtb.init(startup_allocator, dtb_address);
    dtb.fdtTraverse(initrd.initRamfsCallback);
    dtb.deinit(startup_allocator);

    const initrd_start_ptr = initrd.getInitrdStartPtr();
    const initrd_end_ptr = initrd.getInitrdEndPtr();

    std.log.info("Board revision: 0x{X}", .{board_revision});
    std.log.info("ARM Memory Base: 0x{X}", .{arm_memory.@"0"});
    std.log.info("ARM Memory Size: 0x{X}", .{arm_memory.@"1"});
    std.log.info("Initrd Start: 0x{X}", .{initrd_start_ptr});
    std.log.info("Initrd End: 0x{X}", .{initrd_end_ptr});
    std.log.info("DTB Address: 0x{X}", .{dtb_address});
    std.log.info("DTB Size: 0x{X}", .{dtb_size});

    fba = std.heap.FixedBufferAllocator.init(buffer);
    var fa = PageAllocator.init(startup_allocator, mem) catch {
        @panic("Cannot init page allocator!");
    };

    fa.memory_reserve(0x0000, 0x1000); // spin tables
    fa.memory_reserve(@intFromPtr(&_flash_img_start), @intFromPtr(&_flash_img_end));
    fa.memory_reserve(initrd_start_ptr, initrd_end_ptr);
    fa.memory_reserve(dtb_address, dtb_address + dtb_size);

    var da = DynamicAllocator.init(&fa);
    allocator = da.allocator();

    initrd.init(allocator);
    defer initrd.deinit();

    thread.create(allocator, shell.simpleShell, true);
    sched.idle(&allocator);
}

extern const _flash_img_start: u32;
extern const _flash_img_end: u32;

comptime {
    @export(&exception.fromEl2ToEl1, .{ .name = "fromEl2ToEl1" });
    @export(&exception.coreTimerEnable, .{ .name = "coreTimerEnable" });

    // Avoid using x0 as it stores the address of dtb
    asm (
        \\ .section .text.boot
        \\ .global _start
        \\ _start:
        \\      bl fromEl2ToEl1
        \\      bl coreTimerEnable
        \\      ldr x1, =_stack_top
        \\      mov sp, x1
        \\      ldr x1, =_bss_start
        \\      ldr x2, =_bss_end
        \\      mov x3, #0
        \\ 1:
        \\      cmp x1, x2
        \\      b.ge 2f
        \\      str x3, [x1], #8
        \\      b 1b
        \\ 2:
        \\      b main
    );
}

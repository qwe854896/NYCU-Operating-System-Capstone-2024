const std = @import("std");
const drivers = @import("drivers");
const exception = @import("exception.zig");
const sched = @import("sched.zig");
const fs = @import("fs.zig");
const heap = @import("lib/heap.zig");
const dtb = @import("lib/dtb.zig");
const thread = @import("thread.zig");
const mm = @import("mm.zig");
const uart = drivers.uart;
const mailbox = drivers.mailbox;

const PageAllocator = heap.PageAllocator(.{ .verbose_log = false });
const DynamicAllocator = heap.DynamicAllocator(.{ .verbose_log = false });
const Vfs = fs.Vfs;
const TmpFs = fs.TmpFs;
const InitramFs = fs.InitramFs;
const UartVNode = fs.UartVNode;
const FramebufferVNode = fs.FramebufferVNode;

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

var page_allocator: std.mem.Allocator = undefined;
pub fn getSingletonPageAllocator() std.mem.Allocator {
    return page_allocator;
}

var vfs: Vfs = undefined;
pub fn getSingletonVfs() *Vfs {
    return &vfs;
}

var initrd: fs.initrd.Initrd = undefined;
pub fn getSingletonInitrd() *fs.initrd.Initrd {
    return &initrd;
}

// Main function for the kernel
export fn main(dtb_address: usize) void {
    drivers.init();

    const kernel_identity_offset = 0xffff000000000000;

    const board_revision = mailbox.getBoardRevision() catch {
        @panic("Cannot obtain board revision from mailbox.");
    };
    const arm_memory = mailbox.getArmMemory() catch {
        @panic("Cannot obtain ARM memory information from mailbox.");
    };
    const arm_memory_address: usize = arm_memory.@"0";
    const mem: []allowzero u8 = @as([*]allowzero u8, @ptrFromInt(arm_memory_address + kernel_identity_offset))[0..arm_memory.@"1"];

    const buffer_len = mem.len >> 7;
    const buffer_addr = std.mem.alignForward(usize, @intFromPtr(&_flash_img_end), 1 << heap.log2_page_size);
    const buffer: []u8 = @as([*]u8, @ptrFromInt(buffer_addr))[0..buffer_len];
    var fba = std.heap.FixedBufferAllocator.init(buffer);
    const startup_allocator = fba.allocator();

    const dtb_size = dtb.totalSize(@ptrFromInt(dtb_address)) catch 0;
    var dtb_root = dtb.init(startup_allocator, dtb_address);
    dtb_root.fdtTraverse(fs.initrd.initRamfsCallback);
    dtb_root.deinit(startup_allocator);

    const initrd_start_ptr = fs.initrd.getInitrdStartPtr();
    const initrd_end_ptr = fs.initrd.getInitrdEndPtr();

    std.log.info("Board revision: 0x{X}", .{board_revision});
    std.log.info("ARM Memory Base: 0x{X}", .{arm_memory.@"0"});
    std.log.info("ARM Memory Size: 0x{X}", .{arm_memory.@"1"});
    std.log.info("Initrd Start: 0x{X}", .{initrd_start_ptr});
    std.log.info("Initrd End: 0x{X}", .{initrd_end_ptr});
    std.log.info("DTB Address: 0x{X}", .{dtb_address});
    std.log.info("DTB Size: 0x{X}", .{dtb_size});
    std.log.info("img: start: 0x{X} end: 0x{X}", .{ @intFromPtr(&_flash_img_start), @intFromPtr(&_flash_img_end) });

    fba = std.heap.FixedBufferAllocator.init(buffer);
    var fa = PageAllocator.init(startup_allocator, mem) catch {
        @panic("Cannot init page allocator!");
    };

    fa.memory_reserve(0x0000, 0x1000); // spin tables
    fa.memory_reserve(0x1000, 0x4000); // Initial PGD, PUD, and PMD
    fa.memory_reserve(@intFromPtr(&_flash_img_start) - kernel_identity_offset, @intFromPtr(&_flash_img_end) - kernel_identity_offset);
    fa.memory_reserve(initrd_start_ptr, initrd_end_ptr);
    fa.memory_reserve(dtb_address, dtb_address + dtb_size);

    var da = DynamicAllocator.init(&fa);
    page_allocator = fa.allocator();
    allocator = da.allocator();

    mm.map.initPageTableCache(page_allocator);
    mm.map.initPageFrameRefCounts(allocator);

    const invalid_pgd = page_allocator.create(mm.map.PageTable) catch {
        @panic("Cannot create kernel page table!");
    };
    invalid_pgd.* = @splat(.{});

    asm volatile (
        \\ msr ttbr0_el1, %[arg0]
        :
        : [arg0] "r" (@intFromPtr(invalid_pgd)),
    );

    initrd = fs.initrd.Initrd.init(allocator);
    defer initrd.deinit();

    vfs = Vfs.init(allocator);
    defer vfs.deinit();

    vfs.registerFileSystem(TmpFs.fileSystem()) catch {
        @panic("Cannot register tmpfs!");
    };
    vfs.registerFileSystem(InitramFs.fileSystem()) catch {
        @panic("Cannot reigster initramfs!");
    };
    vfs.registerDeviceFile(0, UartVNode.fileNodeOps()) catch {
        @panic("Cannot register uart device node");
    };
    vfs.registerDeviceFile(1, FramebufferVNode.fileNodeOps()) catch {
        @panic("Cannot register uart device node");
    };

    if (!vfs.initRootfs(allocator, TmpFs.fileSystem().name)) {
        unreachable;
    }
    defer vfs.deinitRootfs();

    vfs.mkdir("/initramfs") catch {
        @panic("Cannot create initramfs directory!");
    };
    const initramfs_mount = vfs.mount(allocator, "/initramfs", InitramFs.fileSystem().name) catch {
        @panic("Cannot mount initramfs!");
    };
    defer Vfs.releaseMount(initramfs_mount);

    vfs.mkdir("/dev") catch {
        @panic("Cannot create /dev directory!");
    };
    vfs.mknod("/dev/uart", 0, 0) catch {
        @panic("Cannot create /dev/uart!");
    };
    vfs.mknod("/dev/framebuffer", 0, 1) catch {
        @panic("Cannot create /dev/framebuffer!");
    };

    sched.idle(&allocator);
}

extern const _flash_img_start: u32;
extern const _flash_img_end: u32;

comptime {
    @export(&exception.fromEl2ToEl1, .{ .name = "fromEl2ToEl1" });
    @export(&exception.coreTimerEnable, .{ .name = "coreTimerEnable" });
    @export(&mm.tcrInit, .{ .name = "tcrInit" });
    @export(&mm.mairInit, .{ .name = "mairInit" });
    @export(&mm.enableMMU, .{ .name = "enableMMU" });

    // Avoid using x0 as it stores the address of dtb
    asm (
        \\ .section .text.boot
        \\ .global _start
        \\ _start:
        \\      bl fromEl2ToEl1
        \\      bl coreTimerEnable
        \\      bl tcrInit
        \\      bl mairInit
        \\      bl enableMMU
        \\      ldr x2, =boot_rest
        \\      br x2
        \\ boot_rest:
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

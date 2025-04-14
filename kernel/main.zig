const std = @import("std");
const gpio = @import("gpio.zig");
const uart = @import("uart.zig");
const mailbox = @import("mailbox.zig");
const reboot = @import("reboot.zig");
const cpio = @import("cpio.zig");
const dtb = @import("dtb/main.zig");
const interrupt = @import("interrupt.zig");
const page_allocator = @import("heap/page_allocator.zig");
const dynamic_allocator = @import("heap/dynamic_allocator.zig");

const startup_allocator = page_allocator.startup_allocator;
const mini_uart_reader = uart.mini_uart_reader;
const mini_uart_writer = uart.mini_uart_writer;

const PageAllocator = page_allocator.PageAllocator(.{ .verbose_log = true });
const DynamicAllocator = dynamic_allocator.DynamicAllocator(.{ .verbose_log = true });

pub const std_options: std.Options = .{
    .log_level = .info,
    .logFn = uart.miniUARTLogFn,
};

const Command = enum {
    None,
    Hello,
    Help,
    Reboot,
    ListFiles,
    GetFileContent,
    DemoSimpleAlloc,
    ExecFileContent,
    DemoPageAlloc,
    DemoPageFree,
};

fn parseCommand(command: []const u8) Command {
    if (std.mem.eql(u8, command, "hello")) {
        return Command.Hello;
    } else if (std.mem.eql(u8, command, "help")) {
        return Command.Help;
    } else if (std.mem.eql(u8, command, "reboot")) {
        return Command.Reboot;
    } else if (std.mem.eql(u8, command, "ls")) {
        return Command.ListFiles;
    } else if (std.mem.eql(u8, command, "cat")) {
        return Command.GetFileContent;
    } else if (std.mem.eql(u8, command, "demo")) {
        return Command.DemoSimpleAlloc;
    } else if (std.mem.eql(u8, command, "exec")) {
        return Command.ExecFileContent;
    } else if (std.mem.eql(u8, command, "alloc")) {
        return Command.DemoPageAlloc;
    } else if (std.mem.eql(u8, command, "free")) {
        return Command.DemoPageFree;
    } else {
        return Command.None;
    }
}

fn execFile(content: []const u8) void {
    const program_stack = startup_allocator.alloc(u8, 0x1000) catch {
        @panic("Out of Memory! No buffer for executing a file.");
    };
    const program_start_address: usize = @intFromPtr(content.ptr);
    const program_stack_address: usize = @intFromPtr(program_stack.ptr);
    _ = mini_uart_writer.print("User program at 0x{X} will be run with the stack address 0x{X}\n", .{ program_start_address, program_stack_address }) catch {};
    asm volatile (
        \\ mov x1, 0x0
        \\ msr spsr_el1, x1
        \\ mov x1, %[arg0]
        \\ msr elr_el1, x1
        \\ mov x1, %[arg1]
        \\ msr sp_el0, x1
        \\ eret
        :
        : [arg0] "r" (program_start_address),
          [arg1] "r" (program_stack_address),
        : "x1"
    );
}

fn simpleShell(allocator: std.mem.Allocator) void {
    var buffer = startup_allocator.alloc(u8, 256) catch {
        @panic("Out of Memory! No buffer for simple shell.");
    };

    var alloc_map = std.AutoHashMap(usize, []u8).init(startup_allocator);
    defer alloc_map.deinit();

    while (true) {
        _ = mini_uart_writer.write("# ") catch {};

        var recvlen = mini_uart_reader.read(buffer) catch 0;
        const command = parseCommand(buffer[0..recvlen]);

        switch (command) {
            Command.Hello => {
                _ = mini_uart_writer.write("Hello, World!\n") catch {};
            },
            Command.Help => {
                _ = mini_uart_writer.write("Commands:\n") catch {};
                _ = mini_uart_writer.write("  hello - Print 'Hello, World!'\n") catch {};
                _ = mini_uart_writer.write("  help - Print this help message\n") catch {};
                _ = mini_uart_writer.write("  reboot - Reboot the system\n") catch {};
                _ = mini_uart_writer.write("  ls - List files in the initramfs\n") catch {};
                _ = mini_uart_writer.write("  cat - Print the content of a file in the initramfs\n") catch {};
                _ = mini_uart_writer.write("  demo - Run a simple allocator demo\n") catch {};
                _ = mini_uart_writer.write("  exec - Execute a file in the initramfs\n") catch {};
                _ = mini_uart_writer.write("  alloc - Run a page allocator demo\n") catch {};
                _ = mini_uart_writer.write("  free - Run a page free demo\n") catch {};
            },
            Command.None => {
                _ = mini_uart_writer.write("Unknown command: ") catch {};
                _ = mini_uart_writer.write(buffer[0..recvlen]) catch {};
                _ = mini_uart_writer.write("\n") catch {};
            },
            Command.Reboot => {
                reboot.reset(100);
            },
            Command.ListFiles => {
                const fs = cpio.listFiles(startup_allocator);
                if (fs) |files| {
                    for (files) |file| {
                        _ = mini_uart_writer.print("{s}\n", .{file}) catch {};
                    }
                }
            },
            Command.GetFileContent => {
                _ = mini_uart_writer.write("Filename: ") catch {};
                recvlen = mini_uart_reader.read(buffer) catch 0;
                const c = cpio.getFileContent(buffer[0..recvlen]);
                if (c) |content| {
                    _ = mini_uart_writer.print("{s}\n", .{content}) catch {};
                } else {
                    std.log.info("No such file", .{});
                }
            },
            Command.DemoSimpleAlloc => {
                _ = mini_uart_writer.write("Length of Allocated Memory?: ") catch {};
                recvlen = mini_uart_reader.read(buffer) catch 0;

                const name_size = std.fmt.parseInt(u32, buffer[0..recvlen], 10) catch 0;
                const demo_buffer = startup_allocator.alloc(u8, name_size) catch {
                    continue;
                };

                _ = mini_uart_writer.write("Content: ") catch {};
                recvlen = mini_uart_reader.read(demo_buffer) catch 0;

                _ = mini_uart_writer.write("\n") catch {};
                _ = mini_uart_writer.print("Buffer Address: 0x{X}\n", .{@intFromPtr(demo_buffer.ptr)}) catch {};
                _ = mini_uart_writer.write("Buffer Content: ") catch {};
                _ = mini_uart_writer.write(demo_buffer) catch {};
                _ = mini_uart_writer.write("\n") catch {};
            },
            Command.ExecFileContent => {
                _ = mini_uart_writer.write("Filename: ") catch {};
                recvlen = mini_uart_reader.read(buffer) catch 0;
                const c = cpio.getFileContent(buffer[0..recvlen]);
                if (c) |content| {
                    execFile(content);
                } else {
                    std.log.info("No such file", .{});
                }
            },
            Command.DemoPageAlloc => {
                _ = mini_uart_writer.write("Length of Allocated Memory?: ") catch {};
                recvlen = mini_uart_reader.read(buffer) catch 0;

                const name_size = std.fmt.parseInt(u32, buffer[0..recvlen], 10) catch 0;
                const demo_buffer: []u8 = allocator.alloc(u8, name_size) catch {
                    _ = mini_uart_writer.write("Allocation failed\n") catch {};
                    continue;
                };

                alloc_map.put(@intFromPtr(demo_buffer.ptr), demo_buffer) catch {
                    @panic("Failed to put in map");
                };

                _ = mini_uart_writer.print("Buffer Address: 0x{X}\n", .{@intFromPtr(demo_buffer.ptr)}) catch {};
            },
            Command.DemoPageFree => {
                _ = mini_uart_writer.write("Address of Allocated Memory?: ") catch {};
                recvlen = mini_uart_reader.read(buffer) catch 0;

                const address = std.fmt.parseInt(usize, buffer[2..recvlen], 16) catch 0;
                const demo_buffer = alloc_map.get(address);

                if (demo_buffer) |db| {
                    _ = alloc_map.remove(address);
                    allocator.free(db);
                    _ = mini_uart_writer.print("Freed memory at address: 0x{X}\n", .{address}) catch {};
                } else {
                    _ = mini_uart_writer.print("No such address: 0x{X}\n", .{address}) catch {};
                }
            },
        }
    }
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    std.log.err("!KERNEL PANIC!", .{});
    std.log.err("{s}", .{msg});

    if (error_return_trace) |trace| {
        for (trace.instruction_addresses) |address| {
            if (address == 0) {
                break;
            }
            std.log.err("0x{X}", .{address});
        }
    }

    reboot.reset(100);
    while (true) {}
}

// Main function for the kernel
export fn main(dtb_address: usize) void {
    gpio.init();
    uart.init();
    interrupt.init();

    const board_revision = mailbox.getBoardRevision() catch {
        @panic("Cannot obtain board revision from mailbox.");
    };
    const arm_memory = mailbox.getArmMemory() catch {
        @panic("Cannot obtain ARM memory information from mailbox.");
    };

    const dtb_size = dtb.init(startup_allocator, dtb_address);
    dtb.fdtTraverse(cpio.initRamfsCallback);

    const initrd_start_ptr = cpio.getInitrdStartPtr();
    const initrd_end_ptr = cpio.getInitrdEndPtr();

    std.log.info("Board revision: 0x{X}", .{board_revision});
    std.log.info("ARM Memory Base: 0x{X}", .{arm_memory.@"0"});
    std.log.info("ARM Memory Size: 0x{X}", .{arm_memory.@"1"});
    std.log.info("Initrd Start: 0x{X}", .{initrd_start_ptr});
    std.log.info("Initrd End: 0x{X}", .{initrd_end_ptr});
    std.log.info("DTB Address: 0x{X}", .{dtb_address});
    std.log.info("DTB Size: 0x{X}", .{dtb_size});

    const mem: []allowzero u8 = @as([*]allowzero u8, @ptrFromInt(arm_memory.@"0"))[0..arm_memory.@"1"];
    var fa = PageAllocator.init(mem) catch {
        @panic("Cannot init page allocator!");
    };

    fa.memory_reserve(0x0000, 0x1000); // spin tables
    fa.memory_reserve(@intFromPtr(&_flash_img_start), @intFromPtr(&_flash_img_end));
    fa.memory_reserve(initrd_start_ptr, initrd_end_ptr);
    fa.memory_reserve(dtb_address, dtb_address + dtb_size);

    var da = DynamicAllocator.init(&fa);

    const allocator = da.allocator();

    simpleShell(allocator);
}

extern const _flash_img_start: u32;
extern const _flash_img_end: u32;

comptime {
    // Avoid using x0 as it stores the address of dtb
    asm (
        \\ .section .text.boot
        \\ .global _start
        \\ _start:
        \\      bl from_el2_to_el1
        \\      bl core_timer_enable
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

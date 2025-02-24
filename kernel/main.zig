const std = @import("std");
const utils = @import("utils.zig");
const gpio = @import("gpio.zig");
const uart = @import("uart.zig");
const mailbox = @import("mailbox.zig");
const reboot = @import("reboot.zig");
const cpio = @import("cpio.zig");
const allocator = @import("allocator.zig");

const SimpleAllocator = allocator.SimpleAllocator;
const MiniUARTReader = uart.MiniUARTReader;
const MiniUARTWriter = uart.MiniUARTWriter;

const Command = enum {
    None,
    Hello,
    Help,
    Reboot,
    ListFiles,
    GetFileContent,
    DemoSimpleAlloc,
};

fn parse_command(command: []const u8) Command {
    // if (std.mem.eql(u8, command, "hello")) {
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
    } else {
        return Command.None;
    }
}

fn simple_shell() void {
    var buffer = SimpleAllocator.alloc(u8, 256) catch {
        @panic("Out of Memory! No buffer for simple shell.");
    };
    while (true) {
        _ = MiniUARTWriter.write("# ") catch {};

        var recvlen = MiniUARTReader.read(buffer) catch 0;
        const command = parse_command(buffer[0..recvlen]);

        switch (command) {
            Command.Hello => {
                _ = MiniUARTWriter.write("Hello, World!\n") catch {};
            },
            Command.Help => {
                _ = MiniUARTWriter.write("Commands:\n") catch {};
                _ = MiniUARTWriter.write("  hello - Print 'Hello, World!'\n") catch {};
                _ = MiniUARTWriter.write("  help - Print this help message\n") catch {};
                _ = MiniUARTWriter.write("  reboot - Reboot the system\n") catch {};
                _ = MiniUARTWriter.write("  ls - List files in the initramfs\n") catch {};
                _ = MiniUARTWriter.write("  cat - Print the content of a file in the initramfs\n") catch {};
                _ = MiniUARTWriter.write("  demo - Run a simple allocator demo\n") catch {};
            },
            Command.None => {
                _ = MiniUARTWriter.write("Unknown command: ") catch {};
                _ = MiniUARTWriter.write(buffer[0..recvlen]) catch {};
                _ = MiniUARTWriter.write("\n") catch {};
            },
            Command.Reboot => {
                reboot.reset(100);
            },
            Command.ListFiles => {
                cpio.list_files();
            },
            Command.GetFileContent => {
                _ = MiniUARTWriter.write("Filename: ") catch {};
                recvlen = MiniUARTReader.read(buffer) catch 0;
                cpio.get_file_content(buffer[0..recvlen]);
            },
            Command.DemoSimpleAlloc => {
                var demo_buffer = SimpleAllocator.alloc(u8, 256) catch {
                    continue;
                };
                demo_buffer[0] = 'A';
                demo_buffer[1] = 'B';

                _ = MiniUARTWriter.print("Buffer Address: 0x{X}\n", .{@intFromPtr(demo_buffer.ptr)}) catch {};
                _ = MiniUARTWriter.write("Buffer Content: ") catch {};
                _ = MiniUARTWriter.write(demo_buffer) catch {};
                _ = MiniUARTWriter.write("\n") catch {};
            },
        }
    }
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = error_return_trace;
    _ = MiniUARTWriter.write("\n!KERNEL PANIC!\n") catch {};
    _ = MiniUARTWriter.write(msg) catch {};
    _ = MiniUARTWriter.write("\n") catch {};
    while (true) {}
}

// Main function for the kernel
export fn main(dtb_address: usize) void {
    gpio.init();
    uart.init();

    utils.send_hex("DTB Address: 0x", @intCast(dtb_address));

    mailbox.get_board_revision();
    mailbox.get_arm_memory();

    simple_shell();
}

comptime {
    // Avoid using x0 as it stores the address of dtb
    asm (
        \\ .section .text.boot
        \\ .global _start
        \\ _start:
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

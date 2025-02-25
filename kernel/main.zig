const std = @import("std");
const gpio = @import("gpio.zig");
const uart = @import("uart.zig");
const mailbox = @import("mailbox.zig");
const reboot = @import("reboot.zig");
const cpio = @import("cpio.zig");
const allocator = @import("allocator.zig");

const simple_allocator = allocator.simple_allocator;
const mini_uart_reader = uart.mini_uart_reader;
const mini_uart_writer = uart.mini_uart_writer;

const Command = enum {
    None,
    Hello,
    Help,
    Reboot,
    ListFiles,
    GetFileContent,
    DemoSimpleAlloc,
};

fn parseCommand(command: []const u8) Command {
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

fn simpleShell() void {
    var buffer = simple_allocator.alloc(u8, 256) catch {
        @panic("Out of Memory! No buffer for simple shell.");
    };
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
                cpio.listFiles();
            },
            Command.GetFileContent => {
                _ = mini_uart_writer.write("Filename: ") catch {};
                recvlen = mini_uart_reader.read(buffer) catch 0;
                cpio.getFileContent(buffer[0..recvlen]);
            },
            Command.DemoSimpleAlloc => {
                _ = mini_uart_writer.write("Length of Allocated Memory?: ") catch {};
                recvlen = mini_uart_reader.read(buffer) catch 0;

                const name_size = std.fmt.parseInt(u32, buffer[0..recvlen], 10) catch 0;
                const demo_buffer = simple_allocator.alloc(u8, name_size) catch {
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
        }
    }
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = error_return_trace;
    _ = mini_uart_writer.write("\n!KERNEL PANIC!\n") catch {};
    _ = mini_uart_writer.write(msg) catch {};
    _ = mini_uart_writer.write("\n") catch {};
    while (true) {}
}

// Main function for the kernel
export fn main(dtb_address: usize) void {
    gpio.init();
    uart.init();

    _ = mini_uart_writer.print("DTB Address: 0x{X}\n", .{dtb_address}) catch {};

    mailbox.getBoardRevision();
    mailbox.getArmMemory();

    simpleShell();
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

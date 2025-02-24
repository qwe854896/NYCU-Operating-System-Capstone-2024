const std = @import("std");
const utils = @import("utils.zig");
const gpio = @import("gpio.zig");
const uart = @import("uart.zig");
const mailbox = @import("mailbox.zig");
const reboot = @import("reboot.zig");
const cpio = @import("cpio.zig");
const allocator = @import("allocator.zig");

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
    var buffer = allocator.simple_alloc(256);
    while (true) {
        uart.send_str("# ");

        var recvlen = uart.recv_str(buffer);
        const command = parse_command(buffer[0..recvlen]);

        switch (command) {
            Command.Hello => {
                uart.send_str("Hello, World!\n");
            },
            Command.Help => {
                uart.send_str("Commands:\n");
                uart.send_str("  hello - Print 'Hello, World!'\n");
                uart.send_str("  help - Print this help message\n");
                uart.send_str("  reboot - Reboot the system\n");
                uart.send_str("  ls - List files in the initramfs\n");
                uart.send_str("  cat - Print the content of a file in the initramfs\n");
                uart.send_str("  demo - Run a simple allocator demo\n");
            },
            Command.None => {
                uart.send_str("Unknown command: ");
                uart.send_str(buffer[0..recvlen]);
                uart.send_str("\n");
            },
            Command.Reboot => {
                reboot.reset(100);
            },
            Command.ListFiles => {
                cpio.list_files();
            },
            Command.GetFileContent => {
                uart.send_str("Filename: ");
                recvlen = uart.recv_str(buffer);
                cpio.get_file_content(buffer[0..recvlen]);
            },
            Command.DemoSimpleAlloc => {
                var demo_buffer = allocator.simple_alloc(256);
                demo_buffer[0] = 'A';
                demo_buffer[1] = 'B';

                utils.send_hex("Buffer Address: 0x", @intCast(@intFromPtr(demo_buffer.ptr)));
                uart.send_str("Buffer Content: ");
                uart.send_str(demo_buffer);
                uart.send_str("\n");
            },
        }
    }
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

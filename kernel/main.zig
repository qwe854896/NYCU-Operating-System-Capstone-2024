const std = @import("std");
const gpio = @import("gpio.zig");
const uart = @import("uart.zig");
const mailbox = @import("mailbox.zig");
const reboot = @import("reboot.zig");
const cpio = @import("cpio.zig");

const Command = enum {
    None,
    Hello,
    Help,
    Reboot,
    ListFiles,
    GetFileContent,
};

fn strcmp(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) {
        return false;
    }

    for (0.., a) |i, a_byte| {
        if (a_byte != b[i]) {
            return false;
        }
    }

    return true;
}

fn parse_command(command: []const u8) Command {
    if (strcmp(command, "hello")) {
        return Command.Hello;
    } else if (strcmp(command, "help")) {
        return Command.Help;
    } else if (strcmp(command, "reboot")) {
        return Command.Reboot;
    } else if (strcmp(command, "ls")) {
        return Command.ListFiles;
    } else if (strcmp(command, "cat")) {
        return Command.GetFileContent;
    } else {
        return Command.None;
    }
}

fn simple_shell() void {
    while (true) {
        uart.send_str("# ");

        var buffer: [256]u8 = undefined;
        var recvlen = uart.recv_str(&buffer);
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
                const initramfs_ptr: [*]const u8 = @ptrFromInt(0x8000000);
                const initramfs = initramfs_ptr[0..65536];
                cpio.list_files(initramfs);
            },
            Command.GetFileContent => {
                uart.send_str("Filename: ");
                recvlen = uart.recv_str(&buffer);

                const initramfs_ptr: [*]const u8 = @ptrFromInt(0x8000000);
                const initramfs = initramfs_ptr[0..65536];
                cpio.get_file_content(initramfs, buffer[0..recvlen]);
            },
        }
    }
}

// Main function for the kernel
export fn main() void {
    gpio.init();
    uart.init();

    mailbox.get_board_revision();
    mailbox.get_arm_memory();

    simple_shell();
}

comptime {
    asm (
        \\ .section .text.boot
        \\ .global _start
        \\ _start:
        \\      ldr x0, =_stack_top
        \\      mov sp, x0
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

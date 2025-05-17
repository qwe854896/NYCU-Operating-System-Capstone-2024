const std = @import("std");
const drivers = @import("drivers");
const initrd = @import("fs/initrd.zig");
const syscall = @import("process/syscall/user.zig");
const thread = @import("thread.zig");
const main = @import("main.zig");
const sched = @import("sched.zig");
const uart = drivers.uart;
const processor = @import("arch/aarch64/processor.zig");

const mini_uart_reader = uart.mini_uart_reader;
const mini_uart_writer = uart.mini_uart_writer;

const TrapFrame = processor.TrapFrame;
const Command = enum {
    None,
    Hello,
    Help,
    Reboot,
    ListFiles,
    GetFileContent,
    ExecFileContent,
};

fn runSyscallImg() void {
    var trap_frame: TrapFrame = undefined;
    thread.exec(&trap_frame, "vm_.img");
    thread.end();
}

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
    } else if (std.mem.eql(u8, command, "exec")) {
        return Command.ExecFileContent;
    } else {
        return Command.None;
    }
}

pub fn simpleShell() void {
    var array: [256]u8 = undefined;
    var buffer = array[0..];

    while (true) {
        // Only idle and simpleShell can escape this polling loop
        while (sched.getRunQueueLen() > 2) {
            sched.schedule();
        }

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
                _ = mini_uart_writer.write("  exec - Execute a file in the initramfs\n") catch {};
            },
            Command.None => {
                _ = mini_uart_writer.write("Unknown command: ") catch {};
                _ = mini_uart_writer.write(buffer[0..recvlen]) catch {};
                _ = mini_uart_writer.write("\n") catch {};
            },
            Command.Reboot => {
                drivers.watchdog.reset(100);
            },
            Command.ListFiles => {
                const entries = initrd.listFiles();
                for (entries) |entry| {
                    _ = mini_uart_writer.print("{s}\n", .{entry.name}) catch {};
                }
            },
            Command.GetFileContent => {
                _ = mini_uart_writer.write("Filename: ") catch {};
                recvlen = mini_uart_reader.read(buffer) catch 0;
                const c = initrd.getFileContent(buffer[0..recvlen]);
                if (c) |content| {
                    _ = mini_uart_writer.print("{s}\n", .{content}) catch {};
                } else {
                    std.log.info("No such file", .{});
                }
            },
            Command.ExecFileContent => {
                thread.create(main.getSingletonAllocator(), runSyscallImg);
            },
        }
    }
}

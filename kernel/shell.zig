const std = @import("std");
const uart = @import("peripherals/uart.zig");
const drivers = @import("drivers");
const cpio = @import("cpio.zig");
const syscall = @import("syscall.zig");

const mini_uart_reader = uart.mini_uart_reader;
const mini_uart_writer = uart.mini_uart_writer;

const Command = enum {
    None,
    Hello,
    Help,
    Reboot,
    ListFiles,
    GetFileContent,
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

pub fn simpleShell(allocator: std.mem.Allocator) void {
    var buffer = allocator.alloc(u8, 256) catch {
        @panic("Out of Memory! No buffer for simple shell.");
    };
    defer allocator.free(buffer);

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
                drivers.watchdog.reset(100);
            },
            Command.ListFiles => {
                const fs = cpio.listFiles(allocator);
                if (fs) |files| {
                    for (files) |file| {
                        _ = mini_uart_writer.print("{s}\n", .{file}) catch {};
                    }
                    allocator.free(files);
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
            Command.ExecFileContent => {
                _ = mini_uart_writer.write("Filename: ") catch {};
                recvlen = mini_uart_reader.read(buffer) catch 0;
                const retval = syscall.exec(buffer[0..recvlen], null);
                if (retval != 0) {
                    _ = mini_uart_writer.print("Exec failed with error code: {d}\n", .{retval}) catch {};
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

                _ = mini_uart_writer.print("Buffer Address: 0x{X}\n", .{@intFromPtr(demo_buffer.ptr)}) catch {};
            },
            Command.DemoPageFree => {
                _ = mini_uart_writer.write("Address of Allocated Memory?: ") catch {};
                recvlen = mini_uart_reader.read(buffer) catch 0;

                const address = std.fmt.parseInt(usize, buffer[2..recvlen], 16) catch 0;
                const db: []u8 = @as([*]u8, @ptrFromInt(address))[0..1];

                allocator.free(db);
                _ = mini_uart_writer.print("Freed memory at address: 0x{X}\n", .{address}) catch {};
            },
        }
    }
}

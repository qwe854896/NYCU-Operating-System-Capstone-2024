/// Reference: https://zig.guide/standard-library/readers-and-writers/
const std = @import("std");
const sched = @import("../sched.zig");
const drivers = @import("drivers");
const uart = drivers.uart;

pub fn send(byte: u8) void {
    while (!uart.aux_mu_lsr.read().tx_ready) {
        asm volatile ("nop");
    }
    uart.aux_mu_io.write(.{ .data = byte });
}

pub fn recv() u8 {
    while (!uart.aux_mu_lsr.read().rx_ready) {
        asm volatile ("nop");
    }
    return uart.aux_mu_io.read().data;
}

pub fn yieldRecv() u8 {
    while (!uart.aux_mu_lsr.read().rx_ready) {
        sched.schedule();
    }
    return uart.aux_mu_io.read().data;
}

const MiniUARTWriter = struct {
    const Self = @This();
    const Writer = std.io.Writer(
        Self,
        error{},
        writeFn,
    );
    fn writeFn(self: Self, data: []const u8) error{}!usize {
        _ = self;
        for (data) |byte| {
            switch (byte) {
                '\n' => {
                    send('\r');
                    send('\n');
                },
                else => send(byte),
            }
        }
        return data.len;
    }
    fn init() MiniUARTWriter {
        return .{};
    }
    fn writer(self: Self) Writer {
        return .{ .context = self };
    }
};

const MiniUARTReader = struct {
    const Self = @This();
    const Reader = std.io.Reader(
        Self,
        error{},
        readFn,
    );
    fn readFn(self: Self, data: []u8) error{}!usize {
        _ = self;
        var i: usize = 0;
        while (i < data.len) {
            const c = recv();
            if (c == '\r') {
                _ = mini_uart_writer.write("\n") catch {};
                break;
            }
            send(c);
            data[i] = c;
            i += 1;
        }
        return i;
    }
    fn init() MiniUARTReader {
        return .{};
    }
    fn reader(self: Self) Reader {
        return .{ .context = self };
    }
};

pub const mini_uart_writer = MiniUARTWriter.init().writer();
pub const mini_uart_reader = MiniUARTReader.init().reader();

pub fn miniUARTLogFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    nosuspend mini_uart_writer.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
}

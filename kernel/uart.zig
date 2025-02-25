/// Reference: https://zig.guide/standard-library/readers-and-writers/
const std = @import("std");
const mmio = @import("mmio.zig");

const Register = mmio.Register;

const base_address = mmio.base_address + 0x215000;

const aux_enables = Register.init(base_address + 0x04);
const aux_mu_io_reg = Register.init(base_address + 0x40);
const aux_mu_ier_reg = Register.init(base_address + 0x44);
const aux_mu_iir_reg = Register.init(base_address + 0x48);
const aux_mu_lcr_reg = Register.init(base_address + 0x4C);
const aux_mu_mcr_reg = Register.init(base_address + 0x50);
const aux_mu_lsr_reg = Register.init(base_address + 0x54);
const aux_mu_cntl_reg = Register.init(base_address + 0x60);
const aux_mu_baud_reg = Register.init(base_address + 0x68);

pub fn init() void {
    aux_enables.writeRaw(1); // Enable Mini UART
    aux_mu_cntl_reg.writeRaw(0); // Disable TX and RX during configuration
    aux_mu_ier_reg.writeRaw(0); // Disable interrupts
    aux_mu_lcr_reg.writeRaw(3); // Set data size to 8-bit
    aux_mu_mcr_reg.writeRaw(0); // Disable flow control
    aux_mu_baud_reg.writeRaw(270); // Set baud rate to 115200 (270 divisor)
    aux_mu_iir_reg.writeRaw(6); // Clear FIFOs and set interrupt mode
    aux_mu_cntl_reg.writeRaw(3); // Enable transmitter and receiver
}

fn send(byte: u8) void {
    while ((aux_mu_lsr_reg.readRaw() & 0x20) == 0) {
        asm volatile ("nop"); // Wait until the transmitter is empty
    }
    aux_mu_io_reg.writeRaw(byte);
}

fn recv() u8 {
    while ((aux_mu_lsr_reg.readRaw() & 0x01) == 0) {
        asm volatile ("nop"); // Wait until data is ready
    }
    return @intCast(aux_mu_io_reg.readRaw() & 0xFF);
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

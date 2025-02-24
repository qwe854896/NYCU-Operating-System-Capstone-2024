/// Reference: https://zig.guide/standard-library/readers-and-writers/
const std = @import("std");
const mmio = @import("mmio.zig");

const Register = mmio.Register;

const UART_BASE = mmio.MMIO_BASE + 0x215000;

const AUX_ENABLES = Register.init(UART_BASE + 0x04);
const AUX_MU_IO_REG = Register.init(UART_BASE + 0x40);
const AUX_MU_IER_REG = Register.init(UART_BASE + 0x44);
const AUX_MU_IIR_REG = Register.init(UART_BASE + 0x48);
const AUX_MU_LCR_REG = Register.init(UART_BASE + 0x4C);
const AUX_MU_MCR_REG = Register.init(UART_BASE + 0x50);
const AUX_MU_LSR_REG = Register.init(UART_BASE + 0x54);
const AUX_MU_CNTL_REG = Register.init(UART_BASE + 0x60);
const AUX_MU_BAUD_REG = Register.init(UART_BASE + 0x68);

// UART Initialization
pub fn init() void {
    // Enable Mini UART
    AUX_ENABLES.write_raw(1);

    // Disable TX and RX during configuration
    AUX_MU_CNTL_REG.write_raw(0);

    // Disable interrupts
    AUX_MU_IER_REG.write_raw(0);

    // Set data size to 8-bit
    AUX_MU_LCR_REG.write_raw(3);

    // Disable flow control
    AUX_MU_MCR_REG.write_raw(0);

    // Set baud rate to 115200 (270 divisor)
    AUX_MU_BAUD_REG.write_raw(270);

    // Clear FIFOs and set interrupt mode
    AUX_MU_IIR_REG.write_raw(6);

    // Enable transmitter and receiver
    AUX_MU_CNTL_REG.write_raw(3);
}

// Send a byte over UART
fn send(byte: u8) void {
    while ((AUX_MU_LSR_REG.read_raw() & 0x20) == 0) {
        // Wait until the transmitter is empty
        asm volatile ("nop");
    }
    AUX_MU_IO_REG.write_raw(byte);
}

// Receive a byte over UART
fn recv() u8 {
    while ((AUX_MU_LSR_REG.read_raw() & 0x01) == 0) {
        // Wait until data is ready
        asm volatile ("nop");
    }
    return @intCast(AUX_MU_IO_REG.read_raw() & 0xFF);
}

const MiniUARTWriter__ = struct {
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
    fn writer(self: Self) Writer {
        return .{ .context = self };
    }
};

const MiniUARTWriter_: MiniUARTWriter__ = undefined;
pub const MiniUARTWriter = MiniUARTWriter_.writer();

const MiniUARTReader__ = struct {
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
                _ = MiniUARTWriter.write("\n") catch {};
                break;
            }
            send(c);
            data[i] = c;
            i += 1;
        }
        return i;
    }
    fn reader(self: Self) Reader {
        return .{ .context = self };
    }
};

const MiniUARTReader_: MiniUARTReader__ = undefined;
pub const MiniUARTReader = MiniUARTReader_.reader();

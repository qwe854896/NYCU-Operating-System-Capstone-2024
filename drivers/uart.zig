const std = @import("std");
const mmio = @import("mmio.zig");
const gpio = @import("gpio.zig");
const Register = mmio.Register;

// AUX peripheral registers
const auxenb_val = packed struct(u32) {
    mini_uart: enum(u1) {
        disabled = 0,
        enabled = 1,
    },
    spi_1: enum(u1) {
        disabled = 0,
        enabled = 1,
    },
    spi_2: enum(u1) {
        disabled = 0,
        enabled = 1,
    },
    _unused3: u29 = 0,
};

// Mini UART I/O data register
const aux_mu_io_val = packed struct(u32) {
    data: u8 = 0,
    _unused8: u24 = 0,
};

// Interrupt enable register
const aux_mu_ier_val = packed struct(u32) {
    rx_ir: enum(u1) {
        disabled = 0,
        enabled = 1,
    },
    tx_ir: enum(u1) {
        disabled = 0,
        enabled = 1,
    },
    _unused2: u30 = 0,
};

// Interrupt identify register
const aux_mu_iir_val = packed struct(u32) {
    int_pending: enum(u1) {
        active = 0,
        inactive = 1,
    },
    rx_fifo_clear: enum(u1) {
        no_action = 0,
        clear = 1,
    },
    tx_fifo_clear: enum(u1) {
        no_action = 0,
        clear = 1,
    },
    _unused3: u29 = 0,
};

// Line control register
const aux_mu_lcr_val = packed struct(u32) {
    data_size: enum(u2) {
        _7_bit = 0b00,
        _8_bit = 0b11,
    },
    _unused2: u30 = 0,
};

// Modem control register
const aux_mu_mcr_val = packed struct(u32) {
    _unused0: u1 = 0,
    rts_flow_control: bool = false,
    _unused2: u30 = 0,
};

// Line status register
const aux_mu_lsr_val = packed struct(u32) {
    rx_ready: bool,
    _unused1: u4 = 0,
    tx_ready: bool,
    _unused6: u26 = 0,
};

const aux_mu_cntl_val = packed struct(u32) {
    rx: enum(u1) {
        disabled = 0,
        enabled = 1,
    },
    tx: enum(u1) {
        disabled = 0,
        enabled = 1,
    },
    _unused2: u30 = 0,
};

const aux_mu_baud_val = packed struct(u32) {
    baud_rate: u16 = 0,
    _unused16: u16 = 0,
};

const base_address = mmio.base_address + 0x215000;

const auxenb = Register(auxenb_val, auxenb_val).init(base_address + 0x04);
pub const aux_mu_io = Register(aux_mu_io_val, aux_mu_io_val).init(base_address + 0x40);
const aux_mu_ier = Register(aux_mu_ier_val, aux_mu_ier_val).init(base_address + 0x44);
const aux_mu_iir = Register(aux_mu_iir_val, aux_mu_iir_val).init(base_address + 0x48);
const aux_mu_lcr = Register(aux_mu_lcr_val, aux_mu_lcr_val).init(base_address + 0x4C);
const aux_mu_mcr = Register(aux_mu_mcr_val, aux_mu_mcr_val).init(base_address + 0x50);
pub const aux_mu_lsr = Register(aux_mu_lsr_val, aux_mu_lsr_val).init(base_address + 0x54);
const aux_mu_cntl = Register(aux_mu_cntl_val, aux_mu_cntl_val).init(base_address + 0x60);
const aux_mu_baud = Register(aux_mu_baud_val, aux_mu_baud_val).init(base_address + 0x68);

// UART Initialization
pub fn init() void {
    gpio.gp_fsel_1.modify(.{ ._4 = .alt5, ._5 = .alt5 });
    gpio.gp_pud.modify(.{ .pud = .disabled });

    auxenb.modify(.{ .mini_uart = .enabled });

    aux_mu_cntl.modify(.{ .tx = .disabled, .rx = .disabled });
    aux_mu_ier.modify(.{ .rx_ir = .disabled, .tx_ir = .disabled });
    aux_mu_lcr.modify(.{ .data_size = ._8_bit });
    aux_mu_mcr.modify(.{ .rts_flow_control = false });
    aux_mu_baud.modify(.{ .baud_rate = 270 }); // Set baud rate to 115200
    aux_mu_iir.modify(.{ .rx_fifo_clear = .clear, .tx_fifo_clear = .clear });
    aux_mu_cntl.modify(.{ .tx = .enabled, .rx = .enabled });
}

pub fn send(byte: u8) void {
    while (!aux_mu_lsr.read().tx_ready) {
        asm volatile ("nop");
    }
    aux_mu_io.write(.{ .data = byte });
}

pub fn recv() u8 {
    while (!aux_mu_lsr.read().rx_ready) {
        asm volatile ("nop");
    }
    return aux_mu_io.read().data;
}

/// Reference: https://zig.guide/standard-library/readers-and-writers/
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
                    send('\n');
                    send('\r');
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
            if (c == '\r' or c == '\n') {
                _ = mini_uart_writer.write("\n") catch {};
                break;
            }
            if (c != '\xf0') {
                if (c == '\x7f') {
                    if (i >= 1) {
                        i -= 1;
                        _ = mini_uart_writer.write("\x08 \x08") catch {};
                    }
                } else {
                    send(c);
                    data[i] = c;
                    i += 1;
                }
            }
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

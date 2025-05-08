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
const aux_mu_io = Register(aux_mu_io_val, aux_mu_io_val).init(base_address + 0x40);
const aux_mu_ier = Register(aux_mu_ier_val, aux_mu_ier_val).init(base_address + 0x44);
const aux_mu_iir = Register(aux_mu_iir_val, aux_mu_iir_val).init(base_address + 0x48);
const aux_mu_lcr = Register(aux_mu_lcr_val, aux_mu_lcr_val).init(base_address + 0x4C);
const aux_mu_mcr = Register(aux_mu_mcr_val, aux_mu_mcr_val).init(base_address + 0x50);
const aux_mu_lsr = Register(aux_mu_lsr_val, aux_mu_lsr_val).init(base_address + 0x54);
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

// Send a byte over UART
fn send(byte: u8) void {
    while (!aux_mu_lsr.read().tx_ready) {
        asm volatile ("nop");
    }
    aux_mu_io.write(.{ .data = byte });
}

// Receive a byte over UART
pub fn recv() u8 {
    while (!aux_mu_lsr.read().rx_ready) {
        asm volatile ("nop");
    }
    return aux_mu_io.read().data;
}

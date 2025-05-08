const mmio = @import("mmio.zig");
const Register = mmio.Register;

const fsel_val = enum(u3) {
    input = 0b000,
    output = 0b001,
    alt0 = 0b100,
    alt1 = 0b101,
    alt2 = 0b110,
    alt3 = 0b111,
    alt4 = 0b011,
    alt5 = 0b010,
};

const gp_fsel_val = packed struct(u32) {
    _0: fsel_val,
    _1: fsel_val,
    _2: fsel_val,
    _3: fsel_val,
    _4: fsel_val,
    _5: fsel_val,
    _6: fsel_val,
    _7: fsel_val,
    _8: fsel_val,
    _9: fsel_val,
    _unused30: u2 = 0,
};

const gp_pud_val = packed struct(u32) {
    pud: enum(u2) {
        disabled = 0b00,
        pulldown = 0b01,
        pullup = 0b10,
    },
    _unused2: u30 = 0,
};

const base_address = mmio.base_address + 0x200000;

pub const gp_fsel_1 = Register(gp_fsel_val, gp_fsel_val).init(base_address + 0x04);
pub const gp_pud = Register(gp_pud_val, gp_pud_val).init(base_address + 0x94);

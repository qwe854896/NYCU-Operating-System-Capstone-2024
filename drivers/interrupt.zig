const mmio = @import("mmio.zig");
const Register = mmio.Register;

const irq_enable_1_val = packed struct(u32) {
    _unused0: u1 = 0,
    timer_match_1: bool,
    _unused2: u1 = 0,
    timer_match_3: bool,
    _unused4: u5 = 0,
    usb_controller: bool,
    _unused10: u19 = 0,
    aux_int: bool,
    _unused30: u2 = 0,
};

const base_address = mmio.base_address + 0xB000;

const irq_enable_1 = Register(irq_enable_1_val, irq_enable_1_val).init(base_address + 0x210);

pub fn init() void {
    irq_enable_1.modify(.{ .aux_int = true });
}

const mmio = @import("mmio.zig");
const Register = mmio.Register;

const base_address = mmio.base_address + 0x200000;

const gpfsel1 = Register.init(base_address + 0x04);
const gppud = Register.init(base_address + 0x94);

// GPIO Initialization for Mini UART
pub fn init() void {
    // Set GPIO 14 & 15 to ALT5 (Mini UART mode)
    var reg = gpfsel1.readRaw();

    reg &= ~@as(u32, 0b111 << 12) & ~@as(u32, 0b111 << 15); // Clear FSEL14 and FSEL15
    reg |= (0b010 << 12) | (0b010 << 15); // ALT5 for UART
    gpfsel1.writeRaw(reg);

    // Disable pull-up/down for GPIO 14 & 15
    gppud.writeRaw(0);
}

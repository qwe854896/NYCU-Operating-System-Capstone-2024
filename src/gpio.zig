const mmio = @import("mmio.zig");
const Register = mmio.Register;

const GPIO_BASE = mmio.MMIO_BASE + 0x200000;

const GPFSEL1 = Register.init(GPIO_BASE + 0x04);
const GPPUD = Register.init(GPIO_BASE + 0x94);

// GPIO Initialization for Mini UART
pub fn init() void {
    // Set GPIO 14 & 15 to ALT5 (Mini UART mode)
    var reg = GPFSEL1.read_raw();
    reg &= ~@as(u32, 0b111 << 12) & ~@as(u32, 0b111 << 15); // Clear FSEL14 and FSEL15
    reg |= (0b010 << 12) | (0b010 << 15); // ALT5 for UART
    GPFSEL1.write_raw(reg);

    // Disable pull-up/down for GPIO 14 & 15
    GPPUD.write_raw(0);
}

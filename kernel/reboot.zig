const mmio = @import("mmio.zig");

const Register = mmio.Register;

const pm_password: u32 = 0x5a000000;
const pm_rstc = Register.init(mmio.base_address + 0x0010001c);
const pm_wdog = Register.init(mmio.base_address + 0x00100024);

pub fn reset(tick: u32) void {
    // Reboot after watchdog timer expires
    pm_rstc.writeRaw(pm_password | 0x20); // Full reset
    pm_wdog.writeRaw(pm_password | tick); // Set watchdog timer ticks
}

pub fn cancelReset() void {
    pm_rstc.writeRaw(pm_password | 0); // Full reset
    pm_wdog.writeRaw(pm_password | 0); // Clear watchdog timer
}

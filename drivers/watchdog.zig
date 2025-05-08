const mmio = @import("mmio.zig");
const Register = mmio.Register;

const base_address = mmio.base_address + 0x100000;

const pm_password: u32 = 0x5a000000;
const pm_rstc = Register(u32, u32).init(base_address + 0x1c);
const pm_wdog = Register(u32, u32).init(base_address + 0x24);

pub fn reset(tick: u32) void {
    // Reboot after watchdog timer expires
    pm_rstc.write(pm_password | 0x20); // Full reset
    pm_wdog.write(pm_password | tick); // Set watchdog timer ticks
}

pub fn cancelReset() void {
    pm_rstc.write(pm_password | 0); // Full reset
    pm_wdog.write(pm_password | 0); // Clear watchdog timer
}

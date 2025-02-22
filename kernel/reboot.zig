const mmio = @import("mmio.zig");

const Register = mmio.Register;

const PM_PASSWORD: u32 = 0x5a000000;
const PM_RSTC = Register.init(mmio.MMIO_BASE + 0x0010001c);
const PM_WDOG = Register.init(mmio.MMIO_BASE + 0x00100024);

pub fn reset(tick: u32) void {
    // Reboot after watchdog timer expires
    PM_RSTC.write_raw(PM_PASSWORD | 0x20); // Full reset
    PM_WDOG.write_raw(PM_PASSWORD | tick); // Set watchdog timer ticks
}

pub fn cancel_reset() void {
    PM_RSTC.write_raw(PM_PASSWORD | 0); // Full reset
    PM_WDOG.write_raw(PM_PASSWORD | 0); // Clear watchdog timer
}

pub const uart = @import("uart.zig");
pub const interrupt = @import("interrupt.zig");
pub const mailbox = @import("mailbox.zig");
pub const watchdog = @import("watchdog.zig");

pub fn init() void {
    uart.init();
    interrupt.init();
}

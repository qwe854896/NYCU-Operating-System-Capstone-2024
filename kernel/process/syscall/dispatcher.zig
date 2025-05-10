const numbers = @import("numbers.zig");
const handlers = @import("handlers.zig");
const TrapFrame = @import("../../asm/processor.zig").TrapFrame;

pub fn dispatch(trap_frame: *TrapFrame) void {
    switch (trap_frame.x8) {
        numbers.getpid => handlers.sysGetpid(trap_frame),
        numbers.uartread => handlers.sysUartread(trap_frame),
        numbers.uartwrite => handlers.sysUartwrite(trap_frame),
        numbers.exec => handlers.sysExec(trap_frame),
        numbers.fork => handlers.sysFork(trap_frame),
        numbers.exit => handlers.sysExit(trap_frame),
        numbers.mbox_call => handlers.sysMboxCall(trap_frame),
        numbers.kill => handlers.sysKill(trap_frame),
        numbers.signal => handlers.sysSignal(trap_frame),
        numbers.sigkill => handlers.sysSigkill(trap_frame),
        numbers.sigreturn => handlers.sysSigreturn(trap_frame),
        else => {
            trap_frame.x0 = @bitCast(@as(isize, -38)); // -ENOSYS
        },
    }
}

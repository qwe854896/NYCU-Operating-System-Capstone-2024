const numbers = @import("numbers.zig");
const handlers = @import("handlers.zig");
const TrapFrame = @import("../../arch/aarch64/processor.zig").TrapFrame;

pub fn dispatch(trap_frame: *TrapFrame) void {
    switch (trap_frame.x8) {
        numbers.sys_getpid => handlers.sysGetpid(trap_frame),
        numbers.sys_uart_read => handlers.sysUartread(trap_frame),
        numbers.sys_uart_write => handlers.sysUartwrite(trap_frame),
        numbers.sys_exec => handlers.sysExec(trap_frame),
        numbers.sys_fork => handlers.sysFork(trap_frame),
        numbers.sys_exit => handlers.sysExit(trap_frame),
        numbers.sys_mbox_call => handlers.sysMboxCall(trap_frame),
        numbers.sys_kill => handlers.sysKill(trap_frame),
        numbers.sys_signal => handlers.sysSignal(trap_frame),
        numbers.sys_sigkill => handlers.sysSigkill(trap_frame),
        numbers.sys_sigreturn => handlers.sysSigreturn(trap_frame),
        numbers.sys_mmap => handlers.sysMmap(trap_frame),
        else => {
            trap_frame.x0 = @bitCast(@as(isize, -38)); // -ENOSYS
        },
    }
}

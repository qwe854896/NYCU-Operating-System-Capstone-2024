pub const sys_getpid = 0;
pub const sys_uart_read = 1;
pub const sys_uart_write = 2;
pub const sys_exec = 3;
pub const sys_fork = 4;
pub const sys_exit = 5;
pub const sys_mbox_call = 6;
pub const sys_kill = 7;
pub const sys_signal = 8;
pub const sys_sigkill = 9;
pub const sys_mmap = 10;
pub const sys_sigreturn = 20;

pub const signals = struct {
    pub const sigkill: i32 = 9;
};

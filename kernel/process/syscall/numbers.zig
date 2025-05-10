pub const getpid = 0;
pub const uartread = 1;
pub const uartwrite = 2;
pub const exec = 3;
pub const fork = 4;
pub const exit = 5;
pub const mbox_call = 6;
pub const kill = 7;
pub const signal = 8;
pub const sigkill = 9;
pub const sigreturn = 20;

pub const signals = struct {
    pub const sigkill: i32 = 9;
};

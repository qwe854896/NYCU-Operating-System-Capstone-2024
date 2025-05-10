const numbers = @import("numbers.zig");
const syscall = @import("../../arch/aarch64/syscall.zig");

// 0: int getpid()
pub fn getpid() i32 {
    return @intCast(syscall.syscall0(numbers.sys_getpid));
}

// 1: size_t uartread(char buf[], size_t size)
pub fn uartread(buf: []u8, size: usize) u64 {
    if (size > buf.len) @panic("Buffer overflow");
    return syscall.syscall2(numbers.sys_uart_read, @intFromPtr(buf.ptr), size);
}

// 2: size_t uartwrite(const char buf[], size_t size)
pub fn uartwrite(buf: []const u8, size: usize) u64 {
    if (size > buf.len) @panic("Buffer overflow");
    return syscall.syscall2(numbers.sys_uart_write, @intFromPtr(buf.ptr), size);
}

// 3: int exec(const char *name, char *const argv[])
pub fn exec(name: []const u8, argv: ?[*]const [*:0]const u8) i32 {
    return @intCast(syscall.syscall2(numbers.sys_exec, @intFromPtr(name.ptr), @intFromPtr(argv)));
}

// 4: int fork()
pub fn fork() i32 {
    return @intCast(syscall.syscall0(numbers.sys_fork));
}

// 5: void exit(int status)
pub fn exit(status: i32) noreturn {
    _ = syscall.syscall1(numbers.sys_exit, @intCast(status));
    unreachable;
}

// 6: int mbox_call(unsigned char ch, unsigned int *mbox)
pub fn mbox_call(ch: u8, mailbox: []u32) i32 {
    return @intCast(syscall.syscall2(numbers.sys_mbox_call, ch, @intFromPtr(mailbox.ptr)));
}

// 7: void kill(int pid)
pub fn kill(pid: i32) void {
    _ = syscall.syscall1(numbers.sys_kill, @bitCast(pid));
}

// Keep sysSigreturn as re-export
pub const sysSigreturn = syscall.sysSigreturn;

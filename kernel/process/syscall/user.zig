// 0: int getpid()
pub fn getpid() i32 {
    var x0: i32 = undefined;
    asm volatile (
        \\ mov x8, #0
        \\ svc 0
        \\ mov %[ret], x0
        : [ret] "=r" (x0),
        :
        : "x8"
    );
    return x0;
}

// 1: size_t uartread(char buf[], size_t size)
pub fn uartread(buf: []u8, size: usize) u64 {
    if (size > buf.len) {
        @panic("Buffer size is too small!");
    }
    var x0: u64 = undefined;
    asm volatile (
        \\ mov x0, %[x0]
        \\ mov x1, %[x1]
        \\ mov x8, #1
        \\ svc 0
        \\ mov %[ret], x0
        : [ret] "=r" (x0),
        : [x0] "r" (@intFromPtr(buf.ptr)),
          [x1] "r" (size),
        : "x0", "x1", "x8"
    );
    return x0;
}

// 2: size_t uartwrite(const char buf[], size_t size)
pub fn uartwrite(buf: []const u8, size: usize) u64 {
    if (size > buf.len) {
        @panic("Buffer size is too small!");
    }
    var x0: u64 = undefined;
    asm volatile (
        \\ mov x0, %[x0]
        \\ mov x1, %[x1]
        \\ mov x8, #2
        \\ svc 0
        \\ mov %[ret], x0
        : [ret] "=r" (x0),
        : [x0] "r" (@intFromPtr(buf.ptr)),
          [x1] "r" (size),
        : "x0", "x1", "x8"
    );
    return x0;
}

// 3: int exec(const char *name, char *const argv[])
pub fn exec(name: []const u8, argv: ?[*]const [*:0]const u8) i32 {
    var x0: i32 = undefined;
    asm volatile (
        \\ mov x0, %[x0]
        \\ mov x1, %[x1]
        \\ mov x8, #3
        \\ svc 0
        \\ mov %[ret], x0
        : [ret] "=r" (x0),
        : [x0] "r" (@intFromPtr(name.ptr)),
          [x1] "r" (@intFromPtr(argv)),
        : "x0", "x1", "x8"
    );
    return x0;
}

// 4: int fork()
pub fn fork() i32 {
    var x0: i32 = undefined;
    asm volatile (
        \\ mov x8, #4
        \\ svc 0
        \\ mov %[ret], x0
        : [ret] "=r" (x0),
        :
        : "x8"
    );
    return x0;
}

// 5: void exit(int status)
pub fn exit(status: i32) void {
    asm volatile (
        \\ mov x0, %[x0]
        \\ mov x8, #5
        \\ svc 0
        :
        : [x0] "r" (status),
        : "x0", "x8"
    );
}

// 6: int mbox_call(unsigned char ch, unsigned int *mbox)
pub fn mbox_call(ch: u8, mailbox: []u32) i32 {
    var x0: i32 = undefined;
    asm volatile (
        \\ mov x0, %[x0]
        \\ mov x1, %[x1]
        \\ mov x8, #6
        \\ svc 0
        \\ mov %[ret], x0
        : [ret] "=r" (x0),
        : [x0] "r" (ch),
          [x1] "r" (@intFromPtr(mailbox.ptr)),
        : "x0", "x1", "x8"
    );
    return x0;
}

// 7: void kill(int pid)
pub fn kill(pid: i32) void {
    asm volatile (
        \\ mov x0, %[x0]
        \\ mov x8, #7
        \\ svc 0
        :
        : [x0] "r" (pid),
        : "x0", "x8"
    );
}

// 8: void signal(int SIGNAL, void (*handler)())

// 9: void sigkill(int pid, int SIGNAL)

// 20: void sigreturn()
pub extern fn sysSigreturn() void;
comptime {
    asm (
        \\ sysSigreturn:
        \\  mov x8, #20
        \\  svc 0
    );
}

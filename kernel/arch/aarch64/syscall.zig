pub fn syscall0(number: usize) usize {
    var result: usize = undefined;
    asm volatile (
        \\ mov x8, %[nr]
        \\ svc 0
        \\ mov %[ret], x0
        : [ret] "=r" (result),
        : [nr] "r" (number),
        : "x8", "memory"
    );
    return result;
}

pub fn syscall1(number: usize, arg1: usize) usize {
    var result: usize = undefined;
    asm volatile (
        \\ mov x0, %[arg1]
        \\ mov x8, %[nr]
        \\ svc 0
        \\ mov %[ret], x0
        : [ret] "=r" (result),
        : [nr] "r" (number),
          [arg1] "r" (arg1),
        : "x0", "x8", "memory"
    );
    return result;
}

pub fn syscall2(number: usize, arg1: usize, arg2: usize) usize {
    var result: usize = undefined;
    asm volatile (
        \\ mov x0, %[arg1]
        \\ mov x1, %[arg2]
        \\ mov x8, %[nr]
        \\ svc 0
        \\ mov %[ret], x0
        : [ret] "=r" (result),
        : [nr] "r" (number),
          [arg1] "r" (arg1),
          [arg2] "r" (arg2),
        : "x0", "x1", "x8", "memory"
    );
    return result;
}

pub fn syscall3(number: usize, arg1: usize, arg2: usize, arg3: usize) usize {
    var result: usize = undefined;
    asm volatile (
        \\ mov x0, %[arg1]
        \\ mov x1, %[arg2]
        \\ mov x2, %[arg3]
        \\ mov x8, %[nr]
        \\ svc 0
        \\ mov %[ret], x0
        : [ret] "=r" (result),
        : [nr] "r" (number),
          [arg1] "r" (arg1),
          [arg2] "r" (arg2),
          [arg3] "r" (arg3),
        : "x0", "x1", "x2", "x8", "memory"
    );
    return result;
}

export fn sysSigreturn() callconv(.Naked) void {
    asm volatile (
        \\ mov x8, #20
        \\ svc 0
        \\ ret
    );
}

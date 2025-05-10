pub fn getSpsrEl1() usize {
    var value: usize = undefined;
    asm volatile ("mrs %[v], spsr_el1"
        : [v] "=r" (value),
    );
    return value;
}

pub fn getElrEl1() usize {
    var value: usize = undefined;
    asm volatile ("mrs %[v], elr_el1"
        : [v] "=r" (value),
    );
    return value;
}

pub fn setElrEl1(value: usize) void {
    asm volatile ("msr elr_el1, %[v]"
        :
        : [v] "r" (value),
    );
}

pub fn getEsrEl1() usize {
    var value: usize = undefined;
    asm volatile ("mrs %[v], esr_el1"
        : [v] "=r" (value),
    );
    return value;
}

pub fn getSpEl0() usize {
    var value: usize = undefined;
    asm volatile ("mrs %[v], sp_el0"
        : [v] "=r" (value),
    );
    return value;
}

pub fn setSpEl0(value: usize) void {
    asm volatile ("msr sp_el0, %[v]"
        :
        : [v] "r" (value),
    );
}
pub fn getCntfrqEl0() usize {
    var value: usize = undefined;
    asm volatile ("mrs %[v], cntfrq_el0"
        : [v] "=r" (value),
    );
    return value;
}

pub fn setCntpTvalEl0(value: usize) void {
    asm volatile ("msr cntp_tval_el0, %[v]"
        :
        : [v] "r" (value),
    );
}

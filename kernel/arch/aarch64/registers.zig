pub fn getEsrEl1() usize {
    var value: usize = undefined;
    asm volatile ("mrs %[v], esr_el1"
        : [v] "=r" (value),
    );
    return value;
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

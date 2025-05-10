pub fn jumpToUserMode(entry: usize, stack: usize) void {
    asm volatile (
        \\ ldr lr, =thread_return_label
        \\ mov x1, 0x0
        \\ msr spsr_el1, x1
        \\ mov x1, %[entry]
        \\ msr elr_el1, x1
        \\ mov x1, %[stack]
        \\ msr sp_el0, x1
        \\ eret
        \\ thread_return_label:
        :
        : [entry] "r" (entry),
          [stack] "r" (stack),
        : "x1"
    );
}

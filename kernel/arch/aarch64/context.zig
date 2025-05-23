pub extern fn switchTo(usize, usize) void;
pub extern fn getCurrent() usize;

pub fn invalidateCache() void {
    asm volatile (
        \\ tlbi vmalle1is     // Invalidate all TLB entries
        \\ dsb ish            // Ensure TLB invalidation
        \\ isb                // Synchronize pipeline
    );
}

pub fn switchTtbr0(next_pgd: usize) void {
    var current_ttbr0: usize = 0;
    asm volatile ("mrs %[cur], ttbr0_el1"
        : [cur] "=r" (current_ttbr0),
    );
    if (current_ttbr0 != next_pgd) {
        asm volatile (
            \\ mov x0, %[arg0]
            \\ dsb ish            // Ensure write completion
            \\ msr ttbr0_el1, x0  // Update translation table
            :
            : [arg0] "r" (next_pgd),
            : "x0"
        );
        invalidateCache();
    }
}

comptime {
    asm (
        \\ .global switchTo
        \\ switchTo:
        \\     stp x19, x20, [x0, 16 * 0]
        \\     stp x21, x22, [x0, 16 * 1]
        \\     stp x23, x24, [x0, 16 * 2]
        \\     stp x25, x26, [x0, 16 * 3]
        \\     stp x27, x28, [x0, 16 * 4]
        \\     stp fp, lr, [x0, 16 * 5]
        \\     mov x9, sp
        \\     str x9, [x0, 16 * 6]
        \\
        \\     ldp x19, x20, [x1, 16 * 0]
        \\     ldp x21, x22, [x1, 16 * 1]
        \\     ldp x23, x24, [x1, 16 * 2]
        \\     ldp x25, x26, [x1, 16 * 3]
        \\     ldp x27, x28, [x1, 16 * 4]
        \\     ldp fp, lr, [x1, 16 * 5]
        \\     ldr x9, [x1, 16 * 6]
        \\     mov sp,  x9
        \\     msr tpidr_el1, x1
        \\     ret
        \\
        \\ .global getCurrent
        \\ getCurrent:
        \\     mrs x0, tpidr_el1
        \\     ret
    );
}

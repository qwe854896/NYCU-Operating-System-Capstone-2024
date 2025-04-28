const std = @import("std");
const log = std.log.scoped(.interrupt);
const mmio = @import("mmio.zig");
const Register = mmio.Register;

const base_address = mmio.base_address + 0xB000;

const irq_enable_1 = Register.init(base_address + 0x210);

pub fn init() void {
    var reg = irq_enable_1.readRaw();
    reg |= (0b1 << 29); // Aux int
    irq_enable_1.writeRaw(reg);
}

export fn exceptionEntry() void {
    var spsr_el1: usize = undefined;
    var elr_el1: usize = undefined;
    var esr_el1: usize = undefined;

    asm volatile (
        \\ mrs %[arg0], spsr_el1
        \\ mrs %[arg1], elr_el1
        \\ mrs %[arg2], esr_el1
        : [arg0] "=r" (spsr_el1),
          [arg1] "=r" (elr_el1),
          [arg2] "=r" (esr_el1),
    );

    log.info("Exception:", .{});
    log.info("  SPSR_EL1: 0x{b}", .{spsr_el1});
    log.info("  ELR_EL1: 0x{X}", .{elr_el1});
    log.info("  ESR_EL1: 0x{b}", .{esr_el1});
}

export fn coreTimerEntry() void {
    var cntpct_el0: usize = undefined;
    var cntfrq_el0: usize = undefined;

    asm volatile (
        \\ mrs %[arg0], cntpct_el0
        \\ mrs %[arg1], cntfrq_el0
        \\ mov x0, 2
        \\ mul x0, x0, %[arg1]
        \\ msr cntp_tval_el0, x0
        : [arg0] "=r" (cntpct_el0),
          [arg1] "=r" (cntfrq_el0),
        :
        : "x0"
    );

    log.info("Core Timer Exception!", .{});
    log.info("  {} seconds after booting...", .{cntpct_el0 / cntfrq_el0});
}

comptime {
    // Avoid using x0 as it stores the address of dtb
    asm (
        \\ from_el2_to_el1:
        \\      mov x1, #0x00300000 // No trap to all NEON & FP instructions
        \\      msr cpacr_el1, x1   // References: https://developer.arm.com/documentation/ka006062/latest/
        \\      adr x1, exception_vector_table
        \\      msr vbar_el1, x1
        \\      mov x1, (1 << 31)
        \\      msr hcr_el2, x1
        \\      mov x1, 0x3c5
        \\      msr spsr_el2, x1
        \\      msr elr_el2, lr
        \\      eret
    );

    // Avoid using x0 as it stores the address of dtb
    asm (
        \\ core_timer_enable:
        \\      mov x1, 1
        \\      msr cntp_ctl_el0, x1 // enable
        \\      mrs x1, cntfrq_el0
        \\      msr cntp_tval_el0, x1 // set expired time
        \\      mov x1, 2
        \\      ldr x2, =0x40000040 // CORE0_TIMER_IRQ_CTRL
        \\      str w1, [x2] // unmask timer interrupt
        \\      ret
    );

    asm (
        \\ .align 11 // vector table should be aligned to 0x800
        \\ exception_vector_table:
        \\      b exception_handler // branch to a handler function.
        \\      .align 7 // entry size is 0x80, .align will pad 0
        \\      b exception_handler
        \\      .align 7
        \\      b exception_handler
        \\      .align 7
        \\      b exception_handler
        \\      .align 7
        \\
        \\      b exception_handler
        \\      .align 7
        \\      b exception_handler
        \\      .align 7
        \\      b exception_handler
        \\      .align 7
        \\      b exception_handler
        \\      .align 7
        \\
        \\      b exception_handler
        \\      .align 7
        \\      b core_timer_handler
        \\      .align 7
        \\      b exception_handler
        \\      .align 7
        \\      b exception_handler
        \\      .align 7
        \\
        \\      b exception_handler
        \\      .align 7
        \\      b exception_handler
        \\      .align 7
        \\      b exception_handler
        \\      .align 7
        \\      b exception_handler
        \\      .align 7
    );

    asm (
        \\ .macro save_all
        \\      sub sp, sp, 32 * 8
        \\      stp x0, x1, [sp ,16 * 0]
        \\      stp x2, x3, [sp ,16 * 1]
        \\      stp x4, x5, [sp ,16 * 2]
        \\      stp x6, x7, [sp ,16 * 3]
        \\      stp x8, x9, [sp ,16 * 4]
        \\      stp x10, x11, [sp ,16 * 5]
        \\      stp x12, x13, [sp ,16 * 6]
        \\      stp x14, x15, [sp ,16 * 7]
        \\      stp x16, x17, [sp ,16 * 8]
        \\      stp x18, x19, [sp ,16 * 9]
        \\      stp x20, x21, [sp ,16 * 10]
        \\      stp x22, x23, [sp ,16 * 11]
        \\      stp x24, x25, [sp ,16 * 12]
        \\      stp x26, x27, [sp ,16 * 13]
        \\      stp x28, x29, [sp ,16 * 14]
        \\      str x30, [sp, 16 * 15]
        \\ .endm
    );

    asm (
        \\ .macro load_all
        \\      ldp x0, x1, [sp ,16 * 0]
        \\      ldp x2, x3, [sp ,16 * 1]
        \\      ldp x4, x5, [sp ,16 * 2]
        \\      ldp x6, x7, [sp ,16 * 3]
        \\      ldp x8, x9, [sp ,16 * 4]
        \\      ldp x10, x11, [sp ,16 * 5]
        \\      ldp x12, x13, [sp ,16 * 6]
        \\      ldp x14, x15, [sp ,16 * 7]
        \\      ldp x16, x17, [sp ,16 * 8]
        \\      ldp x18, x19, [sp ,16 * 9]
        \\      ldp x20, x21, [sp ,16 * 10]
        \\      ldp x22, x23, [sp ,16 * 11]
        \\      ldp x24, x25, [sp ,16 * 12]
        \\      ldp x26, x27, [sp ,16 * 13]
        \\      ldp x28, x29, [sp ,16 * 14]
        \\      ldr x30, [sp, 16 * 15]
        \\      add sp, sp, 32 * 8
        \\ .endm
    );

    asm (
        \\ exception_handler:
        \\      save_all
        \\      bl exceptionEntry
        \\      load_all
        \\      eret
    );

    asm (
        \\ core_timer_handler:
        \\      save_all
        \\      bl coreTimerEntry
        \\      load_all
        \\      eret
    );
}

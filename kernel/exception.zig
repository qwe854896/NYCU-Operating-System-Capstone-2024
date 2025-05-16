const std = @import("std");
const sched = @import("sched.zig");
const processor = @import("arch/aarch64/processor.zig");
const registers = @import("arch/aarch64/registers.zig");
const dispatcher = @import("process/syscall/dispatcher.zig");
const thread = @import("thread.zig");
const log = std.log.scoped(.exception);

const TrapFrame = processor.TrapFrame;
const ThreadContext = thread.ThreadContext;

export fn exceptionEntry(sp: usize) void {
    const trap_frame: *TrapFrame = @ptrFromInt(sp);
    var self: *ThreadContext = thread.threadFromCurrent();
    self.trap_frame = trap_frame;

    log.info("Exception occurred! tid: {}", .{self.id});
    log.info("Exception:", .{});
    log.info("  SPSR_EL1: 0b{b:0>32}", .{trap_frame.spsr_el1});
    log.info("  ELR_EL1: 0x{X}", .{trap_frame.elr_el1});
    log.info("  ESR_EL1: 0b{b:0>32}", .{registers.getEsrEl1()});

    while (true) {
        asm volatile ("nop");
    }
}

export fn coreTimerEntry(sp: usize) void {
    const trap_frame: *TrapFrame = @ptrFromInt(sp);
    var self: *ThreadContext = thread.threadFromCurrent();
    self.trap_frame = trap_frame;

    sched.schedule();

    registers.setCntpTvalEl0(registers.getCntfrqEl0() >> 5);
}

export fn syscallEntry(sp: usize) void {
    const trap_frame: *TrapFrame = @ptrFromInt(sp);
    var self: *ThreadContext = thread.threadFromCurrent();
    self.trap_frame = trap_frame;

    if ((registers.getEsrEl1() >> 26) != 0b010101) {
        log.info("Exception occurred! tid: {}", .{self.id});
        log.info("Exception:", .{});
        log.info("  SPSR_EL1: 0b{b:0>32}", .{trap_frame.spsr_el1});
        log.info("  ELR_EL1: 0x{X}", .{trap_frame.elr_el1});
        log.info("  ESR_EL1: 0b{b:0>32}", .{registers.getEsrEl1()});
        while (true) {
            asm volatile ("nop");
        }
    }

    dispatcher.dispatch(trap_frame);
}

// Avoid using x0 as it stores the address of dtb
pub fn fromEl2ToEl1() callconv(.Naked) void {
    asm volatile (
        \\      mov x1, #0x00300000 // No trap to all NEON & FP instructions
        \\      msr cpacr_el1, x1   // References: https://developer.arm.com/documentation/ka006062/latest/
        \\      adr x1, exception_vector_table
        \\      ldr x2, =0xffff000000000000
        \\      add x1, x1, x2
        \\      msr vbar_el1, x1
        \\      mov x1, (1 << 31)
        \\      msr hcr_el2, x1
        \\      mov x1, 0x3c5
        \\      msr spsr_el2, x1
        \\      msr elr_el2, lr
        \\      eret
    );
}

// Avoid using x0 as it stores the address of dtb
pub fn coreTimerEnable() callconv(.Naked) void {
    asm volatile (
        \\      mov x1, 1
        \\      msr cntp_ctl_el0, x1 // enable
        \\      mrs x1, cntfrq_el0
        \\      lsr x1, x1, #5
        \\      msr cntp_tval_el0, x1
        \\      mrs x1, cntkctl_el1
        \\      orr x1, x1, #1
        \\      msr cntkctl_el1, x1
        \\      mov x1, 2
        \\      ldr x2, =0x40000040 // CORE0_TIMER_IRQ_CTRL
        \\      str w1, [x2] // unmask timer interrupt
        \\      ret
    );
}

comptime {
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
        \\      b syscall_handler
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
        \\      sub sp, sp, 34 * 8
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
        \\      mrs x9, elr_el1
        \\      mrs x10, sp_el0
        \\      mrs x11, spsr_el1
        \\      stp x30, x9, [sp ,16 * 15]
        \\      stp x10, x11, [sp ,16 * 16]
        \\ .endm
    );

    asm (
        \\ .macro load_all
        \\      ldp x30, x9, [sp ,16 * 15]
        \\      ldp x10, x11, [sp ,16 * 16]
        \\      msr elr_el1, x9
        \\      msr sp_el0, x10
        \\      msr spsr_el1, x11
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
        \\      add sp, sp, 34 * 8
        \\ .endm
    );

    asm (
        \\ exception_handler:
        \\      save_all
        \\      mov x0, sp
        \\      bl exceptionEntry
        \\      load_all
        \\      eret
    );

    asm (
        \\ core_timer_handler:
        \\      save_all
        \\      mov x0, sp
        \\      bl coreTimerEntry
        \\      load_all
        \\      eret
    );

    asm (
        \\ syscall_handler:
        \\      save_all
        \\      mov x0, sp
        \\      bl syscallEntry
        \\      load_all
        \\      eret
    );
}

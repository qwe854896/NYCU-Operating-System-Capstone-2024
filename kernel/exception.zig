const std = @import("std");
const drivers = @import("drivers");
const log = std.log.scoped(.exception);
const processor = @import("asm/processor.zig");
const context = @import("asm/context.zig");
const syscall = @import("syscall.zig");
const sched = @import("sched.zig");
const uart = drivers.uart;
const mailbox = drivers.mailbox;

const TrapFrame = processor.TrapFrame;
const Task = sched.Task;

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

    const self: *Task = @ptrFromInt(context.getCurrent());
    log.info("Exception occurred! tid: {}", .{self.id});

    log.info("Exception:", .{});
    log.info("  SPSR_EL1: 0b{b:0>32}", .{spsr_el1});
    log.info("  ELR_EL1: 0x{X}", .{elr_el1});
    log.info("  ESR_EL1: 0b{b:0>32}", .{esr_el1});

    while (true) {
        asm volatile ("nop");
    }
}

export fn coreTimerEntry(sp: usize) void {
    const trap_frame: *TrapFrame = @ptrFromInt(sp);
    var self: *Task = @ptrFromInt(context.getCurrent());
    self.trap_frame = trap_frame;

    sched.schedule();

    asm volatile (
        \\ mrs x0, cntfrq_el0
        \\ lsr x0, x0, #5
        \\ msr cntp_tval_el0, x0
        ::: "x0");
}

fn sysExitEntry() noreturn {
    sched.endThread();
}

fn sysGetpidEntry(trap_frame: *TrapFrame) void {
    const self: *Task = @ptrFromInt(context.getCurrent());
    trap_frame.x0 = self.id;
}

fn yieldRecv() u8 {
    while (!uart.aux_mu_lsr.read().rx_ready) {
        sched.schedule();
    }
    return uart.aux_mu_io.read().data;
}

fn sysUartReadEntry(trap_frame: *TrapFrame) void {
    var buf: []u8 = @as([*]u8, @ptrFromInt(trap_frame.x0))[0..trap_frame.x1];
    var i: usize = 0;
    while (i < trap_frame.x1) : (i += 1) {
        buf[i] = yieldRecv();
    }
    trap_frame.x0 = i;
}

fn sysUartwriteEntry(trap_frame: *TrapFrame) void {
    if (trap_frame.x0 == 0) {
        trap_frame.x0 = @bitCast(@as(i64, -1));
        return;
    }
    const buf: []const u8 = @as([*]const u8, @ptrFromInt(trap_frame.x0))[0..trap_frame.x1];
    var i: usize = 0;
    while (i < trap_frame.x1) : (i += 1) {
        uart.send(buf[i]);
    }
    trap_frame.x0 = i;
}

fn sysForkEntry(trap_frame: *TrapFrame) void {
    sched.forkThread(trap_frame);
}

fn sysKillEntry(trap_frame: *TrapFrame) void {
    sched.killThread(@intCast(trap_frame.x0));
}

fn sysExecEntry(trap_frame: *TrapFrame) void {
    const name: [:0]const u8 = std.mem.span(@as([*:0]const u8, @ptrFromInt(trap_frame.x0)));
    sched.execThread(trap_frame, name);
}

fn sysMboxCallEntry(trap_frame: *TrapFrame) void {
    const retval = mailbox.mboxCall(@intCast(trap_frame.x0), trap_frame.x1);
    trap_frame.x0 = @intCast(@as(u1, @bitCast(retval)));
}

pub fn isSigkillPending() void {
    const self: *Task = @ptrFromInt(context.getCurrent());

    if (!self.has_sigkill) {
        return;
    }
    self.has_sigkill = false;

    var trap_frame = self.trap_frame.?;

    // Save trap_frame onto the top of the user-space stack
    var sp_el0: usize = undefined;
    var elr_el1: usize = undefined;
    asm volatile (
        \\ mrs %[arg0], sp_el0
        \\ mrs %[arg1], elr_el1
        : [arg0] "=r" (sp_el0),
          [arg1] "=r" (elr_el1),
    );
    trap_frame.elr_el1 = elr_el1;

    log.info("Before sigreturn: 0x{x}", .{elr_el1});

    sp_el0 -= @sizeOf(TrapFrame);
    @as(*TrapFrame, @ptrFromInt(sp_el0)).* = trap_frame.*;

    // move user-space stack, also update
    asm volatile (
        \\ msr sp_el0, %[arg0]
        \\ msr elr_el1, %[arg1]
        :
        : [arg0] "r" (sp_el0),
          [arg1] "r" (self.sigkill_handler),
    );

    trap_frame.x30 = @intFromPtr(&syscall.sysSigreturn); // lr
}

fn sysSigKillEntry(trap_frame: *TrapFrame) void {
    const pid: u32 = @intCast(trap_frame.x0);
    const signal: i32 = @intCast(trap_frame.x1);
    const thread = sched.findThreadByPid(pid);
    if (thread) |t| {
        if (signal == syscall.sigkill) {
            if (t.data.sigkill_handler == 0) {
                sched.killThread(@intCast(trap_frame.x0));
            } else {
                t.data.has_sigkill = true;
            }
        }
    }
}

fn sysSigreturnEntry(trap_frame: *TrapFrame) void {
    var sp_el0: usize = undefined;
    asm volatile (
        \\ mrs %[arg0], sp_el0
        : [arg0] "=r" (sp_el0),
    );

    trap_frame.* = @as(*TrapFrame, @ptrFromInt(sp_el0)).*;
    sp_el0 += @sizeOf(TrapFrame);

    const elr_el1 = trap_frame.elr_el1;
    log.info("After sigreturn: 0x{x}", .{elr_el1});

    asm volatile (
        \\ msr sp_el0, %[arg0]
        \\ msr elr_el1, %[arg1]
        :
        : [arg0] "r" (sp_el0),
          [arg1] "r" (elr_el1),
    );
}

fn sysSignalEntry(trap_frame: *TrapFrame) void {
    const self: *Task = @ptrFromInt(context.getCurrent());
    const signal: i32 = @intCast(trap_frame.x0);
    const handler: usize = @intCast(trap_frame.x1);

    log.info("Set signal {} handler of {} to 0x{}", .{ signal, self.id, handler });
    if (signal == syscall.sigkill) {
        self.sigkill_handler = handler;
    }
}

export fn syscallEntry(sp: usize) void {
    const trap_frame: *TrapFrame = @ptrFromInt(sp);
    var self: *Task = @ptrFromInt(context.getCurrent());
    self.trap_frame = trap_frame;

    var elr_el1: usize = undefined;

    asm volatile (
        \\ mrs %[arg0], elr_el1
        : [arg0] "=r" (elr_el1),
    );

    // mrs x0, CurrentEL
    const inst: *u32 = @ptrFromInt(elr_el1);
    if (inst.* == 0xd5384240) {
        asm volatile (
            \\ msr elr_el1, %[arg0]
            :
            : [arg0] "r" (elr_el1 + 4),
        );
        trap_frame.x0 = 0 << 2;
        return;
    }

    switch (trap_frame.x8) {
        syscall.sys_getpid => sysGetpidEntry(trap_frame),
        syscall.sys_fork => sysForkEntry(trap_frame),
        syscall.sys_uartread => sysUartReadEntry(trap_frame),
        syscall.sys_uartwrite => sysUartwriteEntry(trap_frame),
        syscall.sys_mbox_call => sysMboxCallEntry(trap_frame),
        syscall.sys_exit => sysExitEntry(),
        syscall.sys_kill => sysKillEntry(trap_frame),
        syscall.sys_exec => sysExecEntry(trap_frame),
        syscall.sys_sigkill => sysSigKillEntry(trap_frame),
        syscall.sys_signal => sysSignalEntry(trap_frame),
        syscall.sys_sigreturn => sysSigreturnEntry(trap_frame),
        else => {
            log.info("Unknown syscall number: {}", .{trap_frame.x8});
            while (true) {
                asm volatile ("nop");
            }
        },
    }
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

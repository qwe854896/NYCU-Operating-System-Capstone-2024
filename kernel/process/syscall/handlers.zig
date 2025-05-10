const std = @import("std");
const drivers = @import("drivers");
const processor = @import("../../asm/processor.zig");
const sched = @import("../../sched.zig");
const context = @import("../../asm/context.zig");
const uart = drivers.uart;
const mailbox = drivers.mailbox;
const numbers = @import("numbers.zig");

const Task = sched.Task;
const TrapFrame = processor.TrapFrame;

pub fn sysGetpid(trap_frame: *TrapFrame) void {
    const self: *Task = @ptrFromInt(context.getCurrent());
    trap_frame.x0 = self.id;
}

fn yieldRecv() u8 {
    while (!uart.aux_mu_lsr.read().rx_ready) {
        sched.schedule();
    }
    return uart.aux_mu_io.read().data;
}

pub fn sysUartread(trap_frame: *TrapFrame) void {
    var buf: []u8 = @as([*]u8, @ptrFromInt(trap_frame.x0))[0..trap_frame.x1];
    var i: usize = 0;
    while (i < trap_frame.x1) : (i += 1) {
        buf[i] = yieldRecv();
    }
    trap_frame.x0 = i;
}

pub fn sysUartwrite(trap_frame: *TrapFrame) void {
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

pub fn sysFork(trap_frame: *TrapFrame) void {
    sched.forkThread(trap_frame);
}

pub fn sysExit(_: *TrapFrame) void {
    sched.endThread();
}

pub fn sysKill(trap_frame: *TrapFrame) void {
    sched.killThread(@intCast(trap_frame.x0));
}

pub fn sysExec(trap_frame: *TrapFrame) void {
    const name: [:0]const u8 = std.mem.span(@as([*:0]const u8, @ptrFromInt(trap_frame.x0)));
    sched.execThread(trap_frame, name);
}

pub fn sysMboxCall(trap_frame: *TrapFrame) void {
    const retval = mailbox.mboxCall(@intCast(trap_frame.x0), trap_frame.x1);
    trap_frame.x0 = @intCast(@as(u1, @bitCast(retval)));
}

pub fn sysSigkill(trap_frame: *TrapFrame) void {
    const pid: u32 = @intCast(trap_frame.x0);
    const signal: i32 = @intCast(trap_frame.x1);
    const thread = sched.findThreadByPid(pid);
    if (thread) |t| {
        if (signal == numbers.signals.sigkill) {
            if (t.data.sigkill_handler == 0) {
                sched.killThread(@intCast(trap_frame.x0));
            } else {
                t.data.has_sigkill = true;
            }
        }
    }
}

fn userSigreturnStub() callconv(.Naked) void {
    asm volatile (
        \\ mov x8, #20
        \\ svc 0
    );
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

    trap_frame.x30 = @intFromPtr(&userSigreturnStub); // lr
}

pub fn sysSignal(trap_frame: *TrapFrame) void {
    const self: *Task = @ptrFromInt(context.getCurrent());
    const signal: i32 = @intCast(trap_frame.x0);
    const handler: usize = @intCast(trap_frame.x1);

    if (signal == numbers.signals.sigkill) {
        self.sigkill_handler = handler;
    }
}

pub fn sysSigreturn(trap_frame: *TrapFrame) void {
    var sp_el0: usize = undefined;
    asm volatile (
        \\ mrs %[arg0], sp_el0
        : [arg0] "=r" (sp_el0),
    );

    trap_frame.* = @as(*TrapFrame, @ptrFromInt(sp_el0)).*;
    sp_el0 += @sizeOf(TrapFrame);

    const elr_el1 = trap_frame.elr_el1;

    asm volatile (
        \\ msr sp_el0, %[arg0]
        \\ msr elr_el1, %[arg1]
        :
        : [arg0] "r" (sp_el0),
          [arg1] "r" (elr_el1),
    );
}

const std = @import("std");
const drivers = @import("drivers");
const numbers = @import("numbers.zig");
const sched = @import("../../sched.zig");
const context = @import("../../arch/aarch64/context.zig");
const processor = @import("../../arch/aarch64/processor.zig");
const thread = @import("../../thread.zig");
const mm = @import("../../mm.zig");
const main = @import("../../main.zig");
const Vfs = @import("../../fs/Vfs.zig");
const uart = drivers.uart;
const mailbox = drivers.mailbox;
const getSingletonVfs = main.getSingletonVfs;
const getSingletonAllocator = main.getSingletonAllocator;

const TrapFrame = processor.TrapFrame;
const ThreadContext = thread.ThreadContext;

pub fn sysGetpid(trap_frame: *TrapFrame) void {
    const self: *ThreadContext = thread.threadFromCurrent();
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
    thread.fork(trap_frame);
}

pub fn sysExit(_: *TrapFrame) void {
    thread.end();
}

pub fn sysKill(trap_frame: *TrapFrame) void {
    thread.kill(@intCast(trap_frame.x0));
}

pub fn sysExec(trap_frame: *TrapFrame) void {
    const name: [:0]const u8 = std.mem.span(@as([*:0]const u8, @ptrFromInt(trap_frame.x0)));
    thread.exec(trap_frame, name);
}

pub fn sysMboxCall(trap_frame: *TrapFrame) void {
    const self: *ThreadContext = thread.threadFromCurrent();
    const va = trap_frame.x1;
    const pa = mm.map.virtToPhys(self.pgd.?, va) catch {
        trap_frame.x0 = 0;
        return;
    };
    const retval = mailbox.mboxCall(@intCast(trap_frame.x0), pa);
    trap_frame.x0 = @intCast(@as(u1, @bitCast(retval)));
}

pub fn sysSigkill(trap_frame: *TrapFrame) void {
    const pid: u32 = @intCast(trap_frame.x0);
    const signal: i32 = @intCast(trap_frame.x1);
    const ctx = sched.findThreadByPid(pid);
    if (ctx) |t| {
        if (signal == numbers.signals.sigkill) {
            if (t.sigkill_handler == null) {
                thread.kill(@intCast(trap_frame.x0));
            } else {
                t.has_sigkill = true;
            }
        }
    }
}

pub fn userSigreturnStub() callconv(.Naked) void {
    asm volatile (
        \\ mov x8, #20
        \\ svc 0
    );
}

pub fn isSigkillPending() void {
    const self: *ThreadContext = thread.threadFromCurrent();

    if (!self.has_sigkill) {
        return;
    }
    self.has_sigkill = false;

    var trap_frame = self.trap_frame.?;

    // Save trap_frame onto the top of the user-space stack
    const sp_el0: usize = trap_frame.sp_el0 - @sizeOf(TrapFrame);
    @as(*TrapFrame, @ptrFromInt(sp_el0)).* = trap_frame.*;

    trap_frame.x30 = 0xfffffffff000 | (@intFromPtr(&userSigreturnStub) & 0xfff); // lr
    trap_frame.elr_el1 = self.sigkill_handler.?;
    trap_frame.sp_el0 = sp_el0;
}

pub fn sysSignal(trap_frame: *TrapFrame) void {
    const self: *ThreadContext = thread.threadFromCurrent();
    const signal: i32 = @intCast(trap_frame.x0);
    const handler: usize = @intCast(trap_frame.x1);

    if (signal == numbers.signals.sigkill) {
        self.sigkill_handler = handler;
    }
}

pub fn sysSigreturn(trap_frame: *TrapFrame) void {
    const sp_el0: usize = trap_frame.sp_el0;
    trap_frame.* = @as(*TrapFrame, @ptrFromInt(sp_el0)).*;
}

pub fn sysMmap(trap_frame: *TrapFrame) void {
    const MAP_ANONYMOUS = 0x20;
    const MAP_POPULATE = 0x8000;
    const PROT_READ = 0b001;
    const PROT_WRITE = 0b010;
    const PROT_EXEC = 0b100;

    const self: *ThreadContext = thread.threadFromCurrent();
    const addr: usize = @intCast(trap_frame.x0);
    const len: usize = @intCast(trap_frame.x1);
    const prot: i32 = @intCast(trap_frame.x2);
    const flags: i32 = @intCast(trap_frame.x3);
    const fd: i32 = @intCast(trap_frame.x4);
    const file_offset: i32 = @intCast(trap_frame.x5);
    _ = fd;
    _ = file_offset;

    const valid = (flags & MAP_POPULATE) != 0 and (flags & MAP_ANONYMOUS) != 0;
    const read_only = (prot & PROT_WRITE) == 0;
    const exec = (prot & PROT_EXEC) != 0;

    if ((prot & PROT_READ) == 0) {
        trap_frame.x0 = std.mem.alignForwardLog2(addr, 12);
        return;
    }

    trap_frame.x0 = mm.map.mapPages(
        self.pgd.?,
        std.mem.alignForwardLog2(addr, 12),
        std.mem.alignForwardLog2(len, 12),
        0,
        .{
            .valid = valid,
            .user = true,
            .read_only = read_only,
            .el0_exec = exec,
            .el1_exec = false,
            .mair_index = 1,
            .policy = if ((flags & MAP_ANONYMOUS) != 0) .anonymous else .program,
        },
        .PTE,
    ) catch @bitCast(@as(i64, -1));
}

pub fn sysOpen(trap_frame: *TrapFrame) void {
    const self: *ThreadContext = thread.threadFromCurrent();

    const pathname: [:0]const u8 = std.mem.span(@as([*:0]const u8, @ptrFromInt(trap_frame.x0)));
    const flags = trap_frame.x1;

    const resolved_pathname = std.fs.path.resolvePosix(getSingletonAllocator(), &.{ self.cwd.?, pathname }) catch {
        trap_frame.x0 = @bitCast(@as(i64, -1));
        return;
    };
    defer getSingletonAllocator().free(resolved_pathname);

    for (0..16) |fd| {
        if (self.fd_table[fd] == null) {
            self.fd_table[fd] = getSingletonVfs().open(resolved_pathname, @bitCast(@as(u32, @truncate(flags)))) catch {
                trap_frame.x0 = @bitCast(@as(i64, -1));
                return;
            };
            trap_frame.x0 = fd;
            break;
        }
    } else {
        trap_frame.x0 = @bitCast(@as(i64, -1));
        return;
    }
}

pub fn sysClose(trap_frame: *TrapFrame) void {
    const self: *ThreadContext = thread.threadFromCurrent();
    const fd = trap_frame.x0;
    Vfs.close(&self.fd_table[fd].?);
    self.fd_table[fd] = null;
    trap_frame.x0 = 0;
}

pub fn sysWrite(trap_frame: *TrapFrame) void {
    const self: *ThreadContext = thread.threadFromCurrent();
    const fd = trap_frame.x0;
    const buf: []const u8 = @as([*]const u8, @ptrFromInt(trap_frame.x1))[0..trap_frame.x2];
    trap_frame.x0 = Vfs.write(&self.fd_table[fd].?, buf);
}

pub fn sysRead(trap_frame: *TrapFrame) void {
    const self: *ThreadContext = thread.threadFromCurrent();
    const fd = trap_frame.x0;
    const buf: []u8 = @as([*]u8, @ptrFromInt(trap_frame.x1))[0..trap_frame.x2];
    trap_frame.x0 = Vfs.read(&self.fd_table[fd].?, buf);
}

pub fn sysMkdir(trap_frame: *TrapFrame) void {
    const pathname: [:0]const u8 = std.mem.span(@as([*:0]const u8, @ptrFromInt(trap_frame.x0)));
    getSingletonVfs().mkdir(pathname) catch {
        trap_frame.x0 = @bitCast(@as(i64, -1));
        return;
    };
    trap_frame.x0 = 0;
}

pub fn sysMount(trap_frame: *TrapFrame) void {
    const target: [:0]const u8 = std.mem.span(@as([*:0]const u8, @ptrFromInt(trap_frame.x1)));
    const filesystem: [:0]const u8 = std.mem.span(@as([*:0]const u8, @ptrFromInt(trap_frame.x2)));

    _ = getSingletonVfs().mount(
        getSingletonAllocator(),
        target,
        filesystem,
    ) catch {
        trap_frame.x0 = @bitCast(@as(i64, -1));
        return;
    };

    trap_frame.x0 = 0;
}

pub fn sysChdir(trap_frame: *TrapFrame) void {
    const self: *ThreadContext = thread.threadFromCurrent();
    const path: [:0]const u8 = std.mem.span(@as([*:0]const u8, @ptrFromInt(trap_frame.x0)));

    self.cwd = getSingletonAllocator().dupe(u8, path) catch {
        trap_frame.x0 = @bitCast(@as(i64, -1));
        return;
    };
    trap_frame.x0 = 0;
}

pub fn sysIoctl(trap_frame: *TrapFrame) void {
    const self: *ThreadContext = thread.threadFromCurrent();
    const fd = trap_frame.x0;
    trap_frame.x0 = Vfs.ioctl(&self.fd_table[fd].?, trap_frame.x1, trap_frame.x2);
}

pub fn sysLseek64(trap_frame: *TrapFrame) void {
    const self: *ThreadContext = thread.threadFromCurrent();
    const fd = trap_frame.x0;
    trap_frame.x0 = Vfs.lseek64(&self.fd_table[fd].?, @bitCast(trap_frame.x1), @enumFromInt(trap_frame.x2)) catch @bitCast(@as(i64, -1));
}

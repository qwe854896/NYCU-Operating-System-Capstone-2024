const std = @import("std");
const processor = @import("arch/aarch64/processor.zig");
const context = @import("arch/aarch64/context.zig");
const syscall = @import("process/syscall/user.zig");
const sched = @import("sched.zig");
const thread_asm = @import("arch/aarch64/thread.zig");
const mm = @import("mm.zig");
const handlers = @import("process/syscall/handlers.zig");
const main = @import("main.zig");
const Vfs = @import("fs/Vfs.zig");
const jumpToUserMode = thread_asm.jumpToUserMode;
const jumpToKernelMode = thread_asm.jumpToKernelMode;
const getSingletonVfs = main.getSingletonVfs;
const log = std.log.scoped(.thread);

const CpuContext = processor.CpuContext;
const TrapFrame = processor.TrapFrame;

var pid_count: u32 = 0;

fn threadFromCpu(ctx: *CpuContext) *ThreadContext {
    return @ptrFromInt(@intFromPtr(ctx) - @offsetOf(ThreadContext, "cpu_context"));
}

pub fn threadFromCurrent() *ThreadContext {
    const ctx: *CpuContext = @ptrFromInt(context.getCurrent());
    return threadFromCpu(ctx);
}

pub const ThreadContext = struct {
    const Self = @This();

    id: u32,
    entry: usize,

    kernel_stack: []u8,

    pgd: ?*mm.map.PageTable = null,
    program: ?Vfs.File = null,
    trap_frame: ?*processor.TrapFrame = null,
    sigkill_handler: ?usize = null,
    cwd: ?[]u8 = null,
    fd_table: [16]?Vfs.File = undefined,

    ended: bool = false,
    has_sigkill: bool = false,

    allocator: std.mem.Allocator,
    cpu_context: processor.CpuContext,

    pub fn init(allocator: std.mem.Allocator, id: u32, entry: ?*const fn () void) Self {
        var self = Self{
            .id = id,
            .entry = @intFromPtr(entry),
            .kernel_stack = allocator.alignedAlloc(u8, 16, 0x10000) catch {
                @panic("Out of Memory! No buffer for thread kernel stack.");
            },
            .allocator = allocator,
            .cpu_context = .{
                .pc = @intFromPtr(&startKernel),
            },
        };
        self.cpu_context.sp = @as(usize, @intFromPtr(self.kernel_stack.ptr)) + self.kernel_stack.len;
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.kernel_stack);
        if (self.pgd) |pgd| {
            mm.map.deepDestroy(pgd, 3);
            self.allocator.destroy(pgd);
        }
        if (self.program) |*program| {
            Vfs.close(program);
        }
        if (self.cwd) |cwd| {
            self.allocator.free(cwd);
        }
        for (0..16) |fd| {
            if (self.fd_table[fd]) |*file| {
                Vfs.close(file);
            }
        }
    }
};

pub fn create(allocator: std.mem.Allocator, entry: fn () void) void {
    pid_count += 1;
    sched.appendThread(ThreadContext.init(allocator, pid_count, entry));
}

fn startUser() void {
    const self: *ThreadContext = threadFromCurrent();
    const va = 0;
    const v_stack_end = 0xfffffffff000;
    preparePageTableForUser(self.pgd.?);
    context.switchTtbr0(@intFromPtr(self.pgd.?));
    context.invalidateCache();
    jumpToUserMode(va, v_stack_end);
    syscall.exit(0);
    while (true) {
        asm volatile ("nop");
    }
}

fn startKernel() void {
    const self: *ThreadContext = threadFromCurrent();
    jumpToKernelMode(self.entry);
    end();
}

pub fn end() noreturn {
    const self: *ThreadContext = threadFromCurrent();
    self.ended = true;
    while (true) {
        sched.schedule();
    }
}

pub fn fork(parent_trap_frame: *TrapFrame) void {
    const self: *ThreadContext = threadFromCurrent();

    pid_count += 1;

    var t = ThreadContext.init(self.allocator, pid_count, null);

    // Copy Stack
    @memcpy(t.kernel_stack, self.kernel_stack);
    // @memcpy(t.user_stack, self.user_stack);

    t.sigkill_handler = self.sigkill_handler;
    t.program = self.program.?;
    t.cwd = self.allocator.dupe(u8, "/") catch {
        @panic("Out of Memory! No buffer for current working directory.");
    };
    t.fd_table[0] = getSingletonVfs().open("/dev/uart", @bitCast(@as(u32, 0))) catch {
        @panic("Cannot open UART device.");
    };
    t.fd_table[1] = t.fd_table[0];
    t.fd_table[2] = t.fd_table[0];
    for (3..16) |fd| {
        t.fd_table[fd] = null;
    }

    // Handle Child TrapFrame
    t.trap_frame = @ptrFromInt(@intFromPtr(t.kernel_stack.ptr) + (@intFromPtr(parent_trap_frame) - @intFromPtr(self.kernel_stack.ptr)));
    t.trap_frame.?.x0 = 0;

    // Handle Parent TrapFrame
    parent_trap_frame.x0 = t.id;

    t.pgd = self.allocator.create(mm.map.PageTable) catch {
        @panic("Out of Memory! No buffer for thread page table.");
    };
    t.pgd.?.* = mm.map.deepCopy(self.pgd.?, 3);

    context.invalidateCache();
    context.switchTo(context.getCurrent(), context.getCurrent());

    const new_self: *ThreadContext = threadFromCurrent();
    if (@intFromPtr(self) == @intFromPtr(new_self)) {
        t.cpu_context = self.cpu_context;
        t.cpu_context.fp = @intFromPtr(t.kernel_stack.ptr) + (self.cpu_context.fp - @intFromPtr(self.kernel_stack.ptr));
        t.cpu_context.sp = @intFromPtr(t.kernel_stack.ptr) + (self.cpu_context.sp - @intFromPtr(self.kernel_stack.ptr));
        sched.appendThread(t);
    }
}

pub fn exec(_: *TrapFrame, name: []const u8) void {
    const self: *ThreadContext = threadFromCurrent();

    if (self.program) |*program| {
        Vfs.close(program);
    }

    self.program = getSingletonVfs().open(name, @bitCast(@as(u32, 0))) catch {
        @panic("Cannot open program.");
    };

    if (self.pgd) |pgd| {
        mm.map.deepDestroy(pgd, 3);
        self.allocator.destroy(pgd);
    }

    self.pgd = self.allocator.create(mm.map.PageTable) catch {
        @panic("Out of Memory! No buffer for thread page table.");
    };
    self.pgd.?.* = @splat(.{});

    if (self.cwd) |cwd| {
        self.allocator.free(cwd);
    }
    self.cwd = self.allocator.dupe(u8, "/") catch {
        @panic("Out of Memory! No buffer for current working directory.");
    };

    self.fd_table[0] = getSingletonVfs().open("/dev/uart", @bitCast(@as(u32, 0))) catch {
        @panic("Cannot open UART device.");
    };
    self.fd_table[1] = self.fd_table[0];
    self.fd_table[2] = self.fd_table[0];
    for (3..16) |fd| {
        self.fd_table[fd] = null;
    }

    asm volatile (
        \\ mov sp, %[arg0]
        \\ br %[arg1]
        :
        : [arg0] "r" (@intFromPtr(self.kernel_stack.ptr) + self.kernel_stack.len),
          [arg1] "r" (@intFromPtr(&startUser)),
    );

    unreachable;
}

pub fn kill(pid: u32) void {
    const self: *ThreadContext = threadFromCurrent();
    if (pid == self.id) {
        end();
    }
    sched.removeThread(pid);
}

fn preparePageTableForUser(
    pgd: *mm.map.PageTable,
) void {
    const self: *ThreadContext = threadFromCurrent();
    const va = 0;
    const v_stack_start = 0xffffffffb000;
    const v_stack_end = 0xfffffffff000;

    const program_len = Vfs.lseek64(&self.program.?, 0, .seek_end) catch {
        @panic("Cannot get program size.");
    };

    _ = mm.map.mapPages(
        pgd,
        va,
        std.mem.alignForwardLog2(program_len, 12),
        0,
        .{
            .valid = false,
            .user = true,
            .read_only = false,
            .el0_exec = true,
            .el1_exec = false,
            .mair_index = 1,
            .policy = .program,
        },
        .PTE,
    ) catch {
        @panic("Cannot map user program memory!");
    };

    _ = mm.map.mapPages(
        pgd,
        v_stack_start,
        v_stack_end - v_stack_start,
        0,
        .{
            .valid = false,
            .user = true,
            .read_only = false,
            .el0_exec = false,
            .el1_exec = false,
            .mair_index = 1,
            .policy = .anonymous,
        },
        .PTE,
    ) catch {
        @panic("Cannot map user stack memory!");
    };

    _ = mm.map.mapPages(
        pgd,
        0x3C000000,
        0x4000000,
        0xFFFF00003C000000,
        .{
            .valid = false,
            .user = true,
            .read_only = false,
            .el0_exec = false,
            .el1_exec = false,
            .mair_index = 0,
            .policy = .direct,
        },
        .PMD,
    ) catch {
        @panic("Cannot map device memory for user!");
    };
    _ = mm.map.mapPages(
        pgd,
        0xfffffffff000,
        0x1000,
        @intFromPtr(&handlers.userSigreturnStub) & ~@as(u64, 0xfff),
        .{
            .valid = false,
            .user = true,
            .read_only = true,
            .el0_exec = true,
            .el1_exec = false,
            .mair_index = 1,
            .policy = .direct,
        },
        .PTE,
    ) catch |err| {
        log.info("{s}", .{@errorName(err)});
        @panic("Cannot map sigreturn stub for user!");
    };
}

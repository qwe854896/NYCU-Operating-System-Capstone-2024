const std = @import("std");
const processor = @import("arch/aarch64/processor.zig");
const context = @import("arch/aarch64/context.zig");
const syscall = @import("process/syscall/user.zig");
const initrd = @import("fs/initrd.zig");
const sched = @import("sched.zig");
const thread_asm = @import("arch/aarch64/thread.zig");
const mm = @import("mm.zig");
const handlers = @import("process/syscall/handlers.zig");
const jumpToUserMode = thread_asm.jumpToUserMode;
const jumpToKernelMode = thread_asm.jumpToKernelMode;
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
    pgd: *mm.map.PageTable,
    user_stack: []u8,

    program: ?[]u8 = null,
    trap_frame: ?*processor.TrapFrame = null,
    sigkill_handler: ?usize = null,

    ended: bool = false,
    has_sigkill: bool = false,

    allocator: std.mem.Allocator,
    cpu_context: processor.CpuContext,

    pub fn init(allocator: std.mem.Allocator, id: u32, entry: ?*const fn () void, user_stack_size: usize) Self {
        var self = Self{
            .id = id,
            .entry = @intFromPtr(entry),
            .kernel_stack = allocator.alignedAlloc(u8, 16, 0x8000) catch {
                @panic("Out of Memory! No buffer for thread kernel stack.");
            },
            .pgd = allocator.create(mm.map.PageTable) catch {
                @panic("Out of Memory! No buffer for thread page table.");
            },
            .user_stack = allocator.alignedAlloc(u8, 16, user_stack_size) catch {
                @panic("Out of Memory! No buffer for thread user stack.");
            },
            .allocator = allocator,
            .cpu_context = .{
                .pc = @intFromPtr(&startKernel),
            },
        };
        self.pgd.* = @splat(@bitCast(@as(u64, 0)));
        self.cpu_context.sp = @as(usize, @intFromPtr(self.kernel_stack.ptr)) + self.kernel_stack.len;
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.kernel_stack);
        self.allocator.free(self.user_stack);
        // if (self.program) |p| {
        // self.allocator.free(p);
        // }
    }
};

pub fn create(allocator: std.mem.Allocator, entry: fn () void) void {
    pid_count += 1;
    sched.appendThread(ThreadContext.init(allocator, pid_count, entry, 0x4000));
}

fn startUser() void {
    const self: *ThreadContext = threadFromCurrent();
    const va = 0;
    const v_stack_end = 0xfffffffff000;
    preparePageTableForUser(self.pgd, self.program, self.user_stack);
    context.switchTtbr0(@intFromPtr(self.pgd));
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
    const self: *volatile ThreadContext = threadFromCurrent();

    pid_count += 1;

    var t = ThreadContext.init(self.allocator, pid_count, null, self.user_stack.len);

    // Copy Stack
    @memcpy(t.kernel_stack, self.kernel_stack);
    @memcpy(t.user_stack, self.user_stack);

    t.sigkill_handler = self.sigkill_handler;
    t.program = self.program;

    // Handle Child TrapFrame
    t.trap_frame = @ptrFromInt(@intFromPtr(t.kernel_stack.ptr) + (@intFromPtr(parent_trap_frame) - @intFromPtr(self.kernel_stack.ptr)));
    t.trap_frame.?.x0 = 0;

    // Handle Parent TrapFrame
    parent_trap_frame.x0 = t.id;

    preparePageTableForUser(t.pgd, t.program, t.user_stack);

    context.switchTo(context.getCurrent(), context.getCurrent());

    const new_self: *volatile ThreadContext = threadFromCurrent();
    if (@intFromPtr(self) == @intFromPtr(new_self)) {
        t.cpu_context = self.cpu_context;
        t.cpu_context.fp = @intFromPtr(t.kernel_stack.ptr) + (self.cpu_context.fp - @intFromPtr(self.kernel_stack.ptr));
        t.cpu_context.sp = @intFromPtr(t.kernel_stack.ptr) + (self.cpu_context.sp - @intFromPtr(self.kernel_stack.ptr));
        sched.appendThread(t);
    }
}

pub fn exec(trap_frame: *TrapFrame, name: []const u8) void {
    const self: *ThreadContext = threadFromCurrent();
    const program = initrd.getFileContent(name);

    if (program) |p| {
        // if (self.program) |sp| {
        //     self.allocator.free(sp);
        // }

        self.program = self.allocator.alignedAlloc(u8, 16, p.len) catch {
            @panic("Out of Memory! No buffer for new program.");
        };
        log.info("New program address: 0x{X}", .{@intFromPtr(self.program.?.ptr)});
        @memcpy(self.program.?, p);

        asm volatile (
            \\ mov sp, %[arg0]
            \\ br %[arg1]
            :
            : [arg0] "r" (@intFromPtr(self.kernel_stack.ptr) + self.kernel_stack.len),
              [arg1] "r" (@intFromPtr(&startUser)),
        );

        unreachable;
    } else {
        trap_frame.x0 = @bitCast(@as(i64, -1));
    }
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
    program: ?[]const u8,
    user_stack: []u8,
) void {
    const va = 0;
    const v_stack_start = 0xffffffffb000;
    const v_stack_end = 0xfffffffff000;

    if (program) |prog| {
        mm.map.mapPages(
            pgd,
            va,
            std.mem.alignForwardLog2(prog.len, 12),
            @intFromPtr(prog.ptr),
            .{
                .user = true,
                .read_only = false,
                .el0_exec = true,
                .el1_exec = false,
                .mair_index = 1,
            },
            .PTE,
        ) catch {
            @panic("Cannot map user program memory!");
        };
    } else {
        @panic("Program must be provided to map user program memory!");
    }

    mm.map.mapPages(
        pgd,
        v_stack_start,
        v_stack_end - v_stack_start,
        @intFromPtr(user_stack.ptr),
        .{
            .user = true,
            .read_only = false,
            .el0_exec = false,
            .el1_exec = false,
            .mair_index = 1,
        },
        .PTE,
    ) catch {
        @panic("Cannot map user stack memory!");
    };

    mm.map.mapPages(
        pgd,
        0x3C000000,
        0x4000000,
        0xFFFF00003C000000,
        .{
            .user = true,
            .read_only = false,
            .el0_exec = false,
            .el1_exec = false,
            .mair_index = 0,
        },
        .PMD,
    ) catch {
        @panic("Cannot map device memory for user!");
    };
    mm.map.mapPages(
        pgd,
        0xfffffffff000,
        0x1000,
        @intFromPtr(&handlers.userSigreturnStub) & ~@as(u64, 0xfff),
        .{
            .user = true,
            .read_only = true,
            .el0_exec = true,
            .el1_exec = false,
            .mair_index = 1,
        },
        .PTE,
    ) catch |err| {
        log.info("{s}", .{@errorName(err)});
        @panic("Cannot map sigreturn stub for user!");
    };
}

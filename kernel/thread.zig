const std = @import("std");
const processor = @import("arch/aarch64/processor.zig");
const context = @import("arch/aarch64/context.zig");
const syscall = @import("process/syscall/user.zig");
const initrd = @import("fs/initrd.zig");
const sched = @import("sched.zig");
const thread_asm = @import("arch/aarch64/thread.zig");
const mm = @import("mm.zig");
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
    ended: bool = false,

    entry: usize,
    trap_frame: ?*processor.TrapFrame = null,

    kernel_stack: usize,
    kernel_stack_size: usize,
    user_stack: usize = 0,
    user_stack_size: usize = 0,
    program: usize = 0,
    program_size: usize = 0,
    pgd: ?*mm.map.PageTable = null,

    sigkill_handler: usize = 0,
    has_sigkill: bool = false,

    allocator: std.mem.Allocator,
    cpu_context: processor.CpuContext,

    pub fn init(allocator: std.mem.Allocator, id: u32, entry: ?*const fn () void, stack_size: usize) Self {
        const kernel_stack = allocator.alignedAlloc(u8, 16, stack_size) catch {
            @panic("Out of Memory! No buffer for thread stack.");
        };

        var self = Self{
            .id = id,
            .entry = @intFromPtr(entry),
            .kernel_stack = @intFromPtr(kernel_stack.ptr),
            .kernel_stack_size = kernel_stack.len,
            .allocator = allocator,
            .cpu_context = .{},
        };

        self.cpu_context.sp = self.kernel_stack + self.kernel_stack_size;

        const user_stack = allocator.alignedAlloc(u8, 16, stack_size) catch {
            @panic("Out of Memory! No buffer for thread stack.");
        };
        self.user_stack = @intFromPtr(user_stack.ptr);
        self.user_stack_size = user_stack.len;

        self.pgd = allocator.create(mm.map.PageTable) catch {
            @panic("Cannot create kernel page table!");
        };
        @memset(@as([]u8, @ptrCast(self.pgd.?)), 0);

        self.cpu_context.pc = @intFromPtr(&startKernel);

        return self;
    }

    pub fn deinit(self: *Self) void {
        const kernel_stack: []u8 = @as([*]u8, @ptrFromInt(self.kernel_stack))[0..self.kernel_stack_size];
        self.allocator.free(kernel_stack);

        const user_stack: []u8 = @as([*]u8, @ptrFromInt(self.user_stack))[0..self.user_stack_size];
        self.allocator.free(user_stack);

        if (self.program_size != 0) {
            // const program: []u8 = @as([*]u8, @ptrFromInt(self.program))[0..self.program_size];
            // self.allocator.free(program);
        }
    }
};

pub fn create(allocator: std.mem.Allocator, entry: fn () void) void {
    pid_count += 1;
    sched.appendThread(ThreadContext.init(allocator, pid_count, entry, 0x8000));
}

fn startUser() void {
    const self: *ThreadContext = threadFromCurrent();
    const va = 0;
    const v_stack_start = 0xffffffffb000;
    const v_stack_end = 0xfffffffff000;
    mm.map.mapPages(
        self.pgd.?,
        va,
        std.mem.alignForwardLog2(self.program_size, 12),
        self.program,
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
    mm.map.mapPages(
        self.pgd.?,
        v_stack_start,
        v_stack_end - v_stack_start,
        self.user_stack,
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
    context.switchTtbr0(@intFromPtr(self.pgd.?));
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

    var t = ThreadContext.init(self.allocator, pid_count, null, self.user_stack_size);

    const parent_kernel_stack: []u8 = @as([*]u8, @ptrFromInt(self.kernel_stack))[0..self.kernel_stack_size];
    const parent_user_stack: []u8 = @as([*]u8, @ptrFromInt(self.user_stack))[0..self.user_stack_size];
    const child_kernel_stack: []u8 = @as([*]u8, @ptrFromInt(t.kernel_stack))[0..t.kernel_stack_size];
    const child_user_stack: []u8 = @as([*]u8, @ptrFromInt(t.user_stack))[0..t.user_stack_size];

    // Copy Stack
    @memcpy(child_kernel_stack, parent_kernel_stack);
    @memcpy(child_user_stack, parent_user_stack);

    // Handle Parent TrapFrame
    parent_trap_frame.x0 = t.id;

    context.switchTo(context.getCurrent(), context.getCurrent());

    const new_self: *volatile ThreadContext = threadFromCurrent();
    if (@intFromPtr(self) == @intFromPtr(new_self)) {
        // Handle Child TrapFrame
        var child_trap_frame: *TrapFrame = @ptrFromInt(t.kernel_stack + (@intFromPtr(parent_trap_frame) - self.kernel_stack));
        child_trap_frame.x0 = 0;
        child_trap_frame.x29 = t.user_stack + (parent_trap_frame.x29 - self.user_stack);
        child_trap_frame.sp_el0 = t.user_stack + (parent_trap_frame.sp_el0 - self.user_stack);

        t.sigkill_handler = self.sigkill_handler;

        // Copy Kernel Context
        t.cpu_context = self.cpu_context;

        // Handle Child Context
        t.cpu_context.fp = t.kernel_stack + (self.cpu_context.fp - self.kernel_stack);
        t.cpu_context.sp = t.kernel_stack + (self.cpu_context.sp - self.kernel_stack);

        sched.appendThread(t);
    }
}

pub fn exec(trap_frame: *TrapFrame, name: []const u8) void {
    const self: *ThreadContext = threadFromCurrent();
    const program = initrd.getFileContent(name);

    if (program) |p| {
        if (self.program_size != 0) {
            // const old_program: []u8 = @as([*]u8, @ptrFromInt(self.program))[0..self.program_size];
            // self.allocator.free(old_program);
        }

        const new_program = self.allocator.alignedAlloc(u8, 16, p.len) catch {
            @panic("Out of Memory! No buffer for new program.");
        };
        log.info("New program address: 0x{X}", .{@intFromPtr(new_program.ptr)});
        @memcpy(new_program, p);

        self.program = @intFromPtr(new_program.ptr);
        self.program_size = new_program.len;
        self.entry = @intFromPtr(new_program.ptr);

        asm volatile (
            \\ mov sp, %[arg0]
            \\ br %[arg1]
            :
            : [arg0] "r" (self.kernel_stack + self.kernel_stack_size),
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

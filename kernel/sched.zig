const std = @import("std");
const log = std.log.scoped(.sched);
const processor = @import("asm/processor.zig");
const context = @import("asm/context.zig");
const syscall = @import("syscall.zig");
const initrd = @import("fs/initrd.zig");
const exception = @import("exception.zig");

const ThreadContext = processor.ThreadContext;
const TrapFrame = processor.TrapFrame;
const DoublyLinkedList = std.DoublyLinkedList;
const RunQueue = DoublyLinkedList(Task);

pub const Task = packed struct {
    const Self = @This();

    thread_context: ThreadContext = .{ .cpu_context = .{} },
    id: u32,
    entry: usize,
    kernel_stack: usize,
    kernel_stack_size: usize,
    user_stack: usize,
    user_stack_size: usize,
    program: usize = 0,
    program_size: usize = 0,
    ended: bool = false,
    allocator: *const std.mem.Allocator,
    sigkill_handler: usize = 0,
    has_sigkill: bool = false,
    trap_frame: ?*TrapFrame = null,

    pub fn init(allocator: *const std.mem.Allocator, id: u32, entry: ?*const fn () void, stack_size: usize) Self {
        const kernel_stack = allocator.alignedAlloc(u8, 16, stack_size) catch {
            @panic("Out of Memory! No buffer for thread stack.");
        };
        const user_stack = allocator.alignedAlloc(u8, 16, stack_size) catch {
            @panic("Out of Memory! No buffer for thread stack.");
        };

        var self = Self{
            .id = id,
            .entry = @intFromPtr(entry),
            .kernel_stack = @intFromPtr(kernel_stack.ptr),
            .kernel_stack_size = kernel_stack.len,
            .user_stack = @intFromPtr(user_stack.ptr),
            .user_stack_size = user_stack.len,
            .allocator = allocator,
        };

        self.thread_context.cpu_context.pc = @intFromPtr(&startThread);
        self.thread_context.cpu_context.sp = self.kernel_stack + self.kernel_stack_size;

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

var pid_count: u32 = 0;
var run_queue = RunQueue{};

pub fn createThread(allocator: *const std.mem.Allocator, entry: fn () void) void {
    pid_count += 1;

    var thread = allocator.create(RunQueue.Node) catch {
        @panic("Out of Memory! No buffer for thread.");
    };

    thread.data = Task.init(allocator, pid_count, entry, 0x8000);

    run_queue.append(thread);
}

pub fn forkThread(parent_trap_frame: *TrapFrame) void {
    const self: *volatile Task = @ptrFromInt(context.getCurrent());

    pid_count += 1;
    var thread = self.allocator.create(RunQueue.Node) catch {
        @panic("Out of Memory! No buffer for forking a thread.");
    };

    thread.data = Task.init(self.allocator, pid_count, null, self.user_stack_size);

    const parent_kernel_stack: []u8 = @as([*]u8, @ptrFromInt(self.kernel_stack))[0..self.kernel_stack_size];
    const parent_user_stack: []u8 = @as([*]u8, @ptrFromInt(self.user_stack))[0..self.user_stack_size];
    const child_kernel_stack: []u8 = @as([*]u8, @ptrFromInt(thread.data.kernel_stack))[0..thread.data.kernel_stack_size];
    const child_user_stack: []u8 = @as([*]u8, @ptrFromInt(thread.data.user_stack))[0..thread.data.user_stack_size];

    // Copy Stack
    @memcpy(child_kernel_stack, parent_kernel_stack);
    @memcpy(child_user_stack, parent_user_stack);

    // Handle Parent TrapFrame
    parent_trap_frame.x0 = thread.data.id;

    context.switchTo(context.getCurrent(), context.getCurrent());

    const new_self: *volatile Task = @ptrFromInt(context.getCurrent());
    if (@intFromPtr(self) == @intFromPtr(new_self)) {
        // Handle Child TrapFrame
        var child_trap_frame: *TrapFrame = @ptrFromInt(thread.data.kernel_stack + (@intFromPtr(parent_trap_frame) - self.kernel_stack));
        child_trap_frame.x0 = 0;
        child_trap_frame.x29 = thread.data.user_stack + (parent_trap_frame.x29 - self.user_stack);

        thread.data.sigkill_handler = self.sigkill_handler;

        // Copy Kernel Context
        thread.data.thread_context.cpu_context = self.thread_context.cpu_context;

        // Handle Child Context
        thread.data.thread_context.cpu_context.fp = thread.data.kernel_stack + (self.thread_context.cpu_context.fp - self.kernel_stack);
        thread.data.thread_context.cpu_context.sp = thread.data.kernel_stack + (self.thread_context.cpu_context.sp - self.kernel_stack);
        thread.data.thread_context.cpu_context.sp_el0 = thread.data.user_stack + (self.thread_context.cpu_context.sp_el0 - self.user_stack);

        run_queue.append(thread);
    }
}

pub fn execThread(trap_frame: *TrapFrame, name: []const u8) void {
    const self: *volatile Task = @ptrFromInt(context.getCurrent());
    const p = initrd.getFileContent(name);

    if (p) |program| {
        if (self.program_size != 0) {
            // const old_program: []u8 = @as([*]u8, @ptrFromInt(self.program))[0..self.program_size];
            // self.allocator.free(old_program);
        }

        const new_program = self.allocator.alignedAlloc(u8, 16, program.len) catch {
            @panic("Out of Memory! No buffer for new program.");
        };
        log.info("New program address: 0x{X}", .{@intFromPtr(new_program.ptr)});
        @memcpy(new_program, program);

        self.program = @intFromPtr(new_program.ptr);
        self.program_size = new_program.len;
        self.entry = @intFromPtr(new_program.ptr);

        asm volatile (
            \\ mov sp, %[arg0]
            \\ br %[arg1]
            :
            : [arg0] "r" (self.kernel_stack + self.kernel_stack_size),
              [arg1] "r" (@intFromPtr(&startThread)),
        );

        unreachable;
    } else {
        trap_frame.x0 = @bitCast(@as(i64, -1));
    }
}

pub fn schedule() void {
    const next_task = &run_queue.first.?.data;
    run_queue.append(run_queue.popFirst().?);
    context.switchTo(context.getCurrent(), @intFromPtr(next_task));
    exception.isSigkillPending();
}

pub fn idle(allocator: *const std.mem.Allocator) void {
    var thread = allocator.create(RunQueue.Node) catch {
        @panic("Out of Memory! No buffer for thread.");
    };

    thread.data = Task.init(allocator, 0, null, 0);

    run_queue.append(thread);

    const ctx = @intFromPtr(&thread.data);
    context.switchTo(ctx, ctx);

    while (run_queue.len > 1) {
        killZombies();
        schedule();
    }
}

fn startThread() void {
    const self: *Task = @ptrFromInt(context.getCurrent());

    asm volatile (
        \\ ldr lr, =user_thread_get_back_here
        \\ mov x1, 0x0
        \\ msr spsr_el1, x1
        \\ mov x1, %[arg0]
        \\ msr elr_el1, x1
        \\ mov x1, %[arg1]
        \\ msr sp_el0, x1
        \\ eret
        :
        : [arg0] "r" (self.entry),
          [arg1] "r" (self.user_stack + self.user_stack_size),
        : "x1"
    );

    asm volatile (
        \\ user_thread_get_back_here:
    );

    syscall.exit(0);

    while (true) {
        asm volatile ("nop");
    }
}

pub fn endThread() noreturn {
    const self: *Task = @ptrFromInt(context.getCurrent());
    self.ended = true;
    while (true) {
        schedule();
    }
}

pub fn findThreadByPid(pid: u32) ?*RunQueue.Node {
    var it = run_queue.first;
    while (it) |node| {
        it = node.next;
        if (node.data.id == pid) {
            return node;
        }
    }
    return null;
}

pub fn killThread(pid: u32) void {
    const self: *Task = @ptrFromInt(context.getCurrent());
    if (pid == self.id) {
        endThread();
    }

    const thread = findThreadByPid(pid);
    if (thread) |t| {
        log.info("Thread {} ended!", .{t.data.id});
        run_queue.remove(t);
        t.data.deinit();
        t.data.allocator.destroy(t);
    }
}

fn killZombies() void {
    var it = run_queue.first;
    while (it) |node| {
        it = node.next;
        if (node.data.ended) {
            log.info("Thread {} ended!", .{node.data.id});
            run_queue.remove(node);
            node.data.deinit();
            node.data.allocator.destroy(node);
        }
    }
}

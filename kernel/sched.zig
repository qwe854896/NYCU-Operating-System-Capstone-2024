const std = @import("std");
const log = std.log.scoped(.sched);
const processor = @import("asm/processor.zig");
const context = @import("asm/context.zig");

const ThreadContext = processor.ThreadContext;
const Task = packed struct {
    const Self = @This();

    thread_context: ThreadContext = .{ .cpu_context = .{} },
    id: u32,
    entry: usize,
    stack: usize,
    stack_size: usize,
    ended: bool = false,
    allocator: *const std.mem.Allocator,

    pub fn init(allocator: *const std.mem.Allocator, id: u32, entry: ?*const fn () void, stack_size: usize) Self {
        const stack = allocator.alignedAlloc(u8, 16, stack_size) catch {
            @panic("Out of Memory! No buffer for thread stack.");
        };

        var self = Self{
            .id = id,
            .entry = @intFromPtr(entry),
            .stack = @intFromPtr(stack.ptr),
            .stack_size = stack.len,
            .allocator = allocator,
        };

        self.thread_context.cpu_context.pc = @intFromPtr(&run);
        self.thread_context.cpu_context.sp = @intFromPtr(stack.ptr) + stack.len;

        return self;
    }

    pub fn deinit(self: *Self) void {
        const stack: []u8 = @as([*]u8, @ptrFromInt(self.stack))[0..self.stack_size];
        self.allocator.free(stack);
    }
};
const DoublyLinkedList = std.DoublyLinkedList;
const RunQueue = DoublyLinkedList(Task);

var pid_count: u32 = 0;
var run_queue = RunQueue{};

pub fn threadCreate(allocator: *const std.mem.Allocator, entry: fn () void) void {
    pid_count += 1;

    var thread = allocator.create(RunQueue.Node) catch {
        @panic("Out of Memory! No buffer for thread.");
    };

    thread.data = Task.init(allocator, pid_count, entry, 0x8000);

    run_queue.append(thread);
}

pub fn schedule() void {
    const next_task = &run_queue.first.?.data;
    run_queue.append(run_queue.popFirst().?);
    context.switchTo(context.getCurrent(), @intFromPtr(next_task));
}

pub fn idle(allocator: *const std.mem.Allocator) void {
    var thread = allocator.create(RunQueue.Node) catch {
        @panic("Out of Memory! No buffer for thread.");
    };

    thread.data = Task.init(allocator, 0, null, 0);

    run_queue.append(thread);

    const ctx = @intFromPtr(&thread.data);
    context.switchTo(ctx, ctx);

    log.info("Idle thread context address: 0x{X}", .{ctx});

    while (true) {
        killZombies();
        schedule();
    }
}

pub fn currentThread() Task {
    const thread: *Task = @ptrFromInt(context.getCurrent());
    return thread.*;
}

fn run() void {
    const self: *Task = @ptrFromInt(context.getCurrent());

    asm volatile (
        \\      blr %[arg0]
        :
        : [arg0] "r" (self.entry),
    );

    if (@intFromPtr(self) != context.getCurrent()) {
        @panic("Current thread is not the same as the one running!");
    }

    self.ended = true;

    while (true) {
        schedule();
    }
}

fn killZombies() void {
    var it = run_queue.first;
    while (it) |node| {
        it = node.next;
        if (node.data.ended) {
            node.data.deinit();
            node.data.allocator.destroy(node);
            run_queue.remove(node);
        }
    }
}

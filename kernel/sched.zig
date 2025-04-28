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
    started: bool = false,
    ended: bool = false,
    allocator: *const std.mem.Allocator,

    pub fn init(allocator: *const std.mem.Allocator, id: u32, entry: ?*const fn () void, stack_size: usize, started: bool) Self {
        const stack = allocator.alignedAlloc(u8, 16, stack_size) catch {
            @panic("Out of Memory! No buffer for thread stack.");
        };
        return .{
            .id = id,
            .entry = @intFromPtr(entry),
            .stack = @intFromPtr(stack.ptr),
            .stack_size = stack.len,
            .started = started,
            .allocator = allocator,
        };
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

pub fn threadCreate(allocator: std.mem.Allocator, entry: fn () void) void {
    pid_count += 1;

    var thread = allocator.create(RunQueue.Node) catch {
        @panic("Out of Memory! No buffer for thread.");
    };

    thread.data = Task.init(&allocator, pid_count, entry, 0x8000, false);

    run_queue.append(thread);
}

pub fn schedule() void {
    var next_thread = &run_queue.first.?.data;
    run_queue.append(run_queue.popFirst().?);

    if (!next_thread.started) {
        const pc = @intFromPtr(&run);
        const sp = next_thread.stack + next_thread.stack_size;

        next_thread.started = true;
        next_thread.thread_context.cpu_context.pc = pc;
        next_thread.thread_context.cpu_context.sp = sp;
    }

    context.switchTo(context.getCurrent(), @intFromPtr(next_thread));
}

pub fn idle(allocator: std.mem.Allocator) void {
    var thread = allocator.create(RunQueue.Node) catch {
        @panic("Out of Memory! No buffer for thread.");
    };

    thread.data = Task.init(&allocator, 0, null, 0, true);

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

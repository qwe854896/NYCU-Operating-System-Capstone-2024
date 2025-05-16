const std = @import("std");
const context = @import("arch/aarch64/context.zig");
const handlers = @import("process/syscall/handlers.zig");
const thread = @import("thread.zig");
const log = std.log.scoped(.sched);

const ThreadContext = thread.ThreadContext;
const DoublyLinkedList = std.DoublyLinkedList;
const RunQueue = DoublyLinkedList(Task);

pub const Task = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    thread_context: ThreadContext,

    pub fn init(allocator: std.mem.Allocator, t: ThreadContext) Self {
        return .{
            .allocator = allocator,
            .thread_context = t,
        };
    }

    pub fn deinit(self: *Self) void {
        self.thread_context.deinit();
    }
};

var run_queue = RunQueue{};

pub fn getRunQueueLen() usize {
    return run_queue.len;
}

pub fn appendThread(t: ThreadContext) void {
    var node = t.allocator.create(RunQueue.Node) catch {
        @panic("Out of Memory! No buffer for thread.");
    };
    node.data = Task.init(t.allocator, t);
    run_queue.append(node);
}

pub fn removeThread(pid: u32) void {
    const node = findNodeByPid(pid);
    if (node) |n| {
        log.info("Thread {} ended!", .{pid});
        run_queue.remove(n);
        n.data.deinit();
        n.data.allocator.destroy(n);
    }
}

pub fn schedule() void {
    const next_task = &run_queue.first.?.data;
    run_queue.append(run_queue.popFirst().?);
    context.switchTtbr0(@intFromPtr(next_task.thread_context.pgd));
    context.switchTo(context.getCurrent(), @intFromPtr(next_task) + @offsetOf(Task, "thread_context") + @offsetOf(ThreadContext, "cpu_context"));
    handlers.isSigkillPending();
}

pub fn idle(allocator: *const std.mem.Allocator) void {
    var node = allocator.create(RunQueue.Node) catch {
        @panic("Out of Memory! No buffer for thread.");
    };
    run_queue.append(node);

    const ctx = @intFromPtr(&node.data) + @offsetOf(Task, "thread_context") + @offsetOf(ThreadContext, "cpu_context");
    context.switchTo(ctx, ctx);

    while (run_queue.len > 1) {
        killZombies();
        schedule();
    }
}

pub fn findThreadByPid(pid: u32) ?*ThreadContext {
    const node = findNodeByPid(pid) orelse return null;
    return &node.data.thread_context;
}

fn killZombies() void {
    var it = run_queue.first;
    while (it) |node| {
        it = node.next;
        if (node.data.thread_context.ended) {
            log.info("Thread {} ended!", .{node.data.thread_context.id});
            run_queue.remove(node);
            node.data.deinit();
            node.data.allocator.destroy(node);
        }
    }
}

fn findNodeByPid(pid: u32) ?*RunQueue.Node {
    var it = run_queue.first;
    while (it) |node| {
        it = node.next;
        if (node.data.thread_context.id == pid) {
            return node;
        }
    }
    return null;
}

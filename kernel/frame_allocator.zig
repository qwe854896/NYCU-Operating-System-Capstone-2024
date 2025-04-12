const std = @import("std");
const buddy = @import("buddy.zig");

const mem = std.mem;
const Buddy = buddy.Buddy;

const startup_allocator = @import("allocator.zig").simple_allocator;

fn fixUp(len: usize) usize {
    if (len == 0) {
        return 1;
    }
    var n = len - 1;
    n |= n >> 1;
    n |= n >> 2;
    n |= n >> 4;
    n |= n >> 8;
    n |= n >> 16;
    n |= n >> 32;
    return n + 1;
}

const Config = struct {
    verbose_log: bool = false,
};

pub fn FrameAllocator(comptime config: Config) type {
    return struct {
        const Self = @This();
        const ConfiguredBuddy = Buddy(.{ .verbose_log = config.verbose_log });

        manager: *ConfiguredBuddy,
        bytes: []allowzero u8,

        pub fn init(bytes: []allowzero u8) Self {
            const fix_len = fixUp(bytes.len);
            const num_of_pages = fix_len >> 12;
            const ctx_len = num_of_pages << 1;

            var ctx = startup_allocator.alloc(u8, ctx_len) catch {
                @panic("Out of Memory! No buffer for buddy system manager.");
            };
            const manager = ConfiguredBuddy.init(ctx[0..ctx_len]);

            var self = Self{
                .manager = manager,
                .bytes = bytes[0..],
            };

            self.memory_reserve(bytes.len, fix_len);

            return self;
        }

        pub fn allocator(self: *Self) mem.Allocator {
            return .{
                .ptr = self,
                .vtable = &.{
                    .alloc = alloc,
                    .resize = resize,
                    .free = free,
                    .remap = remap,
                },
            };
        }

        pub fn memory_reserve(self: *Self, start: usize, end: usize) void {
            const start_index = start >> 12;
            const end_index = (end + 0xFFF) >> 12;
            self.manager.reserve(start_index, end_index);
        }

        fn alloc(ctx: *anyopaque, len: usize, alignment: mem.Alignment, ret_addr: usize) ?[*]u8 {
            _ = alignment;
            _ = ret_addr;
            const self: *Self = @ptrCast(@alignCast(ctx));
            const num_of_pages = (len + 0xFFF) >> 12;
            const offset = self.manager.alloc(num_of_pages) orelse return null;
            return @ptrFromInt(@intFromPtr(self.bytes.ptr) + (offset << 12));
        }

        fn resize(ctx: *anyopaque, buf: []u8, alignment: mem.Alignment, new_len: usize, ret_addr: usize) bool {
            _ = alignment;
            _ = ret_addr;
            const self: *Self = @ptrCast(@alignCast(ctx));
            const ok = new_len <= self.allocSize(buf.ptr);
            return ok;
        }

        fn free(ctx: *anyopaque, buf: []u8, alignment: mem.Alignment, ret_addr: usize) void {
            _ = alignment;
            _ = ret_addr;
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.manager.free((@intFromPtr(buf.ptr) - @intFromPtr(self.bytes.ptr)) >> 12);
        }

        fn remap(context: *anyopaque, memory: []u8, alignment: mem.Alignment, new_len: usize, return_address: usize) ?[*]u8 {
            return if (resize(context, memory, alignment, new_len, return_address)) memory.ptr else null;
        }

        fn allocSize(self: *const Self, ptr: [*]u8) usize {
            const offset = @intFromPtr(ptr) - @intFromPtr(self.bytes.ptr);
            const index = self.manager.backward(offset);
            const size = self.manager.indexToSize(index);
            return size;
        }
    };
}

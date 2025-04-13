const std = @import("std");
const buddy = @import("buddy.zig");
const log = std.log.scoped(.page);
const mem = std.mem;
const log2_int = std.math.log2_int;
const Buddy = buddy.Buddy;
const assert = std.debug.assert;

var buffer: [0x1000000]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);
pub const startup_allocator = fba.allocator();

pub const log2_page_size = 12;
pub const page_size = 1 << log2_page_size;

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

pub fn PageAllocator(comptime config: Config) type {
    return struct {
        const Self = @This();
        const ConfiguredBuddy = Buddy(.{ .verbose_log = config.verbose_log });

        manager: *ConfiguredBuddy,
        bytes: []allowzero u8,

        pub fn init(bytes: []allowzero u8) Self {
            const fix_len = fixUp(bytes.len);
            const num_of_pages = fix_len >> log2_page_size;
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

        pub fn memory_reserve(self: *Self, start: usize, end: usize) void {
            const start_index = start >> log2_page_size;
            const end_index = mem.alignForwardLog2(end, log2_page_size) >> log2_page_size;
            self.manager.reserve(start_index, end_index);
        }

        pub fn allocator(self: *Self) mem.Allocator {
            return .{
                .ptr = self,
                .vtable = &.{
                    .alloc = alloc,
                    .free = free,
                    .resize = resize,
                    .remap = remap,
                },
            };
        }

        fn alloc(context: *anyopaque, n: usize, alignment: mem.Alignment, ra: usize) ?[*]u8 {
            _ = ra;
            assert(n > 0);
            const self: *Self = @ptrCast(@alignCast(context));
            const alignment_bytes = alignment.toByteUnits();
            const aligned_len = mem.alignForwardLog2(n, log2_page_size);
            const offset = self.manager.alloc(@max(aligned_len, alignment_bytes) >> log2_page_size) orelse return null;
            const array: [*]u8 = @ptrFromInt(@intFromPtr(self.bytes.ptr) + (offset << log2_page_size));
            const result_ptr = mem.alignPointer(array, alignment_bytes) orelse return null;
            if (config.verbose_log) {
                log.info("Allocate 0x{X} at order {}, page 0x{X}.", .{ @intFromPtr(result_ptr), log2_int(usize, fixUp(aligned_len)) - log2_page_size, @intFromPtr(result_ptr) >> log2_page_size });
            }
            return result_ptr;
        }

        fn free(context: *anyopaque, memory: []u8, alignment: mem.Alignment, return_address: usize) void {
            _ = alignment;
            _ = return_address;
            const self: *Self = @ptrCast(@alignCast(context));
            if (config.verbose_log) {
                log.info("Free 0x{X} at order {}, page 0x{X}.", .{ @intFromPtr(memory.ptr), log2_int(usize, fixUp(memory.len)) - log2_page_size, @intFromPtr(memory.ptr) >> log2_page_size });
            }
            self.manager.free((@intFromPtr(memory.ptr) - @intFromPtr(self.bytes.ptr)) >> log2_page_size);
        }

        fn resize(context: *anyopaque, memory: []u8, alignment: mem.Alignment, new_len: usize, return_address: usize) bool {
            _ = alignment;
            _ = return_address;
            const self: *Self = @ptrCast(@alignCast(context));
            return new_len <= self.allocSize(memory.ptr);
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

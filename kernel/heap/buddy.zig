const std = @import("std");
const log = std.log.scoped(.buddy);
const assert = std.debug.assert;
const isPowerOfTwo = std.math.isPowerOfTwo;
const log2_int = std.math.log2_int;
const testing = std.testing;

pub const Log2Usize = std.math.Log2Int(usize);

const Config = struct {
    verbose_log: bool = false,
};

pub fn Buddy(comptime config: Config) type {
    return struct {
        const Self = @This();

        log_len: Log2Usize,
        frees: []usize,

        pub fn init(allocator: std.mem.Allocator, len: usize) !Self {
            assert(isPowerOfTwo(len));

            const log_len = log2_int(usize, len);

            var self = Self{
                .log_len = log_len,
                .frees = try allocator.alloc(usize, len << 1),
            };

            var log_node_size = log_len + 1;

            for (1..len << 1) |i| {
                if (isPowerOfTwo(i)) {
                    log_node_size -= 1;
                }
                self.setFree(i, log_node_size);
            }

            if (config.verbose_log) {
                log.info("Add page 0x{X} to order {}.", .{ 0, self.log_len });
            }

            return self;
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            allocator.free(self.frees);
        }

        pub fn getMetadata(self: *const Self) []u8 {
            return @ptrCast(self.frees);
        }

        pub fn alloc(self: *Self, len: usize) ?usize {
            const new_len = fixUp(len);
            const log_len = log2_int(usize, new_len);

            if (self.frees[1] < new_len) {
                return null;
            }

            var index: usize = 1;
            var log_node_size = self.log_len;

            while (log_node_size != log_len) : (log_node_size -= 1) {
                if (config.verbose_log and self.isFree(index, log_node_size)) {
                    log.info("Remove page 0x{X} from order {}.", .{ self.indexToOffset(index), log_node_size });
                    log.info("Add page 0x{X} to order {}.", .{ self.indexToOffset(left(index)), log_node_size - 1 });
                    log.info("Add page 0x{X} to order {}.", .{ self.indexToOffset(right(index)), log_node_size - 1 });
                }

                const left_free = @bitReverse(self.frees[left(index)] >> log_len);
                const right_free = @bitReverse(self.frees[right(index)] >> log_len);

                if (left_free >= right_free) {
                    index = left(index);
                } else {
                    index = right(index);
                }
            }

            self.frees[index] = 0;

            const offset = (index << log_len) - self.getLen();

            if (config.verbose_log) {
                log.info("Remove page 0x{X} from order {}.", .{ offset, log_len });
            }

            while (index != 1) {
                index = parent(index);
                self.frees[index] = self.frees[left(index)] | self.frees[right(index)];
            }

            return offset;
        }

        pub fn free(self: *Self, offset: usize) void {
            assert(offset < self.getLen());

            var log_node_size: Log2Usize = 0;
            var index = offset + self.getLen(); // start from the leaf node

            while (self.isFree(index, log_node_size)) : (index = parent(index)) {
                log_node_size += 1;
                if (index == 1) {
                    return;
                }
            }

            self.setFree(index, log_node_size);

            if (config.verbose_log) {
                log.info("Add page 0x{X} to order {}.", .{ offset, log_node_size });
            }

            while (index != 1) {
                index = parent(index);
                log_node_size += 1;

                const left_free = self.isFree(left(index), log_node_size - 1);
                const right_free = self.isFree(right(index), log_node_size - 1);

                if (left_free and right_free) {
                    if (config.verbose_log) {
                        log.info("Remove page 0x{X} from order {}.", .{ self.indexToOffset(left(index)), log_node_size - 1 });
                        log.info("Remove page 0x{X} from order {}.", .{ self.indexToOffset(right(index)), log_node_size - 1 });
                        log.info("Add page 0x{X} to order {}.", .{ self.indexToOffset(index), log_node_size });
                    }
                    self.setFree(index, log_node_size);
                } else {
                    self.frees[index] = self.frees[left(index)] | self.frees[right(index)];
                }
            }
        }

        pub fn size(self: *const Self, offset: usize) usize {
            return self.indexToSize(self.backward(offset));
        }

        pub fn reserve(self: *Self, start_offset: usize, end_offset: usize) void {
            if (config.verbose_log) {
                log.info("Reserve pages: [0x{X}, 0x{X}).", .{ start_offset, end_offset });
            }
            self.recursive_reserve(self.log_len, 1, 0, self.getLen(), start_offset, end_offset);
        }

        fn recursive_reserve(self: *Self, log_node_size: Log2Usize, index: usize, left_offset: usize, right_offset: usize, start_offset: usize, end_offset: usize) void {
            if (right_offset <= start_offset or end_offset <= left_offset) {
                return;
            }

            const split = self.isFree(index, log_node_size);

            if (start_offset <= left_offset and right_offset <= end_offset) {
                self.frees[index] = 0;
                if (config.verbose_log and split) {
                    log.info("Remove page 0x{X} from order {}.", .{ self.indexToOffset(index), log_node_size });
                }
                return;
            }

            if (config.verbose_log and split) {
                log.info("Remove page 0x{X} from order {}.", .{ self.indexToOffset(index), log_node_size });
                log.info("Add page 0x{X} to order {}.", .{ self.indexToOffset(left(index)), log_node_size - 1 });
                log.info("Add page 0x{X} to order {}.", .{ self.indexToOffset(right(index)), log_node_size - 1 });
            }

            const middle_offset = (left_offset + right_offset) >> 1;
            self.recursive_reserve(log_node_size - 1, left(index), left_offset, middle_offset, start_offset, end_offset);
            self.recursive_reserve(log_node_size - 1, right(index), middle_offset, right_offset, start_offset, end_offset);

            self.frees[index] = self.frees[left(index)] | self.frees[right(index)];
        }

        pub fn backward(self: *const Self, offset: usize) usize {
            assert(offset < self.getLen());
            var index = offset + self.getLen(); // start from leaf node
            while (self.frees[index] != 0) {
                index = parent(index);
            }
            return index;
        }

        inline fn getLen(self: *const Self) usize {
            return @as(usize, 1) << @as(Log2Usize, @intCast(self.log_len));
        }

        inline fn isFree(self: *const Self, index: usize, log_node_size: Log2Usize) bool {
            return self.frees[index] == (@as(usize, 1) << log_node_size);
        }

        inline fn setFree(self: *const Self, index: usize, log_node_size: Log2Usize) void {
            self.frees[index] = @as(usize, 1) << log_node_size;
        }

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

        inline fn left(index: usize) usize {
            return index << 1;
        }

        inline fn right(index: usize) usize {
            return index << 1 | 1;
        }

        inline fn parent(index: usize) usize {
            return index >> 1;
        }

        pub inline fn indexToSize(self: *const Self, index: usize) usize {
            return self.getLen() >> log2_int(usize, index);
        }

        inline fn indexToOffset(self: *const Self, index: usize) usize {
            return index * self.indexToSize(index) - self.getLen();
        }

        pub fn format(self: *const Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            const len = self.getLen();

            var log_len = self.log_len + 1;

            var count: usize = 0;
            for (1..(len << 1)) |i| {
                if (isPowerOfTwo(i)) {
                    log_len -= 1;
                }
                count += @as(usize, @intCast(@as(u1, @bitCast(self.isFree(i, log_len) and !self.isFree(i ^ 1, log_len)))));
                if (isPowerOfTwo(i + 1)) {
                    try std.fmt.format(writer, "Order {}: {} blocks\n", .{ log_len, count });
                    count = 0;
                }
            }
        }
    };
}

test "Buddy" {
    const heap_size = 16;

    var buddy = try Buddy(.{}).init(testing.allocator, heap_size);
    defer buddy.deinit(testing.allocator);

    for (0..16) |i| {
        const offset = buddy.alloc(1).?;
        try testing.expectEqual(i, offset);
        try testing.expectEqual(@as(usize, 1), buddy.size(offset));
    }

    try testing.expect(buddy.alloc(1) == null);

    for (0..16) |i| {
        buddy.free(i);
    }

    for (0..16) |i| {
        const offset = buddy.alloc(1).?;
        try testing.expectEqual(i, offset);
        try testing.expectEqual(@as(usize, 1), buddy.size(offset));
    }

    try testing.expect(buddy.alloc(1) == null);

    for (0..16) |i| {
        buddy.free(i);
    }

    try testing.expectEqual(@as(usize, 0), buddy.alloc(8).?);
    try testing.expectEqual(@as(usize, 8), buddy.size(0));
    try testing.expectEqual(@as(usize, 8), buddy.alloc(8).?);
    try testing.expectEqual(@as(usize, 8), buddy.size(8));
    try testing.expect(buddy.alloc(8) == null);
    buddy.free(8);
    try testing.expectEqual(@as(usize, 8), buddy.alloc(4).?);
    try testing.expectEqual(@as(usize, 4), buddy.size(8));
    try testing.expectEqual(@as(usize, 12), buddy.alloc(4).?);
    try testing.expectEqual(@as(usize, 4), buddy.size(12));
    buddy.free(12);
    try testing.expectEqual(@as(usize, 12), buddy.alloc(3).?);
    try testing.expectEqual(@as(usize, 4), buddy.size(12));
    buddy.free(12);
    try testing.expectEqual(@as(usize, 12), buddy.alloc(2).?);
    try testing.expectEqual(@as(usize, 2), buddy.size(12));
    try testing.expectEqual(@as(usize, 14), buddy.alloc(2).?);
    try testing.expectEqual(@as(usize, 2), buddy.size(14));
    buddy.free(12);
    buddy.free(14);
    buddy.free(0);
    buddy.free(8);
    try testing.expectEqual(@as(usize, 0), buddy.alloc(16).?);
    try testing.expectEqual(@as(usize, 16), buddy.size(0));
    try testing.expect(buddy.alloc(1) == null);
    buddy.free(0);

    // Allocate small blocks first.
    try testing.expectEqual(@as(usize, 0), buddy.alloc(8).?);
    try testing.expectEqual(@as(usize, 8), buddy.alloc(4).?);
    buddy.free(0);
    try testing.expectEqual(@as(usize, 12), buddy.alloc(4).?);
    try testing.expectEqual(@as(usize, 0), buddy.alloc(8).?);
}

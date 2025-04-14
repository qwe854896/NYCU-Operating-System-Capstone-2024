const std = @import("std");
const log = std.log.scoped(.buddy);
const DynamicBitSet = std.bit_set.DynamicBitSet;
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
        bitset: DynamicBitSet,

        pub fn init(allocator: std.mem.Allocator, len: usize) !Self {
            assert(isPowerOfTwo(len));

            var self = Self{
                .log_len = log2_int(usize, len),
                .bitset = try DynamicBitSet.initEmpty(allocator, len << 2),
            };

            var log_node_size = self.log_len + 1;

            for (1..len << 1) |i| {
                if (isPowerOfTwo(i)) {
                    log_node_size -= 1;
                }
                self.setFree(i, log_node_size, true);
            }

            if (config.verbose_log) {
                log.info("Add page 0x{X} to order {}.", .{ 0, self.log_len });
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.bitset.deinit();
        }

        pub fn alloc(self: *Self, len: usize) ?usize {
            const log_len = log2_int(usize, fixUp(len));

            if (self.getMsb(1, self.log_len) == null or self.getMsb(1, self.log_len).? < log_len) {
                return null;
            }

            var index: usize = 1;
            var log_node_size = self.log_len;

            while (log_node_size != log_len) : (log_node_size -= 1) {
                if (config.verbose_log and self.getFree(index, log_node_size)) {
                    log.info("Remove page 0x{X} from order {}.", .{ self.indexToOffset(index), log_node_size });
                    log.info("Add page 0x{X} to order {}.", .{ self.indexToOffset(left(index)), log_node_size - 1 });
                    log.info("Add page 0x{X} to order {}.", .{ self.indexToOffset(right(index)), log_node_size - 1 });
                }

                const left_lsb = self.getLsb(left(index), log_node_size, log_len);
                const right_lsb = self.getLsb(right(index), log_node_size, log_len);

                if (right_lsb == null or (left_lsb != null and left_lsb.? <= right_lsb.?)) {
                    index = left(index);
                } else {
                    index = right(index);
                }
            }

            self.setFree(index, log_len, false);

            const offset = (index << log_len) - self.getLen();

            if (config.verbose_log) {
                log.info("Remove page 0x{X} from order {}.", .{ offset, log_len });
            }

            while (index != 1) {
                index = parent(index);
                log_node_size += 1;

                for (log_len..log_node_size) |order| {
                    self.setBitmap(index, log_node_size, order, self.getBitmap(left(index), log_node_size - 1, order) or self.getBitmap(right(index), log_node_size - 1, order));
                }

                self.setFree(index, log_node_size, false);
            }

            return offset;
        }

        pub fn free(self: *Self, offset: usize) void {
            assert(offset < self.getLen());

            var log_node_size: Log2Usize = 0;
            var index = offset + self.getLen(); // start from the leaf node

            while (self.getFree(index, log_node_size)) : (index = parent(index)) {
                log_node_size += 1;
                if (index == 1) {
                    return;
                }
            }

            self.setFree(index, log_node_size, true);

            if (config.verbose_log) {
                log.info("Add page 0x{X} to order {}.", .{ offset, log_node_size });
            }

            const log_len = log_node_size;

            while (index != 1) {
                index = parent(index);
                log_node_size += 1;

                const left_free = self.getFree(left(index), log_node_size - 1);
                const right_free = self.getFree(right(index), log_node_size - 1);

                if (left_free and right_free) {
                    if (config.verbose_log) {
                        log.info("Remove page 0x{X} from order {}.", .{ self.indexToOffset(left(index)), log_node_size - 1 });
                        log.info("Remove page 0x{X} from order {}.", .{ self.indexToOffset(right(index)), log_node_size - 1 });
                        log.info("Add page 0x{X} to order {}.", .{ self.indexToOffset(index), log_node_size });
                    }
                    self.setFree(index, log_node_size, true);
                    self.setBitmap(index, log_node_size, log_node_size - 1, false);
                } else {
                    self.setBitmap(index, log_node_size, log_node_size - 1, left_free or right_free);
                }

                for (log_len..log_node_size - 1) |order| {
                    self.setBitmap(index, log_node_size, order, self.getBitmap(left(index), log_node_size - 1, order) or self.getBitmap(right(index), log_node_size - 1, order));
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

            const split = self.getFree(index, log_node_size);
            self.setFree(index, log_node_size, false);

            if (start_offset <= left_offset and right_offset <= end_offset) {
                if (config.verbose_log) {
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

            for (0..log_node_size) |order| {
                self.setBitmap(index, log_node_size, order, self.getBitmap(left(index), log_node_size - 1, order) or self.getBitmap(right(index), log_node_size - 1, order));
            }
        }

        pub fn backward(self: *const Self, offset: usize) usize {
            assert(offset < self.getLen());
            var index = offset + self.getLen(); // start from leaf node
            var log_node_size: Log2Usize = 0;
            while (self.getMsb(index, log_node_size) != null) {
                index = parent(index);
                log_node_size += 1;
            }
            return index;
        }

        inline fn getLen(self: *const Self) usize {
            return @as(usize, 1) << @as(Log2Usize, @intCast(self.log_len));
        }

        inline fn getLsb(self: *const Self, index: usize, log_bit: Log2Usize, log_start: Log2Usize) ?Log2Usize {
            for (log_start..log_bit) |order| {
                if (self.getBitmap(index, log_bit - 1, order)) {
                    return @intCast(order);
                }
            }
            return null;
        }

        inline fn getMsb(self: *const Self, index: usize, log_bit: Log2Usize) ?Log2Usize {
            var order = log_bit;
            while (true) : (order -= 1) {
                if (self.getBitmap(index, log_bit, order)) {
                    return order;
                }
                if (order == 0) {
                    return null;
                }
            }
        }

        inline fn setFree(self: *Self, index: usize, log_bit: Log2Usize, value: bool) void {
            self.setBitmap(index, log_bit, log_bit, value);
        }

        inline fn getFree(self: *const Self, index: usize, log_bit: Log2Usize) bool {
            return self.getBitmap(index, log_bit, log_bit);
        }

        inline fn setBitmap(self: *Self, index: usize, log_bit: Log2Usize, order: usize, value: bool) void {
            self.bitset.setValue(self.getBitmapIndex(index, log_bit, order), value);
        }

        inline fn getBitmap(self: *const Self, index: usize, log_bit: Log2Usize, order: usize) bool {
            return self.bitset.isSet(self.getBitmapIndex(index, log_bit, order));
        }

        inline fn getBitmapIndex(self: *const Self, index: usize, log_bit: Log2Usize, order: usize) usize {
            const p = (self.getLen() << 2) - (@as(usize, @intCast(log_bit + 2)) << (self.log_len - log_bit + 1));
            const f = (log_bit + 1) * (index ^ (@as(usize, 1) << (self.log_len - log_bit)));
            return p + f + order;
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
                count += @as(usize, @intCast(@as(u1, @bitCast(self.getFree(i, log_len) and !self.getFree(i ^ 1, log_len)))));
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
    defer buddy.deinit();

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

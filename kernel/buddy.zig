const std = @import("std");
const log = std.log.scoped(.buddy);
const assert = std.debug.assert;
const isPowerOfTwo = std.math.isPowerOfTwo;
const log2_int = std.math.log2_int;
const testing = std.testing;

pub const Log2Usize = std.math.Log2Int(usize);

pub const Buddy = struct {
    const Self = @This();

    /// Should be accessed from getter and setter
    /// u5 is enough, but u8 seems to be more portable
    log_len: u8,
    log_longest: [1]u8,

    /// Inference the number of pages from passed context
    /// For example, if the ctx.len is 16, then the number of pages is 8
    /// log_len should be 3
    /// log_longest's size should be 15
    pub fn init(ctx: []u8) *Self {
        const len = ctx.len >> 1;
        assert(isPowerOfTwo(len));

        const self: *Self = @ptrCast(@alignCast(ctx));

        self.setLen(len);

        var node_size = len << 1;

        for (0..ctx.len - 1) |i| {
            if (isPowerOfTwo(i + 1)) {
                node_size >>= 1;
            }
            self.setLongest(i, node_size);
        }

        log.info("Add page 0x{X} to order {}.", .{ 0, self.log_len });

        return self;
    }

    pub fn alloc(self: *Self, len: usize) ?usize {
        const new_len = fixUp(len);

        if (self.getLongest(0) < new_len) {
            return null;
        }

        var index: usize = 0;
        var node_size = self.getLen();
        while (node_size != new_len) : (node_size >>= 1) {
            if (self.getLongest(index) == node_size) {
                log.info("Remove page 0x{X} from order {}.", .{ self.indexToOffset(index), log2_int(usize, node_size) });
                log.info("Add page 0x{X} to order {}.", .{ self.indexToOffset(left(index)), log2_int(usize, node_size >> 1) });
                log.info("Add page 0x{X} to order {}.", .{ self.indexToOffset(right(index)), log2_int(usize, node_size >> 1) });
            }
            const left_longest = self.getLongest(left(index));
            const right_longest = self.getLongest(right(index));
            if (left_longest >= new_len and (right_longest < new_len or right_longest >= left_longest)) {
                index = left(index);
            } else {
                index = right(index);
            }
        }

        self.setLongest(index, 0);

        const offset = (index + 1) * node_size - self.getLen();

        log.info("Remove page 0x{X} from order {}.", .{ offset, log2_int(usize, node_size) });
        log.info("Allocate page 0x{X} at order {}.", .{ offset, log2_int(usize, node_size) });

        while (index != 0) {
            index = parent(index);
            self.setLongest(index, @max(self.getLongest(left(index)), self.getLongest(right(index))));
        }

        return offset;
    }

    pub fn free(self: *Self, offset: usize) void {
        assert(offset < self.getLen());

        var node_size: usize = 1;
        var index = offset + self.getLen() - 1; // start from the leaf node

        while (self.getLongest(index) != 0) : (index = parent(index)) {
            node_size <<= 1;
            if (index == 0) {
                return;
            }
        }
        self.setLongest(index, node_size);

        log.info("Free page 0x{X} at order {}.", .{ offset, log2_int(usize, node_size) });
        log.info("Add page 0x{X} to order {}.", .{ offset, log2_int(usize, node_size) });

        while (index != 0) {
            index = parent(index);
            node_size <<= 1;

            const left_longest = self.getLongest(left(index));
            const right_longest = self.getLongest(right(index));

            if (left_longest + right_longest == node_size) {
                self.setLongest(index, node_size);
                log.info("Remove page 0x{X} from order {}.", .{ self.indexToOffset(left(index)), log2_int(usize, node_size >> 1) });
                log.info("Remove page 0x{X} from order {}.", .{ self.indexToOffset(right(index)), log2_int(usize, node_size >> 1) });
                log.info("Add page 0x{X} to order {}.", .{ self.indexToOffset(index), log2_int(usize, node_size) });
            } else {
                self.setLongest(index, @max(left_longest, right_longest));
            }
        }
    }

    pub fn size(self: *const Self, offset: usize) usize {
        return self.indexToSize(self.backward(offset));
    }

    fn backward(self: *const Self, offset: usize) usize {
        assert(offset < self.getLen());
        var index = offset + self.getLen() - 1; // start from leaf node
        while (self.getLongest(index) != 0) {
            index = parent(index);
        }
        return index;
    }

    inline fn setLen(self: *Self, len: usize) void {
        self.log_len = log2_int(usize, len);
    }

    inline fn getLen(self: *const Self) usize {
        return @as(usize, 1) << @as(Log2Usize, @intCast(self.log_len));
    }

    /// Map node_size
    /// 0 1 2 4 8 16 32 ...
    /// to log_longest
    /// 0 1 2 3 4 5  6  ...
    inline fn setLongest(self: *Self, index: usize, node_size: usize) void {
        const ptr: [*]u8 = @ptrCast(&self.log_longest);
        ptr[index] = log2_int(usize, node_size << 1 | 1);
    }

    inline fn getLongest(self: *const Self, index: usize) usize {
        const ptr: [*]const u8 = @ptrCast(&self.log_longest);
        return (@as(usize, 1) << @as(Log2Usize, @intCast(ptr[index]))) >> 1;
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
        return index << 1 | 1;
    }

    inline fn right(index: usize) usize {
        return (index << 1) + 2;
    }

    inline fn parent(index: usize) usize {
        return ((index + 1) >> 1) - 1;
    }

    inline fn indexToSize(self: *const Self, index: usize) usize {
        return self.getLen() >> log2_int(usize, index + 1);
    }

    inline fn indexToOffset(self: *const Self, index: usize) usize {
        return (index + 1) * self.indexToSize(index) - self.getLen();
    }
};

test "Buddy" {
    const heap_size = 16;

    const S = struct {
        var ctx: [2 * heap_size]u8 = undefined;
    };

    var buddy = Buddy.init(S.ctx[0..]);

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

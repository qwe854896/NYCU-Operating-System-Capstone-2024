const std = @import("std");

var buffer: [0x1000000]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);
pub const simple_allocator = fba.allocator();

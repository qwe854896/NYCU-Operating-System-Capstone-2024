const utils = @import("utils.zig");

const _heap_start = 0x800000;
var heap_offset: usize = 0;

/// Allocates a contiguous memory block of `size` bytes.
/// Align to 16 bytes.
pub fn simple_alloc(size: usize) []u8 {
    const ptr: [*]u8 = @ptrFromInt(_heap_start + heap_offset);
    heap_offset += size;
    heap_offset = utils.align_up(heap_offset, 16);
    return ptr[0..size];
}

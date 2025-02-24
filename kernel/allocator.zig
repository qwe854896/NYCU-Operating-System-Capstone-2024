// Reference: https://github.com/ziglang/zig/blob/cf90dfd3098bef5b3c22d5ab026173b3c357f2dd/lib/std/heap/PageAllocator.zig

const std = @import("std");
const utils = @import("utils.zig");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

// TODO: determine the address of fake heap
const _heap_start = 0x800000;
var heap_offset: usize = 0;

pub const SimpleAllocator: Allocator = .{
    .ptr = undefined,
    .vtable = &vtable,
};

const vtable: Allocator.VTable = .{
    .alloc = alloc,
    .resize = resize,
    .free = free,
};

/// Allocates a contiguous memory block of `len` bytes.
/// Align to 16 bytes.
fn alloc(_: *anyopaque, len: usize, log2_align: u8, _: usize) ?[*]u8 {
    assert(len > 0);

    const alignment = @as(usize, 1) << @as(Allocator.Log2Align, @intCast(log2_align));

    var addr = _heap_start + heap_offset;
    addr = utils.align_up(addr, alignment);

    const ptr: [*]u8 = @ptrFromInt(addr);
    addr += len;

    heap_offset = addr - _heap_start;

    return ptr;
}

/// `false` indicates the resize could not be completed without moving the
/// allocation to a different address.
fn resize(
    _: *anyopaque,
    _: []u8,
    _: u8,
    _: usize,
    _: usize,
) bool {
    return false;
}

fn free(_: *anyopaque, _: []u8, _: u8, _: usize) void {}

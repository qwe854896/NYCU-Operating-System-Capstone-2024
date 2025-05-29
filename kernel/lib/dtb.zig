const std = @import("std");
const dtb = @import("dtb/dtb.zig");

pub const Node = dtb.Node;
pub const Prop = dtb.Prop;
pub const totalSize = dtb.totalSize;

const Self = @This();

root: *Node,

pub fn init(allocator: std.mem.Allocator, dtb_address: usize) Self {
    const dtb_size = totalSize(@ptrFromInt(dtb_address)) catch 0;
    const dtb_slice = @as([*]const u8, @ptrFromInt(dtb_address))[0..dtb_size];
    return .{
        .root = dtb.parse(allocator, dtb_slice) catch {
            @panic("Error occured when parsing dtb files\n");
        },
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.root.deinit(allocator);
}

pub fn fdtTraverse(self: *const Self, callbackFunc: fn (*const Node) void) void {
    callbackFunc(self.root);
}

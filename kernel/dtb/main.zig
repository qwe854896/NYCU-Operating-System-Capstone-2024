const std = @import("std");
const dtb = @import("dtb.zig");

pub const Node = dtb.Node;
pub const Prop = dtb.Prop;

var dtb_root: *dtb.Node = undefined;

pub fn init(allocator: std.mem.Allocator, dtb_address: usize) u32 {
    const dtb_size = dtb.totalSize(@ptrFromInt(dtb_address)) catch 0;
    const dtb_slice = @as([*]const u8, @ptrFromInt(dtb_address))[0..dtb_size];

    dtb_root = dtb.parse(allocator, dtb_slice) catch {
        @panic("Error occured when parsing dtb files\n");
    };

    return dtb_size;
}

pub fn fdtTraverse(callbackFunc: fn (*dtb.Node) void) void {
    callbackFunc(dtb_root);
}

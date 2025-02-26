const std = @import("std");
const dtb = @import("dtb.zig");
const allocator = @import("../allocator.zig");

const simple_allocator = allocator.simple_allocator;

var dtb_root: *dtb.Node = undefined;

pub fn init(dtb_address: usize) void {
    const dtb_size = dtb.totalSize(@ptrFromInt(dtb_address)) catch 0;
    const dtb_slice = @as([*]const u8, @ptrFromInt(dtb_address))[0..dtb_size];

    dtb_root = dtb.parse(simple_allocator, dtb_slice) catch {
        @panic("Error occured when parsing dtb files\n");
    };

    std.log.info("DTB Address: 0x{X}", .{dtb_address});
    std.log.info("DTB Size: 0x{X}", .{dtb_size});
    // std.log.info("{}", .{dtb_root});
}

pub fn fdtTraverse(callbackFunc: fn (*dtb.Node) void) void {
    callbackFunc(dtb_root);
}

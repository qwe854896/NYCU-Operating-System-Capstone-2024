const VNode = @import("VNode.zig");

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    lookup: *const fn (*anyopaque, component_name: []const u8) ?*VNode,
    create: *const fn (*anyopaque, component_name: []const u8) ?*VNode,
    mkdir: *const fn (*anyopaque, component_name: []const u8) ?*VNode,
};

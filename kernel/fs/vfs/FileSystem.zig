const Allocator = @import("std").mem.Allocator;
const FileSystem = @import("FileSystem.zig");
const Mount = @import("Mount.zig");
const VNode = @import("VNode.zig");

vtable: *const VTable,
name: []const u8,

pub const VTable = struct {
    setupMount: *const fn (Allocator) ?Mount,
    releaseRoot: *const fn (*VNode) void,
};

const VNode = @import("VNode.zig");
const FileOperations = @import("FileOperations.zig");

vnode: *anyopaque,
f_pos: usize,
f_ops: FileOperations,
flags: Flags,

pub const Flags = packed struct(u32) {
    _unused0: u6 = 0,
    creat: bool = false,
    _unused7: u25 = 0,
};

const Mount = @import("Mount.zig");
const VNodeOperations = @import("VNodeOperations.zig");
const FileOperations = @import("FileOperations.zig");

ptr: *anyopaque,
mount: ?Mount,
v_ops: ?VNodeOperations,
f_ops: ?FileOperations,

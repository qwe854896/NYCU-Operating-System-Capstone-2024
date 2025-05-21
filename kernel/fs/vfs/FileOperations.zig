const std = @import("std");
const File = @import("File.zig");
const VNode = @import("VNode.zig");

vtable: *const VTable,

pub const VTable = struct {
    open: ?*const fn (*anyopaque) ?File = null,
    read: ?*const fn (file: *File, buf: []u8) usize = null,
    write: ?*const fn (file: *File, buf: []const u8) usize = null,
    close: ?*const fn (file: *File) usize = null,
    lseek64: ?*const fn (file: *File, offset: isize, whence: Whence) usize = null,
    ioctl: ?*const fn (file: *File, request: usize, arg: usize) usize = null,
};

pub const Whence = enum(usize) {
    seek_set = 0,
    seek_end = 2,
};

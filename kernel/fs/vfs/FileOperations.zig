const std = @import("std");
const File = @import("File.zig");
const VNode = @import("VNode.zig");

ptr: ?*anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    open: ?*const fn (*anyopaque) ?File,
    read: ?*const fn (file: *File, buf: []u8) usize,
    write: ?*const fn (file: *File, buf: []const u8) usize,
    close: ?*const fn (file: *File) usize,
    lseek64: ?*const fn (file: *File, offset: isize, whence: Whence) usize,
};

pub const Whence = enum(usize) {
    seek_set = 0,
};

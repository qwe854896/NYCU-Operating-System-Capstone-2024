const std = @import("std");
const dtb = @import("dtb/main.zig");

var initrd: []const u8 = undefined;

const Header = extern struct {
    magic: [6]u8 align(1),
    ino: [8]u8 align(1),
    mode: [8]u8 align(1),
    uid: [8]u8 align(1),
    gid: [8]u8 align(1),
    nlink: [8]u8 align(1),
    mtime: [8]u8 align(1),
    filesize: [8]u8 align(1),
    devmajor: [8]u8 align(1),
    devminor: [8]u8 align(1),
    rdevmajor: [8]u8 align(1),
    rdevminor: [8]u8 align(1),
    namesize: [8]u8 align(1),
    check: [8]u8 align(1),
};

fn alignUp(value: usize, size: usize) usize {
    return (value + size - 1) & ~(size - 1);
}

pub fn initRamfsCallback(dtb_root: *dtb.Node) void {
    var initrd_start_ptr: [*]const u8 = undefined;
    var initrd_end_ptr: [*]const u8 = undefined;

    if (dtb_root.child("chosen")) |chosen_root| {
        if (chosen_root.prop(dtb.Prop.LinuxInitrdStart)) |prop| {
            std.log.info("Initrd Start: 0x{X}", .{prop});
            initrd_start_ptr = @ptrFromInt(prop);
        }
        if (chosen_root.prop(dtb.Prop.LinuxInitrdEnd)) |prop| {
            std.log.info("Initrd End: 0x{X}", .{prop});
            initrd_end_ptr = @ptrFromInt(prop);
        }
    }

    const len: usize = @intFromPtr(initrd_end_ptr) - @intFromPtr(initrd_start_ptr);
    initrd = initrd_start_ptr[0..len];
}

pub fn listFiles(allocator: std.mem.Allocator) ?[][]const u8 {
    var files = std.ArrayList([]const u8).init(allocator);
    var offset: usize = 0;

    while (offset + @sizeOf(Header) <= initrd.len) {
        const header: *const Header = @alignCast(@ptrCast(initrd[offset..].ptr));

        if (std.mem.eql(u8, header.magic[0..6], "070701")) {
            offset += @sizeOf(Header);

            const name_size = std.fmt.parseInt(u32, header.namesize[0..8], 16) catch 0;
            if (offset + name_size > initrd.len) break;

            const name = initrd[offset .. offset + name_size - 1];

            offset = alignUp(offset + name_size, 4);

            if (std.mem.eql(u8, name, "TRAILER!!!")) break;

            files.appendSlice(&.{name}) catch {};

            const file_size = std.fmt.parseInt(u32, header.filesize[0..8], 16) catch 0;
            offset = alignUp(offset + file_size, 4);
        } else {
            break;
        }
    }
    return files.toOwnedSlice() catch null;
}

pub fn getFileContent(filename: []const u8) ?[]const u8 {
    var offset: usize = 0;

    while (offset + @sizeOf(Header) <= initrd.len) {
        const header: *const Header = @alignCast(@ptrCast(initrd[offset..].ptr));

        if (std.mem.eql(u8, header.magic[0..6], "070701")) {
            offset += @sizeOf(Header);

            const name_size = std.fmt.parseInt(u32, header.namesize[0..8], 16) catch 0;
            if (offset + name_size > initrd.len) break;

            const name = initrd[offset .. offset + name_size - 1];
            offset = alignUp(offset + name_size, 4);

            if (std.mem.eql(u8, name, "TRAILER!!!")) break;

            if (std.mem.eql(u8, name, filename)) {
                const file_size = std.fmt.parseInt(u32, header.filesize[0..8], 16) catch 0;
                if (offset + file_size > initrd.len) break;

                return initrd[offset .. offset + file_size];
            }

            const file_size = std.fmt.parseInt(u32, header.filesize[0..8], 16) catch 0;
            offset = alignUp(offset + file_size, 4);
        } else {
            break;
        }
    }
    return null;
}

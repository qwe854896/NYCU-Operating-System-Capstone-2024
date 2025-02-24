const std = @import("std");
const utils = @import("utils.zig");
const uart = @import("uart.zig");

const MiniUARTWriter = uart.MiniUARTWriter;

// TODO: enlarge the size of initramfs
const INITRAMFS_PTR: [*]const u8 = @ptrFromInt(0x8000000);
const INITRAMFS = INITRAMFS_PTR[0..65536];

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

pub fn list_files() void {
    var offset: usize = 0;

    while (offset + @sizeOf(Header) <= INITRAMFS.len) {
        const header: *const Header = @alignCast(@ptrCast(INITRAMFS[offset..].ptr));

        if (std.mem.eql(u8, header.magic[0..6], "070701")) {
            offset += @sizeOf(Header);

            const name_size = std.fmt.parseInt(u32, header.namesize[0..8], 16) catch 0;
            if (offset + name_size > INITRAMFS.len) break;

            const name = INITRAMFS[offset .. offset + name_size - 1];

            offset = utils.align_up(offset + name_size, 4);

            if (std.mem.eql(u8, name, "TRAILER!!!")) break;

            _ = MiniUARTWriter.write(name) catch {};
            _ = MiniUARTWriter.write("\n") catch {};

            const file_size = std.fmt.parseInt(u32, header.filesize[0..8], 16) catch 0;
            offset = utils.align_up(offset + file_size, 4);
        } else {
            break;
        }
    }
}

pub fn get_file_content(filename: []const u8) void {
    var offset: usize = 0;

    while (offset + @sizeOf(Header) <= INITRAMFS.len) {
        const header: *const Header = @alignCast(@ptrCast(INITRAMFS[offset..].ptr));

        if (std.mem.eql(u8, header.magic[0..6], "070701")) {
            offset += @sizeOf(Header);

            const name_size = std.fmt.parseInt(u32, header.namesize[0..8], 16) catch 0;
            if (offset + name_size > INITRAMFS.len) break;

            const name = INITRAMFS[offset .. offset + name_size - 1];
            offset = utils.align_up(offset + name_size, 4);

            if (std.mem.eql(u8, name, "TRAILER!!!")) break;

            if (std.mem.eql(u8, name, filename)) {
                const file_size = std.fmt.parseInt(u32, header.filesize[0..8], 16) catch 0;
                if (offset + file_size > INITRAMFS.len) break;

                _ = MiniUARTWriter.write(INITRAMFS[offset .. offset + file_size]) catch {};
                break;
            }

            const file_size = std.fmt.parseInt(u32, header.filesize[0..8], 16) catch 0;
            offset = utils.align_up(offset + file_size, 4);
        } else {
            break;
        }
    }
}

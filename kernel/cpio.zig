const std = @import("std");
const uart = @import("uart.zig");

const mini_uart_writer = uart.mini_uart_writer;

// TODO: enlarge the size of initramfs
const initrd_start_ptr: [*]const u8 = @ptrFromInt(0x8000000);
const initrd = initrd_start_ptr[0..65536];

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

pub fn listFiles() void {
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

            _ = mini_uart_writer.write(name) catch {};
            _ = mini_uart_writer.write("\n") catch {};

            const file_size = std.fmt.parseInt(u32, header.filesize[0..8], 16) catch 0;
            offset = alignUp(offset + file_size, 4);
        } else {
            break;
        }
    }
}

pub fn getFileContent(filename: []const u8) void {
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

                _ = mini_uart_writer.write(initrd[offset .. offset + file_size]) catch {};
                break;
            }

            const file_size = std.fmt.parseInt(u32, header.filesize[0..8], 16) catch 0;
            offset = alignUp(offset + file_size, 4);
        } else {
            break;
        }
    }
}

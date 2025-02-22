const std = @import("std");
const uart = @import("uart.zig");

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

fn parse_hex(buf: []const u8) u32 {
    return std.fmt.parseInt(u32, buf, 16) catch 0;
}

fn align_up(value: usize, size: usize) usize {
    return (value + size - 1) & ~(size - 1);
}

fn strcmp(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) {
        return false;
    }

    for (0.., a) |i, a_byte| {
        if (a_byte != b[i]) {
            return false;
        }
    }

    return true;
}

pub fn list_files(buffer: []const u8) void {
    var offset: usize = 0;

    while (offset + @sizeOf(Header) <= buffer.len) {
        const header: *const Header = @alignCast(@ptrCast(buffer[offset..].ptr));

        if (strcmp(header.magic[0..6], "070701")) {
            offset += @sizeOf(Header);

            const name_size = parse_hex(header.namesize[0..8]);
            if (offset + name_size > buffer.len) break;

            const name = buffer[offset .. offset + name_size - 1];

            offset = align_up(offset + name_size, 4);

            if (strcmp(name, "TRAILER!!!")) break;

            uart.send_str(name);
            uart.send_str("\n");

            const file_size = parse_hex(header.filesize[0..8]);
            offset = align_up(offset + file_size, 4);
        } else {
            break;
        }
    }
}

pub fn get_file_content(buffer: []const u8, filename: []const u8) void {
    var offset: usize = 0;

    while (offset + @sizeOf(Header) <= buffer.len) {
        const header: *const Header = @alignCast(@ptrCast(buffer[offset..].ptr));

        if (strcmp(header.magic[0..6], "070701")) {
            offset += @sizeOf(Header);

            const name_size = parse_hex(header.namesize[0..8]);
            if (offset + name_size > buffer.len) break;

            const name = buffer[offset .. offset + name_size - 1];
            offset = align_up(offset + name_size, 4);

            if (strcmp(name, "TRAILER!!!")) break;

            if (strcmp(name, filename)) {
                const file_size = parse_hex(header.filesize[0..8]);
                if (offset + file_size > buffer.len) break;

                uart.send_str(buffer[offset .. offset + file_size]);
                break;
            }

            const file_size = parse_hex(header.filesize[0..8]);
            offset = align_up(offset + file_size, 4);
        } else {
            break;
        }
    }
}

const std = @import("std");
const entries = @import("entries.zig");

pub const Error = error{
    BadMagic,
    Truncated,
    InvalidHeader,
    OutOfMemory,
};

pub const Header = struct {
    filesize: usize,
    namesize: usize,
    name: []const u8,
    data_offset: usize,
};

pub fn parse(allocator: std.mem.Allocator, blob: []const u8) Error![]entries.Entry {
    var list = std.ArrayList(entries.Entry).init(allocator);
    errdefer list.deinit();

    var offset: usize = 0;

    while (offset + @sizeOf(entries.CpioHeader) <= blob.len) {
        const header_ptr: *const entries.CpioHeader = @alignCast(@ptrCast(blob[offset..].ptr));

        if (!std.mem.eql(u8, &header_ptr.magic, "070701"))
            return error.BadMagic;

        const filesize = try parseHexField(header_ptr.filesize[0..8]);
        const namesize = try parseHexField(header_ptr.namesize[0..8]);

        offset += @sizeOf(entries.CpioHeader);

        if (offset + namesize > blob.len)
            return error.Truncated;

        const name = blob[offset..][0 .. namesize - 1];
        offset = alignUp(offset + namesize, 4);

        if (std.mem.eql(u8, name, "TRAILER!!!"))
            break;

        try list.append(.{
            .name = name[0 .. std.mem.indexOfScalar(u8, name, 0) orelse name.len],
            .size = filesize,
            .offset = offset,
        });

        offset = alignUp(offset + filesize, 4);
    }

    return list.toOwnedSlice();
}

fn parseHexField(field: []const u8) Error!usize {
    return std.fmt.parseInt(usize, field, 16) catch error.InvalidHeader;
}

fn alignUp(value: usize, alignment: usize) usize {
    return (value + alignment - 1) & ~(alignment - 1);
}

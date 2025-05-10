pub const CpioHeader = extern struct {
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

pub const Entry = struct {
    name: []const u8,
    size: usize,
    offset: usize,
};

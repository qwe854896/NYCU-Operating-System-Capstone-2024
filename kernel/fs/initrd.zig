const std = @import("std");
const dtb = @import("../lib/dtb.zig");
const Cpio = @import("../lib/Cpio.zig");

var blob: []const u8 = undefined;

pub fn initRamfsCallback(dtb_root: *const dtb.Node) void {
    var initrd_start_ptr: [*]const u8 = undefined;
    var initrd_end_ptr: [*]const u8 = undefined;

    if (dtb_root.propAt(&.{"chosen"}, .LinuxInitrdStart)) |prop| {
        initrd_start_ptr = @ptrFromInt(prop);
    }
    if (dtb_root.propAt(&.{"chosen"}, .LinuxInitrdEnd)) |prop| {
        initrd_end_ptr = @ptrFromInt(prop);
    }

    const len: usize = @intFromPtr(initrd_end_ptr) - @intFromPtr(initrd_start_ptr);

    initrd_start_ptr += 0xFFFF000000000000; // workaround
    blob = initrd_start_ptr[0..len];
}

pub fn getInitrdStartPtr() usize {
    return @intFromPtr(blob.ptr) - 0xFFFF000000000000; // workaround
}

pub fn getInitrdEndPtr() usize {
    return @intFromPtr(blob.ptr) - 0xFFFF000000000000 + blob.len; // workaround
}

pub const Initrd = struct {
    const Self = @This();

    cpio: Cpio,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .cpio = Cpio.init(allocator, blob) catch {
                @panic("Error occurred when parsing initrd files\n");
            },
        };
    }

    pub fn deinit(self: *Self) void {
        self.cpio.deinit();
    }

    pub fn getFileContent(self: Self, filename: []const u8) ?[]const u8 {
        const entry = self.cpio.get(filename);
        if (entry) |e| {
            return self.cpio.getFileContent(e);
        } else {
            return null;
        }
    }

    pub fn listFiles(self: Self) []const Cpio.Entry {
        return self.cpio.list();
    }
};

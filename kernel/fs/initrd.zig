const std = @import("std");
const dtb = @import("../lib/dtb.zig");
const cpio = @import("../lib/cpio.zig");

var initrd_start_ptr: [*]const u8 = undefined;
var initrd_end_ptr: [*]const u8 = undefined;
var initrd: []const u8 = undefined;

pub fn init(allocator: std.mem.Allocator) void {
    cpio.Cpio.init(allocator, initrd) catch {
        @panic("Error occurred when parsing initrd files\n");
    };
}

pub fn deinit() void {
    cpio.Cpio.deinit();
}

pub fn initRamfsCallback(dtb_root: *dtb.Node) void {
    if (dtb_root.propAt(&.{"chosen"}, .LinuxInitrdStart)) |prop| {
        initrd_start_ptr = @ptrFromInt(prop);
    }
    if (dtb_root.propAt(&.{"chosen"}, .LinuxInitrdEnd)) |prop| {
        initrd_end_ptr = @ptrFromInt(prop);
    }

    const len: usize = @intFromPtr(initrd_end_ptr) - @intFromPtr(initrd_start_ptr);
    initrd_start_ptr += 0xFFFF000000000000; // workaround
    initrd = initrd_start_ptr[0..len];
    initrd_start_ptr -= 0xFFFF000000000000; // workaround
}

pub fn getInitrdStartPtr() usize {
    return @intFromPtr(initrd_start_ptr);
}

pub fn getInitrdEndPtr() usize {
    return @intFromPtr(initrd_end_ptr);
}

pub fn getFileContent(filename: []const u8) ?[]const u8 {
    const entry = cpio.Cpio.get(filename);
    if (entry) |e| {
        return cpio.Cpio.getFileContent(e);
    } else {
        return null;
    }
}

pub fn listFiles() []const cpio.Entry {
    return cpio.list();
}

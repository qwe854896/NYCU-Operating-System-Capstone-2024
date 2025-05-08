const std = @import("std");
const parser = @import("parser.zig");
const entries = @import("entries.zig");

pub const Entry = entries.Entry;
pub const Error = parser.Error;

var cpio: Cpio = undefined;

pub const Cpio = struct {
    const Self = @This();

    entries: []Entry,
    allocator: std.mem.Allocator,
    blob: []const u8,

    pub fn init(allocator: std.mem.Allocator, blob: []const u8) Error!void {
        cpio = .{
            .entries = try parser.parse(allocator, blob),
            .allocator = allocator,
            .blob = blob,
        };
    }

    pub fn deinit() void {
        const self: *Self = @ptrCast(@alignCast(&cpio));
        self.allocator.free(self.entries);
    }

    pub fn get(filename: []const u8) ?Entry {
        const self: *Self = @ptrCast(@alignCast(&cpio));
        for (self.entries) |entry| {
            if (std.mem.eql(u8, entry.name, filename)) return entry;
        }
        return null;
    }

    pub fn getFileContent(entry: Entry) []const u8 {
        const self: *Self = @ptrCast(@alignCast(&cpio));
        return self.blob[entry.offset..][0..entry.size];
    }
};

pub fn list() []const Entry {
    return cpio.entries;
}

const std = @import("std");
const parser = @import("cpio/parser.zig");

pub const Entry = @import("cpio/entries.zig").Entry;
pub const Error = parser.Error;

const Self = @This();

entries: []Entry,
allocator: std.mem.Allocator,
blob: []const u8,

pub fn init(allocator: std.mem.Allocator, blob: []const u8) Error!Self {
    return .{
        .entries = try parser.parse(allocator, blob),
        .allocator = allocator,
        .blob = blob,
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.entries);
}

pub fn get(self: Self, filename: []const u8) ?Entry {
    for (self.entries) |entry| {
        if (std.mem.eql(u8, entry.name, filename)) return entry;
    }
    return null;
}

pub fn getFileContent(self: Self, entry: Entry) []const u8 {
    return self.blob[entry.offset..][0..entry.size];
}

pub fn list(self: Self) []const Entry {
    return self.entries;
}

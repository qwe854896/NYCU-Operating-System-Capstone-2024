// Reference: https://www.scattered-thoughts.net/writing/mmio-in-zig/
const std = @import("std");

pub const base_address = 0x3F000000;

pub fn Register(comptime Read: type, comptime Write: type) type {
    return struct {
        raw_ptr: *volatile u32,

        const Self = @This();

        pub fn init(address: usize) Self {
            return .{ .raw_ptr = @ptrFromInt(address) };
        }

        fn read_raw(self: Self) u32 {
            return self.raw_ptr.*;
        }

        fn write_raw(self: Self, value: u32) void {
            self.raw_ptr.* = value;
        }

        pub fn read(self: Self) Read {
            return @bitCast(self.raw_ptr.*);
        }

        pub fn write(self: Self, value: Write) void {
            self.raw_ptr.* = @bitCast(value);
        }

        pub fn modify(self: Self, new_value: anytype) void {
            if (Read != Write) {
                @compileError("Can't modify because read and write types for this register aren't the same.");
            }
            var old_value = self.read();
            inline for (std.meta.fields(@TypeOf(new_value))) |field| {
                @field(old_value, field.name) = @field(new_value, field.name);
            }
            self.write(old_value);
        }
    };
}

// Reference: https://www.scattered-thoughts.net/writing/mmio-in-zig/

pub const base_address = 0x3F000000;

pub const Register = struct {
    raw_ptr: *volatile u32, // It's important to use volatile, so reads and writes are never optimized

    pub fn init(address: usize) Register {
        return Register{ .raw_ptr = @ptrFromInt(address) };
    }

    pub fn readRaw(self: Register) u32 {
        return self.raw_ptr.*;
    }

    pub fn writeRaw(self: Register, value: u32) void {
        self.raw_ptr.* = value;
    }
};

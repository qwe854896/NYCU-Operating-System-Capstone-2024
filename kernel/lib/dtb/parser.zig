const std = @import("std");
const dtb = @import("dtb.zig");
const traverser = @import("traverser.zig");

pub const Error = traverser.Error || std.mem.Allocator.Error || error{
    MissingCells,
    UnsupportedCells,
    BadValue,
};

pub fn parse(allocator: std.mem.Allocator, blob: []const u8) Error!*dtb.Node {
    var parser: Parser = undefined;
    try parser.init(allocator, blob);

    var root =
        switch (try parser.traverser.event()) {
            .BeginNode => |node_name| try parser.handleNode(node_name, null, null),
            else => return error.BadStructure,
        };
    errdefer root.deinit(allocator);

    switch (try parser.traverser.event()) {
        .End => {},
        else => return error.Internal,
    }

    return root;
}

/// ---
const Parser = struct {
    const Self = @This();

    allocator: std.mem.Allocator = undefined,
    traverser: traverser.Traverser = undefined,

    fn init(self: *Self, allocator: std.mem.Allocator, blob: []const u8) !void {
        self.* = Parser{
            .allocator = allocator,
            .traverser = undefined,
        };
        try self.traverser.init(blob);
    }

    fn handleNode(self: *Self, node_name: []const u8, root: ?*dtb.Node, parent: ?*dtb.Node) Error!*dtb.Node {
        var props = std.ArrayList(dtb.Prop).init(self.allocator);
        var children = std.ArrayList(*dtb.Node).init(self.allocator);

        errdefer {
            for (props.items) |p| {
                p.deinit(self.allocator);
            }
            props.deinit();
            for (children.items) |c| {
                c.deinit(self.allocator);
            }
            children.deinit();
        }

        const node = try self.allocator.create(dtb.Node);
        errdefer self.allocator.destroy(node);

        while (true) {
            switch (try self.traverser.event()) {
                .BeginNode => |child_name| {
                    var subnode = try self.handleNode(child_name, root orelse node, node);
                    errdefer subnode.deinit(self.allocator);
                    try children.append(subnode);
                },
                .EndNode => {
                    break;
                },
                .Prop => |prop| {
                    var parsedProp = try self.handleProp(prop.name, prop.value);
                    errdefer parsedProp.deinit(self.allocator);
                    try props.append(parsedProp);
                },
                .End => return error.Internal,
            }
        }
        node.* = .{
            .name = node_name,
            .props = try props.toOwnedSlice(),
            .root = root orelse node,
            .parent = parent,
            .children = try children.toOwnedSlice(),
        };
        return node;
    }

    fn handleProp(self: *Parser, name: []const u8, value: []const u8) Error!dtb.Prop {
        if (std.mem.eql(u8, name, "#address-cells")) {
            return dtb.Prop{ .AddressCells = try integer(u32, value) };
        } else if (std.mem.eql(u8, name, "#size-cells")) {
            return dtb.Prop{ .SizeCells = try integer(u32, value) };
        } else if (std.mem.eql(u8, name, "#interrupt-cells")) {
            return dtb.Prop{ .InterruptCells = try integer(u32, value) };
        } else if (std.mem.eql(u8, name, "#clock-cells")) {
            return dtb.Prop{ .ClockCells = try integer(u32, value) };
        } else if (std.mem.eql(u8, name, "reg-shift")) {
            return dtb.Prop{ .RegShift = try integer(u32, value) };
        } else if (std.mem.eql(u8, name, "status")) {
            return dtb.Prop{ .Status = try status(value) };
        } else if (std.mem.eql(u8, name, "phandle")) {
            return dtb.Prop{ .PHandle = try integer(u32, value) };
        } else if (std.mem.eql(u8, name, "interrupt-controller")) {
            return .InterruptController;
        } else if (std.mem.eql(u8, name, "interrupt-parent")) {
            return dtb.Prop{ .InterruptParent = try integer(u32, value) };
        } else if (std.mem.eql(u8, name, "compatible")) {
            return dtb.Prop{ .Compatible = try self.stringList(value) };
        } else if (std.mem.eql(u8, name, "clock-names")) {
            return dtb.Prop{ .ClockNames = try self.stringList(value) };
        } else if (std.mem.eql(u8, name, "clock-output-names")) {
            return dtb.Prop{ .ClockOutputNames = try self.stringList(value) };
        } else if (std.mem.eql(u8, name, "interrupt-names")) {
            return dtb.Prop{ .InterruptNames = try self.stringList(value) };
        } else if (std.mem.eql(u8, name, "clock-frequency")) {
            return dtb.Prop{ .ClockFrequency = try u32OrU64(value) };
        } else if (std.mem.eql(u8, name, "reg-io-width")) {
            return dtb.Prop{ .RegIoWidth = try u32OrU64(value) };
        } else if (std.mem.eql(u8, name, "pinctrl-names")) {
            return dtb.Prop{ .PinctrlNames = try self.stringList(value) };
        } else if (std.mem.eql(u8, name, "pinctrl-0")) {
            return dtb.Prop{ .Pinctrl0 = try self.integerList(u32, value) };
        } else if (std.mem.eql(u8, name, "pinctrl-1")) {
            return dtb.Prop{ .Pinctrl1 = try self.integerList(u32, value) };
        } else if (std.mem.eql(u8, name, "pinctrl-2")) {
            return dtb.Prop{ .Pinctrl2 = try self.integerList(u32, value) };
        } else if (std.mem.eql(u8, name, "assigned-clock-rates")) {
            return dtb.Prop{ .AssignedClockRates = try self.integerList(u32, value) };
        } else if (std.mem.eql(u8, name, "device_type")) {
            return dtb.Prop{ .DeviceType = string(value) };
        } else if (std.mem.eql(u8, name, "linux,initrd-start")) {
            return dtb.Prop{ .LinuxInitrdStart = try u32OrU64(value) };
        } else if (std.mem.eql(u8, name, "linux,initrd-end")) {
            return dtb.Prop{ .LinuxInitrdEnd = try u32OrU64(value) };
        } else {
            return dtb.Prop{ .Unknown = .{ .name = name, .value = value } };
        }
    }

    fn integer(comptime T: type, value: []const u8) !T {
        if (value.len != @sizeOf(T))
            return error.BadStructure;
        return std.mem.readInt(T, value[0..@sizeOf(T)], .big);
    }

    fn integerList(self: *Parser, comptime T: type, value: []const u8) ![]T {
        if (value.len % @sizeOf(T) != 0)
            return error.BadStructure;
        var list = try self.allocator.alloc(T, value.len / @sizeOf(T));
        var i: usize = 0;
        while (i < list.len) : (i += 1) {
            list[i] = std.mem.bigToNative(T, @as(*const T, @alignCast(@ptrCast(value[i * @sizeOf(T) ..].ptr))).*);
        }
        return list;
    }

    fn u32OrU64(value: []const u8) !u64 {
        return switch (value.len) {
            @sizeOf(u32) => @as(u64, try integer(u32, value)),
            @sizeOf(u64) => try integer(u64, value),
            else => error.BadStructure,
        };
    }

    fn string(value: []const u8) []const u8 {
        return value[0 .. value.len - 1];
    }

    fn stringList(self: *Parser, value: []const u8) Error![][]const u8 {
        const count = std.mem.count(u8, value, "\x00");
        var strings = try self.allocator.alloc([]const u8, count);
        errdefer self.allocator.free(strings);
        var offset: usize = 0;
        var strings_i: usize = 0;
        while (offset < value.len) : (strings_i += 1) {
            const len = std.mem.len(@as([*c]const u8, @ptrCast(value[offset..])));
            strings[strings_i] = value[offset .. offset + len];
            offset += len + 1;
        }
        return strings;
    }

    fn status(value: []const u8) Error!dtb.PropStatus {
        if (std.mem.eql(u8, value, "okay\x00")) {
            return dtb.PropStatus.Okay;
        } else if (std.mem.eql(u8, value, "disabled\x00")) {
            return dtb.PropStatus.Disabled;
        } else if (std.mem.eql(u8, value, "fail\x00")) {
            return dtb.PropStatus.Fail;
        }
        return error.BadValue;
    }
};

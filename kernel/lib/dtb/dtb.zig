const std = @import("std");
const parser = @import("parser.zig");
const traverser = @import("traverser.zig");
pub const Traverser = traverser.Traverser;
pub const totalSize = traverser.totalSize;

pub const Node = struct {
    name: []const u8,
    props: []Prop,
    root: *Node,
    parent: ?*Node,
    children: []*Node,

    pub fn propAt(start: *const Node, path: []const []const u8, comptime prop_tag: std.meta.Tag(Prop)) ?std.meta.TagPayload(Prop, prop_tag) {
        var node: *const Node = start;
        var i: usize = 0;
        while (i < path.len) : (i += 1) {
            node = node.child(path[i]) orelse return null;
        }
        return node.prop(prop_tag);
    }

    pub fn child(node: *const Node, child_name: []const u8) ?*Node {
        for (node.children) |c| {
            if (std.mem.eql(u8, child_name, c.name)) {
                return c;
            }
        }
        return null;
    }

    pub fn prop(node: *const Node, comptime prop_tag: std.meta.Tag(Prop)) ?std.meta.TagPayload(Prop, prop_tag) {
        for (node.props) |p| {
            if (p == prop_tag) {
                return @field(p, @tagName(prop_tag));
            }
        }
        return null;
    }

    pub fn interruptCells(node: *Node) ?u32 {
        if (node.interruptParent()) |ip| {
            if (ip.prop(.InterruptCells)) |ic| {
                return ic;
            } else {
                return ip.interruptCells();
            }
        }

        if (node.prop(.InterruptCells)) |ic| {
            return ic;
        }

        return null;
    }

    pub fn interruptParent(node: *Node) ?*Node {
        if (node.prop(.InterruptParent)) |ip| {
            return node.root.findPHandle(ip);
        }
        return node.parent;
    }

    pub fn findPHandle(node: *Node, phandle: u32) ?*Node {
        if (node.prop(.PHandle)) |v| {
            if (v == phandle) {
                return node;
            }
        }
        for (node.children) |c| {
            if (c.findPHandle(phandle)) |n| {
                return n;
            }
        }
        return null;
    }

    pub fn addressCells(node: *const Node) ?u32 {
        return node.prop(.AddressCells) orelse (node.parent orelse return null).addressCells();
    }

    pub fn sizeCells(node: *const Node) ?u32 {
        return node.prop(.SizeCells) orelse (node.parent orelse return null).sizeCells();
    }

    pub fn deinit(node: *Node, allocator: std.mem.Allocator) void {
        for (node.props) |p| {
            p.deinit(allocator);
        }
        allocator.free(node.props);
        for (node.children) |c| {
            c.deinit(allocator);
        }
        allocator.free(node.children);
        allocator.destroy(node);
    }

    pub fn format(node: Node, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try node.formatNode(writer, 0);
    }

    fn formatNode(node: Node, writer: anytype, depth: usize) !void {
        try indent(writer, depth);
        try std.fmt.format(writer, "Node <{'}>\n", .{std.zig.fmtEscapes(node.name)});
        for (node.props) |p| {
            try indent(writer, depth + 1);
            try std.fmt.format(writer, "{}\n", .{p});
        }
        for (node.children) |c| {
            try c.formatNode(writer, depth + 1);
        }
    }

    fn indent(writer: anytype, depth: usize) !void {
        var i: usize = 0;
        while (i < depth) : (i += 1) {
            try writer.writeAll("  ");
        }
    }
};

pub const PropStatus = enum {
    Okay,
    Disabled,
    Fail,

    pub fn format(status: PropStatus, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (status) {
            .Okay => try writer.writeAll("okay"),
            .Disabled => try writer.writeAll("disabled"),
            .Fail => try writer.writeAll("fail"),
        }
    }
};

pub const Prop = union(enum) {
    AddressCells: u32,
    SizeCells: u32,
    InterruptCells: u32,
    ClockCells: u32,
    RegShift: u32,
    PHandle: u32,
    InterruptParent: u32,
    Reg: [][2]u128,
    Ranges: [][3]u128,
    Compatible: [][]const u8,
    Status: PropStatus,
    Interrupts: [][]u32,
    Clocks: [][]u32,
    ClockNames: [][]const u8,
    ClockOutputNames: [][]const u8,
    ClockFrequency: u64,
    InterruptController: void,
    InterruptNames: [][]const u8,
    RegIoWidth: u64,
    PinctrlNames: [][]const u8,
    Pinctrl0: []u32,
    Pinctrl1: []u32,
    Pinctrl2: []u32,
    AssignedClockRates: []u32,
    AssignedClocks: [][]u32,
    DeviceType: []const u8,
    LinuxInitrdStart: u64,
    LinuxInitrdEnd: u64,
    Unknown: PropUnknown,

    pub fn format(prop: Prop, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (prop) {
            .AddressCells => |v| try std.fmt.format(writer, "#address-cells: 0x{x:0>2}", .{v}),
            .SizeCells => |v| try std.fmt.format(writer, "#size-cells: 0x{x:0>2}", .{v}),
            .InterruptCells => |v| try std.fmt.format(writer, "#interrupt-cells: 0x{x:0>2}", .{v}),
            .ClockCells => |v| try std.fmt.format(writer, "#clock-cells: 0x{x:0>2}", .{v}),
            .RegShift => |v| try std.fmt.format(writer, "reg-shift: 0x{x:0>2}", .{v}),
            .Reg => |v| {
                try writer.writeAll("reg: <");
                for (v, 0..) |pair, i| {
                    if (i != 0) {
                        try writer.writeAll(">, <");
                    }
                    try std.fmt.format(writer, "0x{x:0>2} 0x{x:0>2}", .{ pair[0], pair[1] });
                }
                try writer.writeByte('>');
            },
            .Ranges => |v| {
                try writer.writeAll("ranges: <");
                for (v, 0..) |triple, i| {
                    if (i != 0) {
                        try writer.writeAll(">, <");
                    }
                    try std.fmt.format(writer, "0x{x:0>2} 0x{x:0>2} 0x{x:0>2}", .{ triple[0], triple[1], triple[2] });
                }
                try writer.writeByte('>');
            },
            .Compatible => |v| try (StringListFormatter{ .string_list = v }).write("compatible: ", writer),
            .Status => |v| try std.fmt.format(writer, "status: \"{s}\"", .{v}),
            .PHandle => |v| try std.fmt.format(writer, "phandle: <0x{x:0>2}>", .{v}),
            .InterruptController => try std.fmt.format(writer, "interrupt-controller", .{}),
            .InterruptParent => |v| try std.fmt.format(writer, "interrupt-parent: <0x{x:0>2}>", .{v}),
            .Interrupts => |groups| {
                try writer.writeAll("interrupts: <");
                for (groups, 0..) |group, i| {
                    if (i != 0) {
                        try writer.writeAll(">, <");
                    }
                    for (group, 0..) |item, j| {
                        if (j != 0) {
                            try writer.writeAll(" ");
                        }
                        try std.fmt.format(writer, "0x{x:0>2}", .{item});
                    }
                }
                try writer.writeAll(">");
            },
            .Clocks,
            .AssignedClocks,
            => |groups| {
                switch (prop) {
                    .Clocks => try writer.writeAll("clocks: <"),
                    .AssignedClocks => try writer.writeAll("assigned-clocks: <"),
                    else => unreachable,
                }
                for (groups, 0..) |group, i| {
                    if (i != 0) {
                        try writer.writeAll(">, <");
                    }
                    for (group, 0..) |item, j| {
                        if (j != 0) {
                            try writer.writeAll(" ");
                        }
                        try std.fmt.format(writer, "0x{x:0>2}", .{item});
                    }
                }
                try writer.writeAll(">");
            },
            .ClockNames => |v| try (StringListFormatter{ .string_list = v }).write("clock-names: ", writer),
            .ClockOutputNames => |v| try (StringListFormatter{ .string_list = v }).write("clock-output-names: ", writer),
            .ClockFrequency => |v| try (FrequencyFormatter{ .freq = v }).write("clock-frequency: ", writer),
            .InterruptNames => |v| try (StringListFormatter{ .string_list = v }).write("interrupt-names: ", writer),
            .RegIoWidth => |v| try std.fmt.format(writer, "reg-io-width: 0x{x:0>2}", .{v}),
            .PinctrlNames => |v| try (StringListFormatter{ .string_list = v }).write("pinctrl-names: ", writer),
            .Pinctrl0, .Pinctrl1, .Pinctrl2 => |phandles| {
                try std.fmt.format(writer, "pinctrl{s}: <", .{switch (prop) {
                    .Pinctrl0 => "0",
                    .Pinctrl1 => "1",
                    .Pinctrl2 => "2",
                    else => unreachable,
                }});
                for (phandles, 0..) |phandle, i| {
                    if (i != 0) {
                        try writer.writeAll(" ");
                    }
                    try std.fmt.format(writer, "0x{x:0>4}", .{phandle});
                }
                try writer.writeByte('>');
            },
            .AssignedClockRates => |clock_rates| {
                try writer.writeAll("assigned-clock-rates: <");
                for (clock_rates, 0..) |clock_rate, i| {
                    if (i != 0) {
                        try writer.writeAll(" ");
                    }
                    try (FrequencyFormatter{ .freq = clock_rate }).write("", writer);
                }
                try writer.writeByte('>');
            },
            .DeviceType => |v| try std.fmt.format(writer, "device_type: \"{s}\"", .{v}),
            .LinuxInitrdStart => |v| try std.fmt.format(writer, "linux,initrd-start: 0x{x:0>2}", .{v}),
            .LinuxInitrdEnd => |v| try std.fmt.format(writer, "linux,initrd-end: 0x{x:0>2}", .{v}),
            .Unknown => |v| try std.fmt.format(writer, "{'}: (unk {} bytes) <{}>", .{ std.zig.fmtEscapes(v.name), v.value.len, std.zig.fmtEscapes(v.value) }),
        }
    }

    const FrequencyFormatter = struct {
        freq: u64,

        // Exists to work around https://github.com/ziglang/zig/issues/7534.
        pub fn write(this: @This(), comptime prefix: []const u8, writer: anytype) !void {
            try writer.writeAll(prefix);
            try this.format("", .{}, writer);
        }

        pub fn format(this: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            if (this.freq / 1_000_000_000 > 0) {
                try std.fmt.format(writer, "{d}GHz", .{@as(f32, @floatFromInt(this.freq / 1_000_000)) / 1_000});
            } else if (this.freq / 1_000_000 > 0) {
                try std.fmt.format(writer, "{d}MHz", .{@as(f32, @floatFromInt(this.freq / 1_000)) / 1_000});
            } else if (this.freq / 1_000 > 0) {
                try std.fmt.format(writer, "{d}kHz", .{@as(f32, @floatFromInt(this.freq)) / 1_000});
            } else {
                try std.fmt.format(writer, "{}Hz", .{this.freq});
            }
        }
    };
    const StringListFormatter = struct {
        string_list: [][]const u8,

        // Exists to work around https://github.com/ziglang/zig/issues/7534.
        pub fn write(this: @This(), comptime prefix: []const u8, writer: anytype) !void {
            try writer.writeAll(prefix);
            try this.format("", .{}, writer);
        }

        pub fn format(this: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.writeByte('"');
            for (this.string_list, 0..) |s, i| {
                if (i != 0) {
                    try writer.writeAll("\", \"");
                }
                try writer.writeAll(s);
            }
            try writer.writeByte('"');
        }
    };

    pub fn deinit(prop: Prop, allocator: std.mem.Allocator) void {
        switch (prop) {
            .Reg => |v| allocator.free(v),
            .Ranges => |v| allocator.free(v),

            .Compatible,
            .ClockNames,
            .ClockOutputNames,
            .InterruptNames,
            .PinctrlNames,
            => |v| allocator.free(v),

            .Interrupts,
            .Clocks,
            .AssignedClocks,
            => |groups| {
                for (groups) |group| {
                    allocator.free(group);
                }
                allocator.free(groups);
            },

            .Pinctrl0,
            .Pinctrl1,
            .Pinctrl2,
            => |phandles| allocator.free(phandles),

            .AssignedClockRates => |clock_rates| allocator.free(clock_rates),

            .AddressCells,
            .SizeCells,
            .InterruptCells,
            .ClockCells,
            .RegShift,
            .PHandle,
            .InterruptController,
            .InterruptParent,
            .Status,
            .Unknown,
            .ClockFrequency,
            .RegIoWidth,
            .DeviceType,
            .LinuxInitrdStart,
            .LinuxInitrdEnd,
            => {},
        }
    }
};

pub const PropUnknown = struct {
    name: []const u8,
    value: []const u8,
};

pub const parse = parser.parse;
pub const Error = parser.Error;

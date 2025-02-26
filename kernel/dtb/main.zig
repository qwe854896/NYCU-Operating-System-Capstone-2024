const dtb = @import("dtb.zig");
const uart = @import("../uart.zig");
const allocator = @import("../allocator.zig");

const mini_uart_writer = uart.mini_uart_writer;
const simple_allocator = allocator.simple_allocator;

var dtb_root: *dtb.Node = undefined;

pub fn init(dtb_address: usize) void {
    const dtb_size = dtb.totalSize(@ptrFromInt(dtb_address)) catch 0;
    const dtb_slice = @as([*]const u8, @ptrFromInt(dtb_address))[0..dtb_size];

    _ = mini_uart_writer.print("DTB Address: 0x{X}\n", .{dtb_address}) catch {};
    _ = mini_uart_writer.print("DTB Size: 0x{X}\n", .{dtb_size}) catch {};

    dtb_root = dtb.parse(simple_allocator, dtb_slice) catch {
        @panic("Error occured when parsing dtb files\n");
    };

    // dtb_root.format("", .{}, mini_uart_writer) catch {
    //     @panic("Cannot print the format string of dtb prop");
    // };
}

pub fn fdtTraverse(callbackFunc: fn (*dtb.Node) void) void {
    callbackFunc(dtb_root);
}

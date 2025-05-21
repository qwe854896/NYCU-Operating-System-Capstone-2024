const drivers = @import("drivers");
const vfs = @import("vfs.zig");
const sched = @import("../sched.zig");
const uart = drivers.uart;

const File = vfs.File;
const FileOperations = vfs.FileOperations;
const Whence = FileOperations.Whence;

const Self = @This();

pub fn fileNodeOps() FileOperations {
    return .{
        .vtable = &.{
            .open = open,
            .read = null,
            .write = null,
            .close = null,
            .lseek64 = null,
        },
    };
}

fn fileOps() FileOperations {
    return .{
        .vtable = &.{
            .open = null,
            .read = read,
            .write = write,
            .close = close,
            .lseek64 = lseek64,
        },
    };
}

fn open(ctx: *anyopaque) ?File {
    return .{
        .vnode = ctx,
        .f_pos = 0,
        .f_ops = fileOps(),
        .flags = .{},
    };
}

fn yieldRecv() u8 {
    while (!uart.aux_mu_lsr.read().rx_ready) {
        sched.schedule();
    }
    return uart.aux_mu_io.read().data;
}

fn read(_: *File, buf: []u8) usize {
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        buf[i] = yieldRecv();
    }
    return buf.len;
}

fn write(_: *File, buf: []const u8) usize {
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        uart.send(buf[i]);
    }
    return buf.len;
}

fn close(_: *File) usize {
    return 0;
}

fn lseek64(_: *File, _: isize, _: Whence) usize {
    return 0;
}

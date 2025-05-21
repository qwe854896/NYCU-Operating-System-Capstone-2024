const std = @import("std");
const drivers = @import("drivers");
const vfs = @import("vfs.zig");
const mailbox = drivers.mailbox;
const log = std.log.scoped(.framebuffer);

const File = vfs.File;
const FileOperations = vfs.FileOperations;
const Whence = FileOperations.Whence;

const Self = @This();

var lfb: []u8 = undefined;

pub fn fileNodeOps() FileOperations {
    return .{
        .ptr = null,
        .vtable = &.{
            .open = open,
        },
    };
}

fn fileOps() FileOperations {
    return .{
        .ptr = null,
        .vtable = &.{
            .open = null,
            .read = read,
            .write = write,
            .close = close,
            .lseek64 = lseek64,
            .ioctl = ioctl,
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

fn read(_: *File, _: []u8) usize {
    return 0;
}

fn write(file: *File, buf: []const u8) usize {
    const bytes_to_write = @min(buf.len, lfb.len - file.f_pos);
    @memcpy(lfb[file.f_pos..][0..bytes_to_write], buf[0..bytes_to_write]);
    file.f_pos += bytes_to_write;
    return bytes_to_write;
}

fn close(_: *File) usize {
    return 0;
}

fn lseek64(file: *File, offset: isize, whence: Whence) usize {
    switch (whence) {
        .seek_set => file.f_pos = @intCast(offset),
        .seek_end => file.f_pos = @intCast(@as(isize, @intCast(lfb.len)) + offset),
    }
    return file.f_pos;
}

const FramebufferInfo = packed struct {
    width: u32,
    height: u32,
    pitch: u32,
    isrgb: u32,
};

fn ioctl(_: *File, request: usize, arg: usize) usize {
    if (request == 0) {
        var fb_info: *FramebufferInfo = @ptrFromInt(arg);

        var mbox: [35]u32 align(16) = undefined;

        mbox[0] = 35 * 4; // buffer size in bytes
        mbox[1] = mailbox.request_code;

        mbox[2] = 0x48003; // set phy wh
        mbox[3] = 8;
        mbox[4] = 8;
        mbox[5] = 1024; // FrameBufferInfo.width
        mbox[6] = 768; // FrameBufferInfo.height

        mbox[7] = 0x48004; // set virt wh
        mbox[8] = 8;
        mbox[9] = 8;
        mbox[10] = 1024; // FrameBufferInfo.virtual_width
        mbox[11] = 768; // FrameBufferInfo.virtual_height

        mbox[12] = 0x48009; // set virt offset
        mbox[13] = 8;
        mbox[14] = 8;
        mbox[15] = 0; // FrameBufferInfo.x_offset
        mbox[16] = 0; // FrameBufferInfo.y.offset

        mbox[17] = 0x48005; // set depth
        mbox[18] = 4;
        mbox[19] = 4;
        mbox[20] = 32; // FrameBufferInfo.depth

        mbox[21] = 0x48006; // set pixel order
        mbox[22] = 4;
        mbox[23] = 4;
        mbox[24] = 1; // RGB, not BGR preferably

        mbox[25] = 0x40001; // get framebuffer, gets alignment on request
        mbox[26] = 8;
        mbox[27] = 8;
        mbox[28] = 4096; // FrameBufferInfo.pointer
        mbox[29] = 0; // FrameBufferInfo.size

        mbox[30] = 0x40008; // get pitch
        mbox[31] = 4;
        mbox[32] = 4;
        mbox[33] = 0; // FrameBufferInfo.pitch

        mbox[34] = mailbox.end_tag;

        if (mailbox.mboxCall(8, @intFromPtr(&mbox)) and mbox[20] == 32 and mbox[28] != 0) {
            mbox[28] &= 0x3FFFFFFF; // convert GPU address to ARM address
            fb_info.width = mbox[5]; // get actual physical width
            fb_info.height = mbox[6]; // get actual physical height
            fb_info.pitch = mbox[33]; // get number of bytes per line
            fb_info.isrgb = mbox[24]; // get the actual channel order
            lfb = @as([*]u8, @ptrFromInt(@as(u64, mbox[28]) | 0xffff000000000000))[0..mbox[29]];
        } else {
            log.err("Unable to set screen resolution to 1024x768x32\n", .{});
            return @bitCast(@as(isize, -1));
        }
    }

    return 0;
}

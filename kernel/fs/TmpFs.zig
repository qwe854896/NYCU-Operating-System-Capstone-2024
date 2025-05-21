const std = @import("std");
const vfs = @import("vfs.zig");
const assert = std.debug.assert;

const VNodeHashMap = std.StringHashMap(*VNode);
const Allocator = std.mem.Allocator;

const Mount = vfs.Mount;
const FileSystem = vfs.FileSystem;
const VNode = vfs.VNode;
const File = vfs.File;
const VNodeOperations = vfs.VNodeOperations;
const FileOperations = vfs.FileOperations;
const Whence = vfs.FileOperations.Whence;

pub fn fileSystem() FileSystem {
    return .{
        .vtable = &.{
            .setupMount = setupMount,
            .releaseRoot = releaseRoot,
        },
        .name = "tmpfs",
    };
}

fn setupMount(allocator: Allocator) ?Mount {
    const root_node = initRootVnode(allocator) orelse return null;
    return .{ .root = root_node, .fs = fileSystem() };
}

fn initRootVnode(allocator: Allocator) ?*VNode {
    const root_dir = allocator.create(TmpDir) catch return null;
    const node = allocator.create(VNode) catch return null;

    root_dir.* = TmpDir.init(allocator);
    node.* = .{
        .ptr = root_dir,
        .mount = null,
        .v_ops = TmpDir.vOps(),
        .f_ops = null,
    };

    return node;
}

fn releaseRoot(vnode: *VNode) void {
    const root_dir: *TmpDir = @ptrCast(@alignCast(vnode.ptr));
    const allocator = root_dir.allocator;

    root_dir.deinit();

    allocator.destroy(vnode);
    allocator.destroy(root_dir);
}

const TmpDir = struct {
    entries: VNodeHashMap,
    allocator: Allocator,

    pub fn init(allocator: Allocator) TmpDir {
        return .{
            .entries = VNodeHashMap.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TmpDir) void {
        var iterator = self.entries.iterator();
        while (iterator.next()) |entry| {
            const vnode = entry.value_ptr.*;
            if (vnode.f_ops) |_| {
                const file_node: *TmpFileNode = @alignCast(@ptrCast(vnode.ptr));
                self.allocator.destroy(file_node);
            }
            if (vnode.v_ops) |_| {
                const dir_node: *TmpDir = @alignCast(@ptrCast(vnode.ptr));
                dir_node.deinit();
                self.allocator.destroy(dir_node);
            }
            self.allocator.destroy(vnode);
            self.allocator.free(entry.key_ptr.*);
        }
        self.entries.deinit();
    }

    pub fn vOps() VNodeOperations {
        return .{
            .vtable = &.{
                .lookup = lookup,
                .create = create,
                .mkdir = mkdir,
            },
        };
    }

    fn lookup(ctx: *anyopaque, name: []const u8) ?*VNode {
        const dir: *TmpDir = @ptrCast(@alignCast(ctx));
        return dir.entries.get(name);
    }

    fn create(ctx: *anyopaque, name: []const u8) ?*VNode {
        const dir: *TmpDir = @ptrCast(@alignCast(ctx));
        const file = dir.initFileVnode() orelse return null;
        const copy_name = dir.allocator.dupe(u8, name) catch return null;
        dir.entries.put(copy_name, file) catch return null;
        return file;
    }

    fn mkdir(ctx: *anyopaque, name: []const u8) ?*VNode {
        const dir: *TmpDir = @ptrCast(@alignCast(ctx));
        const child_dir = dir.initDirVnode() orelse return null;
        const copy_name = dir.allocator.dupe(u8, name) catch return null;
        dir.entries.put(copy_name, child_dir) catch return null;
        return child_dir;
    }

    fn initFileVnode(dir: *const TmpDir) ?*VNode {
        const file = dir.allocator.create(TmpFileNode) catch return null;
        file.* = TmpFileNode.init();
        const node = dir.allocator.create(VNode) catch return null;
        node.* = .{
            .ptr = file,
            .mount = null,
            .v_ops = null,
            .f_ops = TmpFileNode.fileNodeOps(),
        };
        return node;
    }

    fn initDirVnode(dir: *const TmpDir) ?*VNode {
        const child_dir = dir.allocator.create(TmpDir) catch return null;
        child_dir.* = TmpDir.init(dir.allocator);
        const node = dir.allocator.create(VNode) catch return null;
        node.* = .{
            .ptr = child_dir,
            .mount = null,
            .v_ops = TmpDir.vOps(),
            .f_ops = null,
        };
        return node;
    }
};

const TmpFileNode = struct {
    data: [4096]u8 = undefined,
    size: usize = 0,

    pub fn init() TmpFileNode {
        return .{
            .data = undefined,
            .size = 0,
        };
    }

    pub fn deinit(self: *TmpFileNode) void {
        _ = self;
    }

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
        const self: *TmpFileNode = @ptrCast(@alignCast(ctx));
        return .{
            .vnode = self,
            .f_pos = 0,
            .f_ops = fileOps(),
            .flags = .{},
        };
    }

    fn read(file: *File, buf: []u8) usize {
        const self: *TmpFileNode = @ptrCast(@alignCast(file.vnode));
        const bytes_to_read = @min(buf.len, self.size - file.f_pos);
        @memcpy(buf[0..bytes_to_read], self.data[file.f_pos..][0..bytes_to_read]);
        file.f_pos += bytes_to_read;
        return bytes_to_read;
    }

    fn write(file: *File, buf: []const u8) usize {
        const self: *TmpFileNode = @ptrCast(@alignCast(file.vnode));
        const bytes_to_write = @min(buf.len, 4096 - file.f_pos);
        @memcpy(self.data[file.f_pos..][0..bytes_to_write], buf[0..bytes_to_write]);
        file.f_pos += bytes_to_write;
        self.size = @max(self.size, file.f_pos);
        return bytes_to_write;
    }

    fn close(_: *File) usize {
        return 0;
    }

    fn lseek64(file: *File, offset: isize, whence: Whence) usize {
        switch (whence) {
            .seek_set => file.f_pos = @intCast(offset),
            .seek_end => file.f_pos = @intCast(4096 + offset),
        }
        return file.f_pos;
    }
};

const std = @import("std");
const vfs = @import("vfs.zig");
const initrd = @import("initrd.zig");

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
        .type = .initram,
    };
}

fn setupMount(allocator: Allocator) ?Mount {
    const root_node = initRootVnode(allocator) orelse return null;
    return .{ .root = root_node, .fs = fileSystem() };
}

fn initRootVnode(allocator: Allocator) ?*VNode {
    const root_dir = allocator.create(InitramDir) catch return null;
    const node = allocator.create(VNode) catch return null;

    root_dir.* = InitramDir.init(allocator);

    const entries = initrd.listFiles();
    for (entries) |entry| {
        const file = root_dir.initFileVnode(entry.name) orelse return null;
        const copy_name = root_dir.allocator.dupe(u8, entry.name) catch return null;
        root_dir.entries.put(copy_name, file) catch return null;
    }

    node.* = .{
        .ptr = root_dir,
        .mount = null,
        .v_ops = root_dir.vOps(),
        .f_ops = null,
    };

    return node;
}

fn releaseRoot(vnode: *VNode) void {
    const root_dir: *InitramDir = @ptrCast(@alignCast(vnode.ptr));
    const allocator = root_dir.allocator;

    root_dir.deinit();

    allocator.destroy(vnode);
    allocator.destroy(root_dir);
}

const InitramDir = struct {
    entries: VNodeHashMap,
    allocator: Allocator,

    pub fn init(allocator: Allocator) InitramDir {
        return .{
            .entries = VNodeHashMap.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *InitramDir) void {
        var iterator = self.entries.iterator();
        while (iterator.next()) |entry| {
            const vnode = entry.value_ptr.*;
            if (vnode.f_ops) |_| {
                const file_node: *InitramFileNode = @alignCast(@ptrCast(vnode.ptr));
                file_node.deinit();
                self.allocator.destroy(file_node);
            }
            if (vnode.v_ops) |_| {
                const dir_node: *InitramDir = @alignCast(@ptrCast(vnode.ptr));
                dir_node.deinit();
                self.allocator.destroy(dir_node);
            }
            self.allocator.destroy(vnode);
            self.allocator.free(entry.key_ptr.*);
        }
        self.entries.deinit();
    }

    pub fn vOps(self: *InitramDir) VNodeOperations {
        return .{
            .ptr = self,
            .vtable = &.{
                .lookup = lookup,
                .create = create,
                .mkdir = mkdir,
            },
        };
    }

    fn lookup(ctx: *anyopaque, name: []const u8) ?*VNode {
        const dir: *InitramDir = @ptrCast(@alignCast(ctx));
        return dir.entries.get(name);
    }

    fn create(_: *anyopaque, _: []const u8) ?*VNode {
        return null;
    }

    fn mkdir(_: *anyopaque, _: []const u8) ?*VNode {
        return null;
    }

    fn initFileVnode(dir: *const InitramDir, name: []const u8) ?*VNode {
        const file = dir.allocator.create(InitramFileNode) catch return null;
        file.* = InitramFileNode.init(dir.allocator, name) catch return null;
        const node = dir.allocator.create(VNode) catch return null;
        node.* = .{
            .ptr = file,
            .mount = null,
            .v_ops = null,
            .f_ops = file.fileNodeOps(),
        };
        return node;
    }

    fn initDirVnode(dir: *const InitramDir) ?*VNode {
        const child_dir = dir.allocator.create(InitramDir) catch return null;
        child_dir.* = InitramDir.init(dir.allocator);
        const node = dir.allocator.create(VNode) catch return null;
        node.* = .{
            .ptr = child_dir,
            .mount = null,
            .v_ops = child_dir.vOps(),
            .f_ops = null,
        };
        return node;
    }
};

const InitramFileNode = struct {
    data: []u8,
    size: usize,
    allocator: Allocator,

    pub fn init(allocator: Allocator, filename: []const u8) !InitramFileNode {
        const content = initrd.getFileContent(filename).?;
        return .{
            .data = try allocator.dupe(u8, content),
            .size = content.len,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *InitramFileNode) void {
        self.allocator.free(self.data);
    }

    pub fn fileNodeOps(self: *InitramFileNode) FileOperations {
        return .{
            .ptr = self,
            .vtable = &.{
                .open = open,
                .read = null,
                .write = null,
                .close = null,
                .lseek64 = null,
            },
        };
    }

    fn fileOps(self: *InitramFileNode) FileOperations {
        return .{
            .ptr = self,
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
        const self: *InitramFileNode = @ptrCast(@alignCast(ctx));
        return .{
            .vnode = self,
            .f_pos = 0,
            .f_ops = self.fileOps(),
            .flags = .{},
        };
    }

    fn read(file: *File, buf: []u8) usize {
        const self: *InitramFileNode = @ptrCast(@alignCast(file.vnode));
        const bytes_to_read = @min(buf.len, self.size - file.f_pos);
        @memcpy(buf[0..bytes_to_read], self.data[file.f_pos..][0..bytes_to_read]);
        file.f_pos += bytes_to_read;
        return bytes_to_read;
    }

    fn write(_: *File, _: []const u8) usize {
        return @bitCast(@as(isize, -1));
    }

    fn close(_: *File) usize {
        return 0;
    }

    fn lseek64(file: *File, offset: isize, whence: Whence) usize {
        const self: *InitramFileNode = @ptrCast(@alignCast(file.vnode));
        switch (whence) {
            .seek_set => file.f_pos = @intCast(offset),
            .seek_end => file.f_pos = @intCast(@as(isize, @intCast(self.size)) + offset),
        }
        return file.f_pos;
    }
};

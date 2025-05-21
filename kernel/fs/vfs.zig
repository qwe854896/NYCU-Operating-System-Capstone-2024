const std = @import("std");

pub const VNode = @import("vfs/VNode.zig");
pub const VNodeOperations = @import("vfs/VNodeOperations.zig");
pub const FileSystem = @import("vfs/FileSystem.zig");
pub const Mount = @import("vfs/Mount.zig");
pub const File = @import("vfs/File.zig");
pub const FileOperations = @import("vfs/FileOperations.zig");

const Whence = FileOperations.Whence;
const FileSystemHashMap = std.StringHashMap(FileSystem);
const DeviceFileHashMap = std.AutoHashMap(u64, FileOperations);
const Self = @This();

rootfs: ?Mount,
filesystems: FileSystemHashMap,
devicefiles: DeviceFileHashMap,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .filesystems = FileSystemHashMap.init(allocator),
        .devicefiles = DeviceFileHashMap.init(allocator),
        .rootfs = null,
    };
}

pub fn deinit(self: *Self) void {
    self.filesystems.deinit();
    self.devicefiles.deinit();
}

pub fn registerFileSystem(self: *Self, fs_name: []const u8, fs: FileSystem) !void {
    try self.filesystems.put(fs_name, fs);
}

pub fn registerDeviceFile(self: *Self, dev: u64, fo: FileOperations) !void {
    try self.devicefiles.put(dev, fo);
}

pub fn initRootfs(self: *Self, allocator: std.mem.Allocator, fs_name: []const u8) bool {
    const fs = self.filesystems.get(fs_name) orelse return false;
    self.rootfs = fs.vtable.setupMount(allocator) orelse return false;
    return true;
}

pub fn deinitRootfs(self: *Self) void {
    if (self.rootfs) |rootfs| {
        releaseMount(rootfs);
    }
}

pub fn releaseMount(m: Mount) void {
    m.fs.vtable.releaseRoot(m.root);
}

pub fn open(self: *Self, pathname: []const u8, flags: File.Flags) !File {
    // Handle root edge case
    if (std.mem.eql(u8, pathname, "/")) return error.EISDIR;

    // Split into parent directory and filename
    const dirname = std.fs.path.dirname(pathname) orelse return error.EINVAL;
    const filename = std.fs.path.basename(pathname);

    // Lookup parent directory
    var parent_dir = try self.lookup(dirname);

    if (parent_dir.mount) |m| {
        parent_dir = m.root;
    }

    // Check if file exists in parent
    if (parent_dir.v_ops.?.vtable.lookup(parent_dir.v_ops.?.ptr, filename)) |vnode| {
        return vnode.f_ops.?.vtable.open.?(vnode.f_ops.?.ptr orelse vnode) orelse error.ENOENT;
    } else {
        if (!flags.creat) return error.ENOENT;

        // Create new file in parent directory
        const new_file = parent_dir.v_ops.?.vtable.create(parent_dir.v_ops.?.ptr, filename) orelse return error.EIO;

        return new_file.f_ops.?.vtable.open.?(new_file.f_ops.?.ptr orelse new_file) orelse error.ENOENT;
    }
    return error.EIO;
}

pub fn close(file: *File) void {
    if (file.f_ops.vtable.close) |close_fn| {
        _ = close_fn(file);
    }
}

pub fn write(file: *File, buf: []const u8) usize {
    guard(file.f_ops.vtable.write != null) catch return 0;
    return file.f_ops.vtable.write.?(file, buf);
}

pub fn read(file: *File, buf: []u8) usize {
    guard(file.f_ops.vtable.read != null) catch return 0;
    return file.f_ops.vtable.read.?(file, buf);
}

pub fn mkdir(self: *Self, pathname: []const u8) !void {
    // Split into parent directory and new dir name
    const dirname = std.fs.path.dirname(pathname) orelse return error.EINVAL;
    const new_dir_name = std.fs.path.basename(pathname);

    // Lookup parent directory
    const parent_dir = try self.lookup(dirname);

    // Create directory in parent
    _ = parent_dir.v_ops.?.vtable.mkdir(parent_dir.v_ops.?.ptr, new_dir_name) orelse return error.EIO;
}

pub fn lseek64(file: *File, offset: isize, whence: Whence) !usize {
    if (file.f_ops.vtable.lseek64) |seekFn| {
        return seekFn(file, offset, whence);
    } else {
        return error.EINVAL;
    }
    switch (whence) {
        .seek_set => file.f_pos = @intCast(offset),
        else => return error.EINVAL,
    }
    return file.f_pos;
}

pub fn mount(self: *Self, allocator: std.mem.Allocator, target_path: []const u8, fs_name: []const u8) !Mount {
    var target_vnode = try self.lookup(target_path);

    const fs = self.filesystems.get(fs_name) orelse return error.ENODEV;

    target_vnode.mount = fs.vtable.setupMount(allocator);

    return target_vnode.mount.?;
}

pub fn unmount(self: *Self, target_path: []const u8) !void {
    var target_vnode = try self.lookup(target_path);

    if (target_vnode.mount) |mnt| {
        releaseMount(mnt);
        target_vnode.mount = null;
    } else {
        return error.EINVAL; // Not a mount point
    }
}

fn lookup(self: *Self, path: []const u8) !*VNode {
    const rootfs = self.rootfs orelse return error.EINVAL;

    var current = rootfs.root;
    var components = std.mem.splitScalar(u8, path, '/');

    if (components.peek() == null) {
        return error.EINVAL; // No components to look up
    }
    _ = components.next();

    while (components.next()) |component| {
        if (component.len == 0) continue;

        if (current.mount) |m| {
            current = m.root;
        }

        guard(current.v_ops != null) catch return error.ENOTDIR;
        current = current.v_ops.?.vtable.lookup(current.v_ops.?.ptr, component) orelse return error.ENOENT;
    }

    return current;
}

pub fn mknod(self: *Self, pathname: []const u8, mode: u32, dev: u64) !void {
    _ = mode;

    if (std.mem.eql(u8, pathname, "/")) return error.EISDIR;

    const dirname = std.fs.path.dirname(pathname) orelse return error.EINVAL;
    const filename = std.fs.path.basename(pathname);

    var parent_dir = try self.lookup(dirname);

    if (parent_dir.mount) |m| {
        parent_dir = m.root;
    }

    if (parent_dir.v_ops.?.vtable.lookup(parent_dir.v_ops.?.ptr, filename)) |vnode| {
        _ = vnode;
        return error.EEXIST;
    } else {
        const new_file = parent_dir.v_ops.?.vtable.create(parent_dir.v_ops.?.ptr, filename) orelse return error.EIO;
        new_file.f_ops = self.devicefiles.get(dev) orelse return error.ENODEV;
        return;
    }
    return error.EIO;
}

// Helper functions
inline fn guard(cond: bool) error{EFault}!void {
    if (!cond) return error.EFault;
}

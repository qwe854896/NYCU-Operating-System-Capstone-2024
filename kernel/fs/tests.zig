const std = @import("std");
const Vfs = @import("Vfs.zig");
const TmpFs = @import("TmpFs.zig");
const testing = std.testing;

// Helper function for common test setup/teardown
fn withTmpVfs(comptime testFn: anytype) !void {
    const allocator = testing.allocator;

    var vfs = Vfs.init(allocator);
    defer vfs.deinit();

    try vfs.registerFileSystem(TmpFs.fileSystem());

    if (!vfs.initRootfs(allocator, TmpFs.fileSystem().name)) {
        unreachable;
    }
    defer vfs.deinitRootfs();

    try testFn(&vfs);
}

test "file creation lifecycle" {
    try withTmpVfs(struct {
        fn run(vfs: *Vfs) !void {
            const test_path = "/testfile";

            // Test creation
            var file = try vfs.open(test_path, .{ .creat = true });
            defer Vfs.close(&file);

            // Test existence
            var check_file = try vfs.open(test_path, .{});
            defer Vfs.close(&check_file);
        }
    }.run);
}

test "O_CREAT flag behavior" {
    try withTmpVfs(struct {
        fn run(vfs: *Vfs) !void {
            const new_file = "/newfile";

            // Test 1: No file without O_CREAT
            try testing.expectError(error.ENOENT, vfs.open(new_file, .{}));

            // Test 2: Successful creation with O_CREAT
            var file = try vfs.open(new_file, .{ .creat = true });
            defer Vfs.close(&file);

            // Verify persistence
            var check = try vfs.open(new_file, .{});
            defer Vfs.close(&check);
        }
    }.run);
}

test "directory operations" {
    try withTmpVfs(struct {
        fn run(vfs: *Vfs) !void {
            const dir_path = "/testdir";
            const file_path = dir_path ++ "/file";

            try vfs.mkdir(dir_path);

            // Create file in subdirectory
            var file = try vfs.open(file_path, .{ .creat = true });
            defer Vfs.close(&file);

            // Verify path resolution
            var check = try vfs.open(file_path, .{});
            defer Vfs.close(&check);
        }
    }.run);
}

test "file I/O operations" {
    try withTmpVfs(struct {
        fn run(vfs: *Vfs) !void {
            const test_path = "/testfile";
            const test_data = "Hello tmpfs!";

            // Write test data
            var file = try vfs.open(test_path, .{ .creat = true });
            defer Vfs.close(&file);

            const written = Vfs.write(&file, test_data);
            try testing.expectEqual(test_data.len, written);

            // Read back verification
            try testing.expectEqual(0, Vfs.lseek64(&file, 0, .seek_set));
            try testing.expectEqual(0, file.f_pos);

            var buffer: [128]u8 = undefined;
            const read = Vfs.read(&file, &buffer);
            try testing.expectEqual(test_data.len, read);
            try testing.expectEqualStrings(test_data, buffer[0..read]);

            // EOF check
            const eof_read = Vfs.read(&file, &buffer);
            try testing.expectEqual(0, eof_read);
        }
    }.run);
}

test "mount isolation" {
    try withTmpVfs(struct {
        fn run(vfs: *Vfs) !void {
            const mount_point = "/mnt";
            const test_file = mount_point ++ "/file";

            // Setup mount point
            try vfs.mkdir(mount_point);

            // Mount new instance
            const mnt = try vfs.mount(testing.allocator, mount_point, TmpFs.fileSystem().name);
            defer Vfs.releaseMount(mnt);

            // Create file in mount
            var file = try vfs.open(test_file, .{ .creat = true });
            defer Vfs.close(&file);

            // Verify isolation from root
            try testing.expectError(error.ENOENT, vfs.open("/file", .{}));

            // Verify persistence
            var check = try vfs.open(test_file, .{});
            defer Vfs.close(&check);
        }
    }.run);
}

test "remove mount point" {
    try withTmpVfs(struct {
        fn run(vfs: *Vfs) !void {
            const mount_point = "/mnt";
            const test_file = mount_point ++ "/file";

            // Setup mount point
            try vfs.mkdir(mount_point);

            // Mount new instance
            const mnt = try vfs.mount(testing.allocator, mount_point, TmpFs.fileSystem().name);
            _ = mnt;

            // Create file in mount
            var file = try vfs.open(test_file, .{ .creat = true });
            defer Vfs.close(&file);

            // Verify persistence
            var check = try vfs.open(test_file, .{});
            defer Vfs.close(&check);

            // Remove mount point
            try vfs.unmount(mount_point);

            // Verify mount point removal
            try testing.expectError(error.ENOENT, vfs.open(test_file, .{}));
        }
    }.run);
}

test "Basic 1: tmpfile" {
    try withTmpVfs(struct {
        fn run(vfs: *Vfs) !void {
            const test_path = "/tmpfile";
            const test_data = "tmpfile test";

            var file = try vfs.open(test_path, .{ .creat = true });
            const written = Vfs.write(&file, test_data);
            Vfs.close(&file);

            var buffer: [128]u8 = undefined;
            var check_file = try vfs.open(test_path, .{});
            const read = Vfs.read(&check_file, &buffer);
            Vfs.close(&check_file);

            try testing.expectEqual(written, read);
            try testing.expectEqualStrings(test_data, buffer[0..read]);
        }
    }.run);
}

test "Basic 2: tmpdir" {
    try withTmpVfs(struct {
        fn run(vfs: *Vfs) !void {
            const test_dir = "/tmp";
            const test_path = test_dir ++ "/tmpfile";
            const test_data_1 = "tmpdir test";
            const test_data_2 = "mnt test";

            try vfs.mkdir(test_dir);

            var file = try vfs.open(test_path, .{ .creat = true });
            const written_1 = Vfs.write(&file, test_data_1);
            Vfs.close(&file);

            var buffer: [128]u8 = undefined;
            var check_file_1 = try vfs.open(test_path, .{});
            const read_1 = Vfs.read(&check_file_1, &buffer);
            Vfs.close(&check_file_1);

            try testing.expectEqual(written_1, read_1);
            try testing.expectEqualStrings(test_data_1, buffer[0..read_1]);

            const mnt = try vfs.mount(testing.allocator, test_dir, TmpFs.fileSystem().name);
            defer Vfs.releaseMount(mnt);

            file = try vfs.open(test_path, .{ .creat = true });
            const written_2 = Vfs.write(&file, test_data_2);
            Vfs.close(&file);

            var check_file_2 = try vfs.open(test_path, .{});
            const read_2 = Vfs.read(&check_file_2, &buffer);
            Vfs.close(&check_file_2);

            try testing.expectEqualStrings(test_data_2, buffer[0..read_2]);
            try testing.expectEqual(written_2, read_2);
        }
    }.run);
}

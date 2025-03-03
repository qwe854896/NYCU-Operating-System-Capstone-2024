const std = @import("std");

pub fn build(b: *std.Build) !void {
    const ARCH = "aarch64";
    const MODEL = "raspi3b";
    const BOOTLOADER_NAME = "bootloader";
    const KERNEL_NAME = "kernel8";
    const QEMU = "qemu-system-" ++ ARCH;

    const target = b.resolveTargetQuery(std.Target.Query.parse(.{
        .arch_os_abi = "aarch64-freestanding-eabi",
        .cpu_features = "cortex_a53+strict_align",
    }) catch @panic("failed to obtain platform target"));
    const optimize = b.standardOptimizeOption(.{});

    const kernel_elf = b.addExecutable(.{
        .name = KERNEL_NAME ++ ".elf",
        .root_source_file = b.path("kernel/main.zig"),
        .linkage = .static,
        .link_libc = false,
        .target = target,
        .optimize = optimize,
    });
    kernel_elf.setLinkerScript(b.path("kernel/linker.ld"));
    b.installArtifact(kernel_elf);

    const kernel_bin = kernel_elf.addObjCopy(.{ .format = .bin });

    const kernel_img_name = KERNEL_NAME ++ ".img";
    const kernel_img = b.addInstallBinFile(kernel_bin.getOutput(), kernel_img_name);

    const bootloader_elf = b.addExecutable(.{
        .name = BOOTLOADER_NAME ++ ".elf",
        .root_source_file = b.path("bootloader/main.zig"),
        .linkage = .static,
        .link_libc = false,
        .target = target,
        .optimize = optimize,
    });
    bootloader_elf.setLinkerScript(b.path("bootloader/linker.ld"));
    b.installArtifact(bootloader_elf);

    const bootloader_bin = bootloader_elf.addObjCopy(.{ .format = .bin });

    const bootloader_img_name = BOOTLOADER_NAME ++ ".img";
    const bootloader_img = b.addInstallBinFile(bootloader_bin.getOutput(), bootloader_img_name);

    var default_step = b.step("default", "Override the default step");
    default_step.dependOn(b.getInstallStep());
    default_step.dependOn(&kernel_img.step);
    default_step.dependOn(&bootloader_img.step);

    b.default_step = default_step;

    const kernel_img_path = b.getInstallPath(.bin, kernel_img_name);
    const bootloader_img_path = b.getInstallPath(.bin, bootloader_img_name);
    _ = bootloader_img_path;

    var qemu_args = std.ArrayList([]const u8).init(b.allocator);
    defer qemu_args.deinit();
    try qemu_args.appendSlice(&.{
        QEMU,
        "-M",
        MODEL,
        "-display",
        "none",
        "-serial",
        "null",
        "-serial",
        // "pty", // if you want to test bootloader
        "stdio",
        "-initrd",
        "assets/initramfs.cpio",
        "-dtb",
        "assets/bcm2710-rpi-3-b-plus.dtb",
        "-kernel",
        // bootloader_img_path, // if you want to test bootloader
        kernel_img_path,
    });

    var current_qemu_args = try qemu_args.clone();
    const qemu_command = b.addSystemCommand(try current_qemu_args.toOwnedSlice());

    const qemu_step = b.step("run", "Run in qemu");
    qemu_step.dependOn(&qemu_command.step);

    current_qemu_args = try qemu_args.clone();
    try current_qemu_args.appendSlice(&.{
        "-S",
        "-s",
    });
    const qemu_debug_command = b.addSystemCommand(try current_qemu_args.toOwnedSlice());

    const qemu_debug_step = b.step("debug", "Run in qemu with gdb");
    qemu_debug_step.dependOn(&qemu_debug_command.step);
}

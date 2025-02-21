const std = @import("std");

pub fn build(b: *std.Build) !void {
    const ARCH = "aarch64";
    const MODEL = "raspi3b";
    const KERNEL_NAME = "kernel8";
    const CROSS_COMPILE = ARCH ++ "-linux-gnu-";
    const OBJCOPY = CROSS_COMPILE ++ "objcopy";
    const QEMU = "qemu-system-" ++ ARCH;

    const target = b.resolveTargetQuery(std.zig.CrossTarget{
        .cpu_arch = .aarch64,
        .os_tag = .freestanding,
        .abi = .eabi,
        .cpu_model = .{ .explicit = &std.Target.aarch64.cpu.cortex_a53 },
    });
    const optimize = b.standardOptimizeOption(.{});

    const kernel_elf_name = KERNEL_NAME ++ ".elf";
    const kernel_elf_path = b.getInstallPath(.bin, kernel_elf_name);
    const kernel = b.addExecutable(.{
        .name = kernel_elf_name,
        .root_source_file = b.path("src/main.zig"),
        .linkage = .static,
        .link_libc = false,
        .target = target,
        .optimize = optimize,
    });
    kernel.setLinkerScript(b.path("src/linker.ld"));
    b.installArtifact(kernel);

    const kernel_img_name = KERNEL_NAME ++ ".img";
    const kernel_img_path = b.getInstallPath(.bin, kernel_img_name);
    const kernel_img = b.addSystemCommand(&.{
        OBJCOPY,
        "-O",
        "binary",
        kernel_elf_path,
        kernel_img_path,
    });
    kernel_img.step.dependOn(b.getInstallStep());

    // start qemu if use `zig build qemu`
    const qemu_step = b.step("run", "Run in qemu");
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
        "stdio",
        "-kernel",
        kernel_img_path,
    });
    var current_qemu_args = try qemu_args.clone();
    const qemu_command = b.addSystemCommand(try current_qemu_args.toOwnedSlice());

    qemu_command.step.dependOn(&kernel_img.step);
    qemu_step.dependOn(&qemu_command.step);

    // start qemu debug
    const qemu_debug_step = b.step("debug", "Run in qemu with gdb");
    current_qemu_args = try qemu_args.clone();
    try current_qemu_args.appendSlice(&.{
        "-S",
        "-s",
    });
    const qemu_debug_command = b.addSystemCommand(try current_qemu_args.toOwnedSlice());

    qemu_debug_command.step.dependOn(&kernel_img.step);
    qemu_debug_step.dependOn(&qemu_debug_command.step);
}

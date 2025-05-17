const std = @import("std");
const Build = std.Build;
const Target = std.Target;
const ArrayList = std.ArrayList;
const OptimizeMode = std.builtin.OptimizeMode;
const ResolvedTarget = Build.ResolvedTarget;

pub fn build(b: *Build) !void {
    const bootloader_mode = b.option(bool, "bootloader", "Enable bootloader chainloading") orelse false;
    const target = setupAArch64Target(b);
    const optimize = b.standardOptimizeOption(.{});

    const kernel = addStaticExecutable(b, .{
        .name = "kernel8.elf",
        .root_source = "kernel/main.zig",
        .linker_script = "kernel/linker.ld",
        .target = target,
        .optimize = optimize,
    });
    const kernel_drivers = addDriversModule(b, 0xFFFF00003F000000);
    kernel.root_module.addImport("drivers", kernel_drivers);

    const bootloader = addStaticExecutable(b, .{
        .name = "bootloader.elf",
        .root_source = "bootloader/main.zig",
        .linker_script = "bootloader/linker.ld",
        .target = target,
        .optimize = optimize,
    });
    const bootloader_drivers = addDriversModule(b, 0x000000003F000000);
    bootloader.root_module.addImport("drivers", bootloader_drivers);

    b.installArtifact(kernel);
    if (bootloader_mode) b.installArtifact(bootloader);

    const artifacts = .{
        .kernel = kernel,
        .bootloader = bootloader,
    };
    try setupExecutionSteps(b, artifacts, bootloader_mode);
}

fn setupAArch64Target(b: *Build) ResolvedTarget {
    return b.resolveTargetQuery(
        .{
            .cpu_arch = .aarch64,
            .os_tag = .freestanding,
            .abi = .eabi,
            .cpu_model = .{
                .explicit = &Target.aarch64.cpu.cortex_a53,
            },
        },
    );
}

fn addStaticExecutable(b: *Build, options: struct {
    name: []const u8,
    root_source: []const u8,
    linker_script: []const u8,
    target: ResolvedTarget,
    optimize: OptimizeMode,
}) *Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = options.name,
        .root_source_file = b.path(options.root_source),
        .target = options.target,
        .optimize = options.optimize,
        .linkage = .static,
        .link_libc = false,
    });
    exe.setLinkerScript(b.path(options.linker_script));
    return exe;
}

fn addDriversModule(
    b: *Build,
    mmio_base_address: usize,
) *Build.Module {
    const drivers = b.createModule(.{ .root_source_file = b.path("drivers/main.zig") });
    const drivers_options = b.addOptions();
    drivers_options.addOption(usize, "mmio_base_address", mmio_base_address);
    drivers.addOptions("config", drivers_options);
    return drivers;
}

fn setupExecutionSteps(
    b: *Build,
    artifacts: anytype,
    bootloader_mode: bool,
) !void {
    const kernel_img = b.addInstallBinFile(artifacts.kernel.addObjCopy(.{ .format = .bin }).getOutput(), "kernel8.img");
    const bootloader_img = b.addInstallBinFile(artifacts.bootloader.addObjCopy(.{ .format = .bin }).getOutput(), "bootloader.img");

    const base_args = try buildQemuArgs(
        b,
        b.getInstallPath(.bin, if (bootloader_mode) bootloader_img.dest_rel_path else kernel_img.dest_rel_path),
        if (bootloader_mode) "pty" else "stdio",
    );
    defer base_args.deinit();

    const install_image_step = b.step("install-image", "Install images");
    install_image_step.dependOn(&kernel_img.step);
    if (bootloader_mode) install_image_step.dependOn(&bootloader_img.step);

    try addQemuSteps(b, base_args, install_image_step);
}

fn buildQemuArgs(b: *Build, kernel_path: []const u8, serial_mode: []const u8) !ArrayList([]const u8) {
    var args = ArrayList([]const u8).init(b.allocator);
    try args.appendSlice(&.{
        "qemu-system-aarch64",
        "-M",
        "raspi3b",
        "-serial",
        "null",
        "-serial",
        serial_mode,
        "-initrd",
        "assets/initramfs.cpio",
        "-dtb",
        "assets/bcm2710-rpi-3-b-plus.dtb",
        "-kernel",
        kernel_path,
    });
    return args;
}

fn addQemuSteps(
    b: *Build,
    base_args: ArrayList([]const u8),
    install_image_step: *Build.Step,
) !void {
    // Run configuration
    const run_cmd = b.addSystemCommand(base_args.items);
    run_cmd.step.dependOn(install_image_step);

    const run_step = b.step("run", "Execute in QEMU");
    run_step.dependOn(&run_cmd.step);

    // Debug configuration
    var debug_args = try base_args.clone();
    defer debug_args.deinit();

    try debug_args.appendSlice(&.{ "-S", "-s" });

    const debug_cmd = b.addSystemCommand(debug_args.items);
    debug_cmd.step.dependOn(install_image_step);
    debug_cmd.step.dependOn(b.getInstallStep());

    const debug_step = b.step("debug", "Debug in QEMU with GDB");
    debug_step.dependOn(&debug_cmd.step);
}

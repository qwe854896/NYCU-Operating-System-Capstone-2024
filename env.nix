{
  stdenv,
  mkShell,
  clang-tools,
  qemu,
  pwndbg,
  zig,
}:

mkShell {
  CROSS_COMPILE = stdenv.cc.targetPrefix;
  depsBuildBuild = [
    clang-tools
    qemu
    pwndbg.packages.x86_64-linux.default
    zig.packages.x86_64-linux.default
  ];
  hardeningDisable = [ "all" ];
}

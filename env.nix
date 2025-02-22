{
  stdenv,
  mkShell,
  clang-tools,
  qemu,
  pwndbg,
  zig,
  python312,
}:

mkShell {
  CROSS_COMPILE = stdenv.cc.targetPrefix;
  depsBuildBuild = [
    clang-tools
    qemu
    python312
    pwndbg.packages.x86_64-linux.default
    zig.packages.x86_64-linux.default
  ];
  hardeningDisable = [ "all" ];
}

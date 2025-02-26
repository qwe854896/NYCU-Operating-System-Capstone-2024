{
  system,
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
    pwndbg.packages.${system}.pwndbg-lldb
    zig.packages.${system}.master
  ];
  hardeningDisable = [ "all" ];
}

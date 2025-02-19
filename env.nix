{
  stdenv,
  mkShell,
  clang-tools,
  qemu,
  gef,
}:

mkShell {
  CROSS_COMPILE = stdenv.cc.targetPrefix;
  depsBuildBuild = [
    clang-tools
    qemu
    gef
  ];
  hardeningDisable = [ "all" ];
}

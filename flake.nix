{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    pwndbg.url = "github:pwndbg/pwndbg/dev";
  };

  outputs =
    { nixpkgs, pwndbg, ... }:
    let
      eachSystem = nixpkgs.lib.genAttrs [ "x86_64-linux" ];
    in
    {
      devShell = eachSystem (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            crossSystem.config = "aarch64-linux-gnu";
          };
        in
        pkgs.callPackage ./env.nix { inherit pwndbg; }
      );
    };
}

{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
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
        pkgs.callPackage ./env.nix { }
      );
    };
}

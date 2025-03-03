{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    pwndbg.url = "github:pwndbg/pwndbg/dev";
    zig.url = "github:mitchellh/zig-overlay";
  };

  outputs =
    {
      nixpkgs,
      pwndbg,
      zig,
      ...
    }:
    let
      eachSystem = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-darwin"
      ];
    in
    {
      devShells = eachSystem (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
          };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              qemu
              python312
              pwndbg.packages.${system}.pwndbg-lldb
              zig.packages.${system}.master
            ];
          };
        }
      );
    };
}

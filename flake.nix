{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pwndbg = {
      url = "github:pwndbg/pwndbg/dev";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
    };

    zls = {
      url = "github:zigtools/zls";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        zig-overlay.follows = "zig-overlay";
      };
    };

    nixvim = {
      url = "github:elythh/nixvim?rev=b28c11a1e8c4473a6bc02936ad7feba3e877c41b";
    };
  };

  outputs =
    {
      nixpkgs,
      pwndbg,
      zig-overlay,
      zls,
      nixvim,
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
          nixvimExtended = nixvim.nixvimConfigurations.${system}.nixvim.extendModules {
            modules = [
              {
                colorschemes.catppuccin.enable = true;
                plugins.lsp.servers.zls = {
                  enable = true;
                  package = zls.packages.${system}.default;
                };
              }
            ];
          };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              just
              qemu
              python313
              python313Packages.pyserial
              pwndbg.packages.${system}.default
              zig-overlay.packages.${system}."0.14.1"
              nixvimExtended.config.build.package
              minicom
            ];
          };
        }
      );
    };
}

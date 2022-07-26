{
  description = "Cachix Deploy Agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-22.05";
    nixos-hardware.url = "github:nixos/nixos-hardware";
    cachix.url = "github:cachix/cachix/master";
    cachix-deploy-flake.url = "github:cachix/cachix-deploy-flake";
  };

  outputs = { self, nixpkgs, nixos-hardware, cachix, cachix-deploy-flake }:
    let
      system = "x86_64-linux";
      pkgs = import "${nixpkgs}" {
        inherit system;
        # ngrok, vscode, zoom-us, signal-desktop
        config.allowUnfree = true;
      };
      cachix-deploy-lib = cachix-deploy-flake.lib pkgs;
    in {
      defaultPackage."${system}" = cachix-deploy-lib.spec {
        agents = {
          cherimoya = cachix-deploy-lib.nixos {
            imports = [
              ./cherimoya 
              (nixos-hardware + "/lenovo/thinkpad/p14s/amd/gen2") 
            ];
            services.cachix-agent.package = import cachix { inherit system; };
          };
        };
      };
    };
}

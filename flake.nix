{
  description = "Cachix Deploy Agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";
    cachix.url = "github:cachix/cachix";
    cachix-deploy-flake.url = "github:cachix/cachix-deploy-flake";
  };

  outputs = { self, nixpkgs, cachix, cachix-deploy-flake }:
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
            ];
            # https://github.com/NixOS/nixos-hardware/blob/master/lenovo/thinkpad/p14s/amd/gen2/default.nix
            boot.kernelParams = [ "amdgpu.backlight=0" ];
            services.cachix-agent.package = cachix.packages.${system}.cachix;
          };
        };
      };
    };
}

{
  description = "Cachix Deploy Agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    cachix.url = "github:cachix/cachix";
    cachix-deploy-flake.url = "github:cachix/cachix-deploy-flake";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    stylix.url = "github:nix-community/stylix/release-25.11";
    stylix.inputs.nixpkgs.follows = "nixpkgs";
    ghostty.url = "github:ghostty-org/ghostty";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, cachix, cachix-deploy-flake, nixos-hardware, stylix, ghostty }:
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
              stylix.nixosModules.stylix
              nixos-hardware.nixosModules.lenovo-yoga-7-slim-gen8 
            ];
            environment.systemPackages = [
              nixpkgs-unstable.legacyPackages.${system}.quickshell
              ghostty.packages.${system}.default
            ];
            services.cachix-agent.package = cachix.packages.${system}.cachix;
          };
        };
      };
    };
}

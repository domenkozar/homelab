{
  description = "Cachix Deploy Agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    cachix.url = "github:cachix/cachix";
    cachix-deploy-flake.url = "github:cachix/cachix-deploy-flake";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    stylix.url = "github:nix-community/stylix/release-25.11";
    stylix.inputs.nixpkgs.follows = "nixpkgs";
    ghostty.url = "github:ghostty-org/ghostty/v1.3.1";
    dms = {
      url = "github:AvengeMedia/DankMaterialShell/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, cachix, cachix-deploy-flake, nixos-hardware, stylix, ghostty, dms }:
    let
      system = "x86_64-linux";
      pkgsUnstable = import "${nixpkgs-unstable}" {
        inherit system;
        config.allowUnfree = true;
      };
      pkgs = import "${nixpkgs}" {
        inherit system;
        # ngrok, vscode, zoom-us, signal-desktop
        config.allowUnfree = true;
        overlays = [
          (final: prev: {
            inherit (pkgsUnstable) dgop;
          })
        ];
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
              dms.nixosModules.default
            ];
            environment.systemPackages = [
              ghostty.packages.${system}.default
            ];
            systemd.user.services.ghostty = {
              description = "Ghostty terminal";
              partOf = [ "graphical-session.target" ];
              after = [ "graphical-session.target" ];
              wantedBy = [ "graphical-session.target" ];
              serviceConfig = {
                ExecStart = "${ghostty.packages.${system}.default}/bin/ghostty";
                Restart = "on-failure";
                RestartSec = 5;
              };
            };
            services.cachix-agent.package = cachix.packages.${system}.cachix;
          };
        };
      };
    };
}

{
  description = "Cachix Deploy Agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    cachix.url = "github:cachix/cachix";
    cachix-deploy-flake.url = "github:cachix/cachix-deploy-flake";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    stylix.url = "github:nix-community/stylix/release-25.11";
    stylix.inputs.nixpkgs.follows = "nixpkgs";
    ghostty.url = "github:ghostty-org/ghostty/main";
    dms = {
      url = "github:AvengeMedia/DankMaterialShell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    quickshell = {
      url = "github:quickshell-mirror/quickshell/v0.3.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    niri-screenshare = {
      url = "github:pantarune/niri-screenshare";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Desktop needs a newer Rust toolchain than the stable system Nixpkgs.
    factorseal.url = "github:cachix/factorseal";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, cachix, cachix-deploy-flake, nixos-hardware, stylix, ghostty, dms, quickshell, niri-screenshare, factorseal }:
    let
      system = "x86_64-linux";
      pkgs = import "${nixpkgs}" {
        inherit system;
        # ngrok, vscode, zoom-us, signal-desktop
        config.allowUnfree = true;
      };
      pkgs-unstable = import "${nixpkgs-unstable}" {
        inherit system;
        config.allowUnfree = true;
      };
      cachix-deploy-lib = cachix-deploy-flake.lib pkgs;
      ghosttyWayland = pkgs.symlinkJoin {
        name = "ghostty-wayland";
        paths = [ ghostty.packages.${system}.default ];
        postBuild = ''
          desktopFile="$out/share/applications/com.mitchellh.ghostty.desktop"
          # Copy before editing, since symlinkJoin links to the upstream file.
          cp --remove-destination "${ghostty.packages.${system}.default}/share/applications/com.mitchellh.ghostty.desktop" "$desktopFile"
          # Cover both the main launcher and its New Window action.
          substituteInPlace "$desktopFile" \
            --replace-fail 'Exec=${ghostty.packages.${system}.default}/bin/ghostty ' \
              'Exec=${pkgs.coreutils}/bin/env EGL_PLATFORM=wayland ${ghostty.packages.${system}.default}/bin/ghostty '
        '';
      };
      niriScreenshare = niri-screenshare.packages.${system}.default.overrideAttrs (old: {
        # NixOS manages portal preferences. A generated user portals.conf
        # would take precedence over the system's other portal settings.
        postPatch = (old.postPatch or "") + ''
          substituteInPlace src/main.rs \
            --replace-fail '    portal_config::ensure_portals_config();' ""
        '';
      });
    in {
      packages.${system}.ghostty-wayland = ghosttyWayland;
      defaultPackage."${system}" = cachix-deploy-lib.spec {
        agents = {
          cherimoya = cachix-deploy-lib.nixos {
            imports = [
              ./cherimoya
              factorseal.nixosModules.factorseal
              stylix.nixosModules.stylix
              nixos-hardware.nixosModules.lenovo-yoga-7-slim-gen8
              dms.nixosModules.default
            ];
            services.factorseal = {
              enable = true;
              mode = "desktop";
              users = [ "domen" ];
              package = factorseal.packages.${system}.factorseal;
              desktopPackage = factorseal.packages.${system}.factorseal-desktop;
            };
            environment.systemPackages = [
              ghosttyWayland
              pkgs-unstable.herdr
            ];
            programs.dank-material-shell.quickshell.package = quickshell.packages.${system}.default;
            xdg.portal.extraPortals = [ niriScreenshare ];
            # Use Ghostty's bundled single-instance service for login and D-Bus launches.
            systemd.packages = [ ghostty.packages.${system}.default ];
            services.dbus.packages = [ ghostty.packages.${system}.default ];
            systemd.user.services."app-com.mitchellh.ghostty" = {
              overrideStrategy = "asDropin";
              environment.EGL_PLATFORM = "wayland";
              partOf = [ "graphical-session.target" ];
              wantedBy = [ "graphical-session.target" ];
              # An interactive shell needs the same command paths as a Niri launch.
              path = [
                "/home/domen"
                "/run/wrappers"
                "/home/domen/.nix-profile"
                "/nix/profile"
                "/home/domen/.local/state/nix/profile"
                "/etc/profiles/per-user/domen"
                "/nix/var/nix/profiles/default"
                "/run/current-system/sw"
              ];
              serviceConfig = {
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

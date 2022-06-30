{
  description = "Cachix Deploy Agents";

  inputs = {
    nixpkgs.url = "github:domenkozar/nixpkgs/backport-cachix-agent-verbose-22.05";
    nixos-hardware.url = "github:nixos/nixos-hardware";
    cachix.url = "github:cachix/cachix/connection-handling";
  };

  outputs = { self, nixpkgs, nixos-hardware, cachix }:
    let
      system = "x86_64-linux";
      pkgs = import "${nixpkgs}" {
        inherit system;
        # ngrok, vscode, zoom-us, signal-desktop
        config.allowUnfree = true;
      };
      cherimoya = pkgs.nixos {
        imports = [ 
          ./cherimoya 
          (nixos-hardware + "/lenovo/thinkpad/p14s/amd/gen2") 
        ];
        services.cachix-agent.package = import cachix { inherit system; };
        services.cachix-agent.verbose = true;
      };
    in {
      defaultPackage."${system}" = pkgs.writeText "cachix-agents.json" (builtins.toJSON {
        agents = {
          cherimoya = cherimoya.toplevel;
        };
      });
    };
}

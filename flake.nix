{
  description = "Cachix Deploy Agents";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-21.05";
    nixos-hardware.url = "github:nixos/nixos-hardware";
    # TODO: remove with 0.7.0 release
    cachix.url = "github:cachix/cachix";
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
      };
    in {
      defaultPackage."${system}" = pkgs.writeText "cachix-agents.json" (builtins.toJSON {
        agents = {
          cherimoya = cherimoya.toplevel;
        };
      });
    };
}

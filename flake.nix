{
  description = "Cachix Deploy Agents";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.05";
    nixos-hardware.url = "github:nixos/nixos-hardware";
  };

  outputs = { self, nixpkgs, nixos-hardware }:
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
      };
    in {
      defaultPackage."${system}" = pkgs.writeText "cachix-agents.json" (builtins.toJSON {
        agents = {
          cherimoya = cherimoya.toplevel;
        };
      });
    };
}
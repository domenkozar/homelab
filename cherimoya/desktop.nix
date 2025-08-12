{ config, pkgs, lib, ... }:

{
  programs.niri.enable = true;
  security.polkit.enable = true;

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  environment.sessionVariables.QUICKSHELL_CONFIG = pkgs.fetchFromGitHub {
    owner = "Amadoabad";
    repo = "Shellado";
    rev = "main";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  # TODO: https://github.com/YaLTeR/niri/blob/main/wiki/Example-systemd-Setup.md

  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ ];
  };

  fonts.packages = with pkgs; [
    commit-mono
  ];

  environment.systemPackages = with pkgs; [
    (chromium.override {
      commandLineArgs = [
        "--ozone-platform=wayland"
        "--enable-features=UseOzonePlatform"
      ];
    })
    swaylock
    swayidle
    swaybg
    fuzzel # launcher
    mako # notification daemon
    ghostty
    wl-clipboard
    wlr-randr
    grim
    slurp
    wallust
    cliphist
    swappy
    kanshi
    brightnessctl
    playerctl
    pavucontrol
    wdisplays
  ];

  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd niri";
        user = "greeter";
      };
    };
  };
}

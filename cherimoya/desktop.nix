{ config, pkgs, lib, ... }:

{
  programs.niri.enable = true;
  programs.waybar.enable = true;
  security.polkit.enable = true;

  programs.niri.settings.environment.NIXOS_OZONE_WL = "1";

  # TODO: https://github.com/YaLTeR/niri/blob/main/wiki/Example-systemd-Setup.md

  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-emoji
    liberation_ttf
    fira-code
    fira-code-symbols
    font-awesome
    nerd-fonts.fira-code
    nerd-fonts.droid-sans-mono
  ];

  environment.systemPackages = with pkgs; [
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

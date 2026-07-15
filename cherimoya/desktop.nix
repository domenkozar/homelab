{ config, pkgs, lib, ... }:

let
  chromium' = pkgs.chromium.override {
    commandLineArgs = [
      "--ozone-platform=wayland"
      # SystemNotifications routes web notifications through the D-Bus
      # notification daemon (DankMaterialShell) instead of Chromium drawing
      # its own toplevel window, which niri would tile.
      "--enable-features=UseOzonePlatform,SystemNotifications"
    ];
  };
in
{
  stylix = {
    enable = true;
    icons.enable = true;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/ocean.yaml";
  };
  
  programs.niri.enable = true;
  security.polkit.enable = true;

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  environment.sessionVariables.FONTCONFIG_FILE = pkgs.makeFontsConf {
    fontDirectories = [
      pkgs.material-symbols
      pkgs.nerd-fonts.caskaydia-mono
    ];
  };

  programs.dank-material-shell = {
    enable = true;
    systemd = {
      enable = true;
      restartIfChanged = true;
    };
  };

  systemd.user.services = {
    chromium = {
      description = "Chromium browser";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = lib.getExe chromium';
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
    redland = {
      description = "Redland";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = lib.getExe pkgs.redland-wayland;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };

  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ ];
  };

  fonts.packages = with pkgs; [
    commit-mono
  ];

  environment.systemPackages = with pkgs; [
    chromium'
    swaylock
    swayidle
    swaybg
    fuzzel # launcher
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
    imv
  ];

  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd niri-session";
        user = "greeter";
      };
    };
  };
}

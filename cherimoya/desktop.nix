{ config, pkgs, lib, ... }:

let
  chromium' = pkgs.chromium.override {
    commandLineArgs = [
      "--ozone-platform=wayland"
      "--enable-features=UseOzonePlatform"
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
  environment.sessionVariables.QS_CONFIG_PATH = (pkgs.fetchFromGitHub {
    owner = "Amadoabad";
    repo = "Shellado";
    rev = "main";
    hash = "sha256-PNWyYHxbE81scI9b12JAbXX3jwo6ukm6bqgIHuzoSjM=";
    postFetch = ''
      patchShebangs $out
    '';
  });
  environment.sessionVariables.QML_IMPORT_PATH = lib.makeSearchPath "lib/qt-6/qml" [
    pkgs.kdePackages.qt5compat
    pkgs.kdePackages.qtbase
    pkgs.kdePackages.qtdeclarative
    pkgs.kdePackages.qtmultimedia
  ];
  environment.sessionVariables.FONTCONFIG_FILE = pkgs.makeFontsConf {
    fontDirectories = [
      pkgs.material-symbols
      pkgs.nerd-fonts.caskaydia-mono
    ];
  };

  systemd.user.services = {
    quickshell = {
      description = "Quickshell status bar";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = lib.getExe pkgs.quickshell;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
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
    mako = {
      description = "Mako notification daemon";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = lib.getExe pkgs.mako;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
    nm-applet = {
      description = "NetworkManager applet";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.networkmanagerapplet}/bin/nm-applet";
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
    mako # notification daemon
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

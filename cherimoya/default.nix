{ config, pkgs, lib, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
  time.timeZone = "Atlantic/Canary";

  networking.hostName = "cherimoya";
  networking.networkmanager.enable = true;
  networking.nameservers = ["1.1.1.1"];

  systemd.coredump.extraConfig = ''
    ExternalSizeMax=8G
    ProcessSizeMax=8G
    JournalSizeMax=8G
  '';

  # Enable sound.
  hardware.bluetooth.enable = true;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  # copied from https://github.com/NixOS/nixpkgs/issues/102547 for high quality cals
  services.pipewire.media-session.config.bluez-monitor.rules = [
    {
      # Matches all cards
      matches = [ { "device.name" = "~bluez_card.*"; } ];
      actions = {
        "update-props" = {
          "bluez5.reconnect-profiles" = [ "hfp_hf" "hsp_hs" "a2dp_sink" ];
          # mSBC is not expected to work on all headset + adapter combinations.
          "bluez5.msbc-support" = true;
        };
      };
    }
    {
      matches = [
        # Matches all sources
        { "node.name" = "~bluez_input.*"; }
        # Matches all outputs
        { "node.name" = "~bluez_output.*"; }
      ];
      actions = {
        "node.pause-on-idle" = false;
      };
    }
  ];

  nix = {
   buildCores = 0;
   maxJobs = 4;
   trustedUsers = [ "root" "@wheel" ];
   extraOptions = ''
     narinfo-cache-negative-ttl = 0
     extra-experimental-features = flakes nix-command
   '';
  };

  environment.variables.EDITOR = lib.mkOverride 0 "vim";
  environment.variables.TERM = "xterm-256color";
  programs.bash.enableCompletion = true;
  programs.autojump.enable = true;

  users.users.domen = {
    isNormalUser = true;
    createHome = true;
    home = "/home/domen";
    extraGroups = [ "wheel" "docker" "podman" "networkmanager" ]; 
    shell = "/run/current-system/sw/bin/bash";
  };

  environment.interactiveShellInit = ''
    export PATH="$HOME/bin:$PATH"

    parse_git_branch() {
        git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/on \1/'
    }
    PS1="$PS1\[\e[0;33;49m\]\$(parse_git_branch)\[\e[0;0m\]\n$ "

    eval "$(direnv hook bash)"

    # append history instead of overwrite
    shopt -s histappend

    # big history, record everything
    export HISTCONTROL=ignoredups:erasedups  # no duplicate entries
    export HISTSIZE=300000
    export HISTFILESIZE=200000
    export PROMPT_COMMAND="history -a; history -c; history -r; $PROMPT_COMMAND"
    export BROWSER=chromium

    # check the window size after each command and, if necessary,
    # update the values of LINES and COLUMNS.
    shopt -s checkwinsize
  '';

  environment.systemPackages = with pkgs; [
    # generally useful tools
    wgetpaste
    pwgen
    curl
    vimHugeX
    vscode
    gitFull
    gitAndTools.tig
    gitAndTools.git-crypt
    tree
    #anki
    sqlite-interactive
    sshfs-fuse
    sshuttle
    fuse
    jwhois
    dos2unix
    gnumake
    libevent
    patchelf
    unetbootin
    gcc
    # https://github.com/matejc/tarman/issues/24
    # pythonPackages.tarman
    sysstat
    speedtest-cli
    mosh
    ngrok
    mtpfs
    lsof

    # sys tools
    rmlint
    extundelete
    hdparm
    tmux
    wget
    nmap
    ncdu
    inetutils
    unzip
    jq
    psmisc
    patray

    # development
    nix-prefetch-scripts
    cachix
    direnv
    shellcheck
    terraform
    gdb

    # haskell
    hlint
    stack
    cabal2nix
    cabal-install

    # elm
    elm2nix

    # X apps
    dmenu
    i3status
    i3lock
    imagemagick
    i3minator
    # TODO: make it a floating window so it's not annoying
    p7zip
    pavucontrol
    xarchiver
    pa_applet
    dunst  # notifications
    arandr
    xvidcap # screenrecording
    escrotum
    geeqie
    networkmanagerapplet
    vlc
    evince
    #skype
    #wine

    # e-residency
    #qdigidoc

    # browsers
    firefox
    chromium

    # games
    #spring
    #springLobby
    #teeworlds
    #xonotic
    #steam

    # postgresql
    #pgadmin

    # python stuff
    #python27Full
    #python33
    python3Full
    #python27Packages.virtualenv
    #python36Packages.virtualenv

    # unfree
    signal-desktop
    zoom-us

    # man pages
    man-pages
    posix_man_pages

    docker
    alsaUtils
  ];

  services.xserver = {
    enable = true;
    autorun = true;
    videoDrivers = [ "amdgpu" ];
    libinput.enable = true;
    windowManager.i3.enable = true;
    desktopManager.xfce.enable = true;
    displayManager.lightdm.enable = true;
    displayManager.autoLogin.enable = true;
    displayManager.autoLogin.user = "domen";
  };

  programs.ssh.startAgent = true;
  programs.gnupg.agent.enable = true;
  programs.gnupg.agent.pinentryFlavor = "gnome3";
  # provides org.freedesktop.secrets
  services.gnome.gnome-keyring.enable = true;

  # e-residency
  services.pcscd.enable = true;
  services.pcscd.plugins = [ pkgs.acsccid ];

  # TODO: need to hash the password
  #users.mutableUsers = false;

  system.stateVersion = "21.05";

  # TODO: usb backup auto play

  virtualisation.virtualbox.host.enable = true;
  users.extraGroups.vboxusers.members = [ "domen" ];

  virtualisation.docker.enable = true;
  systemd.enableUnifiedCgroupHierarchy = false;

  location.provider = "geoclue2";

  # 21.11 requires this to be set
  users.users.localtimed.group = "localtimed";
  users.groups.localtimed = {};
 
  services = {
    locate.enable = true;
    upower.enable = true;
    thermald.enable = true;
    # optimize battery
    tlp.enable = true;
    blueman.enable = true;

    # auto set timezone
    localtime.enable = true;

    cachix-agent.enable = true;

    redshift = {
      enable = true;
      temperature.day = 5700;
      temperature.night = 4600;
    };

    restic.backups.full = {
      paths = [ "/home/domen/dev" "/etc" "/nix/var" ];
      repository = "s3:https://s3.us-west-002.backblazeb2.com/guava-backup";
      passwordFile = "/etc/restic/password";
      s3CredentialsFile = "/etc/restic/b2";
      initialize = true;
      timerConfig = {
        OnCalendar = "03:00";
        RandomizedDelaySec = "3h";
      };
    };
  };
}

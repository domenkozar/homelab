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
  networking.extraHosts = ''
   127.0.0.1 cachix app.cachix test.cachix
  '';

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

  nix = {
   package = pkgs.nixVersions.nix_2_16;
   buildCores = 0;
   maxJobs = 4;
   nixPath = lib.mkForce [];
   trustedUsers = [ "root" "@wheel" ];
   extraOptions = ''
     narinfo-cache-negative-ttl = 0
     show-trace = true
     extra-experimental-features = flakes nix-command
   '';
  };

  environment.variables.EDITOR = lib.mkOverride 0 "vim";
  environment.variables.TERM = "xterm-256color";
  programs.bash.enableCompletion = true;
  programs.autojump.enable = true;
  programs.starship.enable = true;

  users.users.domen = {
    isNormalUser = true;
    createHome = true;
    home = "/home/domen";
    extraGroups = [ "wheel" "docker" "podman" "networkmanager" ]; 
    shell = "/run/current-system/sw/bin/bash";
  };

  environment.interactiveShellInit = ''
    export PATH="$HOME/bin:$PATH"

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
    sshfs-fuse
    fuse
    jwhois
    dos2unix
    gnumake
    patchelf
    gcc
    sysstat
    speedtest-cli
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

    # development
    nix-diff
    cachix
    direnv
    gdb

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
    dunst  # notifications
    arandr
    escrotum
    geeqie
    networkmanagerapplet
    patray
    evince

    # browsers
    firefox
    chromium

    # games
    #spring
    #springLobby
    #teeworlds
    #xonotic
    #steam

    # python stuff
    python3
    #python3Packages.virtualenv

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
  programs.firefox.policies.SecurityDevices.p11-kit-proxy = "${pkgs.p11-kit}/lib/p11-kit-proxy.so";
  programs.firefox.nativeMessagingHosts.euwebid = true;
  environment.etc."chromium/native-messaging-hosts/eu.webeid.json".source = "${pkgs.web-eid-app}/share/web-eid/eu.webeid.json";
  environment.etc."opt/chrome/native-messaging-hosts/eu.webeid.json".source = "${pkgs.web-eid-app}/share/web-eid/eu.webeid.json";
  # Tell p11-kit to load/proxy opensc-pkcs11.so, providing all available slots
  # (PIN1 for authentication/decryption, PIN2 for signing).
  environment.etc."pkcs11/modules/opensc-pkcs11".text = ''
    module: ${pkgs.opensc}/lib/opensc-pkcs11.so
  '';

  # TODO: need to hash the password
  #users.mutableUsers = false;

  system.stateVersion = "22.11";

  # TODO: usb backup auto play

  virtualisation.virtualbox.host.enable = true;
  users.extraGroups.vboxusers.members = [ "domen" ];

  virtualisation.docker.enable = true;
  systemd.enableUnifiedCgroupHierarchy = false;

  location.provider = "geoclue2";

  # chromecast: https://github.com/NixOS/nixpkgs/issues/49630#issuecomment-622498732
  services.avahi.enable = true;

  # See: https://github.com/NixOS/nixpkgs/issues/180175
  systemd.services.NetworkManager-wait-online.enable = false;
 
  services = {
    locate.enable = true;
    upower.enable = true;
    thermald.enable = true;
    # optimize battery
    tlp.enable = true;
    blueman.enable = true;
    earlyoom.enable = true;

    # auto set timezone
    #localtime.enable = true;

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

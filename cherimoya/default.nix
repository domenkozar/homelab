{ config, pkgs, lib, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ./desktop.nix
      ./oo7.nix
    ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # Graphical boot process.
  boot.plymouth.enable = true;
  
  # Enable hugepages
  boot.kernelParams = [
    "hugepages=1024"
    # Force full DP link training to fix USB-C monitor training at HBR2
    # Without this, link training falls back to HBR (2.7 Gbps) instead of
    # HBR2 (5.4 Gbps), causing 4K@60 to degrade to YUV422 6-bpc (green screen)
    "amdgpu.forcelongtraining=1"
  ];
  boot.kernel.sysctl = {
    "vm.nr_hugepages" = 1024;
  };

  # Skip LTTPR on DCN 3.1.4 to avoid unreliable AUX channel through USB-C repeater
  # See: https://gitlab.freedesktop.org/drm/amd/-/issues/3913
  boot.kernelPatches = [{
    name = "amdgpu-skip-lttpr-dcn314";
    patch = ./amdgpu-skip-lttpr-dcn314.patch;
  }];

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
    alsa = {
      enable = true;
      support32Bit = true;
    };
    pulse.enable = true;
  };

  # https://gitlab.freedesktop.org/pipewire/pipewire/-/issues/4875
  systemd.user.services.pipewire.environment.PULSE_LATENCY_MSEC = "60";
  systemd.user.services.pipewire-pulse.environment.PULSE_LATENCY_MSEC = "60";

  nix = {
   settings = {
     cores = 4;
     max-jobs = 4;
     trusted-users = [ "root" "@wheel" ];
   };
   nixPath = lib.mkForce [];
   extraOptions = ''
     narinfo-cache-negative-ttl = 0
     show-trace = true
     extra-experimental-features = flakes nix-command
   '';
  };

  environment.variables = {
    EDITOR = lib.mkOverride 0 "vim";
    TERM = "xterm-256color";
  };

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
    # CLI utilities
    curl
    dos2unix
    htop
    jq
    lsof
    ncdu
    gh
    nmap
    psmisc
    pwgen
    ripgrep
    speedtest-cli
    tmux
    tree
    unzip
    wget
    wgetpaste

    # System tools
    alsa-utils
    extundelete
    fuse
    hdparm
    imagemagick
    inetutils
    rmlint
    sshfs-fuse
    sysstat

    # Development
    cachix
    direnv
    gdb
    gcc
    git-crypt
    tig
    gitFull
    gnumake
    nix-diff
    patchelf
    lastpass-cli
    _1password-cli
    asciinema
    asciinema-agg

    # Desktop environment
    networkmanagerapplet
    patray
    vim
    vscode
    xarchiver
    redland-wayland

    # Browsers
    chromium
    firefox

    # Virtualization
    docker

    # Documentation
    jwhois
    man-pages
    man-pages-posix

    # Unfree software
    signal-desktop
    zoom-us
  ];

  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "amdgpu" ];

  # WORKAROUND: Downgrade DMCUB firmware to fix USB-C monitor DPCD read errors
  # See: https://gitlab.freedesktop.org/drm/amd/-/issues/3913
  # Patch linux-firmware to replace the broken dcn_3_1_4_dmcub.bin with older version
  hardware.firmware = let
    oldDmcubBin = pkgs.fetchurl {
      url = "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/amdgpu/dcn_3_1_4_dmcub.bin?h=20241210";
      hash = "sha256-kwgGljDiT5KB4Fo+SS9VB2AdBE1yN409lp0/XTxTfLo=";
    };
    patchedLinuxFirmware = pkgs.linux-firmware.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        cp ${oldDmcubBin} $out/lib/firmware/amdgpu/dcn_3_1_4_dmcub.bin
      '';
    });
  in lib.mkForce [ patchedLinuxFirmware ];

  programs = {
    ssh.startAgent = true;
    gnupg.agent.enable = true;
    bash.completion.enable = true;
    autojump.enable = true;
    starship.enable = true;
  };
  services.gnome.gcr-ssh-agent.enable = false;

  services.tailscale.enable = true;

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

  # detect location and timezone
  location.provider = "geoclue2";
  services.automatic-timezoned.enable = true;
  # https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
  # time.timeZone = "Atlantic/Canary";

  # Allow geoclue to access wpa_supplicant for WiFi-based geolocation
  services.dbus.packages = [
    (pkgs.writeTextFile {
      name = "geoclue-wpa-dbus-policy";
      text = ''
        <!DOCTYPE busconfig PUBLIC
          "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
          "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
        <busconfig>
          <policy user="geoclue">
            <allow send_destination="fi.w1.wpa_supplicant1"/>
            <allow receive_sender="fi.w1.wpa_supplicant1"/>
          </policy>
        </busconfig>
      '';
      destination = "/share/dbus-1/system.d/geoclue-wpa.conf";
    })
  ];

  # chromecast: https://github.com/NixOS/nixpkgs/issues/49630#issuecomment-622498732
  services.avahi.enable = true;

  # See: https://github.com/NixOS/nixpkgs/issues/180175
  systemd.services.NetworkManager-wait-online.enable = false;
 
  services = {
    # Basic system services
    locate.enable = true;
    upower.enable = true;
    thermald.enable = true;
    earlyoom.enable = true;
    fwupd.enable = true; # firmware updates
    blueman.enable = true;
    tlp.enable = true; # optimize battery

    # Security services
    paretosecurity = {
      enable = true;
      trayIcon = true;
    };
    
    # Application services
    cachix-agent.enable = true;
    
    # Backup services
    restic.backups.full = {
      paths = [ "/home/domen/dev" "/etc" "/nix/var" ];
      repository = "s3:https://s3.us-west-002.backblazeb2.com/guava-backup";
      passwordFile = "/etc/restic/password";
      environmentFile = "/etc/restic/b2";
      initialize = true;
      timerConfig = {
        OnCalendar = "03:00";
        RandomizedDelaySec = "3h";
      };
    };
  };
}

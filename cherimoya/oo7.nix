{ pkgs, ... }:

{
  # oo7: rust-based alternative to gnome-keyring
  # provides org.freedesktop.secrets
  services.dbus.packages = [ pkgs.oo7-server ];

  systemd.user.services.oo7-daemon = {
    description = "oo7 Secret Service";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.oo7-server}/libexec/oo7-daemon";
      Restart = "on-failure";
      Type = "simple";
    };
  };
}

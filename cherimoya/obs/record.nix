{ pkgs, obs ? pkgs.obs-studio }:
let
  python = pkgs.python3.withPackages (p: [ p.websocket-client ]);
  cli = pkgs.writeShellScriptBin "record" ''
    export PATH=${obs}/bin:${pkgs.procps}/bin:${pkgs.glib.bin}/bin:$PATH
    exec ${python}/bin/python3 ${./record.py} "$@"
  '';
  desktop = pkgs.makeDesktopItem {
    name = "homelab-record";
    desktopName = "Record desktop and face";
    comment = "Start recording after a five-second countdown; Super+S stops and saves";
    exec = "${cli}/bin/record";
    icon = "com.obsproject.Studio";
    terminal = false;
    categories = [ "AudioVideo" "Recorder" ];
    keywords = [ "record" "screen" "desktop" "webcam" ];
  };
in
pkgs.symlinkJoin {
  name = "record";
  paths = [ cli desktop ];
  meta.mainProgram = "record";
}

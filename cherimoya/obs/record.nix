{ pkgs, obs ? pkgs.obs-studio }:
let
  python = pkgs.python3.withPackages (p: [ p.websocket-client ]);
in
pkgs.writeShellScriptBin "record" ''
  export PATH=${obs}/bin:${pkgs.procps}/bin:${pkgs.glib.bin}/bin:$PATH
  exec ${python}/bin/python3 ${./record.py} "$@"
''

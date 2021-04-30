{ writeShellScriptBin, symlinkJoin, debugUtils, ... }:
let
  entrypoint = writeShellScriptBin "print-env" ''
    trap 'echo "$(date -u +"%b %d, %y %H:%M:%S +0000"): Caught SIGINT -- exiting" && exit 0' INT
    env

    while true; do
      sleep 1
    done
  '';
in symlinkJoin {
  name = "entrypoint";
  paths = debugUtils ++ [ entrypoint ];
}

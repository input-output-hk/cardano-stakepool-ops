{ runCommand, writeShellScriptBin, symlinkJoin, consul, debugUtils, diffutils
, gitFull, patroni, postgresql_12, remarshal, restic, vault-bin, ... }:
let
  entrypoint = writeShellScriptBin "entrypoint" ''
    trap 'echo "$(date -u +"%b %d, %y %H:%M:%S +0000"): Caught SIGINT -- exiting" && exit 0' INT
    echo "devbox is ready... you can connect using nomad exec"
    while true; do
      sleep 10
    done
  '';
  pctl = writeShellScriptBin "pctl" ''
    patronictl -d consul://$CONSUL_HTTP_ADDR "$@"
  '';
in symlinkJoin {
  name = "entrypoint";
  paths = debugUtils ++ [
    entrypoint
    consul
    diffutils
    gitFull
    patroni
    pctl
    postgresql_12
    remarshal
    restic
    vault-bin
  ];
}


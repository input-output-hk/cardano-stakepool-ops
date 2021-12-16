{ inputs, self }:
final: prev:
let lib = final.lib;
in rec {

  postgres-entrypoint = final.callPackage ./pkgs/postgres-entrypoint.nix { };
  postgres-init-entrypoint =
    final.callPackage ./pkgs/postgres-init-entrypoint.nix { };
  postgres-backup-entrypoint =
    final.callPackage ./pkgs/postgres-backup-entrypoint.nix { };
  postgres-patroni-entrypoint =
    final.callPackage ./pkgs/postgres-patroni-entrypoint.nix { };

  print-env = final.callPackage ./pkgs/print-env.nix { };
  restic-backup = final.callPackage ./pkgs/restic-backup { };
  nomad-driver-nspawn = final.callPackage ./pkgs/nomad-driver-nspawn.nix { };
  devbox-entrypoint = final.callPackage ./pkgs/devbox.nix { };

  nodePkgs = inputs.cardano-node.legacyPackages.${final.system};

  inherit (final.nodePkgs) cardano-cli cardano-node;

  checkFmt = final.writeShellScriptBin "check_fmt.sh" ''
    export PATH="$PATH:${lib.makeBinPath (with final; [ git nixfmt gnugrep ])}"
    . ${./pkgs/check_fmt.sh}
  '';

  checkCue = final.writeShellScriptBin "check_cue.sh" ''
    export PATH="$PATH:${lib.makeBinPath (with final; [ cue ])}"
    cue vet -c
  '';

  debugUtils = with final; [
    awscli
    bashInteractive
    bat
    coreutils
    curl
    dnsutils
    fd
    findutils
    file
    gnugrep
    gnused
    gnutar
    gzip
    htop
    iproute
    iputils
    jq
    less
    lsof
    netcat
    procps
    ripgrep
    smem
    sqlite-interactive
    strace
    tcpdump
    tmux
    tree
    utillinux
    vim
  ];

  devShell = let
    clusterName = builtins.elemAt (builtins.attrNames final.clusters) 0;
    cluster = final.clusters.${clusterName}.proto.config.cluster;
  in prev.mkShell {
    # for bitte-cli
    LOG_LEVEL = "debug";

    DOMAIN = cluster.domain;
    NOMAD_NAMESPACE = "cardano-pools";
    BITTE_CLUSTER = cluster.name;
    AWS_PROFILE = "cardano-pools";
    AWS_DEFAULT_REGION = cluster.region;
    TERRAFORM_ORGANIZATION = cluster.terraformOrganization;

    VAULT_ADDR = "https://vault.${cluster.domain}";
    NOMAD_ADDR = "https://nomad.${cluster.domain}";
    CONSUL_HTTP_ADDR = "https://consul.${cluster.domain}";
    NIX_USER_CONF_FILES = ./nix.conf;

    buildInputs = with final; [
      awscli
      bitte
      cfssl
      cardano-cli
      cardano-node
      consul
      consul-template
      direnv
      jq
      nixfmt
      nomad
      # Causes a stack overflow when added to dev shell
      # Ref: https://github.com/NixOS/nix/issues/3821
      # patroni
      openssl
      pkgconfig
      restic
      sops
      terraform-with-plugins
      vault-bin
      ruby
      cue
    ];
  };

  # Used for caching
  devShellPath = prev.symlinkJoin {
    paths = final.devShell.buildInputs ++ [ final.nixFlakes ];
    name = "devShell";
  };

  inherit (inputs.nixpkgs-unstable.legacyPackages.${final.system})
    traefik patroni;
}

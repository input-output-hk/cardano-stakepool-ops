{
  description = "Bitte for Cardano Pools";

  inputs = {
    bitte.url = "github:input-output-hk/bitte/glusterfs";
    # bitte.url = "path:/home/jlotoski/work/iohk/bitte-wt/bitte";
    # bitte.url = "path:/home/manveru/github/input-output-hk/bitte";
    ops-lib.url = "github:input-output-hk/ops-lib/zfs-image?dir=zfs";
    nixpkgs.follows = "bitte/nixpkgs";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    terranix.follows = "bitte/terranix";
    utils.follows = "bitte/utils";

    # Node 1.26.1 tag (no release branch available)
    cardano-node.url =
      "github:input-output-hk/cardano-node?rev=62f38470098fc65e7de5a4b91e21e36ac30799f3";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, utils, bitte, ... }@inputs:
    let
      opsOverlay = import ./overlay.nix { inherit inputs self; };
      bitteOverlay = bitte.overlay;

      hashiStack = bitte.mkHashiStack {
        flake = self;
        rootDir = ./.;
        inherit pkgs;
        domain = "pools.dev.cardano.org";
      };

      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [
          (final: prev: { inherit (hashiStack) clusters dockerImages; })
          bitteOverlay
          opsOverlay
        ];
      };

      nixosConfigurations = hashiStack.nixosConfigurations // {
        nspawn-test = import ./nspawn/test.nix { inherit nixpkgs; };
      };
    in {
      inherit self nixosConfigurations;
      inherit (hashiStack) nomadJobs dockerImages consulTemplates;

      clusters.x86_64-linux = hashiStack.clusters;
      legacyPackages.x86_64-linux = pkgs;
      devShell.x86_64-linux = pkgs.devShell;
      hydraJobs.x86_64-linux = {
        inherit (pkgs)
          devShellPath bitte nixFlakes sops terraform-with-plugins cfssl consul
          nomad vault-bin cue grafana haproxy grafana-loki victoriametrics
          nomad-driver-nspawn devbox-entrypoint cardano-cli;
      } // (pkgs.lib.mapAttrs (_: v: v.config.system.build.toplevel)
        nixosConfigurations);
    };
}

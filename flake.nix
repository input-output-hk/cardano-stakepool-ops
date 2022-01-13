{
  description = "Bitte for Cardano Stakepools";

  inputs = {
    utils.url = "github:numtide/flake-utils";

    # --- Bitte Stack ----------------------------------------------
    bitte.url = "github:input-output-hk/bitte";
    # bitte.url = "path:/home/jlotoski/work/iohk/bitte-wt/bitte";
    # bitte.url = "path:/home/manveru/github/input-output-hk/bitte";
    nixpkgs.follows = "bitte/nixpkgs";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # --------------------------------------------------------------

    # --- Makes Stack ----------------------------------------------
    makes.url = "github:input-output-hk/makes";
    # --------------------------------------------------------------

    # Inputs
    cardano-node = {
      url = "github:input-output-hk/cardano-node/1.33.0";
      inputs.customConfig.url = "path:./pkgs/node-custom-config";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, bitte, cardano-node, makes, utils, ... }@inputs:

    (makes.lib.flakes.evaluate { inherit inputs; system = "x86_64-linux"; })

    //

    (
      let
        overlays = [ pkgsOverlay entrypointsOverlay bitte.overlay ];

        pkgsOverlay = final: prev: {
          inherit (inputs.nixpkgs-unstable.legacyPackages.${final.system}.dockerTools)
            buildImage buildLayeredImage pullImage;
          inherit (inputs.nixpkgs-unstable.legacyPackages.${final.system})
            traefik complete-alias;
        };

        entrypointsOverlay = final: prev: {
          inherit (inputs.cardano-node.packages.${final.system})
            "testnet/node"
            "mainnet/node"
            "testnet/submit-api"
            "mainnet/submit-api"
            ;
          stakepool-entrypoint = final.callPackage ./entrypoints/stakepool-entrypoint.nix { };
        };

        pkgsForSystem = system: import nixpkgs {
          inherit overlays system;
          config.allowUnfree = true;
        };

        bitteStack = bitte.lib.mkBitteStack {
          inherit self inputs;
          pkgs = pkgsForSystem "x86_64-linux";
          domain = "cardano-pools.iohk.io";
          docker = ./docker;
          clusters = ./clusters;
          deploySshKey = "./secrets/ssh-stakepools-testnet";
          envs = (import ./envs/default.nix).envs self.rev self.dockerImages;
          hydrateModule = (import ./envs/default.nix).bitteHydrateModule;
        };

      in
      utils.lib.eachSystem [ "x86_64-linux" ]
        (system: rec {

          legacyPackages = pkgsForSystem system;

          devShell = legacyPackages.bitteShell rec {
            inherit self;
            profile = "cardano-pools";
            domain = "cardano-pools.iohk.io";
            cluster = "cardano-pools";
            namespace = "cardano-testnet";
            region = "eu-central-1";
            extraPackages = [ ];
            # nixConfig = ''
            #   extra-substituters = https://hydra.${domain}
            #   extra-trusted-public-keys = ${nixpkgs.lib.fileContents ./encrypted/nix-public-key-file}
            # '';
          };

        }) // {
        # eta reduce not possibe since flake check validates for "final" / "prev"
        overlay = final: prev: nixpkgs.lib.composeManyExtensions overlays final prev;
      } // bitteStack
    )

  ; # outputs
}

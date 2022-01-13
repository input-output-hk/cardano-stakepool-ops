{ self, lib, pkgs, config, terralib, ... }:
let
  inherit (self.inputs) bitte;
  inherit (config) cluster;
  inherit (import ./security-group-rules.nix {
    inherit config pkgs lib terralib;
  })
    securityGroupRules;
in {
  imports = [ ./iam.nix ];

  services.consul.policies.developer.servicePrefix."cardano" = {
    policy = "write";
    intentions = "write";
  };

  services.nomad.namespaces = {
    cardano-pools = { description = "Cardano (testnet)"; };
  };

  nix = {
    binaryCaches = [ "https://hydra.iohk.io" ];

    binaryCachePublicKeys =
      [ "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" ];
  };

  cluster = {
    name = "cardano-pools";

    adminNames = [ "samuel.leathers" ];
    developerGithubNames = [ ];
    developerGithubTeamNames = [ "devops" ];
    domain = "cardano-pools.iohk.io";
    kms =
      "arn:aws:kms:eu-central-1:882803439528:key/d78428ce-40ec-439c-83ec-a544dc16e5c0";
    s3Bucket = "cardano-pools";
    terraformOrganization = "cardano-pools";

    s3CachePubKey = lib.fileContents ../../../encrypted/nix-public-key-file;
    flakePath = ../../..;

    autoscalingGroups = let
      defaultModules = [
        bitte.profiles.client
        "${self.inputs.nixpkgs}/nixos/modules/profiles/headless.nix"
        "${self.inputs.nixpkgs}/nixos/modules/virtualisation/ec2-data.nix"
        ./secrets.nix
        ./docker-auth.nix
        ./host-volumes.nix
        ./nspawn.nix
        {
          boot.kernelModules = [ "softdog" ];
          #
          # Watchdog events will be logged but not force the nomad client node to restart
          # Comment this line out to allow forced watchdog restarts
          # Patroni HA Postgres jobs will utilize watchdog and log additional info if it's available
          boot.extraModprobeConfig = "options softdog soft_noboot=1";
        }
      ];

      withNamespace = name:
        pkgs.writeText "nomad-tag.nix" ''
          { services.nomad.client.meta.namespace = "${name}"; }
        '';

      mkModules = name: defaultModules ++ [ "${withNamespace name}" ];
      # For each list item below which represents an auto-scaler machine(s),
      # an autoscaling group name will be created in the form of:
      #
      #   client-$REGION-$INSTANCE_TYPE
      #
      # This works for most cases, but if there is a use case where
      # machines of the same instance type and region need to be
      # separated into different auto-scaling groups, this can be done by
      # setting a string attribute of `asgSuffix` in the list items needed.
      #
      # If used, asgSuffix must be a string matching a regex of: ^[A-Za-z0-9]$
      # Otherwise, nix will throw an error.
      #
      # asgSuffix can be used with the `withNamespace` function above to
      # meta tag nodes in certain autoscaler groups.  The meta tagged nodes
      # can then be used to constrain job deployments via cue definitions
      # or new Nomad node namespace functionality in the (hopefully) near future.
      #
      # Autoscaling groups which utilize an asgSuffix will be named in the form:
      #
      #   client-$REGION-$INSTANCE_TYPE-$ASG_SUFFIX
      #
      # Refs:
      # https://www.nomadproject.io/docs/job-specification/constraint#user-specified-metadata
      # https://github.com/hashicorp/nomad/issues/9342

    in lib.listToAttrs (lib.forEach [
      # Mainnet, 3 regions
      {
        region = "eu-central-1";
        # desiredCapacity = 1;
        instanceType = "t3a.xlarge";
        volumeSize = 500;
        modules = mkModules "cardano-pools";
      }
      {
        region = "eu-west-1";
        # desiredCapacity = 1;
        instanceType = "t3a.xlarge";
        volumeSize = 500;
        modules = mkModules "cardano-pools";
      }
      {
        region = "us-east-2";
        # desiredCapacity = 1;
        instanceType = "t3a.xlarge";
        volumeSize = 500;
        modules = mkModules "cardano-pools";
      }

      # Public testnet, 3 regions
      {
        region = "eu-central-1";
        # desiredCapacity = 1;
        instanceType = "t3a.xlarge";
        volumeSize = 500;
        modules = mkModules "cardano-pools-testnet";
        asgSuffix = "testnet";
      }
      {
        region = "eu-west-1";
        # desiredCapacity = 1;
        instanceType = "t3a.xlarge";
        volumeSize = 500;
        modules = mkModules "cardano-pools-testnet";
        asgSuffix = "testnet";
      }
      {
        region = "us-east-2";
        # desiredCapacity = 1;
        instanceType = "t3a.xlarge";
        volumeSize = 500;
        modules = mkModules "cardano-pools-testnet";
        asgSuffix = "testnet";
      }
    ] (args:
      let
        attrs = ({
          desiredCapacity = 1;
          instanceType = "t3a.large";
          associatePublicIP = true;
          maxInstanceLifetime = 0;
          iam.role = cluster.iam.roles.client;
          iam.instanceProfile.role = cluster.iam.roles.client;

          securityGroupRules = {
            inherit (securityGroupRules) internet internal ssh;
          };
        } // args);
        attrs' = removeAttrs attrs [ "asgSuffix" ];
        suffix = if args ? asgSuffix then
          if (builtins.match "^[A-Za-z0-9]+$" args.asgSuffix) != null then
            "-${args.asgSuffix}"
          else
            throw "asgSuffix must regex match a string of ^[A-Za-z0-9]$"
        else
          "";
        asgName = "client-${attrs.region}-${
            builtins.replaceStrings [ "." ] [ "-" ] attrs.instanceType
          }${suffix}";
      in lib.nameValuePair asgName attrs'));

    instances = {
      core-1 = {
        instanceType = "t3a.medium";
        privateIP = "172.16.0.10";
        subnet = cluster.vpc.subnets.core-1;
        volumeSize = 100;

        modules =
          [ bitte.profiles.core bitte.profiles.bootstrapper ./secrets.nix ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh;
        };

        initialVaultSecrets = {
          consul = ''
            sops --decrypt --extract '["encrypt"]' ${
              config.secrets.encryptedRoot + "/consul-clients.json"
            } \
            | vault kv put kv/bootstrap/clients/consul encrypt=-
          '';

          nomad = ''
            sops --decrypt --extract '["server"]["encrypt"]' ${
              config.secrets.encryptedRoot + "/nomad.json"
            } \
            | vault kv put kv/bootstrap/clients/nomad encrypt=-
          '';
        };
      };

      core-2 = {
        instanceType = "t3a.medium";
        privateIP = "172.16.1.10";
        subnet = cluster.vpc.subnets.core-2;
        volumeSize = 100;

        modules = [ bitte.profiles.core ./secrets.nix ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh;
        };
      };

      core-3 = {
        instanceType = "t3a.medium";
        privateIP = "172.16.2.10";
        subnet = cluster.vpc.subnets.core-3;
        volumeSize = 100;

        modules = [ bitte.profiles.core ./secrets.nix ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh;
        };
      };

      monitoring = {
        instanceType = "t3a.xlarge";
        privateIP = "172.16.0.20";
        subnet = cluster.vpc.subnets.core-1;
        volumeSize = 300;
        route53.domains = [
          "consul.${cluster.domain}"
          "docker.${cluster.domain}"
          "monitoring.${cluster.domain}"
          "nomad.${cluster.domain}"
          "vault.${cluster.domain}"
        ];

        modules =
          [ bitte.profiles.monitoring ./secrets.nix ./monitoring-server.nix ];

        securityGroupRules = {
          inherit (securityGroupRules)
            internet internal ssh http https docker-registry;
        };
      };

      routing = {
        instanceType = "t3a.small";
        privateIP = "172.16.1.20";
        subnet = cluster.vpc.subnets.core-2;
        volumeSize = 30;
        route53.domains = [ "*.${cluster.domain}" ];

        modules = [ bitte.profiles.routing ./secrets.nix ./routing.nix ];

        securityGroupRules = {
          inherit (securityGroupRules) internet internal ssh http https routing;
        };
      };
    };
  };
}

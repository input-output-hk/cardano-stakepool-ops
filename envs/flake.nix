{
  description = "nomad job definitions";
  inputs.data-merge.url = "github:divnix/data-merge";
  outputs = { self, data-merge }:
    let

      # Metadata
      # -----------------------------------------------------------------------

      baseDomain = "cardano-pools.iohk.io";

      mainnetRev = "877cdd12364b098a50f32d8428c192c96aec673c";
      stagingRev = "877cdd12364b098a50f32d8428c192c96aec673c";

      # Library Functions
      # -----------------------------------------------------------------------

      constrainToAwsInstance = value: {
        attribute = "\${attr.unique.platform.aws.instance-id}";
        operator = "=";
        inherit value;
      };

      addPromtail = { task.promtail = import ./extra/promtail.nix; };

      /* * enablePromtail enables the promtail task across all jobs
         and across all of each job's respective task groups.
         *
      */
      enablePromtail = lhs:
        let
          jobNames = builtins.attrNames lhs;
          # each task group ...
          op2 = old: groupName: old // { ${groupName} = addPromtail; };
          # each job ...
          op1 = old: jobName:
            old // {
              ${jobName}.job.${jobName}.group = (builtins.foldl' op2 { }
                (builtins.attrNames lhs.${jobName}.job.${jobName}.group));
            };
        in data-merge.merge lhs (builtins.foldl' op1 { } jobNames);

      # Proto Environments
      # -----------------------------------------------------------------------

      prod-testnet' = let
        lhs = import ./base/default.nix {
          selfRev = mainnetRev;
          namespace = "testnet-prod";
          domain = "testnet.${baseDomain}";
          clientGroup = "prod";
        };
      in enablePromtail lhs;

      staging-testnet' = let
        lhs = import ./base/default.nix {
          selfRev = stagingRev;
          namespace = "testnet-staging";
          domain = "staging.${baseDomain}";
          clientGroup = "staging";
        };
      in enablePromtail lhs;

      dev-testnet' = rev: dockerImages:
        let
          selfRev = rev;
          namespace = "testnet-dev";
          domain = "dev.${baseDomain}";
          clientGroup = "dev";
          lhs = import ./base/default.nix {
            inherit namespace selfRev domain clientGroup;
          };
          # We simulate the custodian's signer in the unstable environment
          # via an encapsulated container environment
          simulatedSignerAGIX = import ./extra/simulatedSignerAGIX/default.nix {
            inherit namespace selfRev domain clientGroup dockerImages;
          };
          lhs' = data-merge.merge lhs { inherit simulatedSignerAGIX; };
        in enablePromtail lhs';

      ops-testnet' = dockerImages:
        let
          selfRev = mainnetRev;
          namespace = "testnet-ops";
          domain = "ops.${baseDomain}";
          # NB: (sporadic) ops is also contraint to 'dev' ClientGroup
          clientGroup = "dev";
          lhs = import ./base/default.nix {
            inherit namespace selfRev domain clientGroup;
          };
          # We simulate the custodian's signer in the unstable environment
          # via an encapsulated container environment
          simulatedSignerAGIX = import ./extra/simulatedSignerAGIX/default.nix {
            inherit namespace selfRev domain clientGroup dockerImages;
          };
          lhs' = data-merge.merge lhs { inherit simulatedSignerAGIX; };
        in enablePromtail lhs';

      # Bitte Hydrate Module
      # -----------------------------------------------------------------------
      #
      # reconcile with: `nix run .#clusters.[...].tf.hydrate.(plan/apply)`
      bitteHydrateModule = import ./hydrate.nix {
        namespaces = [ "testnet-prod" "testnet-dev" ];
        components = [ "backend" "database" "frontend" "rabbit" "signer" ];
      };

      # Shared Spezialisation Config
      DB_DATABASE =
        "erc20_test"; # Database names must remain 63 characters or less
      DB = DB_DATABASE;
      ETH_WALLET = "0x74f79c316eab2db96f2f13f918826a03de89b4fd";
      TOKEN_MANAGER_CONTRACT_ADDRESS =
        "0x90EDD8952dA35522F20D69Efe8983cefbB0A1b3d";

    in {
      inherit bitteHydrateModule;

      # Actual Environments
      # -----------------------------------------------------------------------

      envs = currentRev: dockerImages: {

        testnet-prod = let
          dbEnv = let
            env = {
              inherit DB;
              WALG_S3_PREFIX =
                "s3://iohk-erc20-bitte/backups/testnet-prod/walg";
            };
          in {
            postgres-patroni = { inherit env; };
            postgres-backup-walg = { inherit env; };
          };
        in data-merge.merge prod-testnet' {
          # Stateful services require pegging to a particular instance until
          # arrival of distributed storage
          # TODO: implement distributed storage
          backend.job.backend.constraint = # eu-central-1
            data-merge.append
            [ (constrainToAwsInstance "i-0517760825c4813cd") ];
          databaseHA1.job.databaseHA1.constraint = # eu-central-1
            data-merge.append
            [ (constrainToAwsInstance "i-07e6cd4e028dfdff2") ];
          databaseHA2.job.databaseHA2.constraint = # eu-west-1
            data-merge.append
            [ (constrainToAwsInstance "i-0983d6732b5fc6c08") ];
          databaseHA3.job.databaseHA3.constraint = # us-east-2
            data-merge.append
            [ (constrainToAwsInstance "i-01772e4b906e556c8") ];
          rabbitHA1.job.rabbitHA1.constraint = data-merge.append
            [ (constrainToAwsInstance "i-07e6cd4e028dfdff2") ];
          # External signers need a tcp route to the amqp
          # TODO: mutual transport layer security (mTLS) over the public net
          rabbitHA1.job.rabbitHA1.group.rabbit.service =
            data-merge.update [ 0 ] [{
              tags = data-merge.append [
                "traefik.tcp.routers.erc20-testnet-stable-rabbit.rule=HostSNI(`*`)"
                "traefik.tcp.routers.erc20-testnet-stable-rabbit.entrypoints=amqp"
              ];
            }];
          # Diverging config values
          databaseHA1.job.databaseHA1.group.database.task = dbEnv;
          databaseHA2.job.databaseHA2.group.database.task = dbEnv;
          databaseHA3.job.databaseHA3.group.database.task = dbEnv;
          backend.job.backend.group.backend.task =
            let CARDANO_WALLET_ID = "b6d9979bb02bbb26e859669e7208222dd7fba097";
            in {
              cardano-wallet-init.env = { inherit CARDANO_WALLET_ID; };
              erc20converter-backend.env = {
                inherit ETH_WALLET TOKEN_MANAGER_CONTRACT_ADDRESS
                  CARDANO_WALLET_ID DB_DATABASE;
              };
              erc20converter-backend.env.CARDANO_INPUT_ADDRESS =
                "addr_test1qr8flfmalvcye20lgqu4fer6ns03yzrl3quakm2uuzy54lzauuz7kqsrgtq7rdkl4k387ywrdvymvmdwk6dsynx6pd7sgjjyp2";
              erc20converter-backend.env.DEFAULT_SIGNER_KEY_HASH =
                "9cd346c0a65152fb53babdff626127b0a9dc12486e9bccaace5b0904";
              erc20converter-backend.env.SINGULARITY_MINTING_POLICY =
                "34d1adbf3a7e95b253fd0999fb85e2d41d4121b36b834b83ac069ebb";
              erc20converter-backend.env.SINGULARITY_SIGNER_KEY_HASH =
                "9b25d93444f8c19a2a4fa291643026ddbba9d3365956f482a70a2c22";
            };
          signer.job.signer.group.signer.task = {
            erc20converter-signer.env.VAULT_SECRET_PATH =
              "runtime/data/testnet-prod/signer";
          };
          frontend.job.frontend.group.frontend.task = {
            erc20converter-app.env.NEXT_PUBLIC_PASSWORD_PROTECT = "false";
          };
        };

        testnet-dev = let
          dbEnv = let
            env = {
              inherit DB;
              WALG_S3_PREFIX = "s3://iohk-erc20-bitte/backups/testnet-dev/walg";
            };
          in {
            postgres-patroni = { inherit env; };
            postgres-backup-walg = { inherit env; };
          };
        in data-merge.merge (dev-testnet' currentRev dockerImages) {
          # Stateful services require pegging to a particular instance until
          # arrival of distributed storage
          # TODO: implement distributed storage
          backend.job.backend.constraint = # eu-central-1
            data-merge.append
            [ (constrainToAwsInstance "i-06e2ec749a3d50b30") ];
          databaseHA1.job.databaseHA1.constraint = # eu-central-1
            data-merge.append
            [ (constrainToAwsInstance "i-00358035cc954950d") ];
          databaseHA2.job.databaseHA2.constraint = # eu-west-1
            data-merge.append
            [ (constrainToAwsInstance "i-007b5534bbd7baa86") ];
          databaseHA3.job.databaseHA3.constraint = # us-east-1
            data-merge.append
            [ (constrainToAwsInstance "i-01ec06cc434bdaf8a") ];
          rabbitHA1.job.rabbitHA1.constraint = # eu-central-1
            data-merge.append
            [ (constrainToAwsInstance "i-00358035cc954950d") ];
          # Diverging config values
          databaseHA1.job.databaseHA1.group.database.task = dbEnv;
          databaseHA2.job.databaseHA2.group.database.task = dbEnv;
          databaseHA3.job.databaseHA3.group.database.task = dbEnv;
          backend.job.backend.group.backend.task =
            let CARDANO_WALLET_ID = "0712423b1034a00a499b71ff4bbf0ecabb6e311c";
            in {
              cardano-wallet-init.env = { inherit CARDANO_WALLET_ID; };
              erc20converter-backend.env = {
                inherit ETH_WALLET TOKEN_MANAGER_CONTRACT_ADDRESS
                  CARDANO_WALLET_ID DB_DATABASE;
              };
              erc20converter-backend.env.CARDANO_INPUT_ADDRESS =
                "addr_test1qrtx083j8wtd3zpskxdaj4wuyupk55wehpgzfyp6n3ze9z4y52gpsytvgk88uu4epcdwvhxxjmxp32j6cm9vh8an2d3q9svdqx";
              erc20converter-backend.env.DEFAULT_SIGNER_KEY_HASH =
                "bc090bd574d438b9405a0846bc17bff9b0aee367a1336559fe1296ef";
              erc20converter-backend.env.SINGULARITY_MINTING_POLICY =
                "8fb1cf376fd16f5d595486a47bd3cbaf4f5f87ed864f849ea9823341";
              erc20converter-backend.env.SINGULARITY_SIGNER_KEY_HASH =
                "3ab79f1d2f2604556d8e348897252be09f6ec6e43ee14bc1304c8f15";
            };
          signer.job.signer.group.signer.task = {
            erc20converter-signer.env.VAULT_SECRET_PATH =
              "runtime/data/testnet-dev/signer";
          };
        };
      };

    };
}

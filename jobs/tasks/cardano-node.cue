package tasks

import (
    "github.com/input-output-hk/cardano-stakepool-ops/pkg/schemas/nomad:types"
)

#CardanoNode: types.#stanza.task & {
    #dbSyncNetwork: string

    driver: "exec"

    resources: {
        cpu:    6000
        memory: 1024 * 6
    }

    config: {
        flake:   "github:input-output-hk/cardano-node#testnet/node"
        flake_args: [
          "--override-input", "customConfig", "path:/local/config"
        ]
        command: "/bin/cardano-node-testnet"
    }

    template: "local/config/flake.nix": {
      data: """
      {
        outputs = {...}: {
          x86_64-linux.legacyPackages.customConfigFile = {...}: {
            port = 1234;
          };
        };
      }
      """
    }
}

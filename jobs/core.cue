package jobs

import (
    "github.com/input-output-hk/cardano-stakepool-ops/pkg/schemas/nomad:types"
    "github.com/input-output-hk/cardano-stakepool-ops/pkg/jobs/tasks:tasks"
)

#Core: types.#stanza.job & {
  type: "service"

  group: core: {
    network: {
      mode: "host"
      port: cardano: {}
    }
    task: "cardano-node": tasks.#CardanoNode
    task: telegraf: tasks.#Telegraf
    task: promtail: tasks.#Promtail
  }
}

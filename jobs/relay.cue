package jobs

import (
    "github.com/input-output-hk/cardano-stakepool-ops/pkg/schemas/nomad:types"
    "github.com/input-output-hk/cardano-stakepool-ops/pkg/jobs/tasks:tasks"
)

#Relay: types.#stanza.job & {
  type: "service"

  group: relay: {
    task: "cardano-node": tasks.#CardanoNode
    task: telegraf: tasks.#Telegraf
    task: promtail: tasks.#Promtail
  }
}

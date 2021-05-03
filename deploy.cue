package bitte

import (
	"github.com/input-output-hk/cardano-stakepool-ops/pkg/schemas/nomad:types"
	jobDef "github.com/input-output-hk/cardano-stakepool-ops/pkg/jobs:jobs"
	"list"
)

#namespaces: {
	"cardano-testnet": jobs: {
		relay: #relay
		core:  #core
	}
}

#core:  jobDef.#Core
#relay: jobDef.#Relay

_Namespace: [Name=_]: {
	vars: {
		namespace: =~"^cardano-[a-z-]+$"
		namespace: Name
		let datacenter = "eu-central-1" | "us-east-2" | "eu-west-1"
		datacenters: list.MinItems(1) | [...datacenter] | *["eu-central-1", "us-east-2", "eu-west-1"]
	}
	jobs: [string]: types.#stanza.job
}

#namespaces: _Namespace

for nsName, nsValue in #namespaces {
	rendered: "\(nsName)": {
		for jName, jValue in nsValue.jobs {
			"\(jName)": Job: types.#toJson & {
				#jobName: jName
				#job:     jValue & nsValue.vars
			}
		}
	}
}

for nsName, nsValue in #namespaces {
	// output is alphabetical, so better errors show at the end.
	zchecks: "\(nsName)": {
		for jName, jValue in nsValue.jobs {
			"\(jName)": jValue & nsValue.vars
		}
	}
}

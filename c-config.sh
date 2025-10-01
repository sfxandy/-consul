What it looks like

QZSD emits desired state (services, tags, health, routers/resolvers, gateway intents) into a store (Git repo, DB, object store, or an event stream).

A stateless “reconciler” (operator) watches that store and converges Consul to match it (idempotently).

Pros

Decoupling & safety: Consul-specific logic, tokens, and version quirks live in the reconciler—not inside QZSD.

Auditability & rollback: the store is your source of truth. It’s easy to diff, review, roll back, and replay. Great for compliance.

Dry-run & policy gates: you can validate schemas, run linters, and enforce policy (e.g., intentions must exist before routers) before touching Consul.

Resilience to Consul hiccups: the reconciler can absorb backpressure, batch, rate-limit, and retry without stalling QZSD.

Disaster recovery: rebuilding a Consul cluster is as simple as replaying the store.

Blue/green planes: one desired-state feed can drive two Consul environments (A/B) for cutovers.

Principle of least privilege: only the reconciler holds Consul ACLs; QZSD never touches Consul.

Cons

Eventual consistency: there’s a lag between QZSD emitting and Consul reflecting the change (tunable but real).

More moving parts: you must operate the store and the reconciler, plus their observability/alerts.

Dual schema/version drift: you now own a stable “platform schema” in the store and the mapping to Consul resources—keep those in lockstep.

Complex sequencing: the reconciler must handle dependency graphs (e.g., create resolver before router; ensure intentions exist before exposing via terminating gateway).

Where it shines

Medium/large estates; regulated environments; teams that value GitOps-style workflows, audits, and safe rollouts.

Multi–data center / WAN federation, where you need replayability and staged delivery.

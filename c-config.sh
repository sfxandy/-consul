# QZSD Migration Discussion

There is a legacy service discovery system, internal to the org, called QZSD. 
It's slow, painful, and tightly coupled with the application framework. 
The plan is to migrate to Consul-Envoy using Consul Connect.

---

## Option A — Control plane in QZSD writing directly to Consul

QZSD makes API calls to Consul to register services, configure service-resolvers, routers, terminating gateways, etc.

**Pros:**
- Fewer moving parts
- Lower latency (changes visible immediately)
- Simpler debugging path
- Allows orchestration of multi-step changes

**Cons:**
- Tight coupling to Consul APIs and semantics
- Propagation of failures from Consul back into QZSD
- QZSD must hold powerful ACL tokens (large security blast radius)
- Harder to audit/rollback
- Difficult for blue/green or multi-control-plane evolution

---

## Option B — Intermediate store + reconciler

QZSD writes service data to an intermediate store (Git, DB, or event stream). 
A reconciler process reads the store and applies changes to Consul.

**Pros:**
- Decouples QZSD from Consul specifics
- Clear audit trail and rollback
- Enables dry-run, policy checks, and safer rollouts
- Resilient to Consul hiccups (store absorbs backpressure)
- Easy disaster recovery (replay from store)
- Smaller security blast radius (only reconciler holds Consul tokens)
- Enables blue/green control planes easily

**Cons:**
- Eventual consistency instead of immediate
- More moving parts to manage
- Need to maintain mapping schema (desired state → Consul resources)
- Must handle dependency ordering in the reconciler

---

## Scale Considerations

With ~10,000 services, scale favors Option B. Unknown change rate implies bursts, so buffering, batching, and idempotency are essential.

**Recommended approach:**
- Put static config (resolvers, routers, intentions, gateways) in versioned store
- Put dynamic endpoints on event stream, or rely on agents/sidecars to self-register

---

## Migration Path

1. Shadow mode: QZSD writes to store; reconciler runs in dry-run against Consul  
2. Parallel Consul deployment: reconciler applies config for validation  
3. Incremental cutover via gateways and selected services  
4. Sidecars handle modern services, reconciler handles legacy endpoints  
5. Gradual traffic cutover with resolvers/routers/splitters  
6. Retire QZSD after services migrate  

---

## Blue/Green Control Planes

- Reconciler applies desired state to both clusters (A=green, B=blue).  
- Continuous drift detection ensures configs are identical before switching.  
- Agents switch between clusters by re-pointing to new servers/DNS.  
- Rollback is simple: switch agents back.  

---

## Continuous Drift Detection

Drift detection highlights mismatches between desired and actual state, such as:
- Missing or extra config objects
- Field-level mismatches (timeouts, retries, subset filters)
- Stale service registrations or endpoints
- Partial apply failures
- Namespace/partition mismatches
- Gateway exposure differences
- Intention/security drift (e.g., unexpected allows)

This ensures correctness, auditability, and safe operation at scale.

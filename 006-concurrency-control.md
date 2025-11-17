# ADR-006: Concurrency Control (Consul Session + KV Acquire)
**Status:** Accepted  
**Date:** 2025-11-17

## Context
We will run multiple API instances behind a VIP.

## Decision
Use a per‑service **distributed lock**:
- Create a Consul **Session** with TTL and delete behavior.
- `KV.Acquire` on `svc-handler/locks/<part>/<ns>/<service>`.
- If already held, reply **409 Conflict**.

## Rationale
Ensures single writer per service; locks are automatically released if the process crashes (TTL expiry).

## Operational Considerations
- TTL default 60s; renew every TTL/2 in a goroutine.
- Ensure clock skew is bounded; Consul handles renewals tolerantly.

## Acceptance Criteria
- Concurrent PUTs for the same service result in exactly one apply; others get 409.

## Rollback
Bypass locking in dev mode only (feature flag).

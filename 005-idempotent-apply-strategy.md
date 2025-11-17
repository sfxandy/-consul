# ADR-005: Idempotent Apply Strategy (render → upsert → verify → record ID)
**Status:** Accepted  
**Date:** 2025-11-17

## Context
Clients may retry PUT; multiple workers may act on the same service.

## Decision
For each resource (Defaults, Resolver, Router, TGW):
1. **Render** from request payload.
2. **Upsert** via Consul Config Entries Set.
3. **Verify** via consistent Get; validate against rendered struct.
4. **Capture** an authoritative `resource_id` or version.
5. **Persist** updated resource doc back to `desired/<...>/<resource>.json`.

## Rationale
Ensures convergence and visible provenance of what Consul accepted.

## Consequences
- Read‑after‑write overhead, but strong correctness and auditability.

## Acceptance Criteria
- Replaying the same PUT yields identical desired docs and no diff in Consul.

## Failure Handling
- On verify mismatch: compensate delete or revert to `last_good`, write `status.json`, return 502.

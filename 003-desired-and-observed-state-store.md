# ADR-003: Desired and Observed State Store (Consul KV)
**Status:** Accepted  
**Date:** 2025-11-17

## Context
We want idempotency and auditability without additional infra like Postgres/Redis.

## Problem
Direct "fire and forget" writes to Consul config entries lack context and history.

## Decision
Store **desired** (rendered spec + resource_ids) and **observed** (live snapshot) in **Consul KV** under deterministic keys:
- `svc-handler/desired/<part>/<ns>/<service>/...`
- `svc-handler/observed/<part>/<ns>/<service>.json`

## Rationale
- Dog‑foods Consul; single control plane dependency.
- Deterministic keys enable convergence and simple auditing.

## Consequences
**Positive**
- Full traceability per service and resource.
- No external DB to run.

**Negative**
- KV is document‑oriented; must design schemas deliberately.

## Operational Considerations
- Enable Consul gossip and RPC TLS; ensure KV encrypt in transit.
- Consider Consul snapshots for backup.

## Acceptance Criteria
- After a successful PUT, all expected `desired/*` docs exist with `resource_id` set, and `observed` reflects presence.

## Rollback
Collapse to a single `desired.json` and `observed.json` if sub‑docs prove cumbersome.

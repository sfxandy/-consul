# ADR-004: KV Namespace Scheme (partition/namespace in keys)
**Status:** Accepted  
**Date:** 2025-11-17

## Context
Future multi‑tenant or environment isolation may require partitions or namespaces.

## Decision
Include **partition** and **namespace** segments in every key path, sourced from environment (`CONSUL_PARTITION`, `CONSUL_NAMESPACE`), defaulting to `default/default`.

## Rationale
Prevents collisions; enables gradual adoption of namespaces without key migration.

## Key Format Examples
- Desired base: `svc-handler/desired/<part>/<ns>/<service>/base.json`
- Lock: `svc-handler/locks/<part>/<ns>/<service>`

## Acceptance Criteria
- Changing env moves new keys under the new subtree; old keys remain intact.

## Trade‑offs
Slightly longer keys vs future‑proofing.

## Rollback
Use a flat scheme if multi‑tenancy is permanently out of scope.

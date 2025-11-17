# ADR-007: Resource Set and Ordering
**Status:** Accepted  
**Date:** 2025-11-17

## Context
A registration spans multiple Consul config entries that must be applied in a stable order.

## Decision
Apply and verify in order:
1. **ServiceDefaults** — protocol and timeouts.
2. **ServiceResolver** — placeholder for subsets/failover.
3. **ServiceRouter** — optional HTTP routing policies.
4. **TerminatingGateway** — link virtual name to external upstream.

## Rationale
Dependencies are clear and verification is straightforward.

## Acceptance Criteria
- Each successful apply persists the `resource_id` for that resource doc.

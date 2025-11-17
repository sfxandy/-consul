# ADR-010: Error and Rollback Policy
**Status:** Accepted  
**Date:** 2025-11-17

## Decision
On verify failure for a resource:
- Compensate (delete the resource or revert to `last_good`).
- Write structured error to `observed` and `status.json` (failed_step, attempt, details).
- Release lock and return HTTP 502.

## Acceptance Criteria
- Partial applies leave the system in a bounded, discoverable state.

# ADR-011: Status Documents (FSM)
**Status:** Accepted  
**Date:** 2025-11-17

## Decision
Maintain `status.json` per service with states:
- `pending` → `applying` → `applied` | `apply_failed`
Fields: `attempt`, `retry_after` (optional), `last_error`.

## Rationale
Allows UIs and automation to react deterministically.

# ADR-012: Discovery Chain Snapshot
**Status:** Accepted  
**Date:** 2025-11-17

## Decision
After apply, write an `observed` snapshot including presence flags and `resource_id` or version for Defaults, Resolver, Router, and TGW; include a simple `health` (`ok|degraded|failed`).

## Rationale
One place to query “what is live now,” independent of desired docs.

# ADR-013: Multi‑Replica Topology
**Status:** Accepted  
**Date:** 2025-11-17

## Decision
Run stateless API replicas behind a VIP/Wide‑IP. Use per‑service locks for coordination; no global leader election needed.

## Acceptance Criteria
- Horizontal scaling without reconfiguration.

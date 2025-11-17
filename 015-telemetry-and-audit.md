# ADR-015: Telemetry and Audit
**Status:** Proposed  
**Date:** 2025-11-17

## Decision
Expose `/metrics` for Prometheus (apply timings, counters, error steps). Use structured logs with correlation IDs. KV desired/observed/status serve as durable audit trail.

## Acceptance Criteria
- Step timing histograms exist for render, upsert, verify, and snapshot.

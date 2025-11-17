# ADR-001: Transport and Framework (stdlib net/http + ServeMux)
**Status:** Accepted  
**Date:** 2025-11-17  
**Owner:** Platform Engineering

## Context
We need a small, low-dependency HTTP API that is easy to audit, runs anywhere (bare metal, VM, container), and avoids framework lock‑in. We also want predictable performance and straightforward ops (systemd, Docker/Podman, k8s).

## Problem
Popular frameworks (Gin, Echo, Chi) add dependencies, implicit behaviors, and upgrade risks. We prefer first‑principles control over routing, timeouts, and middleware to match our zero‑trust posture.

## Decision
Implement the API server using Go stdlib **net/http** with **ServeMux**. No third‑party HTTP framework.

## Rationale
- Minimal surface area and attack surface.
- Easier to reason about request lifecycles.
- No framework‑specific middleware or DSLs to learn or maintain.

## Consequences
**Positive**
- Small binary, fast cold start, fewer CVEs.
- Easy to profile/trace and enforce timeouts.
- Predictable behavior across Go versions.

**Negative**
- Less built‑in sugar (validation, middleware chains).
- More boilerplate for things like routing groups and context helpers.

## Operational Considerations
- Expose `/healthz` and `/readyz` endpoints.
- Use environment variables for settings (HTTP_ADDR, CONSUL_*).

## Security Considerations
- Avoid panics on bad input; explicit JSON decoding and size limits.
- Add request size cap (e.g., 1–2 MiB) to block oversized payloads.

## Acceptance Criteria
- Build produces a single static binary.
- Server exposes `GET /healthz` and `GET /readyz`.
- Concurrency safe, race‑free under `-race`.

## Rollback Plan
If stdlib proves too slow to iterate, migrate to `chi` while keeping handlers compatible.

## References
- Go net/http package docs

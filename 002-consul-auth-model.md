# ADR-002: Consul Auth Model (Scoped token, zero‑trust)
**Status:** Accepted  
**Date:** 2025-11-17

## Context
The API manipulates Consul KV, Sessions, and Config Entries. We must minimize blast radius.

## Problem
Using an admin token increases risk (accidental destructive changes, secret exfiltration).

## Decision
Run the API with a **scoped Consul ACL token** granting only:
- KV read/write under `svc-handler/*`
- Session create/renew/destroy
- Config Entries *set/get/delete* for: ServiceDefaults, ServiceResolver, ServiceRouter, TerminatingGateway

No secret materials (private keys) pass through the API.

## Rationale
Least privilege aligns with zero‑trust and auditability.

## Consequences
**Positive**
- Clear authorization boundaries and auditable writes.
- Simple to rotate and revoke.

**Negative**
- Extra work to mint and distribute scoped tokens per environment.

## Operational Considerations
- Token provided via `CONSUL_HTTP_TOKEN` environment variable.
- Prefer Vault to issue and rotate tokens.

## Security
- Deny `agent:*` and service registration APIs; we only touch config entries and KV.

## Acceptance Criteria
- All operations succeed with scoped token; fail with 403 when out of scope.

## Rollback
Temporarily widen token scope (time‑boxed) while investigating missing permissions.

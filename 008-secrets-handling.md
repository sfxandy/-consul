# ADR-008: Secrets Handling (secret references, TGW resolution)
**Status:** Accepted  
**Date:** 2025-11-17

## Context
TGW → upstream may require TLS or mTLS; we must not handle private keys in the API.

## Decision
Payload accepts **references** (e.g., `secrets://vault/...` or `secrets://kv/...`). Resolution occurs **on TGW hosts** (Vault Agent templates/SDS or consul‑template). The API only persists references.

## Security
- No private keys in API logs or KV values.
- TGW node identity must be least‑privilege for secret paths.

## Acceptance Criteria
- mTLS works end‑to‑end with secrets resolved outside the API.

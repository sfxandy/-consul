# ADR-009: Naming Policy (DNS label, no dots)
**Status:** Accepted  
**Date:** 2025-11-17

## Decision
Service names are restricted to lowercase letters, digits, and hyphens, up to 63 chars. Dots are disallowed. The path carries the canonical name. FQDNs remain in `routing.host` and `tls.sni`.

## Rationale
Avoids DNS ambiguities and conflicts with Consul naming.

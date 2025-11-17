# ADR-014: Protocol Awareness
**Status:** Accepted  
**Date:** 2025-11-17

## Decision
`connect.protocol` controls ServiceDefaults (`http` enables L7 features; `tcp` for L4 only). `routing` defines TGW egress including TLS and optional ALPN for HTTP2 or gRPC.

## Validation
- If protocol is `tcp`, router config must be absent.

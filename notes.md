a) Why this is a best-practice, reference role

Deterministic & idempotent: Token minting persists a registry on consul_api_host, enabling safe re-runs and tag-scoped execution without duplication.

Separation of concerns: Compose lives outside the role; the role renders only minimal, DRY HCL overlays (server/agent/ACL) and validates paths.

Podman-correct secrets: Secure overlay follows Podman-Compose rules (no target:/name: remaps); secret name == mounted filename under /run/secrets.

Safe bootstrap gating: Tokenless leader wait via /v1/status/leader; ACL state detected via GET /v1/acl/bootstrap (404 vs 405/403) before actions.

Principled auth: GMT discovered from multiple sources, stored as a host fact, injected via CONSUL_HTTP_TOKEN; sensitive data always no_log.

Right-sized delegation: run_once + delegate_to only for global ops; per-item includes delegate internally (no loop-on-block traps).

Environment portability: HTTP/TLS toggles via env to consul CLI; works identically in dev/UAT/prod.

Operator ergonomics: Clear tags (bootstrap, policies, mint_tokens, secrets, compose_up, set_tokens, verify) map to BAU workflows.

Minimal dependencies: Core Ansible + CLI; no Galaxy collections required.

Tooling integration: cplaneadm wrapper standardizes up/down/restart/status and respects secure overlay readiness.



















Generalisable patterns & techniques this role demonstrates

Idempotent “registry” pattern: Persist computed artefacts (e.g., tokens/IDs) to a small JSON/YAML file on a well-known host, then hydrate facts from it on future runs. Enables safe partial runs (--tags) without recomputing.

Tag-scoped pipelines: Break workflows into orthogonal tagged task files (bootstrap, policies, secrets, compose_up, verify) so operators can run only the slice they need while keeping the whole play idempotent.

run_once + delegate_to discipline: Execute “global” actions exactly once on a coordination host, while per-node actions are delegated deterministically. Avoids the classic loop-on-block and N× duplication pitfalls.

Safe secret handling: Never echo secrets into logs; use no_log: true, pass credentials via environment variables to CLIs (not on the command line or in files), and rely on runtime secret mounts rather than bind-mounting plain files.

Dual-overlay startup (feature-gated bring-up): Maintain a “base” configuration that always starts, and a “secure” overlay applied only when prerequisites exist (e.g., secrets). Detect readiness, then switch overlays. Prevents boot-order races.

Fact hydration from filesystem: Before relying on in-memory facts, attempt to load canonical state from disk (e.g., stat → slurp → set_fact with delegate_facts: true). Makes one-off tags and re-runs robust.

Probe endpoints, not CLIs: Use simple HTTP/JSON probes (or other narrow invariants) for readiness checks instead of parsing human-oriented CLI output. More stable and easier to assert with retries.

Template minimal overlays, not whole stacks: Keep large, shared configs outside the role; render only the small, environment/host-specific overlays via Jinja (paths, joins, feature toggles). Improves DRYness and manual operability.

Environment-driven execution: Feed tools via env vars (addresses, TLS, tokens) so the same tasks work across dev/UAT/prod without branching. Centralises differences in inventory/defaults, not task logic.

Assert early, fail loudly: Use assert with clear fail_msg for prerequisites (files, facts, tokens, secrets) before doing expensive operations. Faster feedback, easier triage.

Defensive path handling in helpers: In shell utilities, normalise paths (realpath -m), expand ~, accept absolute or relative inputs, and avoid double-prefixing. Make .env loaders strip quotes and ignore comments/whitespace.

Operational ergonomics via wrappers: Provide a tiny CLI wrapper (like cplaneadm) to standardise common actions (up/down/restart/status), encapsulate overlay logic, and reduce operator error—keeps Ansible focused on orchestration.

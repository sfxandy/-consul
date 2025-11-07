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

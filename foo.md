```bash

---
# Ensure the Global Management Token (GMT) is available for any tagged run.
# - Never stores secrets in VCS.
# - Reads from safe places (env/Vault/passwordstore/dev dump).
# - Publishes to hostvars[consul_api_host].consul_mgmt_token_eff and a global fallback.

# 0) Short-circuit if GMT already cached on consul_api_host
- name: GMT discovery | short-circuit if already present on consul_api_host
  when: hostvars[consul_api_host].consul_mgmt_token_eff is defined
  debug:
    msg: "GMT already present in hostvars[consul_api_host]"
  run_once: true
  tags: [always]

# 1) Optionally read a dev dump file on the consul_api_host
- name: GMT discovery | check for dev dump file on consul_api_host
  stat:
    path: "{{ consul_dump_gmt_path }}"
  register: _gmt_file
  run_once: true
  delegate_to: "{{ consul_api_host }}"
  tags: [always]

- name: GMT discovery | read dev dump file (if present)
  slurp:
    path: "{{ consul_dump_gmt_path }}"
  register: _gmt_slurp
  when: _gmt_file.stat.exists
  run_once: true
  delegate_to: "{{ consul_api_host }}"
  no_log: true
  tags: [always]

# 2) Build candidate list from safe sources (controller/env + optional dev dump)
- name: GMT discovery | collect candidate sources
  set_fact:
    _gmt_candidates:
      # already-published value on consul_api_host (if any)
      - "{{ (hostvars[consul_api_host].consul_mgmt_token_eff | default('')) }}"
      # explicit var (should be supplied securely, not in defaults file)
      - "{{ (consul_management_token | default('', true)) }}"
      # controller env var
      - "{{ (lookup('env', 'CONSUL_HTTP_TOKEN') | default('', true)) }}"
      # dev dump file content (if present)
      - "{{ (_gmt_slurp.content | b64decode | trim) if (_gmt_slurp is defined) else '' }}"
      # Uncomment exactly one of these if you use a secret backend:
      # - "{{ lookup('community.hashi_vault.hashi_vault',
      #              'secret=kv/data/consul_gmt field=gmt token=' ~ lookup('env','VAULT_TOKEN')) | default('', true) }}"
      # - "{{ lookup('passwordstore', 'consul/gmt') | default('', true) }}"
      # - "{{ lookup('file', playbook_dir ~ '/.secrets/consul_gmt.txt') | default('', true) }}"
  run_once: true
  no_log: true
  tags: [always]

# 3) Pick the first non-empty candidate; publish to consul_api_host and global fallback
- name: GMT discovery | publish effective GMT to consul_api_host
  set_fact:
    consul_mgmt_token_eff: "{{ (_gmt_candidates | select('length') | list | first) | default('') }}"
  run_once: true
  delegate_to: "{{ consul_api_host }}"
  delegate_facts: true
  no_log: true
  tags: [always]

- name: GMT discovery | publish global fallback
  set_fact:
    consul_mgmt_token_eff_global: "{{ hostvars[consul_api_host].consul_mgmt_token_eff | default('') }}"
  run_once: true
  no_log: true
  tags: [always]

# 4) Determine whether current run requires a GMT (so we can fail early on first run if needed)
- name: GMT discovery | compute whether GMT is required for this run
  set_fact:
    _gmt_required_tags: "{{ consul_gmt_required_tags }}"
    _run_tags: "{{ ansible_run_tags | default([]) }}"
    _needs_gmt: "{{ (_run_tags | intersect(_gmt_required_tags)) | length > 0 }}"
  run_once: true
  tags: [always]

# 5) Fail only if:
#    - GMT is required for requested tags,
#    - and it's missing,
#    - and 'bootstrap' is not also requested now.
- name: GMT discovery | fail if GMT required but not available (and bootstrap not requested)
  assert:
    that: consul_mgmt_token_eff_global | length > 0
    fail_msg: >
      Global Management Token not found. Requested tags that require GMT: {{ _run_tags | intersect(_gmt_required_tags) }}.
      Either:
        - run with "--tags bootstrap" first to create a GMT on a fresh cluster, or
        - provide it via a secure source (CONSUL_HTTP_TOKEN env, Vault/passwordstore/file),
        - or enable dev dump at {{ consul_dump_gmt_path }} on {{ consul_api_host }}.
  when:
    - _needs_gmt
    - "'bootstrap' not in _run_tags"
    - (consul_mgmt_token_eff_global | default('')) | length == 0
  run_once: true
  tags: [always]

```

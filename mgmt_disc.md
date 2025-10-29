```bash

---
# GMT discovery (clean, fixed)

# 0) Short-circuit if already present
- name: GMT | already cached on consul_api_host?
  when: hostvars[consul_api_host].consul_mgmt_token_eff is defined
  debug:
    msg: "GMT already present on consul_api_host"
  run_once: true
  tags: [always]

# 1) Check dump file; only slurp if exists
- name: GMT | check dev dump file
  stat:
    path: "{{ consul_dump_gmt_path }}"
  register: _gmt_file
  run_once: true
  delegate_to: "{{ consul_api_host }}"
  tags: [always]

- name: GMT | slurp dev dump (if present)
  slurp:
    path: "{{ consul_dump_gmt_path }}"
  register: _gmt_slurp
  when: _gmt_file.stat.exists | default(false)
  run_once: true
  delegate_to: "{{ consul_api_host }}"
  no_log: true
  tags: [always]

# 2) Derive safe dump value ('' if absent)
- name: GMT | derive safe dump value
  set_fact:
    _gmt_from_dump: >-
      {{
        (_gmt_file.stat.exists | default(false))
        | ternary((_gmt_slurp.content | default('') | b64decode | trim), '')
      }}
  run_once: true
  no_log: true
  tags: [always]

# 3) Build candidates
- name: GMT | collect candidates
  set_fact:
    _gmt_candidates:
      - "{{ hostvars[consul_api_host].consul_mgmt_token_eff | default('') }}"
      - "{{ consul_management_token | default('', true) }}"
      - "{{ lookup('env', 'CONSUL_HTTP_TOKEN') | default('', true) }}"
      - "{{ _gmt_from_dump }}"
      # Optional backends (uncomment one you use):
      # - "{{ lookup('community.hashi_vault.hashi_vault', 'secret=kv/data/consul_gmt field=gmt token=' ~ lookup('env','VAULT_TOKEN')) | default('', true) }}"
      # - "{{ lookup('passwordstore', 'consul/gmt') | default('', true) }}"
      # - "{{ lookup('file', playbook_dir ~ '/.secrets/consul_gmt.txt') | default('', true) }}"
  run_once: true
  no_log: true
  tags: [always]

# 4) Pick first non-empty candidate; publish to consul_api_host and global
- name: GMT | publish effective token to consul_api_host
  set_fact:
    consul_mgmt_token_eff: >-
      {{
        (_gmt_candidates
          | map('default','')
          | map('string')
          | map('trim')
          | reject('equalto','')
          | list
          | first) | default('')
      }}
  run_once: true
  delegate_to: "{{ consul_api_host }}"
  delegate_facts: true
  no_log: true
  tags: [always]

- name: GMT | publish global fallback
  set_fact:
    consul_mgmt_token_eff_global: "{{ hostvars[consul_api_host].consul_mgmt_token_eff | default('') }}"
  run_once: true
  no_log: true
  tags: [always]

# 5) Determine if GMT required for this run
- name: GMT | compute requirement for this run
  set_fact:
    _gmt_required_tags: "{{ consul_gmt_required_tags }}"
    _run_tags: "{{ ansible_run_tags | default([]) }}"
    _needs_gmt: "{{ (_run_tags | intersect(_gmt_required_tags)) | length > 0 }}"
  run_once: true
  tags: [always]

# 6) Fail only if required & missing & not bootstrapping now
- name: GMT | fail if required but missing (and bootstrap not requested)
  assert:
    that: consul_mgmt_token_eff_global | length > 0
    fail_msg: >
      Global Management Token not found. Requested tags that require it: {{ _run_tags | intersect(_gmt_required_tags) }}.
      Run with --tags bootstrap first, or provide via CONSUL_HTTP_TOKEN / Vault / passwordstore / dev dump at {{ consul_dump_gmt_path }} on {{ consul_api_host }}.
  when:
    - _needs_gmt
    - "'bootstrap' not in _run_tags"
    - (consul_mgmt_token_eff_global | default('')) | length == 0
  run_once: true
  tags: [always]

```

```bash

---
# Runs on every tagged invocation to ensure GMT is available (without storing in Git)

# Build CLI env (needed only if we probe Consul; cheap to compute)
- name: Compute CLI env for HTTPS if enabled
  set_fact:
    _cli_env: >-
      {{
        consul_api_use_https
        | ternary(
            {
              'CONSUL_HTTP_ADDR': 'https://127.0.0.1:' ~ consul_https_port|string,
              'CONSUL_CACERT': consul_tls_ca_path,
              'CONSUL_CLIENT_CERT': consul_tls_client_cert,
              'CONSUL_CLIENT_KEY': consul_tls_client_key
            },
            { 'CONSUL_HTTP_ADDR': 'http://127.0.0.1:8500' }
          )
      }}
  run_once: true
  delegate_to: "{{ consul_api_host }}"
  no_log: true
  tags: [always]

# 1) If we already cached it on consul_api_host, do nothing
- name: Short-circuit if GMT already cached on consul_api_host
  when: hostvars[consul_api_host].consul_mgmt_token_eff is defined
  debug:
    msg: "GMT already present in hostvars[consul_api_host]"
  run_once: true
  tags: [always]

# 2) Try dev dump file on consul_api_host
- name: Check GMT dump file (dev)
  stat:
    path: "{{ consul_dump_gmt_path }}"
  register: _gmt_file
  run_once: true
  delegate_to: "{{ consul_api_host }}"
  tags: [always]

- name: Read GMT dump file (dev)
  slurp:
    path: "{{ consul_dump_gmt_path }}"
  register: _gmt_slurp
  when: _gmt_file.stat.exists
  run_once: true
  delegate_to: "{{ consul_api_host }}"
  no_log: true
  tags: [always]

# 3) Build candidate list from safe sources (controller + dev dump)
- name: Collect GMT candidates
  set_fact:
    _gmt_candidates:
      - "{{ (hostvars[consul_api_host].consul_mgmt_token_eff | default('')) }}"
      - "{{ (consul_management_token | default('', true)) }}"
      - "{{ (lookup('env', 'CONSUL_HTTP_TOKEN') | default('', true)) }}"
      - "{{ (_gmt_slurp.content | b64decode | trim) if (_gmt_slurp is defined) else '' }}"
      # Uncomment a backend you actually use:
      # - "{{ lookup('community.hashi_vault.hashi_vault',
      #              'secret=kv/data/consul_gmt field=gmt token=' ~ lookup('env','VAULT_TOKEN')) | default('', true) }}"
      # - "{{ lookup('passwordstore', 'consul/gmt') | default('', true) }}"
      # - "{{ lookup('file', playbook_dir ~ '/.secrets/consul_gmt.txt') | default('', true) }}"
  run_once: true
  no_log: true
  tags: [always]

# 4) Pick first non-empty; publish to consul_api_host and global fallback
- name: Publish effective GMT
  set_fact:
    consul_mgmt_token_eff: "{{ (_gmt_candidates | select('length') | list | first) | default('') }}"
  run_once: true
  delegate_to: "{{ consul_api_host }}"
  delegate_facts: true
  no_log: true
  tags: [always]

- name: Publish global GMT fallback
  set_fact:
    consul_mgmt_token_eff_global: "{{ hostvars[consul_api_host].consul_mgmt_token_eff | default('') }}"
  run_once: true
  no_log: true
  tags: [always]

# 5) If still missing AND we're not running bootstrap, fail early with guidance
- name: Fail if GMT unavailable and bootstrap tag not requested
  assert:
    that: consul_mgmt_token_eff_global | length > 0
    fail_msg: >
      Global Management Token not found. Provide one via:
      - CONSUL_HTTP_TOKEN env, or
      - Vault/passwordstore/file lookup, or
      - dev dump at {{ consul_dump_gmt_path }} on {{ consul_api_host }}.
      (Or run with --tags bootstrap to create a new GMT on a fresh cluster.)
  when:
    - (consul_mgmt_token_eff_global | default('')) | length == 0
    - "'bootstrap' not in (ansible_run_tags | default([]))"
  run_once: true
  tags: [always]

```

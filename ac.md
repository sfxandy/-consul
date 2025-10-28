```

# ===== When ACLs are already bootstrapped (rc != 0), discover GMT safely =====
- name: Check for GMT dump file on consul_api_host (dev)
  stat:
    path: "{{ consul_dump_gmt_path }}"
  register: _gmt_file
  when: _boot.rc != 0
  run_once: true
  delegate_to: "{{ consul_api_host }}"

- name: Read GMT from dump file (dev)
  slurp:
    path: "{{ consul_dump_gmt_path }}"
  register: _gmt_slurp
  when:
    - _boot.rc != 0
    - _gmt_file.stat.exists
  run_once: true
  delegate_to: "{{ consul_api_host }}"
  no_log: true

- name: Collect possible management token sources
  when: _boot.rc != 0
  set_fact:
    _gmt_candidates:
      - "{{ (consul_management_token | default('', true)) }}"
      - "{{ (lookup('env', 'CONSUL_HTTP_TOKEN') | default('', true)) }}"
      - "{{ (_gmt_slurp.content | b64decode | trim) if (_gmt_slurp is defined) else '' }}"

- name: Pick first non-empty GMT candidate
  when: _boot.rc != 0
  set_fact:
    consul_mgmt_token_eff: "{{ (_gmt_candidates | select('length') | list | first) | default('') }}"
  no_log: true

- name: Ensure mgmt token available from a secure source
  when: _boot.rc != 0
  assert:
    that: consul_mgmt_token_eff | length > 0
    fail_msg: >
      Consul ACLs are already bootstrapped (409/rc!=0), but no management token was found.
      Provide one via: Vault/encrypted vars, CONSUL_HTTP_TOKEN env, or dev dump file at {{ consul_dump_gmt_path }} on {{ consul_api_host }}.

```

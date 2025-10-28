```bash

---
# Build CLI env (HTTPS if enabled; else HTTP loopback)
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

- name: Assert policy files are set
  assert:
    that:
      - consul_policy_server_file | length > 0
      - consul_policy_client_file | length > 0
    fail_msg: "Set consul_policy_server_file and consul_policy_client_file to policy HCL files on the controller."

- name: Read server policy file
  slurp:
    src: "{{ consul_policy_server_file }}"
  register: _srv_pol
  delegate_to: localhost

- name: Read client policy file
  slurp:
    src: "{{ consul_policy_client_file }}"
  register: _cli_pol
  delegate_to: localhost

- name: Upsert global server policy ({{ consul_policy_server_name }})
  command: >
    podman exec
    {% for k,v in _cli_env.items() %} -e {{ k }}={{ v }} {% endfor %}
    {{ consul_server_container }} sh -lc
    'cat >/tmp/pol_server.hcl <<''EOF''
    {{ (_srv_pol.content | b64decode) | trim }}
    EOF
    consul acl policy create -name {{ consul_policy_server_name | quote }} -rules @/tmp/pol_server.hcl -token {{ consul_mgmt_token_eff }}
    || consul acl policy update -name {{ consul_policy_server_name | quote }} -rules @/tmp/pol_server.hcl -token {{ consul_mgmt_token_eff }}'
  changed_when: true

- name: Upsert global client policy ({{ consul_policy_client_name }})
  command: >
    podman exec
    {% for k,v in _cli_env.items() %} -e {{ k }}={{ v }} {% endfor %}
    {{ consul_server_container }} sh -lc
    'cat >/tmp/pol_client.hcl <<''EOF''
    {{ (_cli_pol.content | b64decode) | trim }}
    EOF
    consul acl policy create -name {{ consul_policy_client_name | quote }} -rules @/tmp/pol_client.hcl -token {{ consul_mgmt_token_eff }}
    || consul acl policy update -name {{ consul_policy_client_name | quote }} -rules @/tmp/pol_client.hcl -token {{ consul_mgmt_token_eff }}'
  changed_when: true

```


```bash

---
# Build CLI env (reuse logic for completeness)
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

- set_fact: { consul_agent_tokens_map: {} }

- name: Create tokens for server/agent per host
  vars: { target_hosts: "{{ groups['consul_hosts'] }}" }
  loop: "{{ target_hosts }}"
  loop_control: { loop_var: tgt }
  block:
    - set_fact:
        _srv_node: "{{ hostvars[tgt].consul_server_node_name }}"
        _cli_node: "{{ hostvars[tgt].consul_client_node_name }}"

    - name: Create token (server node) → SecretID
      command: >
        podman exec
        {% for k,v in _cli_env.items() %} -e {{ k }}={{ v }} {% endfor %}
        {{ consul_server_container }}
        consul acl token create
        -description "Agent token for {{ _srv_node }}"
        -policy-name {{ consul_policy_server_name | quote }}
        -format=json
        -token {{ consul_mgmt_token_eff }}
      register: _t_srv
      changed_when: true

    - set_fact:
        consul_agent_tokens_map: "{{ consul_agent_tokens_map | combine({ _srv_node: (_t_srv.stdout | from_json).SecretID }) }}"

    - name: Create token (client node) → SecretID
      command: >
        podman exec
        {% for k,v in _cli_env.items() %} -e {{ k }}={{ v }} {% endfor %}
        {{ consul_server_container }}
        consul acl token create
        -description "Agent token for {{ _cli_node }}"
        -policy-name {{ consul_policy_client_name | quote }}
        -format=json
        -token {{ consul_mgmt_token_eff }}
      register: _t_cli
      changed_when: true

    - set_fact:
        consul_agent_tokens_map: "{{ consul_agent_tokens_map | combine({ _cli_node: (_t_cli.stdout | from_json).SecretID }) }}"

```

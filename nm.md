```
[Unit]
Description=HashiCorp Nomad (user instance)
Documentation=https://developer.hashicorp.com/nomad/docs
After=network-online.target
Wants=network-online.target

[Service]
# Use your own binary path or just `nomad` if it's in PATH
ExecStart=/usr/local/bin/nomad agent -config=%h/.config/nomad.d -%E{NOMAD_MODE}
Restart=on-failure
RestartSec=5s

# Environment control (default = server)
Environment=NOMAD_MODE=server

# Increase file descriptors for client workloads
LimitNOFILE=65536

# Optional sandboxed behaviour
ProtectSystem=strict
ProtectHome=no
NoNewPrivileges=true
PrivateTmp=true

# Log output
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
```




```
data_dir = "/home/%u/.local/share/nomad"
log_level = "INFO"
bind_addr = "0.0.0.0"


server {
  enabled          = true
  bootstrap_expect = 1
}


client {
  enabled = true
  servers = ["127.0.0.1:4647"]
}

```

```
server

# Nomad server configuration
server {
  enabled          = true
  bootstrap_expect = {{ nomad_bootstrap_expect | default(1) }}
  data_dir         = "{{ nomad_data_dir | default(ansible_user_dir ~ '/.local/share/nomad') }}/server"
  node_name        = "{{ inventory_hostname }}-server"

  # Optional: enable server telemetry and graceful leave
  raft_protocol    = 3
  leave_on_terminate = true
}

# Optional general networking
bind_addr = "0.0.0.0"

# Advertise address (optional)
advertise {
  http = "{{ hostvars[inventory_hostname]['ansible_default_ipv4']['address'] }}:4646"
  rpc  = "{{ hostvars[inventory_hostname]['ansible_default_ipv4']['address'] }}:4647"
  serf = "{{ hostvars[inventory_hostname]['ansible_default_ipv4']['address'] }}:4648"
}

# Logging
log_level = "{{ nomad_log_level | default('INFO') }}"


```

```
client

# Nomad client configuration
client {
  enabled = true
  servers = {{ nomad_server_addresses | default(['127.0.0.1:4647']) | to_json }}
  node_name = "{{ inventory_hostname }}-client"
  network_interface = "{{ nomad_network_interface | default('eth0') }}"
  data_dir = "{{ nomad_data_dir | default(ansible_user_dir ~ '/.local/share/nomad') }}/client"

  # Optional host volume mount
  host_volume "shared" {
    path      = "{{ nomad_host_volume_path | default(ansible_user_dir ~ '/nomad-volumes/shared') }}"
    read_only = false
  }

  # Optional: container runtime configs (for Podman, etc.)
  options {
    driver.raw_exec.enable = true
  }
}

bind_addr = "0.0.0.0"
log_level = "{{ nomad_log_level | default('INFO') }}"

```






```
# ==========================================================
#  Nomad global configuration
#  (shared by server and client agents)
# ==========================================================

# Directory where Nomad stores its state, logs, and data.
data_dir = "{{ nomad_data_dir | default(ansible_user_dir ~ '/.local/share/nomad') }}"

# Human-readable node name
node_name = "{{ inventory_hostname }}"

# Nomad API bind address
bind_addr = "{{ nomad_bind_addr | default('0.0.0.0') }}"

# Logging verbosity: "TRACE", "DEBUG", "INFO", "WARN", or "ERR"
log_level = "{{ nomad_log_level | default('INFO') }}"

# Optional: telemetry and metrics
telemetry {
  collection_interval = "10s"
  disable_hostname    = false
  prometheus_metrics  = true
}

# Optional: enable the built-in web UI
ui = {{ nomad_enable_ui | default(true) | lower }}

# Optional: ACLs (disabled by default)
acl {
  enabled = {{ nomad_enable_acl | default(false) | lower }}
}

# Optional: advertise addresses — overrides bind if needed
advertise {
  http = "{{ nomad_advertise_http | default(hostvars[inventory_hostname]['ansible_default_ipv4']['address'] ~ ':4646') }}"
  rpc  = "{{ nomad_advertise_rpc  | default(hostvars[inventory_hostname]['ansible_default_ipv4']['address'] ~ ':4647') }}"
  serf = "{{ nomad_advertise_serf | default(hostvars[inventory_hostname]['ansible_default_ipv4']['address'] ~ ':4648') }}"
}
```

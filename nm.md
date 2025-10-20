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

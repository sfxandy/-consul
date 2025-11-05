# Acceptance Criteria — Ansible Role: Deploy HashiCorp Nomad (root & non-root)

- *Scenario: Install Nomad as root with system service*
  - *GIVEN* the role is run with privilege escalation and a target `nomad_version`  
  - *WHEN* the play completes  
  - *THEN* the Nomad binary of the requested version is installed to a root-owned path (e.g., `/usr/local/bin/nomad`) with executable permissions, and a `systemd` service `nomad.service` is created, enabled, and started

- *Scenario: Install Nomad as a non-root user (user-mode service)*
  - *GIVEN* the role is run without privilege escalation and `nomad_run_as_user` is set to the current (non-root) account  
  - *WHEN* the play completes  
  - *THEN* the Nomad binary is installed to a user-writable path (e.g., `$HOME/.local/bin/nomad`), configuration lives under `$HOME/.config/nomad`, and a user-mode `systemd` unit (e.g., `~/.config/systemd/user/nomad.service`) is created, enabled (lingering if required), and started for that user

- *Scenario: Dedicated service account for root-managed installs*
  - *GIVEN* `nomad_service_user` and `nomad_service_group` are provided (default `nomad:nomad`)  
  - *WHEN* the role runs as root  
  - *THEN* the service account and group exist, are system accounts, and own Nomad config/data/log directories

- *Scenario: Idempotent re-run*
  - *GIVEN* Nomad of the requested version is already installed and configuration has not changed  
  - *WHEN* the role is re-run  
  - *THEN* no tasks report changes and the service is not restarted

- *Scenario: Version pinning & checksum verification*
  - *GIVEN* `nomad_version` and a matching SHA256 checksum source are provided  
  - *WHEN* binaries are downloaded and installed  
  - *THEN* the downloaded artifact is verified against the checksum and the task fails if verification does not match

- *Scenario: Server / client mode configuration*
  - *GIVEN* variables indicate `nomad_mode: server|client` and any mode-specific options  
  - *WHEN* templates are rendered  
  - *THEN* `nomad.hcl` and subordinate configs reflect the selected mode and validate via `nomad config validate`

- *Scenario: Configurable directories and permissions*
  - *GIVEN* directory variables for `config_dir`, `data_dir`, and `log_dir`  
  - *WHEN* the role runs  
  - *THEN* those directories are created if absent with correct ownership (service user) and 0750 or stricter permissions

- *Scenario: System service management (root)*
  - *GIVEN* `systemd` is available  
  - *WHEN* the role completes  
  - *THEN* `systemd` unit file contains configurable `ExecStart`, `Environment`, `LimitNOFILE`, `Restart`, and `User` directives, the daemon is reloaded on change, and the service is enabled and started

- *Scenario: User-mode service management (non-root)*
  - *GIVEN* the host supports `systemd --user`  
  - *WHEN* the role completes  
  - *THEN* a user service is created, `systemctl --user daemon-reload` is executed on change, and the service is enabled and started for that user (with lingering enabled if `nomad_enable_lingering: true`)

- *Scenario: TLS optional enablement*
  - *GIVEN* TLS inputs (CA, cert, key paths or content) are provided  
  - *WHEN* the role renders configuration  
  - *THEN* RPC/HTTP/Serf listeners are configured to use TLS, files are written with 0640 permissions to the service user, and the service restarts only if config changed

- *Scenario: Firewall/ports*
  - *GIVEN* firewall management is enabled via `nomad_manage_firewall: true`  
  - *WHEN* the role applies network rules  
  - *THEN* required Nomad ports for the selected mode are allowed (defaults: HTTP 4646, RPC 4647, Serf 4648 TCP/UDP), and rules are idempotent

- *Scenario: Platform matrix*
  - *GIVEN* supported platforms are defined (e.g., Ubuntu 20.04/22.04/24.04, RHEL/Rocky 8/9, Amazon Linux 2/2023)  
  - *WHEN* the role runs on a supported platform  
  - *THEN* facts are detected, the correct package dependencies are installed, and the run completes successfully

- *Scenario: Upgrade & downgrades*
  - *GIVEN* an existing Nomad installation and a different `nomad_version`  
  - *WHEN* the role runs  
  - *THEN* the binary is replaced atomically, a backup of the previous binary is retained (configurable), and the service is safely restarted

- *Scenario: Uninstall (optional)*
  - *GIVEN* `nomad_state: absent`  
  - *WHEN* the role runs  
  - *THEN* the service is stopped/disabled, binaries and unit files are removed, and (optionally) data directories are purged if `nomad_purge_data: true`

- *Scenario: Health checks after deploy*
  - *GIVEN* the service is started  
  - *WHEN* validation tasks execute  
  - *THEN* `nomad --version` returns the requested version, `nomad agent-self` (HTTP) responds with 200, and logs show no errors at warning-or-higher in the last 1 minute

- *Scenario: Secure defaults*
  - *GIVEN* no explicit network `bind_addr` is set  
  - *WHEN* the config is rendered  
  - *THEN* the agent binds to loopback for HTTP by default (or to configured interface), and `enable_syslog`/`log_level` are set to sensible defaults

- *Scenario: Variables and documentation*
  - *GIVEN* the role `README` examples and `defaults/main.yml` are provided  
  - *WHEN* a consumer inspects the role  
  - *THEN* all public variables are documented with descriptions and examples for both root and non-root usage

- *Scenario: Lint & CI*
  - *GIVEN* Ansible linting and molecule tests are configured  
  - *WHEN* CI runs against the role  
  - *THEN* linting passes and molecule verifies root and non-root scenarios with idempotency and convergence

- *Scenario: Logging & rotation*
  - *GIVEN* file logging is enabled  
  - *WHEN* the role completes  
  - *THEN* log files are created in `log_dir` and logrotate (or systemd-journald retention) is configured according to variables

- *Scenario: Failure transparency*
  - *GIVEN* a task fails (e.g., checksum mismatch, unsupported OS)  
  - *WHEN* the role aborts  
  - *THEN* the run fails with a clear message explaining the cause and remediation steps

```
Feature: Run Nomad as a non-root user via user-level systemd

  Background:
    Given a Linux host with systemd installed
    And a non-root OS user "nomadusr" with a home directory "/home/nomadusr"
    And loginctl lingering is allowed for "nomadusr"
    And the following directories exist and are owned by "nomadusr":
      | path                              |
      | /home/nomadusr/.config/nomad.d    |
      | /home/nomadusr/.local/var/nomad   |
      | /home/nomadusr/.local/bin         |

  Scenario: Nomad binary is present and executable for the user
    Given the Nomad version ">=1.7.0"
    When I check "/home/nomadusr/.local/bin/nomad"
    Then the file exists
    And it is executable by "nomadusr"
    And running "nomad version" as "nomadusr" returns the expected version

  Scenario: User-level systemd unit is installed
    Given the file "/home/nomadusr/.config/systemd/user/nomad.service"
    Then it defines "ExecStart=%h/.local/bin/nomad agent -config %h/.config/nomad.d"
    And it defines "Restart=on-failure"
    And it sets "Environment=NOMAD_DATA_DIR=%h/.local/var/nomad"

  Scenario: Lingering enabled so the user service survives logout and reboot
    Given I run "loginctl show-user nomadusr"
    Then "Linger=yes" is present

  Scenario: Service is enabled and started for the user
    When I run "systemctl --user enable --now nomad.service" as "nomadusr"
    Then "systemctl --user is-active nomad.service" is "active"
    And "systemctl --user is-enabled nomad.service" is "enabled"

  Scenario: Service starts automatically after host reboot
    Given the host is rebooted
    When I check "systemctl --user is-active nomad.service" as "nomadusr"
    Then it is "active"

  Scenario: Nomad listens on non-privileged ports
    When the service is running
    Then a process owned by "nomadusr" listens on TCP ports 4646, 4647, and 4648
    And no privileged (<1024) ports are bound

  Scenario: Config directory and data dir are writable by the user only
    Then "/home/nomadusr/.config/nomad.d" is 0700 and owned by "nomadusr"
    And "/home/nomadusr/.local/var/nomad" is 0700 and owned by "nomadusr"

  Scenario: Minimal valid Nomad configuration is in place
    Given a file "/home/nomadusr/.config/nomad.d/00-base.hcl"
    Then the file contains a valid HCL config with:
      | key                  | value                                 |
      | data_dir             | "/home/nomadusr/.local/var/nomad"     |
      | bind_addr            | "0.0.0.0"                             |
      | server.enabled       | true or false (per role variable)     |
      | client.enabled       | true or false (per role variable)     |
    And "nomad agent -config ..." validates without error

  Scenario: Logs are handled by journald under the user
    When I run "journalctl --user -u nomad -n 1" as "nomadusr"
    Then I see a recent log line from Nomad
    And no log files are written outside the user’s home

  Scenario: Health endpoint is reachable
    When I GET "http://127.0.0.1:4646/v1/status/leader"
    Then I receive 200 OK within 5 seconds

  Scenario: Restart on config changes
    Given I change a file in "/home/nomadusr/.config/nomad.d"
    When the user-level systemd path unit or role handler triggers
    Then "nomad.service" restarts
    And "systemctl --user show -p NRestarts nomad" increments by at least 1

  Scenario: No root privileges required at runtime
    When the service is running
    Then the Nomad PID has no effective root privileges
    And capabilities such as CAP_NET_BIND_SERVICE are not present

  Scenario: Firewall allows Nomad ports when enabled
    Given a host firewall is enabled
    Then inbound TCP 4646/4647/4648 are allowed as per role variables
```

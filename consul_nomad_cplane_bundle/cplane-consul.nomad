job "cplane-consul" {
  datacenters = ["lab1"]
  type        = "service"

  group "consul" {
    count = 3

    constraint {
      attribute = "${node.class}"
      value     = "cplane-control"
    }

    update {
      max_parallel     = 1
      min_healthy_time = "30s"
      healthy_deadline = "5m"
      auto_revert      = false
      canary           = 0
    }

    restart {
      attempts = 10
      interval = "10m"
      delay    = "30s"
      mode     = "delay"
    }

    network {
      port "http" { to = 8500 }
    }

    task "cplane-server" {
      driver = "raw_exec"

      config {
        command = "${NOMAD_TASK_DIR}/run-server.sh"
      }

      template {
        destination = "${NOMAD_TASK_DIR}/run-server.sh"
        perms       = "0755"

        data = <<-EOF
          #!/usr/bin/env bash
          set -euo pipefail

          ENVFILE="${HOME}/.env/cplaneadm.env"
          CPLANEADM="${HOME}/.bin/cplaneadm"

          if [[ -f "${ENVFILE}" ]]; then
            . "${ENVFILE}"
          fi

          export COMPOSE_PROFILES="server"
          exec "${CPLANEADM}" up
        EOF
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }

    task "cplane-http" {
      driver = "raw_exec"

      config {
        command = "/usr/local/bin/start-cplane-http.sh"
      }

      resources {
        cpu    = 200
        memory = 256
      }

      service {
        name = "consul-http"
        port = "http"

        check {
          name     = "http-alive"
          type     = "http"
          path     = "/v1/status/leader"
          interval = "5s"
          timeout  = "2s"
        }
      }
    }
  }
}

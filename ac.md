```
Feature: Schedule Consul control plane (Podman) with Nomad
  Nomad should reliably start, stop, and manage a 3-server Consul control plane on specific hosts.

  Background:
    GIVEN a Nomad cluster is available and reachable
    AND three client nodes exist named "Lab 1", "Lab 2", and "Lab 3"
    AND the Nomad "podman" task driver is enabled on all three nodes
    AND Podman is installed and runnable by the Nomad client user on all three nodes
    AND persistent data directories exist and are writable for Consul on each node
    AND network ports 8300, 8301, 8302 (TCP/UDP as needed), 8500 (HTTP), and 8600 (DNS TCP/UDP) are free
    AND gossip encryption key and TLS material (if enabled) are available to the job via Nomad templates or env
    AND a Nomad ACL token with submit permissions is available

  # ---------- Start / health ----------

  Scenario: START the Consul control plane and form a quorum
    GIVEN a Nomad job "consul-servers.nomad.hcl" defines three groups pinned to "Lab 1", "Lab 2", and "Lab 3"
    AND each group runs a task "consul-server" with driver "podman" and image "hashicorp/consul:stable"
    AND each task sets "server = true" and "bootstrap_expect = 3" with a persistent data dir
    AND each task exposes ports "8300", "8301", "8302", "8500", and "8600"
    WHEN I run "nomad job run consul-servers.nomad.hcl"
    THEN all three allocations should be "running" within 120 seconds
    AND a Consul leader should be elected
    AND an HTTP GET to "http://127.0.0.1:8500/v1/status/leader" on any server should return HTTP 200 with a non-empty leader address
    AND a DNS query to "127.0.0.1:8600" for "consul.service.consul" should return a valid response

  Scenario: START remains pinned to the specified hosts
    GIVEN placement constraints use "attr.unique.hostname" equal to "Lab 1", "Lab 2", and "Lab 3" per group
    WHEN the job is running
    THEN each allocation should be on its specified node and not on any other node

  Scenario: RESTART on failure for a single server
    GIVEN the job defines a restart stanza with at least 3 attempts and a delay
    AND the server container on "Lab 1" exits non-zero
    WHEN Nomad detects the failed allocation
    THEN Nomad should restart the container on "Lab 1"
    AND the Consul cluster should remain healthy (quorum maintained) during the restart

  # ---------- Stop / drain ----------

  Scenario: STOP the entire control plane cleanly
    GIVEN the job "consul-servers" is running
    WHEN I run "nomad job stop consul-servers"
    THEN all three allocations should transition to a terminal state within 120 seconds
    AND each server should perform "consul leave" (graceful leave) before container exit
    AND no Consul server processes should remain running on "Lab 1", "Lab 2", or "Lab 3"

  Scenario: DRAIN a single host stops only its server and preserves quorum
    GIVEN the job is running with three servers and "bootstrap_expect = 3"
    WHEN I enable drain mode on "Lab 2" with "force=false"
    THEN the allocation on "Lab 2" should stop gracefully
    AND the remaining two servers should continue to serve requests with a leader elected
    AND no new Consul server allocations should be scheduled on "Lab 2" while drain is active

  # ---------- Persistence / upgrades ----------

  Scenario: PERSISTENT data is reused after restart
    GIVEN the job mounts a persistent data directory for each server
    AND the control plane has already been initialized and then stopped
    WHEN I start the job again
    THEN each server should reuse its Raft data and rejoin the cluster without performing a fresh bootstrap

  Scenario: ROLLING UPGRADE with zero quorum loss
    GIVEN the job sets "update { max_parallel = 1, health_check = 'checks', min_healthy_time = '10s' }"
    AND the image tag is changed from "hashicorp/consul:1.x.y" to "hashicorp/consul:1.x.z"
    WHEN I run "nomad job run -check-index consul-servers.nomad.hcl"
    THEN exactly one server allocation should be updated at a time
    AND the cluster should retain quorum and a leader throughout the update
    AND the job should finish with all allocations "running" on "Lab 1", "Lab 2", and "Lab 3"

  # ---------- Observability ----------

  Scenario: HEALTH checks pass and surface in Nomad
    GIVEN the job defines service checks for HTTP :8500 "/v1/status/leader"
    WHEN the job is running
    THEN Nomad service checks should report "passing" for all three servers
    AND querying "http://127.0.0.1:8500/v1/agent/self" on any server should return HTTP 200

  Scenario: LOGS are accessible for troubleshooting
    GIVEN the job is running
    WHEN I run "nomad alloc logs -stderr <alloc-id>" for any server task
    THEN recent Consul server logs should be visible and include the server ID and leader/raft messages

```

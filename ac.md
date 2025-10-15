```
Feature: Schedule workloads on a specific host with Nomad
  Nomad should start and stop a binary and a Podman pod on a designated node.

  Background:
    GIVEN a Nomad cluster with at least one client node registered as "workhorse-01"
    AND the client node "workhorse-01" has node meta "target=true" and "hostname=workhorse-01"
    AND the Nomad ACL token with job submit privileges is available
    AND the "exec" and "podman" task drivers are enabled on "workhorse-01"
    AND Podman is installed and runnable by the Nomad client user on "workhorse-01"
    AND network ports required by the workloads are free on "workhorse-01"

  # ---------------------- Binary via exec/raw_exec ----------------------

  Scenario: Start a binary on the specific host
    GIVEN a Nomad job file "binary.nomad.hcl" with a task "hello-bin" using the "exec" driver
    AND the task command is "/home/nomadusr/bin/hello" with args "--port" "8081"
    AND the group has a constraint "node.meta.target == true"
    AND the group has a constraint "attr.unique.hostname == workhorse-01"
    WHEN I run "nomad job run binary.nomad.hcl"
    THEN the job "binary" should be in status "running" within 30 seconds
    AND the latest allocation should be placed on node "workhorse-01"
    AND a process named "hello" should be running on "workhorse-01"
    AND "curl http://127.0.0.1:8081/health" on "workhorse-01" should return HTTP 200

  Scenario: Stop the binary cleanly
    GIVEN the job "binary" is running on "workhorse-01"
    WHEN I run "nomad job stop binary"
    THEN the job "binary" should be in status "dead" within 30 seconds
    AND there should be no running process named "hello" on "workhorse-01"
    AND the last allocation status should be "complete" with exit code 0

  Scenario: Restart the binary and remain pinned to the host
    GIVEN the job "binary" is stopped
    WHEN I run "nomad job run binary.nomad.hcl"
    THEN the job "binary" should be in status "running"
    AND the allocation should be on node "workhorse-01" (not any other node)

  Scenario: Binary restarts on task failure
    GIVEN the job "binary" has a restart stanza "attempts = 3, mode = delay, interval = 30s"
    AND the process "hello" exits with a non-zero code
    WHEN Nomad detects the failed allocation
    THEN Nomad should restart the task within the configured interval
    AND the allocation status should become "running" again on "workhorse-01"

  Scenario: Constraint prevents scheduling on a non-target host
    GIVEN another client node "workhorse-02" is registered without node meta "target=true"
    WHEN I drain "workhorse-01"
    THEN the job "binary" should not start on "workhorse-02"
    AND the job should remain "pending" with a constraint evaluation message referencing "node.meta.target"

  # ---------------------- Podman pod ----------------------

  Scenario: Start a Podman pod on the specific host
    GIVEN a Nomad job file "pod.nomad.hcl" with a group "api" using the "podman" driver
    AND the task "api-pod" image is "docker.io/library/nginx:stable"
    AND the task maps port "http" to host port 8082
    AND the group has a constraint "attr.unique.hostname == workhorse-01"
    WHEN I run "nomad job run pod.nomad.hcl"
    THEN the job "pod" should be in status "running" within 60 seconds
    AND the allocation should be on node "workhorse-01"
    AND "curl http://127.0.0.1:8082" on "workhorse-01" should return HTTP 200

  Scenario: Stop the Podman pod cleanly
    GIVEN the job "pod" is running on "workhorse-01"
    WHEN I run "nomad job stop pod"
    THEN the job "pod" should be in status "dead" within 60 seconds
    AND no Podman container from the job "pod" should be running on "workhorse-01"
    AND the last allocation status should be "complete" with exit code 0

  Scenario: Podman pod restarts on container crash
    GIVEN the job "pod" has a restart stanza "attempts = 5, delay = 10s, mode = delay"
    AND the container process exits non-zero
    WHEN Nomad detects the failed allocation
    THEN Nomad should restart the container within the configured delay
    AND the allocation should return to "running" on "workhorse-01"

  Scenario: Podman image pulled only when absent
    GIVEN the job "pod" sets "force_pull = false" in the podman config
    AND the image "docker.io/library/nginx:stable" is already present on "workhorse-01"
    WHEN I run "nomad job run pod.nomad.hcl"
    THEN the allocation should start without pulling the image
    AND the task event stream should not contain a "pulled image" event

  Scenario: Rolling update of the Podman pod (count = 1)
    GIVEN the job "pod" has update stanza "max_parallel = 1, health_check = 'checks', min_healthy_time = '10s'"
    AND the group count is 1
    WHEN I change the image tag to "nginx:stable-perl" and run "nomad job run -check-index pod.nomad.hcl"
    THEN the old allocation should stop only after the new allocation is healthy on "workhorse-01"
    AND there should never be more than 1 running allocation during the update

  # ---------------------- Common assertions ----------------------

  Scenario: Health checks report passing for both jobs
    GIVEN the jobs "binary" and "pod" are running
    WHEN I query "http://127.0.0.1:4646/v1/jobs"
    THEN both jobs should have "Status":"running" and "Stable":true

  Scenario: Jobs survive Nomad client restart on the specific host
    GIVEN the jobs "binary" and "pod" are running on "workhorse-01"
    WHEN the Nomad client service on "workhorse-01" is restarted
    THEN allocations for both jobs should return to status "running" on "workhorse-01" within 60 seconds

  Scenario: Draining the host stops allocations gracefully
    GIVEN the jobs "binary" and "pod" are running on "workhorse-01"
    WHEN I enable drain mode on "workhorse-01" with "force=false"
    THEN existing allocations should stop gracefully within each task's kill_timeout
    AND no new allocations should be scheduled on "workhorse-01" while drain is active



You said:
now replace instances of "workhorse-01" with "Lab2 (alias)"


ChatGPT said:
Absolutely—here’s the same Gherkin with every occurrence of "workhorse-01" replaced by "Lab2 (alias)".

gherkin
Copy code
Feature: Schedule workloads on a specific host with Nomad
  Nomad should start and stop a binary and a Podman pod on a designated node.

  Background:
    GIVEN a Nomad cluster with at least one client node registered as "Lab2 (alias)"
    AND the client node "Lab2 (alias)" has node meta "target=true" and "hostname=Lab2 (alias)"
    AND the Nomad ACL token with job submit privileges is available
    AND the "exec" and "podman" task drivers are enabled on "Lab2 (alias)"
    AND Podman is installed and runnable by the Nomad client user on "Lab2 (alias)"
    AND network ports required by the workloads are free on "Lab2 (alias)"

  # ---------------------- Binary via exec/raw_exec ----------------------

  Scenario: Start a binary on the specific host
    GIVEN a Nomad job file "binary.nomad.hcl" with a task "hello-bin" using the "exec" driver
    AND the task command is "/home/nomadusr/bin/hello" with args "--port" "8081"
    AND the group has a constraint "node.meta.target == true"
    AND the group has a constraint "attr.unique.hostname == Lab2 (alias)"
    WHEN I run "nomad job run binary.nomad.hcl"
    THEN the job "binary" should be in status "running" within 30 seconds
    AND the latest allocation should be placed on node "Lab2 (alias)"
    AND a process named "hello" should be running on "Lab2 (alias)"
    AND "curl http://127.0.0.1:8081/health" on "Lab2 (alias)" should return HTTP 200

  Scenario: Stop the binary cleanly
    GIVEN the job "binary" is running on "Lab2 (alias)"
    WHEN I run "nomad job stop binary"
    THEN the job "binary" should be in status "dead" within 30 seconds
    AND there should be no running process named "hello" on "Lab2 (alias)"
    AND the last allocation status should be "complete" with exit code 0

  Scenario: Restart the binary and remain pinned to the host
    GIVEN the job "binary" is stopped
    WHEN I run "nomad job run binary.nomad.hcl"
    THEN the job "binary" should be in status "running"
    AND the allocation should be on node "Lab2 (alias)" (not any other node)

  Scenario: Binary restarts on task failure
    GIVEN the job "binary" has a restart stanza "attempts = 3, mode = delay, interval = 30s"
    AND the process "hello" exits with a non-zero code
    WHEN Nomad detects the failed allocation
    THEN Nomad should restart the task within the configured interval
    AND the allocation status should become "running" again on "Lab2 (alias)"

  Scenario: Constraint prevents scheduling on a non-target host
    GIVEN another client node "workhorse-02" is registered without node meta "target=true"
    WHEN I drain "Lab2 (alias)"
    THEN the job "binary" should not start on "workhorse-02"
    AND the job should remain "pending" with a constraint evaluation message referencing "node.meta.target"

  # ---------------------- Podman pod ----------------------

  Scenario: Start a Podman pod on the specific host
    GIVEN a Nomad job file "pod.nomad.hcl" with a group "api" using the "podman" driver
    AND the task "api-pod" image is "docker.io/library/nginx:stable"
    AND the task maps port "http" to host port 8082
    AND the group has a constraint "attr.unique.hostname == Lab2 (alias)"
    WHEN I run "nomad job run pod.nomad.hcl"
    THEN the job "pod" should be in status "running" within 60 seconds
    AND the allocation should be on node "Lab2 (alias)"
    AND "curl http://127.0.0.1:8082" on "Lab2 (alias)" should return HTTP 200

  Scenario: Stop the Podman pod cleanly
    GIVEN the job "pod" is running on "Lab2 (alias)"
    WHEN I run "nomad job stop pod"
    THEN the job "pod" should be in status "dead" within 60 seconds
    AND no Podman container from the job "pod" should be running on "Lab2 (alias)"
    AND the last allocation status should be "complete" with exit code 0

  Scenario: Podman pod restarts on container crash
    GIVEN the job "pod" has a restart stanza "attempts = 5, delay = 10s, mode = delay"
    AND the container process exits non-zero
    WHEN Nomad detects the failed allocation
    THEN Nomad should restart the container within the configured delay
    AND the allocation should return to "running" on "Lab2 (alias)"

  Scenario: Podman image pulled only when absent
    GIVEN the job "pod" sets "force_pull = false" in the podman config
    AND the image "docker.io/library/nginx:stable" is already present on "Lab2 (alias)"
    WHEN I run "nomad job run pod.nomad.hcl"
    THEN the allocation should start without pulling the image
    AND the task event stream should not contain a "pulled image" event

  Scenario: Rolling update of the Podman pod (count = 1)
    GIVEN the job "pod" has update stanza "max_parallel = 1, health_check = 'checks', min_healthy_time = '10s'"
    AND the group count is 1
    WHEN I change the image tag to "nginx:stable-perl" and run "nomad job run -check-index pod.nomad.hcl"
    THEN the old allocation should stop only after the new allocation is healthy on "Lab2 (alias)"
    AND there should never be more than 1 running allocation during the update

  # ---------------------- Common assertions ----------------------

  Scenario: Health checks report passing for both jobs
    GIVEN the jobs "binary" and "pod" are running
    WHEN I query "http://127.0.0.1:4646/v1/jobs"
    THEN both jobs should have "Status":"running" and "Stable":true

  Scenario: Jobs survive Nomad client restart on the specific host
    GIVEN the jobs "binary" and "pod" are running on "Lab2 (alias)"
    WHEN the Nomad client service on "Lab2 (alias)" is restarted
    THEN allocations for both jobs should return to status "running" on "Lab2 (alias)" within 60 seconds

  Scenario: Draining the host stops allocations gracefully
    GIVEN the jobs "binary" and "pod" are running on "Lab2 (alias)"
    WHEN I enable drain mode on "Lab2 (alias)" with "force=false"
    THEN existing allocations should stop gracefully within each task's kill_timeout
    AND no new allocations should be scheduled on "Lab2 (alias)" while drain is active
```

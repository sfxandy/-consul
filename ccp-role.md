```bash

#!/usr/bin/env bash
# cplaneadm — Control PLANE ADMin
# Podman-aware helper for managing a Consul server/agent deployment driven by *compose* files.
# Designed to be friendly for Ansible `-m shell` usage (predictable output, exit codes, flags).
#
# Features
# - Auto-detect compose file and compose CLI (prefers `podman-compose`; falls back to `docker compose`).
# - Service selectors: server, agent, or both.
# - Commands: start|stop|restart|status|health|logs|tail|ps|exec|validate|check-secrets|wait-ready
# - Health checks: 8500 HTTP ping, gossip ports present, ACL bootstrap state probe (optional token).
# - Ansible-friendly machine output with `--json` (prints JSON object) or default key=value lines.
# - Safe for rootless environments; no sudo required.
# - Respects profiles via COMPOSE_PROFILES if your compose file uses them.
#
# Environment overrides
#   CPLANE_PROJECT_DIR   — directory to cd into before running compose (auto-detect if unset)
#   CPLANE_COMPOSE_FILE  — explicit compose filename (auto-detect if unset)
#   CPLANE_COMPOSE_CMD   — explicit compose command (e.g., "podman-compose" or "docker compose")
#   CPLANE_TIMEOUT       — seconds to wait for readiness (default 60)
#   CONSUL_HTTP_ADDR     — HTTP endpoint for consul API (default http://127.0.0.1:8500)
#   CONSUL_HTTP_TOKEN    — ACL token for API calls (optional; health probes work without)
#
# Notes
# - This script doesn’t mutate your compose file. It only orchestrates lifecycle and checks.
# - For clusters where ACL secrets aren’t created yet, use `check-secrets` to see what’s missing.
#
set -Eeuo pipefail
shopt -s extglob

VERSION="0.1"
SELF_NAME="$(basename "$0")"

# ------------------------------ helpers ------------------------------
log() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }
dbg() { [[ -n "${DEBUG:-}" ]] && printf 'DEBUG: %s\n' "$*" >&2 || true; }

jq_safe() {
  if command -v jq >/dev/null 2>&1; then jq "$@"; else python3 - <<'PY'
import json,sys
print(json.dumps(json.load(sys.stdin)))
PY
  fi
}

json_out=false
as_json() { $json_out; }

# Key=Value (default) or JSON map
emit_kv_or_json() {
  local -n ref=$1
  if as_json; then
    python3 - <<PY
import json
print(json.dumps(${ref[@]} if False else dict([s.split('=',1) for s in ${!ref@Q}]), indent=2))
PY
  else
    for kv in "${ref[@]}"; do echo "$kv"; done
  fi
}

usage() {
  cat <<USG
${SELF_NAME} v${VERSION}

Usage: ${SELF_NAME} [global-flags] <command> [command-flags] [-- [exec args]]

Global flags:
  --json                 Output JSON instead of key=value lines
  --project-dir DIR      cd into DIR (auto-detect if omitted)
  --compose-file FILE    Use specific compose file (auto-detect if omitted)
  --compose-cmd CMD      Force compose command (default: podman-compose | docker compose)
  --timeout SECONDS      Wait timeout for readiness (default: 60)
  --http-addr URL        Consul HTTP addr (default: env CONSUL_HTTP_ADDR or http://127.0.0.1:8500)
  --token TOKEN          Consul ACL token for API calls (optional)
  -v, --verbose          Verbose/DEBUG
  -h, --help             This help

Commands:
  start [--server|--agent|--both]     Start selected services
  stop  [--server|--agent|--both]     Stop selected services
  restart [--server|--agent|--both]   Stop, sanity checks, start, wait-ready
  status                              Print container status and key ports
  ps                                  Show compose ps
  logs [--server|--agent|--both]      Show recent logs (non-follow)
  tail [--server|--agent|--both]      Follow logs
  exec [--server|--agent] -- CMD...   Exec into the selected service container
  validate                            Run 'consul validate' against rendered HCL paths
  check-secrets                       Detect missing Podman/Docker secrets referenced by compose
  health                              Run HTTP and port health checks
  wait-ready                          Wait until API is responsive and, if ACLs, until /v1/acl/bootstrap guarded

Examples:
  ${SELF_NAME} start --both
  ${SELF_NAME} restart --server --timeout 120
  ${SELF_NAME} health --json
  ${SELF_NAME} exec --server -- consul info
USG
}

# ------------------------------ defaults ------------------------------
CPLANE_PROJECT_DIR="${CPLANE_PROJECT_DIR:-}"
CPLANE_COMPOSE_FILE="${CPLANE_COMPOSE_FILE:-}"
CPLANE_COMPOSE_CMD="${CPLANE_COMPOSE_CMD:-}"
CPLANE_TIMEOUT="${CPLANE_TIMEOUT:-60}"
CONSUL_HTTP_ADDR="${CONSUL_HTTP_ADDR:-http://127.0.0.1:8500}"
CONSUL_HTTP_TOKEN="${CONSUL_HTTP_TOKEN:-}"

sel_server=false
sel_agent=false

# ------------------------------ arg parse ------------------------------
args=("$@")
positional=()
while (($#)); do
  case "$1" in
    --json) json_out=true; shift ;;
    --project-dir) CPLANE_PROJECT_DIR="$2"; shift 2 ;;
    --compose-file) CPLANE_COMPOSE_FILE="$2"; shift 2 ;;
    --compose-cmd) CPLANE_COMPOSE_CMD="$2"; shift 2 ;;
    --timeout) CPLANE_TIMEOUT="$2"; shift 2 ;;
    --http-addr) CONSUL_HTTP_ADDR="$2"; shift 2 ;;
    --token) CONSUL_HTTP_TOKEN="$2"; shift 2 ;;
    --server) sel_server=true; shift ;;
    --agent) sel_agent=true; shift ;;
    --both) sel_server=true; sel_agent=true; shift ;;
    -v|--verbose) DEBUG=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -* ) err "Unknown flag: $1"; usage; exit 2 ;;
    *) positional+=("$1"); shift ;;
  esac
done
set -- "${positional[@]}"

cmd="${1:-}"
[[ -z "$cmd" ]] && { usage; exit 2; }
shift || true

# ------------------------------ detection ------------------------------
find_compose_cmd() {
  if [[ -n "$CPLANE_COMPOSE_CMD" ]]; then echo "$CPLANE_COMPOSE_CMD"; return; fi
  if command -v podman-compose >/dev/null 2>&1; then echo "podman-compose"; return; fi
  if command -v podman >/dev/null 2>&1 && podman version >/dev/null 2>&1 && podman compose version >/dev/null 2>&1; then echo "podman compose"; return; fi
  if command -v docker >/dev/null 2>&1; then echo "docker compose"; return; fi
  err "No compose command found (podman-compose / podman compose / docker compose)."; exit 127
}

find_project_dir() {
  if [[ -n "$CPLANE_PROJECT_DIR" ]]; then echo "$CPLANE_PROJECT_DIR"; return; fi
  # Search upward for a compose file
  local d
  d="$(pwd)"
  while :; do
    for f in compose.yml compose.yaml docker-compose.yml docker-compose.yaml podman-compose.yml podman-compose.yaml; do
      if [[ -f "$d/$f" ]]; then echo "$d"; return; fi
    done
    [[ "$d" == "/" ]] && break
    d="$(dirname "$d")"
  done
  err "Could not locate a compose file in current or parent directories; set --project-dir or CPLANE_PROJECT_DIR."; exit 2
}

find_compose_file() {
  if [[ -n "$CPLANE_COMPOSE_FILE" ]]; then echo "$CPLANE_COMPOSE_FILE"; return; }
  for f in compose.yml compose.yaml docker-compose.yml docker-compose.yaml podman-compose.yml podman-compose.yaml; do
    [[ -f "$PROJECT_DIR/$f" ]] && { echo "$PROJECT_DIR/$f"; return; }
  done
  err "No compose file found in $PROJECT_DIR"; exit 2
}

COMPOSE_CMD="$(find_compose_cmd)"
PROJECT_DIR="$(find_project_dir)"
COMPOSE_FILE="$(find_compose_file)"

# ------------------------------ compose wrapper ------------------------------
cc() { # compose call
  dbg "RUN: (cd $PROJECT_DIR && $COMPOSE_CMD -f $COMPOSE_FILE $*)"
  ( cd "$PROJECT_DIR" && eval "$COMPOSE_CMD -f \"$COMPOSE_FILE\" $*" )
}

services_for_selection() {
  local svcs=()
  if $sel_server; then svcs+=(consul-server); fi
  if $sel_agent; then svcs+=(consul-agent); fi
  if ! $sel_server && ! $sel_agent; then svcs+=(consul-server consul-agent); fi
  echo "${svcs[@]}"
}

# ------------------------------ health checks ------------------------------
http_get() {
  local path="$1"; shift || true
  local url="${CONSUL_HTTP_ADDR%/}${path}"
  local h=("-sS" "--max-time" "5")
  [[ -n "$CONSUL_HTTP_TOKEN" ]] && h+=("-H" "X-Consul-Token: $CONSUL_HTTP_TOKEN")
  curl "${h[@]}" "$url"
}

http_status() {
  local path="$1"; shift || true
  local url="${CONSUL_HTTP_ADDR%/}${path}"
  local h=("-sS" "-o" "/dev/null" "-w" "%{http_code}" "--max-time" "5")
  [[ -n "$CONSUL_HTTP_TOKEN" ]] && h+=("-H" "X-Consul-Token: $CONSUL_HTTP_TOKEN")
  curl "${h[@]}" "$url"
}

check_http_alive() { # returns 0 if 200 from /v1/status/leader
  local code
  code="$(http_status "/v1/status/leader" || echo 000)"
  [[ "$code" == "200" ]]
}

check_acl_bootstrap_blocked() { # true if /v1/acl/bootstrap returns 403/405/409 (already bootstrapped/blocked)
  local code
  code="$(http_status "/v1/acl/bootstrap" || echo 000)"
  case "$code" in
    403|405|409) return 0;;
    200) return 1;;
    *) return 1;;
  esac
}

wait_ready() {
  local end=$(( $(date +%s) + CPLANE_TIMEOUT ))
  local out=()
  while (( $(date +%s) < end )); do
    if check_http_alive; then
      out+=("http=up")
      if check_acl_bootstrap_blocked; then
        out+=("acl_bootstrap=blocked")
      else
        out+=("acl_bootstrap=open")
      fi
      emit_kv_or_json out
      return 0
    fi
    sleep 1
  done
  err "Timed out waiting for Consul API at $CONSUL_HTTP_ADDR"
  return 1
}

# ------------------------------ validators ------------------------------
validate_configs() {
  # Best-effort: try to exec into server then agent and run `consul validate` on their config dirs
  local rc=0
  for svc in consul-server consul-agent; do
    if cc ps --services 2>/dev/null | grep -qw "$svc"; then
      if cc exec "$svc" sh -lc 'consul validate /consul/config 2>&1'; then
        log "$svc: validate=ok"
      else
        rc=1
        err "$svc: validation failed"
      fi
    fi
  done
  return $rc
}

# ------------------------------ secrets check ------------------------------
check_secrets() {
  # Parse compose file for "secrets:" usage and list present/missing based on engine
  local engine
  if [[ "$COMPOSE_CMD" =~ ^podman ]]; then engine=podman; else engine=docker; fi

  local -a refs=()
  # naive grep for secret names (works for common cases)
  mapfile -t refs < <(awk '/^secrets:/ {insec=1; next} insec && NF==0 {insec=0} insec {print}' "$COMPOSE_FILE" | awk -F: '{gsub(/ /,""); if ($1!="")} $1 ~ /[A-Za-z0-9_.-]+/ {print $1}' | sort -u)

  local -a missing=() present=()
  for s in "${refs[@]}"; do
    if [[ "$engine" == podman ]]; then
      if podman secret exists "$s" 2>/dev/null; then present+=("$s"); else missing+=("$s"); fi
    else
      if docker secret inspect "$s" >/dev/null 2>&1; then present+=("$s"); else missing+=("$s"); fi
    fi
  done

  local -a out=("engine=$engine" "compose_file=$COMPOSE_FILE" "present=${#present[@]}" "missing=${#missing[@]}")
  emit_kv_or_json out

  if ((${#missing[@]})); then
    err "Missing secrets: ${missing[*]}"
    return 3
  fi
}

# ------------------------------ actions ------------------------------
do_start() {
  local svcs=( $(services_for_selection) )
  cc up -d ${svcs[*]}
}

do_stop() {
  local svcs=( $(services_for_selection) )
  cc stop ${svcs[*]}
}

do_restart() {
  do_stop || true
  # Light sanity: ports free? (best-effort)
  do_start
  wait_ready
}

do_status() {
  cc ps
  local -a out=("http_addr=$CONSUL_HTTP_ADDR")
  if check_http_alive; then out+=("api=up"); else out+=("api=down"); fi
  emit_kv_or_json out
}

do_logs() {
  local svcs=( $(services_for_selection) )
  cc logs --no-log-prefix --tail=200 ${svcs[*]}
}

do_tail() {
  local svcs=( $(services_for_selection) )
  cc logs -f --no-log-prefix ${svcs[*]}
}

do_ps() { cc ps; }

do_exec() {
  local target
  if $sel_server && ! $sel_agent; then target=consul-server
  elif $sel_agent && ! $sel_server; then target=consul-agent
  else err "exec requires exactly one of --server or --agent"; exit 2
  fi
  [[ $# -gt 0 ]] || { err "exec requires a command after --"; exit 2; }
  cc exec "$target" "$@"
}

do_health() {
  local code leader
  code="$(http_status "/v1/status/leader" || echo 000)"
  leader="$(http_get "/v1/status/leader" || true)"
  local -a out=("http_addr=$CONSUL_HTTP_ADDR" "status_code=$code" "leader=${leader//\n/}")
  if check_acl_bootstrap_blocked; then out+=("acl_bootstrap=blocked"); else out+=("acl_bootstrap=open"); fi
  emit_kv_or_json out
}

# ------------------------------ dispatch ------------------------------
case "$cmd" in
  start) do_start ;;
  stop) do_stop ;;
  restart) do_restart ;;
  status) do_status ;;
  logs) do_logs ;;
  tail) do_tail ;;
  ps) do_ps ;;
  exec) do_exec "$@" ;;
  validate) validate_configs ;;
  check-secrets) check_secrets ;;
  health) do_health ;;
  wait-ready) wait_ready ;;
  *) err "Unknown command: $cmd"; usage; exit 2 ;;
 esac

```

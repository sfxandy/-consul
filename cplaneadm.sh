#!/usr/bin/env bash
# cplaneadm — helper for podman-compose “control plane” stacks
# - Defaults come from ~/.env/cplaneadm.env (optional)
# - Supports base + secure overlays, profiles, per-host overrides
# - Green/red status, safe path expansion, no early exits in env loader

set -Eeuo pipefail

# ---------- Defaults (overridable via env file) ----------
: "${CPLANEADM_ENV:=${HOME}/.env/cplaneadm.env}"
: "${COMPOSE_BASE:=docker-compose.yml}"
: "${COMPOSE_SECURE:=docker-compose.secure.yml}"     # optional overlay
: "${COMPOSE_DIR:=${PWD}}"
: "${COMPOSE_PROFILES:=}"                             # e.g. "bootstrap,secure"
: "${SERVER_SVC:=consul-server}"
: "${AGENT_SVC:=consul-agent}"
: "${SERVER_CONT:=consul-server}"
: "${AGENT_CONT:=consul-agent}"
: "${SECURE_REQUIRED:=false}"                         # if true, fail if overlay missing
: "${NO_COLOR:=false}"

# ---------- UI ----------
if [[ "${NO_COLOR}" == "true" ]]; then
  RED="" GREEN="" YELLOW="" DIM="" BOLD="" NC=""
else
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
  DIM=$'\033[2m'; BOLD=$'\033[1m'; NC=$'\033[0m'
fi

die() { echo -e "${RED}error:${NC} $*" >&2; exit 1; }
note(){ echo -e "${DIM}$*${NC}"; }
ok()  { echo -e "${GREEN}$*${NC}"; }
warn(){ echo -e "${YELLOW}$*${NC}"; }

# ---------- Helpers ----------
expand_path() {
  # realpath -m handles non-existing paths; expand leading ~
  local p="$1"
  [[ "$p" == "~" || "$p" == ~/* ]] && p="${p/#\~/$HOME}"
  realpath -m -- "$p"
}

have() { command -v "$1" >/dev/null 2>&1; }

pcmd() { # run podman-compose with proper -f args, chdir into COMPOSE_DIR
  local -a fargs=()
  [[ -n "${_COMPOSE_BASE:-}" ]]   && fargs+=(-f "${_COMPOSE_BASE}")
  [[ -n "${_COMPOSE_SECURE:-}" ]] && fargs+=(-f "${_COMPOSE_SECURE}")
  ( cd "${COMPOSE_DIR}" && COMPOSE_PROFILES="${COMPOSE_PROFILES}" podman-compose "${fargs[@]}" "$@" )
}

pexec() { # podman exec wrapper
  podman exec "$@"
}

curl_in() { # curl inside container (no token required) for simple probes
  local cont="$1"; shift
  pexec "${cont}" sh -lc "curl -fsS $*"
}

# ---------- Env loader (no early return that aborts script) ----------
load_envfile() {
  local f
  f="$(expand_path "${CPLANEADM_ENV}")"
  if [[ -f "$f" ]]; then
    # shellcheck disable=SC2163
    while IFS= read -r line; do
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
      if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
        # export KEY=VALUE (no eval)
        local k="${line%%=*}" v="${line#*=}"
        export "$k=$v"
      fi
    done <"$f"
    ok "loaded env: $f"
  else
    note "no env file at ${f} (proceeding with defaults)"
  fi
}

# ---------- Compose resolution ----------
resolve_compose() {
  COMPOSE_DIR="$(expand_path "${COMPOSE_DIR}")"
  _COMPOSE_BASE="$(expand_path "${COMPOSE_DIR}/${COMPOSE_BASE}")"
  _COMPOSE_SECURE=""
  [[ -f "${COMPOSE_DIR}/${COMPOSE_SECURE}" ]] && _COMPOSE_SECURE="$(expand_path "${COMPOSE_DIR}/${COMPOSE_SECURE}")"

  [[ -f "${_COMPOSE_BASE}" ]] || die "base compose not found: ${_COMPOSE_BASE}"
  if [[ -n "${_COMPOSE_SECURE}" ]]; then
    note "secure overlay detected: ${_COMPOSE_SECURE}"
  else
    if [[ "${SECURE_REQUIRED}" == "true" ]]; then
      die "secure overlay required but not found: ${COMPOSE_DIR}/${COMPOSE_SECURE}"
    else
      note "no secure overlay present (this is fine for initial bring-up)"
    fi
  fi
}

# ---------- Commands ----------
usage() {
  cat <<EOF
${BOLD}cplaneadm${NC} — control-plane wrapper for podman-compose

Usage: cplaneadm <cmd> [args]
  up [--base-only]              Bring up services (consul-server, consul-agent)
  down                          Stop/remove services
  restart                       Restart both services
  status                        Quick green/red status
  ps                            podman-compose ps
  logs [server|agent|all]       Tail logs
  exec <server|agent> -- CMD    Exec into container and run CMD
  config                        Render combined compose config (for debug)
  env                           Show effective env + compose files

Env (via ${CPLANEADM_ENV}):
  COMPOSE_DIR, COMPOSE_BASE, COMPOSE_SECURE, COMPOSE_PROFILES
  SERVER_SVC, AGENT_SVC, SERVER_CONT, AGENT_CONT, SECURE_REQUIRED

EOF
}

cmd_env() {
  echo "CPLANEADM_ENV=${CPLANEADM_ENV}"
  echo "COMPOSE_DIR=${COMPOSE_DIR}"
  echo "COMPOSE_BASE=${COMPOSE_BASE}"
  echo "COMPOSE_SECURE=${COMPOSE_SECURE}"
  echo "COMPOSE_PROFILES=${COMPOSE_PROFILES}"
  echo "SECURE_REQUIRED=${SECURE_REQUIRED}"
  echo "_COMPOSE_BASE=${_COMPOSE_BASE}"
  echo "_COMPOSE_SECURE=${_COMPOSE_SECURE}"
}

cmd_up() {
  local base_only="false"
  [[ "${1:-}" == "--base-only" ]] && base_only="true"
  if [[ "$base_only" == "true" || -z "${_COMPOSE_SECURE}" ]]; then
    ok "bringing up (base only)"
    pcmd up -d "${SERVER_SVC}" "${AGENT_SVC}"
  else
    ok "bringing up (base + secure)"
    pcmd up -d "${SERVER_SVC}" "${AGENT_SVC}"
  fi
}

cmd_down() {
  pcmd down
}

cmd_restart() {
  pcmd stop "${SERVER_SVC}" "${AGENT_SVC}" || true
  pcmd up -d "${SERVER_SVC}" "${AGENT_SVC}"
}

cmd_ps() {
  pcmd ps
}

cmd_logs() {
  local which="${1:-all}"
  case "$which" in
    server) pcmd logs -f "${SERVER_SVC}" ;;
    agent)  pcmd logs -f "${AGENT_SVC}" ;;
    all|*)  pcmd logs -f "${SERVER_SVC}" "${AGENT_SVC}" ;;
  esac
}

cmd_exec() {
  [[ $# -lt 2 ]] && die "exec needs target (server|agent) and CMD"
  local target="$1"; shift
  local cont
  case "$target" in
    server) cont="${SERVER_CONT}" ;;
    agent)  cont="${AGENT_CONT}" ;;
    *) die "unknown target: $target" ;;
  esac
  pexec -it "${cont}" "$@"
}

cmd_config() {
  pcmd config
}

cmd_status() {
  local ok_server=0 ok_agent=0
  if curl_in "${SERVER_CONT}" "http://127.0.0.1:8500/v1/status/leader" >/dev/null 2>&1; then
    ok_server=1
  fi
  if curl_in "${AGENT_CONT}"  "http://127.0.0.1:8500/v1/status/leader" >/dev/null 2>&1; then
    ok_agent=1
  fi

  if (( ok_server==1 )); then ok "server: healthy (leader endpoint responsive)"; else echo -e "${RED}server: unhealthy${NC}"; fi
  if (( ok_agent==1 ));  then ok "agent : healthy (leader endpoint responsive)"; else echo -e "${RED}agent : unhealthy${NC}"; fi

  note "profiles: ${COMPOSE_PROFILES:-<none>} | compose: ${_COMPOSE_BASE}${_COMPOSE_SECURE:+ + ${_COMPOSE_SECURE}}"
}

# ---------- Main ----------
main() {
  have podman-compose || die "podman-compose not found in PATH"
  have podman || die "podman not found in PATH"

  load_envfile
  resolve_compose

  local cmd="${1:-}"; shift || true
  case "$cmd" in
    up)        cmd_up "$@";;
    down)      cmd_down;;
    restart)   cmd_restart;;
    status)    cmd_status;;
    ps)        cmd_ps;;
    logs)      cmd_logs "$@";;
    exec)      cmd_exec "$@";;
    config)    cmd_config;;
    env)       cmd_env;;
    ""|help|-h|--help) usage;;
    *) die "unknown command: $cmd";;
  esac
}

main "$@"

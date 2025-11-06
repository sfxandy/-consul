#!/usr/bin/env bash
# cplaneadm — helper for podman-compose “control plane” stacks
# - Reads defaults from ~/.env/cplaneadm.env (overrides below)
# - Supports base + secure overlays
# - Manage server | agent | both
# - Safe path expansion, pretty status, no early exits

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
die(){ echo -e "${RED}error:${NC} $*" >&2; exit 1; }
note(){ echo -e "${DIM}$*${NC}"; }
ok(){ echo -e "${GREEN}$*${NC}"; }

# ---------- Helpers ----------
expand_path(){ local p="$1"; [[ "$p" == "~" || "$p" == ~/* ]] && p="${p/#\~/$HOME}"; realpath -m -- "$p"; }
have(){ command -v "$1" >/dev/null 2>&1; }
pcmd(){ # run podman-compose with -f args, cd into COMPOSE_DIR
  local -a fargs=()
  [[ -n "${_COMPOSE_BASE:-}" ]]   && fargs+=(-f "${_COMPOSE_BASE}")
  [[ -n "${_COMPOSE_SECURE:-}" ]] && fargs+=(-f "${_COMPOSE_SECURE}")
  ( cd "${COMPOSE_DIR}" && COMPOSE_PROFILES="${COMPOSE_PROFILES}" podman-compose "${fargs[@]}" "$@" )
}
pexec(){ podman exec "$@"; }
curl_in(){ local c="$1"; shift; pexec "$c" sh -lc "curl -fsS $*"; }

# ---------- Env loader (no early exit) ----------
load_envfile(){
  local f; f="$(expand_path "${CPLANEADM_ENV}")"
  if [[ -f "$f" ]]; then
    # shellcheck disable=SC2163
    while IFS= read -r line; do
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
      if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
        local k="${line%%=*}" v="${line#*=}"; export "$k=$v"
      fi
    done <"$f"
    ok "loaded env: $f"
  else
    note "no env file at ${f} (defaults in use)"
  fi
}

# ---------- Compose resolution ----------
resolve_compose(){
  COMPOSE_DIR="$(expand_path "${COMPOSE_DIR}")"
  _COMPOSE_BASE="$(expand_path "${COMPOSE_DIR}/${COMPOSE_BASE}")"
  _COMPOSE_SECURE=""
  [[ -f "${COMPOSE_DIR}/${COMPOSE_SECURE}" ]] && _COMPOSE_SECURE="$(expand_path "${COMPOSE_DIR}/${COMPOSE_SECURE}")"
  [[ -f "${_COMPOSE_BASE}" ]] || die "base compose not found: ${_COMPOSE_BASE}"
  if [[ -n "${_COMPOSE_SECURE}" ]]; then
    note "secure overlay detected: ${_COMPOSE_SECURE}"
  else
    [[ "${SECURE_REQUIRED}" == "true" ]] && die "secure overlay required but not found: ${COMPOSE_DIR}/${COMPOSE_SECURE}" || note "no secure overlay present (ok for initial bring-up)"
  fi
}

# ---------- Targets: server|agent|both ----------
resolve_targets(){
  local t="${1:-both}"
  case "$t" in
    server) TARGET_SERVICES=("${SERVER_SVC}"); TARGET_CONTAINERS=("${SERVER_CONT}");;
    agent)  TARGET_SERVICES=("${AGENT_SVC}");  TARGET_CONTAINERS=("${AGENT_CONT}");;
    both|"") TARGET_SERVICES=("${SERVER_SVC}" "${AGENT_SVC}"); TARGET_CONTAINERS=("${SERVER_CONT}" "${AGENT_CONT}");;
    *) die "unknown target: $t (use server|agent|both)";;
  esac
}

# ---------- Commands ----------
usage(){
  cat <<EOF
${BOLD}cplaneadm${NC} — podman-compose wrapper

Usage:
  cplaneadm up [server|agent|both] [--base-only]
  cplaneadm down [server|agent|both]
  cplaneadm restart [server|agent|both]
  cplaneadm status [server|agent|both]
  cplaneadm ps
  cplaneadm logs [server|agent|all]
  cplaneadm exec <server|agent> -- CMD
  cplaneadm config
  cplaneadm env
EOF
}

cmd_env(){
  cat <<EOF
CPLANEADM_ENV=${CPLANEADM_ENV}
COMPOSE_DIR=${COMPOSE_DIR}
COMPOSE_BASE=${COMPOSE_BASE}
COMPOSE_SECURE=${COMPOSE_SECURE}
COMPOSE_PROFILES=${COMPOSE_PROFILES}
SECURE_REQUIRED=${SECURE_REQUIRED}
_COMPOSE_BASE=${_COMPOSE_BASE}
_COMPOSE_SECURE=${_COMPOSE_SECURE}
SERVER_SVC=${SERVER_SVC}  AGENT_SVC=${AGENT_SVC}
SERVER_CONT=${SERVER_CONT}  AGENT_CONT=${AGENT_CONT}
EOF
}

cmd_up(){
  local target="${1:-both}"; shift || true
  local base_only="false"; [[ "${1:-}" == "--base-only" ]] && base_only="true"
  resolve_targets "$target"
  if [[ "$base_only" == "true" || -z "${_COMPOSE_SECURE}" ]]; then
    ok "up (base only) → ${TARGET_SERVICES[*]}"
    pcmd up -d "${TARGET_SERVICES[@]}"
  else
    ok "up (base + secure) → ${TARGET_SERVICES[*]}"
    pcmd up -d "${TARGET_SERVICES[@]}"
  fi
}

cmd_down(){
  local target="${1:-both}"; resolve_targets "$target"
  ok "down → ${TARGET_SERVICES[*]}"
  pcmd down --remove-orphans || true
}

cmd_restart(){
  local target="${1:-both}"; resolve_targets "$target"
  ok "restart → ${TARGET_SERVICES[*]}"
  pcmd stop "${TARGET_SERVICES[@]}" || true
  pcmd up -d "${TARGET_SERVICES[@]}"
}

cmd_ps(){ pcmd ps; }

cmd_logs(){
  local which="${1:-all}"
  case "$which" in
    server) pcmd logs -f "${SERVER_SVC}" ;;
    agent)  pcmd logs -f "${AGENT_SVC}" ;;
    all|*)  pcmd logs -f "${SERVER_SVC}" "${AGENT_SVC}" ;;
  esac
}

cmd_exec(){
  [[ $# -lt 2 ]] && die "exec needs target (server|agent) and CMD"
  local target="$1"; shift
  local cont; case "$target" in
    server) cont="${SERVER_CONT}" ;;
    agent)  cont="${AGENT_CONT}" ;;
    *) die "unknown target: $target" ;;
  esac
  pexec -it "${cont}" "$@"
}

cmd_config(){ pcmd config; }

cmd_status(){
  local target="${1:-both}"; resolve_targets "$target"
  for cont in "${TARGET_CONTAINERS[@]}"; do
    if curl_in "${cont}" "http://127.0.0.1:8500/v1/status/leader" >/dev/null 2>&1; then
      ok "${cont}: healthy (leader endpoint responsive)"
    else
      echo -e "${RED}${cont}: unhealthy${NC}"
    fi
  done
  note "profiles: ${COMPOSE_PROFILES:-<none>} | compose: ${_COMPOSE_BASE}${_COMPOSE_SECURE:+ + ${_COMPOSE_SECURE}}"
}

# ---------- Main ----------
main(){
  have podman-compose || die "podman-compose not found in PATH"
  have podman || die "podman not found in PATH"

  load_envfile
  resolve_compose

  local cmd="${1:-}"; shift || true
  case "$cmd" in
    up)        cmd_up "$@";;
    down)      cmd_down "$@";;
    restart)   cmd_restart "$@";;
    status)    cmd_status "$@";;
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

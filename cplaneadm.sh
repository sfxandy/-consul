#!/usr/bin/env bash
set -Eeuo pipefail

: "${CPLANEADM_ENV:=${HOME}/.env/cplaneadm.env}"
: "${COMPOSE_BASE:=docker-compose.yml}"
: "${COMPOSE_SECURE:=docker-compose.secure.yml}"
: "${COMPOSE_DIR:=${PWD}}"
: "${COMPOSE_PROFILES:=}"
: "${SERVER_SVC:=consul-server}"
: "${AGENT_SVC:=consul-agent}"
: "${SERVER_CONT:=consul-server}"
: "${AGENT_CONT:=consul-agent}"
: "${SECURE_REQUIRED:=false}"
: "${NO_COLOR:=false}"

if [[ "${NO_COLOR}" == "true" ]]; then RED="" GREEN="" YELLOW="" DIM="" BOLD="" NC=""
else RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; DIM=$'\033[2m'; BOLD=$'\033[1m'; NC=$'\033[0m'; fi
die(){ echo -e "${RED}error:${NC} $*" >&2; exit 1; }
note(){ echo -e "${DIM}$*${NC}"; }
ok(){ echo -e "${GREEN}$*${NC}"; }

expand_path(){ local p="$1"; [[ "$p" == "~" || "$p" == ~/* ]] && p="${p/#\~/$HOME}"; realpath -m -- "$p"; }
have(){ command -v "$1" >/dev/null 2>&1; }

pcmd(){ local -a fargs=(); [[ -n "${_COMPOSE_BASE:-}" ]] && fargs+=(-f "${_COMPOSE_BASE}"); [[ -n "${_COMPOSE_SECURE:-}" ]] && fargs+=(-f "${_COMPOSE_SECURE}"); ( cd "${COMPOSE_DIR}" && COMPOSE_PROFILES="${COMPOSE_PROFILES}" podman-compose "${fargs[@]}" "$@" ); }
pexec(){ podman exec "$@"; }
curl_in(){ local cont="$1"; shift; pexec "${cont}" sh -lc "curl -fsS $*"; }

load_envfile(){
  local f; f="$(expand_path "${CPLANEADM_ENV}")"
  if [[ -f "$f" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
      if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
        local k="${line%%=*}" v="${line#*=}"; export "$k=$v"
      fi
    done <"$f"
    ok "loaded env: $f"
  else
    note "no env file at ${f} (proceeding with defaults)"
  fi
}

resolve_compose(){
  COMPOSE_DIR="$(expand_path "${COMPOSE_DIR}")"
  _COMPOSE_BASE="$(expand_path "${COMPOSE_DIR}/${COMPOSE_BASE}")"
  _COMPOSE_SECURE=""
  [[ -f "${COMPOSE_DIR}/${COMPOSE_SECURE}" ]] && _COMPOSE_SECURE="$(expand_path "${COMPOSE_DIR}/${COMPOSE_SECURE}")"
  [[ -f "${_COMPOSE_BASE}" ]] || die "base compose not found: ${_COMPOSE_BASE}"
  if [[ -n "${_COMPOSE_SECURE}" ]]; then note "secure overlay detected: ${_COMPOSE_SECURE}"
  else [[ "${SECURE_REQUIRED}" == "true" ]] && die "secure overlay required but not found: ${COMPOSE_DIR}/${COMPOSE_SECURE}" || note "no secure overlay present"; fi
}

# --- target resolution: server|agent|both (default both) ---
resolve_targets(){
  local t="${1:-both}"
  case "$t" in
    server) TARGET_SERVICES=("${SERVER_SVC}"); TARGET_CONTAINERS=("${SERVER_CONT}");;
    agent)  TARGET_SERVICES=("${AGENT_SVC}");  TARGET_CONTAINERS=("${AGENT_CONT}");;
    both|"") TARGET_SERVICES=("${SERVER_SVC}" "${AGENT_SVC}"); TARGET_CONTAINERS=("${SERVER_CONT}" "${AGENT_CONT}");;
    *) die "unknown target: $t (use server|agent|both)";;
  esac
}

usage(){
  cat <<EOF
${BOLD}cplaneadm${NC} — control-plane wrapper for podman-compose

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
  echo "CPLANEADM_ENV=${CPLANEADM_ENV}"
  echo "COMPOSE_DIR=${COMPOSE_DIR}"
  echo "COMPOSE_BASE=${COMPOSE_BASE}"
  echo "COMPOSE_SECURE=${COMPOSE_SECURE}"
  echo "COMPOSE_PROFILES=${COMPOSE_PROFILES}"
  echo "SECURE_REQUIRED=${SECURE_REQUIRED}"
  echo "_COMPOSE_BASE=${_COMPOSE_BASE}"
  echo "_COMPOSE_SECURE=${_COMPOSE_SECURE}"
}

cmd_up(){
  local target="${1:-both}"; shift || true
  local base_only="false"; [[ "${1:-}" == "--base-only" ]] && base_only="true"
  resolve_targets "$target"
  if [[ "$base_only" == "true" || -z "${_COMPOSE_SECURE}" ]]; then
    ok "bringing up (base only) → ${TARGET_SERVICES[*]}"
    pcmd up -d "${TARGET_SERVICES[@]}"
  else
    ok "bringing up (base + secure) → ${TARGET_SERVICES[*]}"
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

main(){
  have podman-compose || die "podman-compose not found"; have podman || die "podman not found"
  load_envfile; resolve_compose
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

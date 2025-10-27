```bash

#!/bin/sh
# cplaneadm-posix — Control PLANE ADMin (POSIX /bin/sh)
# v0.2-POSIX — Podman-only, POSIX-safe var refs (${var}), and $(...) command subs.

set -eu

VERSION="0.2-POSIX"
SELF_NAME="$(basename "$0")"

# ------------------------------ config (env overrides) ------------------------------
CPLANE_PROJECT_DIR="${CPLANE_PROJECT_DIR-}"
CPLANE_COMPOSE_FILE="${CPLANE_COMPOSE_FILE-}"
CPLANE_COMPOSE_CMD="${CPLANE_COMPOSE_CMD-}"
CPLANE_TIMEOUT="${CPLANE_TIMEOUT-60}"
CONSUL_HTTP_ADDR="${CONSUL_HTTP_ADDR-http://127.0.0.1:8500}"
CONSUL_HTTP_TOKEN="${CONSUL_HTTP_TOKEN-}"
COMPOSE_PROFILES="${COMPOSE_PROFILES-}"

JSON_OUT=false
SEL_SERVER=false
SEL_AGENT=false

# ------------------------------ io helpers ------------------------------
log() { printf '%s
' "$*"; }
err() { printf 'ERROR: %s
' "$*" 1>&2; }
dbg() { if [ "${DEBUG-}" ]; then printf 'DEBUG: %s
' "$*" 1>&2; fi; }

as_json() { [ "${JSON_OUT}" = true ]; }

emit_map() {
  # Usage: emit_map key=value key=value ...
  if as_json; then
    if command -v python3 >/dev/null 2>&1; then
      python3 - "$@" <<'PY'
import json, sys
pairs=[s.split('=',1) for s in sys.argv[1:]]
print(json.dumps(dict(pairs), indent=2))
PY
    else
      first=1
      printf '{'
      for kv in "$@"; do
        key=${kv%%=*}; val=${kv#*=}
        if [ ${first} -eq 0 ]; then printf ','; else first=0; fi
        esc_val=$(printf '%s' "${val}" | sed 's/\/\\/g; s/"/\"/g')
        esc_key=$(printf '%s' "${key}" | sed 's/\/\\/g; s/"/\"/g')
        printf '"%s":"%s"' "${esc_key}" "${esc_val}"
      done
      printf '}
'
    fi
  else
    for kv in "$@"; do printf '%s
' "${kv}"; done
  fi
}

usage() {
  cat <<USG
${SELF_NAME} v${VERSION}

Global flags:
  --json                 JSON output
  --project-dir DIR      cd here first (auto-detect if unset)
  --compose-file FILE    compose file path (auto-detect)
  --compose-cmd CMD      podman-compose | podman compose
  --timeout SEC          wait-ready timeout (default ${CPLANE_TIMEOUT})
  --http-addr URL        Consul HTTP addr (default ${CONSUL_HTTP_ADDR})
  --token TOKEN          Consul ACL token (optional)
  --profile LIST         Set COMPOSE_PROFILES (comma sep)
  -v/--verbose           Debug
  -h/--help              Help

Selectors:
  --server | --agent | --both

Commands:
  start|stop|restart|status|ps|logs|tail|exec|validate|check-secrets|health|wait-ready
USG
}

# ------------------------------ arg parse ------------------------------
ORIG_ARGS="$*"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --json) JSON_OUT=true; shift ;;
    --project-dir) CPLANE_PROJECT_DIR="$2"; shift 2 ;;
    --compose-file) CPLANE_COMPOSE_FILE="$2"; shift 2 ;;
    --compose-cmd) CPLANE_COMPOSE_CMD="$2"; shift 2 ;;
    --timeout) CPLANE_TIMEOUT="$2"; shift 2 ;;
    --http-addr) CONSUL_HTTP_ADDR="$2"; shift 2 ;;
    --token) CONSUL_HTTP_TOKEN="$2"; shift 2 ;;
    --profile) COMPOSE_PROFILES="$2"; export COMPOSE_PROFILES; shift 2 ;;
    --server) SEL_SERVER=true; shift ;;
    --agent) SEL_AGENT=true; shift ;;
    --both) SEL_SERVER=true; SEL_AGENT=true; shift ;;
    -v|--verbose) DEBUG=1; shift ;;
    -h/--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) err "Unknown flag: $1"; usage; exit 2 ;;
    *) break ;;
  esac
done

CMD="${1-}"
if [ -z "${CMD}" ]; then usage; exit 2; fi
shift || true

# ------------------------------ detection ------------------------------
find_compose_cmd() {
  if [ -n "${CPLANE_COMPOSE_CMD}" ]; then
    printf '%s
' "${CPLANE_COMPOSE_CMD}"; return
  fi
  if command -v podman-compose >/dev/null 2>&1; then
    printf '%s
' podman-compose; return
  fi
  if command -v podman >/dev/null 2>&1; then
    if podman compose version >/dev/null 2>&1; then
      printf '%s
' "podman compose"; return
    fi
  fi
  err "No compose command found (podman-compose / podman compose)."
  exit 127
}

find_project_dir() {
  if [ -n "${CPLANE_PROJECT_DIR}" ]; then
    printf '%s
' "${CPLANE_PROJECT_DIR}"; return
  fi
  _d="$(pwd)"
  while :; do
    for _f in \
      compose.yml compose.yaml \
      docker-compose.yml docker-compose.yaml \
      podman-compose.yml podman-compose.yaml
    do
      if [ -f "${_d}/${_f}" ]; then printf '%s
' "${_d}"; return; fi
    done
    [ "${_d}" = "/" ] && break
    _d="$(dirname "${_d}")"
  done
  err "Could not locate a compose file; set --project-dir"
  exit 2
}

find_compose_file() {
  if [ -n "${CPLANE_COMPOSE_FILE}" ]; then printf '%s
' "${CPLANE_COMPOSE_FILE}"; return; fi
  for _f in \
    compose.yml compose.yaml \
    docker-compose.yml docker-compose.yaml \
    podman-compose.yml podman-compose.yaml
  do
    if [ -f "${PROJECT_DIR}/${_f}" ]; then printf '%s
' "${PROJECT_DIR}/${_f}"; return; fi
  done
  err "No compose file found in ${PROJECT_DIR}"
  exit 2
}

COMPOSE_CMD="$(find_compose_cmd)"
PROJECT_DIR="$(find_project_dir)"
COMPOSE_FILE="$(find_compose_file)"

# ------------------------------ compose wrapper ------------------------------
cc() {
  dbg "RUN: (cd ${PROJECT_DIR} && ${COMPOSE_CMD} -f ${COMPOSE_FILE} $*)"
  (
    cd "${PROJECT_DIR}"
    eval "${COMPOSE_CMD} -f \"${COMPOSE_FILE}\" $*"
  )
}

services_for_selection() {
  _svcs=""
  if [ "${SEL_SERVER}" = true ]; then _svcs="${_svcs} consul-server"; fi
  if [ "${SEL_AGENT}" = true ];  then _svcs="${_svcs} consul-agent";  fi
  if [ "${SEL_SERVER}" = false ] && [ "${SEL_AGENT}" = false ]; then _svcs="consul-server consul-agent"; fi
  printf '%s
' "${_svcs}" | awk '{$1=$1;print}'
}

# ------------------------------ HTTP helpers ------------------------------
http_get() {
  _path="${1}"; shift || true
  _url="$(printf '%s%s' "${CONSUL_HTTP_ADDR%/}" "${_path}")"
  set -- -sS --max-time 5
  if [ -n "${CONSUL_HTTP_TOKEN}" ]; then
    set -- "$@" -H "X-Consul-Token: ${CONSUL_HTTP_TOKEN}"
  fi
  curl "$@" "${_url}"
}

http_status() {
  _path="${1}"; shift || true
  _url="$(printf '%s%s' "${CONSUL_HTTP_ADDR%/}" "${_path}")"
  set -- -sS -o /dev/null -w '%{http_code}' --max-time 5
  if [ -n "${CONSUL_HTTP_TOKEN}" ]; then
    set -- "$@" -H "X-Consul-Token: ${CONSUL_HTTP_TOKEN}"
  fi
  curl "$@" "${_url}"
}

check_http_alive() {
  _code="$(http_status "/v1/status/leader" 2>/dev/null || printf '000')"
  [ "${_code}" = "200" ]
}

check_acl_bootstrap_blocked() {
  _code="$(http_status "/v1/acl/bootstrap" 2>/dev/null || printf '000')"
  case "${_code}" in
    403|405|409) return 0 ;;
    200) return 1 ;;
    *) return 1 ;;
  esac
}

wait_ready() {
  _now="$(date +%s)"
  _end=$(expr "${_now}" + "${CPLANE_TIMEOUT}")
  while :; do
    _now="$(date +%s)"
    if [ "${_now}" -ge "${_end}" ]; then
      err "Timeout waiting for ${CONSUL_HTTP_ADDR}"
      return 1
    fi
    if check_http_alive; then
      _acl="open"
      if check_acl_bootstrap_blocked; then _acl="blocked"; fi
      _clean_addr="$(printf '%s' "${CONSUL_HTTP_ADDR}" | sed 's#^https\?://##')"
      emit_map "http=http://${_clean_addr}" "api=up" "acl_bootstrap=${_acl}"
      return 0
    fi
    sleep 1
  done
}

# ------------------------------ validators & secrets ------------------------------
validate_configs() {
  _rc=0
  for _svc in consul-server consul-agent; do
    if cc ps --services 2>/dev/null | grep -q "${_svc}"; then
      if cc exec "${_svc}" sh -lc 'consul validate /consul/config 2>&1'; then
        log "${_svc}: validate=ok"
      else
        _rc=1
        err "${_svc}: validation failed"
      fi
    fi
  done
  return ${_rc}
}

check_secrets() {
  _engine=podman
  _refs=$(awk '/^secrets:/ {insec=1; next} insec && NF==0 {insec=0} insec {print}' "${COMPOSE_FILE}" \
    | awk -F: '{gsub(/ /,""); if ($1!="")} $1 ~ /[A-Za-z0-9_.-]+/ {print $1}' \
    | sort -u)

  _missing_count=0
  _present_count=0
  _missing_list=""

  for _s in ${_refs}; do
    if podman secret exists "${_s}" >/dev/null 2>&1; then
      _present_count=$(expr ${_present_count} + 1)
    else
      _missing_count=$(expr ${_missing_count} + 1)
      _missing_list="${_missing_list} ${_s}"
    fi
  done

  emit_map "engine=${_engine}" "compose_file=${COMPOSE_FILE}" "present=${_present_count}" "missing=${_missing_count}"

  if [ "${_missing_count}" -gt 0 ]; then
    err "Missing secrets:${_missing_list}"
    return 3
  fi
}

# ------------------------------ actions ------------------------------
do_start() {
  _svcs="$(services_for_selection)"
  cc up -d ${_svcs}
}

_do_stop() {
  _svcs="$(services_for_selection)"
  cc stop ${_svcs}
}

do_restart() {
  _do_stop || true
  do_start
  wait_ready
}

do_status() {
  cc ps
  _api="down"
  if check_http_alive; then _api="up"; fi
  emit_map "http_addr=${CONSUL_HTTP_ADDR}" "api=${_api}"
}

do_logs() {
  _svcs="$(services_for_selection)"
  cc logs --no-log-prefix --tail=200 ${_svcs}
}

do_tail() {
  _svcs="$(services_for_selection)"
  cc logs -f --no-log-prefix ${_svcs}
}

do_ps() {
  cc ps
}

do_exec() {
  if [ "${SEL_SERVER}" = true ] && [ "${SEL_AGENT}" = false ]; then _target=consul-server;
  elif [ "${SEL_AGENT}" = true ] && [ "${SEL_SERVER}" = false ]; then _target=consul-agent;
  else err "exec requires exactly one of --server or --agent"; exit 2; fi

  if [ "$#" -le 0 ]; then err "exec requires a command after --"; exit 2; fi
  cc exec "${_target}" "$@"
}

do_health() {
  _code="$(http_status "/v1/status/leader" 2>/dev/null || printf '000')"
  _leader="$(http_get "/v1/status/leader" 2>/dev/null || printf '')"
  _leader_one="$(printf '%s' "${_leader}" | tr -d '
')"
  _acl="open"; if check_acl_bootstrap_blocked; then _acl="blocked"; fi
  emit_map "http_addr=${CONSUL_HTTP_ADDR}" "status_code=${_code}" "leader=${_leader_one}" "acl_bootstrap=${_acl}"
}

# ------------------------------ dispatch ------------------------------
case "${CMD}" in
  start) do_start ;;
  stop) _do_stop ;;
  restart) do_restart ;;
  status) do_status ;;
  ps) do_ps ;;
  logs) do_logs ;;
  tail) do_tail ;;
  exec) shift || true; do_exec "$@" ;;
  validate) validate_configs ;;
  check-secrets) check_secrets ;;
  health) do_health ;;
  wait-ready) wait_ready ;;
  *) err "Unknown command: ${CMD}"; usage; exit 2 ;;
esac

```

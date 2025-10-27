```bash

#!/bin/sh
# cplaneadm-lite — tiny POSIX helper for Consul under podman-compose / podman compose
# v0.3 — adds `check-secrets`, expands all functions to multi-line bodies.
# Goals:
#   - Minimal, readable, and easy to audit
#   - Podman-only, compose-file driven
#   - Commands: start | stop | restart | status | ps | logs | tail | health | wait-ready | exec | check-secrets
#   - Selectors: --server | --agent | --both (default: both)
#   - Few flags: --dir, --file, --timeout, --http-addr, --token
#   - Simple stdout; predictable exit codes; no JSON

set -eu

VERSION="0.3"
SELF="$(basename "$0")"

# -------- defaults --------
DIR="${CPLANE_PROJECT_DIR-}"
FILE="${CPLANE_COMPOSE_FILE-}"
TIMEOUT="${CPLANE_TIMEOUT-60}"
HTTP="${CONSUL_HTTP_ADDR-http://127.0.0.1:8500}"
TOKEN="${CONSUL_HTTP_TOKEN-}"
SEL_SERVER=false
SEL_AGENT=false

# -------- helpers --------
err(){ printf 'ERROR: %s\n' "$*" 1>&2; }

info(){ printf '%s\n' "$*"; }

usage() {
  cat <<USG
$SELF v$VERSION (POSIX, podman-only)
Usage: $SELF [global flags] <command> [-- command args]

Commands: start|up, stop, restart, status, ps, logs, tail, health, wait-ready, exec, check-secrets
Selectors: --server | --agent | --both (default both)

Global flags:
  --dir DIR        cd to DIR (auto-detect compose file if --file unset)
  --file FILE      compose file path (auto-detect if unset)
  --timeout SEC    wait-ready timeout (default ${TIMEOUT})
  --http-addr URL  Consul HTTP addr (default ${HTTP})
  --token TOKEN    Consul ACL token (optional)
  -h|--help        this help
USG
}

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "missing dependency: $1"
    exit 127
  fi
}

compose_cmd() {
  if command -v podman-compose >/dev/null 2>&1; then
    printf 'podman-compose'
    return
  fi
  if command -v podman >/dev/null 2>&1 && podman compose version >/dev/null 2>&1; then
    printf 'podman compose'
    return
  fi
  err "no compose command found (need podman-compose or podman compose)"
  exit 127
}

find_dir() {
  if [ -n "${DIR}" ]; then
    printf '%s
' "${DIR}"
    return
  fi
  d="$(pwd)"
  while :; do
    for f in compose.yml compose.yaml docker-compose.yml docker-compose.yaml podman-compose.yml podman-compose.yaml; do
      if [ -f "$d/$f" ]; then
        printf '%s
' "$d"
        return
      fi
    done
    if [ "$d" = "/" ]; then
      break
    fi
    d="$(dirname "$d")"
  done
  err "no compose file found upward from cwd; set --dir or --file"
  exit 2
}

find_file() {
  if [ -n "${FILE}" ]; then
    printf '%s
' "${FILE}"
    return
  fi
  for f in compose.yml compose.yaml docker-compose.yml docker-compose.yaml podman-compose.yml podman-compose.yaml; do
    if [ -f "$DIR/$f" ]; then
      printf '%s
' "$DIR/$f"
      return
    fi
  done
  err "no compose file in $DIR; set --file"
  exit 2
}

cc() {
  (
    cd "${DIR}"
    eval "$(compose_cmd) -f \"${FILE}\" $*"
  )
}

sel_services() {
  s=""
  if [ "${SEL_SERVER}" = true ]; then
    s="${s} consul-server"
  fi
  if [ "${SEL_AGENT}" = true ]; then
    s="${s} consul-agent"
  fi
  if [ "${SEL_SERVER}" = false ] && [ "${SEL_AGENT}" = false ]; then
    s="consul-server consul-agent"
  fi
  printf '%s
' "${s}" | awk '{$1=$1;print}'
}

curl_h() {
  need curl
  set -- -sS --max-time 5 "$@"
  if [ -n "${TOKEN}" ]; then
    set -- "$@" -H "X-Consul-Token: ${TOKEN}"
  fi
  curl "$@"
}

http_code() {
  path="$1"
  curl_h -o /dev/null -w '%{http_code}' "${HTTP%/}${path}"
}

http_get() {
  path="$1"
  curl_h "${HTTP%/}${path}"
}

check_alive() {
  code="$(http_code "/v1/status/leader" || printf 000)"
  if [ "${code}" = 200 ]; then
    return 0
  fi
  return 1
}

check_acl_bootstrap_blocked() {
  code="$(http_code "/v1/acl/bootstrap" || printf 000)"
  case "${code}" in
    403|405|409)
      return 0
      ;;
    200)
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

wait_ready() {
  end=$(expr "$(date +%s)" + "${TIMEOUT}")
  while :; do
    now="$(date +%s)"
    if [ "${now}" -ge "${end}" ]; then
      err "timeout waiting for ${HTTP}"
      return 1
    fi
    if check_alive; then
      acl="open"
      if check_acl_bootstrap_blocked; then
        acl="blocked"
      fi
      info "api=up http=${HTTP} acl_bootstrap=${acl}"
      return 0
    fi
    sleep 1
  done
}

# -------- actions --------
start() {
  cc up -d $(sel_services)
}

stop() {
  cc stop $(sel_services)
}

restart() {
  stop || true
  start
  wait_ready
}

status() {
  cc ps
  if check_alive; then
    info "api=up http=${HTTP}"
  else
    info "api=down http=${HTTP}"
  fi
}

ps_cmd() {
  cc ps
}

logs() {
  cc logs --no-log-prefix --tail=200 $(sel_services)
}

tailf() {
  cc logs -f --no-log-prefix $(sel_services)
}

health() {
  code="$(http_code "/v1/status/leader" || printf 000)"
  leader="$(http_get "/v1/status/leader" 2>/dev/null || printf '')"
  leader="$(printf '%s' "${leader}" | tr -d '
')"
  acl="open"
  if check_acl_bootstrap_blocked; then
    acl="blocked"
  fi
  info "status_code=${code} leader=${leader} acl_bootstrap=${acl}"
}

exec_cmd() {
  if [ "${SEL_SERVER}" = true ] && [ "${SEL_AGENT}" = false ]; then
    tgt=consul-server
  elif [ "${SEL_AGENT}" = true ] && [ "${SEL_SERVER}" = false ]; then
    tgt=consul-agent
  else
    err "exec requires exactly one of --server or --agent"
    exit 2
  fi

  if [ "$#" -le 0 ]; then
    err "exec requires a command after --"
    exit 2
  fi

  cc exec "${tgt}" "$@"
}

check_secrets() {
  # naive scan of top-level `secrets:` block in compose file and verify with podman
  refs=$(awk '/^secrets:/ {insec=1; next} insec && NF==0 {insec=0} insec {print}' "${FILE}" \
    | awk -F: '{gsub(/ /,""); if ($1!="")} $1 ~ /[A-Za-z0-9_.-]+/ {print $1}' \
    | sort -u)

  missing=0
  present=0
  missing_list=""

  for s in ${refs}; do
    if podman secret exists "${s}" >/dev/null 2>&1; then
      present=$(expr ${present} + 1)
    else
      missing=$(expr ${missing} + 1)
      missing_list="${missing_list} ${s}"
    fi
  done

  info "engine=podman compose_file=${FILE} present=${present} missing=${missing}"

  if [ "${missing}" -gt 0 ]; then
    err "Missing secrets:${missing_list}"
    return 3
  fi
}

# -------- parse args --------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir)
      DIR="$2"; shift 2
      ;;
    --file)
      FILE="$2"; shift 2
      ;;
    --timeout)
      TIMEOUT="$2"; shift 2
      ;;
    --http-addr)
      HTTP="$2"; shift 2
      ;;
    --token)
      TOKEN="$2"; shift 2
      ;;
    --server)
      SEL_SERVER=true; shift
      ;;
    --agent)
      SEL_AGENT=true; shift
      ;;
    --both)
      SEL_SERVER=true; SEL_AGENT=true; shift
      ;;
    -h|--help)
      usage; exit 0
      ;;
    --)
      shift; break
      ;;
    start|up|stop|restart|status|ps|logs|tail|health|wait-ready|exec|check-secrets)
      CMD="$1"; shift; break
      ;;
    *)
      CMD="$1"; shift; break
      ;;
  esac
done

if [ -z "${DIR}" ]; then
  DIR="$(find_dir)"
fi
if [ -z "${FILE}" ]; then
  FILE="$(find_file)"
fi

# -------- dispatch --------
case "${CMD-}" in
  start|up)
    start
    ;;
  stop)
    stop
    ;;
  restart)
    restart
    ;;
  status)
    status
    ;;
  ps)
    ps_cmd
    ;;
  logs)
    logs
    ;;
  tail)
    tailf
    ;;
  health)
    health
    ;;
  wait-ready)
    wait_ready
    ;;
  exec)
    exec_cmd "$@"
    ;;
  check-secrets)
    check_secrets
    ;;
  *)
    usage
    exit 2
    ;;
esac

```

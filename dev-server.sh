#!/usr/bin/env bash
set -euo pipefail

### ── Tunables ─────────────────────────────────────────────────────────────────
CONSUL_BIN="${CONSUL_BIN:-consul}"                 # consul binary
BASE_DIR="${BASE_DIR:-$HOME/.consul-dev}"          # state lives here
DC="${DC:-dev-dc}"
NODE_NAME="${NODE_NAME:-dev-consul}"
BIND_ADDR="${BIND_ADDR:-127.0.0.1}"                # server/serf/rpc bind (keep local for single-node)
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Change ALL ports from defaults. Override via env if needed.
PORT_HTTP="${PORT_HTTP:-18500}"                    # default 8500
PORT_HTTPS="${PORT_HTTPS:--1}"                     # set e.g. 18501 if you enable TLS; -1 disables
PORT_GRPC="${PORT_GRPC:-18502}"                    # default 8502
PORT_GRPC_TLS="${PORT_GRPC_TLS:--1}"               # set e.g. 18503; -1 disables
PORT_DNS="${PORT_DNS:-18600}"                      # default 8600
PORT_SERVER_RPC="${PORT_SERVER_RPC:-18300}"        # default 8300
PORT_SERF_LAN="${PORT_SERF_LAN:-18301}"            # default 8301
PORT_SERF_WAN="${PORT_SERF_WAN:-18302}"            # default 8302

# Connect sidecar ephemeral range (also moved off defaults)
SIDECAR_MIN_PORT="${SIDECAR_MIN_PORT:-19000}"
SIDECAR_MAX_PORT="${SIDECAR_MAX_PORT:-19100}"

# Example policy/tokens to preload
LOAD_POLICIES="${LOAD_POLICIES:-true}"
RO_POLICY_NAME="${RO_POLICY_NAME:-dev-readonly}"
ADMIN_POLICY_NAME="${ADMIN_POLICY_NAME:-dev-admin}"

### ── Derived paths ────────────────────────────────────────────────────────────
CONF_DIR="$BASE_DIR/conf.d"
DATA_DIR="$BASE_DIR/data"
RUN_DIR="$BASE_DIR/run"
LOG_DIR="$BASE_DIR/log"
TOKENS_DIR="$BASE_DIR/tokens"
POL_DIR="$BASE_DIR/policies"
PID_FILE="$RUN_DIR/consul.pid"
CONF_FILE="$CONF_DIR/server.hcl"
MGMT_TOKEN_FILE="$TOKENS_DIR/management.token"

mkdir -p "$CONF_DIR" "$DATA_DIR" "$RUN_DIR" "$LOG_DIR" "$TOKENS_DIR" "$POL_DIR"

### ── Checks ──────────────────────────────────────────────────────────────────
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need "$CONSUL_BIN"; need curl; need jq

### ── Config (HTTP on 0.0.0.0; others localhost) ─────────────────────────────
cat >"$CONF_FILE" <<EOF
datacenter  = "${DC}"
node_name   = "${NODE_NAME}"
server      = true
bootstrap_expect = 1
data_dir    = "${DATA_DIR}"
bind_addr   = "${BIND_ADDR}"
log_level   = "${LOG_LEVEL}"

# Per-protocol addresses: expose HTTP to the LAN, keep others local-only
addresses {
  http     = "0.0.0.0"
  https    = "127.0.0.1"
  grpc     = "127.0.0.1"
  grpc_tls = "127.0.0.1"
  dns      = "127.0.0.1"
}

# Move every port off the defaults
ports {
  http       = ${PORT_HTTP}
  https      = ${PORT_HTTPS}
  grpc       = ${PORT_GRPC}
  grpc_tls   = ${PORT_GRPC_TLS}
  dns        = ${PORT_DNS}
  server     = ${PORT_SERVER_RPC}
  serf_lan   = ${PORT_SERF_LAN}
  serf_wan   = ${PORT_SERF_WAN}
}

# Keep random sidecars off the default range too
connect {
  sidecar_min_port = ${SIDECAR_MIN_PORT}
  sidecar_max_port = ${SIDECAR_MAX_PORT}
}

ui_config { enabled = true }
disable_update_check = true
disable_remote_exec  = true

acl {
  enabled                  = true
  default_policy           = "deny"
  down_policy              = "extend-cache"
  enable_token_persistence = true
}
EOF

### ── Start Consul ────────────────────────────────────────────────────────────
CONSUL_HTTP_ADDR="http://127.0.0.1:${PORT_HTTP}"
export CONSUL_HTTP_ADDR

is_up() { curl -s "${CONSUL_HTTP_ADDR}/v1/status/leader" >/dev/null 2>&1; }

if ! is_up; then
  [[ -f "$PID_FILE" ]] && rm -f "$PID_FILE"
  echo "Starting Consul (HTTP port ${PORT_HTTP} on 0.0.0.0; others localhost) ..."
  nohup "$CONSUL_BIN" agent \
    -config-dir "$CONF_DIR" \
    -pid-file "$PID_FILE" \
    >"$LOG_DIR/consul.log" 2>&1 &

  for _ in {1..60}; do is_up && break; sleep 0.5; done
  is_up || { echo "Consul failed to come up. See $LOG_DIR/consul.log" >&2; exit 1; }
else
  echo "Consul already responding on ${CONSUL_HTTP_ADDR}"
fi

### ── ACL bootstrap ───────────────────────────────────────────────────────────
if [[ ! -f "$MGMT_TOKEN_FILE" ]]; then
  echo "Bootstrapping ACLs..."
  BOOTSTRAP_JSON="$(curl -sS -X POST "${CONSUL_HTTP_ADDR}/v1/acl/bootstrap")"
  MGMT_TOKEN="$(echo "$BOOTSTRAP_JSON" | jq -r '.SecretID // empty')"
  [[ -n "$MGMT_TOKEN" ]] || { echo "Bootstrap failed: $BOOTSTRAP_JSON" >&2; exit 1; }
  umask 077; printf "%s" "$MGMT_TOKEN" >"$MGMT_TOKEN_FILE"; umask 022
  echo "Management token saved: $MGMT_TOKEN_FILE"
else
  MGMT_TOKEN="$(cat "$MGMT_TOKEN_FILE")"
  echo "Using existing management token."
fi
XHDR=(-H "X-Consul-Token: ${MGMT_TOKEN}" -H "Content-Type: application/json")

### ── Example policies/tokens (idempotent) ────────────────────────────────────
if [[ "${LOAD_POLICIES}" == "true" ]]; then
  # Read-only
  cat > "$POL_DIR/${RO_POLICY_NAME}.hcl" <<'POL'
agent_prefix ""   { policy = "read" }
node_prefix ""    { policy = "read" }
service_prefix "" { policy = "read" }
query_prefix ""   { policy = "read" }
session_prefix "" { policy = "read" }
key_prefix "dev/" { policy = "read" }
POL

  # Dev-admin
  cat > "$POL_DIR/${ADMIN_POLICY_NAME}.hcl" <<'POL'
agent_prefix ""   { policy = "write" }
node_prefix ""    { policy = "read" }
service_prefix "" { policy = "write" }
query_prefix ""   { policy = "write" }
session_prefix "" { policy = "write" }
key_prefix "dev/" { policy = "write" }
# intention = "write"   # uncomment if you use Connect intentions
POL

  upsert_policy() {
    local name="$1" file="$2"
    if curl -sS "${XHDR[@]}" "${CONSUL_HTTP_ADDR}/v1/acl/policy/name/${name}" | jq -e .ID >/dev/null 2>&1; then
      local id; id="$(curl -sS "${XHDR[@]}" "${CONSUL_HTTP_ADDR}/v1/acl/policy/name/${name}" | jq -r .ID)"
      curl -sS -X PUT "${XHDR[@]}" \
        --data-binary "$(jq -n --arg Name "$name" --arg Rules "$(cat "$file")" '{Name:$Name, Rules:$Rules}')" \
        "${CONSUL_HTTP_ADDR}/v1/acl/policy/${id}" >/dev/null
      echo "Policy '${name}' updated."
    else
      curl -sS -X PUT "${XHDR[@]}" \
        --data-binary "$(jq -n --arg Name "$name" --arg Rules "$(cat "$file")" '{Name:$Name, Rules:$Rules}')" \
        "${CONSUL_HTTP_ADDR}/v1/acl/policy" >/dev/null
      echo "Policy '${name}' created."
    fi
  }

  upsert_policy "$RO_POLICY_NAME"    "$POL_DIR/${RO_POLICY_NAME}.hcl"
  upsert_policy "$ADMIN_POLICY_NAME" "$POL_DIR/${ADMIN_POLICY_NAME}.hcl"

  make_token() {
    local outfile="$1" desc="$2" polname="$3"
    [[ -f "$outfile" ]] && { echo "Token exists: $outfile"; return; }
    local payload; payload="$(jq -n --arg Description "$desc" \
      --arg pn "$polname" '{Description:$Description, Policies:[{Name:$pn}] }')"
    local out; out="$(curl -sS -X PUT "${XHDR[@]}" --data-binary "$payload" "${CONSUL_HTTP_ADDR}/v1/acl/token")"
    local secret; secret="$(echo "$out" | jq -r '.SecretID // empty')"
    [[ -n "$secret" ]] || { echo "Token create failed for $polname: $out" >&2; exit 1; }
    umask 077; printf "%s" "$secret" >"$outfile"; umask 022
    echo "Token for '${polname}' -> $outfile"
  }

  mkdir -p "$TOKENS_DIR"
  make_token "$TOKENS_DIR/${RO_POLICY_NAME}.token"    "Token for ${RO_POLICY_NAME}"    "$RO_POLICY_NAME"
  make_token "$TOKENS_DIR/${ADMIN_POLICY_NAME}.token" "Token for ${ADMIN_POLICY_NAME}" "$ADMIN_POLICY_NAME"
fi

### ── Summary ─────────────────────────────────────────────────────────────────
cat <<EOS

Consul dev server is up with HTTP exposed:

• HTTP (API/UI): 0.0.0.0:${PORT_HTTP}
• HTTPS:         127.0.0.1:${PORT_HTTPS}    (-1 = disabled)
• gRPC:          127.0.0.1:${PORT_GRPC}
• gRPC (TLS):    127.0.0.1:${PORT_GRPC_TLS}  (-1 = disabled)
• DNS:           127.0.0.1:${PORT_DNS}
• Server RPC:    ${PORT_SERVER_RPC}
• Serf LAN/WAN:  ${PORT_SERF_LAN}/${PORT_SERF_WAN}
• Sidecars:      ${SIDECAR_MIN_PORT}-${SIDECAR_MAX_PORT}

Paths:
• Config dir:

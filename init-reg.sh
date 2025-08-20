#!/usr/bin/env bash
set -euo pipefail

: "${CONSUL_HTTP_ADDR:=http://127.0.0.1:8500}"
: "${CONSUL_GRPC_ADDR:=127.0.0.1:8502}"
: "${SERVICE_NAME:?set SERVICE_NAME}"
: "${SERVICE_PORT:?set SERVICE_PORT}"

# Optional knobs
SERVICE_ID="${SERVICE_ID:-${SERVICE_NAME}-$(hostname -s)}"
SERVICE_ADDRESS="${SERVICE_ADDRESS:-}"
SERVICE_TAGS="${SERVICE_TAGS:-}"                  # comma-separated
SERVICE_VERSION="${SERVICE_VERSION:-}"            # put into Meta.version
HEALTHCHECK_HTTP="${HEALTHCHECK_HTTP:-}"          # e.g. /healthz
HEALTHCHECK_INTERVAL="${HEALTHCHECK_INTERVAL:-10s}"
UPSTREAMS="${UPSTREAMS:-}"                        # "payments:9191,inventory:9300"
ENVOY_ADMIN_BIND="${ENVOY_ADMIN_BIND:-127.0.0.1:19000}"

# Transparent proxy (iptables) toggle — requires CAP_NET_ADMIN in this container
TPROXY="${TPROXY:-0}"
# Exclusions for tproxy (comma lists) — e.g. "8500,8502"
TPROXY_EXCLUDE_OUTBOUND_PORTS="${TPROXY_EXCLUDE_OUTBOUND_PORTS:-8500,8502}"
TPROXY_EXCLUDE_INBOUND_PORTS="${TPROXY_EXCLUDE_INBOUND_PORTS:-}"
TPROXY_PROXY_UID="${TPROXY_PROXY_UID:-$(id -u)}"   # usually the container user (e.g. 1001)

header_args=()
if [[ -n "${CONSUL_HTTP_TOKEN:-}" ]]; then
  header_args=(-H "X-Consul-Token: ${CONSUL_HTTP_TOKEN}")
fi

# Build Tags JSON
TAGS_JSON="[]"
if [[ -n "$SERVICE_TAGS" ]]; then
  IFS=',' read -ra tags <<< "$SERVICE_TAGS"
  for t in "${tags[@]}"; do
    t_trim="$(echo "$t" | xargs)"
    [[ -z "$t_trim" ]] && continue
    if [[ "$TAGS_JSON" == "[]" ]]; then
      TAGS_JSON="[\"$t_trim\"]"
    else
      TAGS_JSON="${TAGS_JSON%]} , \"$t_trim\" ]"
    fi
  done
fi

# Build Upstreams JSON for the sidecar
UPSTREAMS_JSON="[]"
if [[ -n "$UPSTREAMS" ]]; then
  IFS=',' read -ra ups <<< "$UPSTREAMS"
  for pair in "${ups[@]}"; do
    name="${pair%%:*}"; port="${pair##*:}"
    [[ -z "$name" || -z "$port" ]] && continue
    entry="{\"destination_name\":\"${name}\",\"local_bind_port\":${port}}"
    if [[ "$UPSTREAMS_JSON" == "[]" ]]; then
      UPSTREAMS_JSON="[ ${entry} ]"
    else
      UPSTREAMS_JSON="${UPSTREAMS_JSON%]} , ${entry} ]"
    fi
  done
fi

CHECK_BLOCK=""
if [[ -n "$HEALTHCHECK_HTTP" ]]; then
  CHECK_BLOCK=$(cat <<JSON
"Check": {
  "Name": "http",
  "HTTP": "http://127.0.0.1:${SERVICE_PORT}${HEALTHCHECK_HTTP}",
  "Interval": "${HEALTHCHECK_INTERVAL}",
  "Method": "GET"
},
JSON
)
fi

ADDR_LINE=""
if [[ -n "$SERVICE_ADDRESS" ]]; then
  ADDR_LINE=$(printf '"Address": "%s",' "$SERVICE_ADDRESS")
fi

META_LINE=""
if [[ -n "$SERVICE_VERSION" ]]; then
  META_LINE=$(printf '"Meta": {"version":"%s"},' "$SERVICE_VERSION")
fi

# Register the app service with a sidecar proxy
cat > /tmp/service.json <<JSON
{
  "ID": "${SERVICE_ID}",
  "Name": "${SERVICE_NAME}",
  ${ADDR_LINE}
  "Port": ${SERVICE_PORT},
  ${META_LINE}
  "Tags": ${TAGS_JSON},
  ${CHECK_BLOCK}
  "Connect": {
    "SidecarService": {
      "Proxy": {
        "Upstreams": ${UPSTREAMS_JSON}
      }
    }
  }
}
JSON

echo "[init] registering service ${SERVICE_ID} -> ${CONSUL_HTTP_ADDR}"
curl -fsSL -X PUT "${header_args[@]}" \
  --data @/tmp/service.json \
  "${CONSUL_HTTP_ADDR}/v1/agent/service/register?replace-existing-checks=true"

# Deregister on exit
cleanup() {
  echo "[init] deregistering ${SERVICE_ID}"
  curl -fsSL -X PUT "${header_args[@]}" \
    "${CONSUL_HTTP_ADDR}/v1/agent/service/deregister/${SERVICE_ID}" || true
}
trap cleanup EXIT

# Optional: enable transparent-proxy iptables in this netns
if [[ "$TPROXY" == "1" ]]; then
  echo "[init] applying redirect-traffic (transparent proxy) rules"
  tp_args=( -proxy-id="${SERVICE_ID}-sidecar-proxy" -proxy-uid="${TPROXY_PROXY_UID}" )
  [[ -n "$TPROXY_EXCLUDE_OUTBOUND_PORTS" ]] && tp_args+=( -exclude-outbound-ports="$TPROXY_EXCLUDE_OUTBOUND_PORTS" )
  [[ -n "$TPROXY_EXCLUDE_INBOUND_PORTS" ]] && tp_args+=( -exclude-inbound-ports="$TPROXY_EXCLUDE_INBOUND_PORTS" )
  consul connect redirect-traffic "${tp_args[@]}"
fi

# Start Envoy for the sidecar
echo "[init] starting Envoy sidecar for ${SERVICE_ID}"
exec consul connect envoy \
  -sidecar-for="${SERVICE_ID}" \
  -admin-bind="${ENVOY_ADMIN_BIND}" \
  -grpc-addr="${CONSUL_GRPC_ADDR}"

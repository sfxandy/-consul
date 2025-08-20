#!/bin/sh
set -eu

: "${RUN_MODE:=sidecar}"

if [ "$RUN_MODE" = "sidecar" ]; then
  : "${SERVICE_ID:?Missing SERVICE_ID (Consul service ID with connect{ sidecar_service {} })}"
  : "${ADMIN_PORT:=19000}"
  exec consul connect envoy -sidecar-for "$SERVICE_ID" -admin-bind "0.0.0.0:${ADMIN_PORT}" ${SIDECAR_EXTRA_ARGS:-} -- ${ENVOY_EXTRA_ARGS:-}

elif [ "$RUN_MODE" = "standalone" ]; then
  : "${ENVOY_CONFIG:=/etc/envoy/envoy.yaml}"
  exec envoy -c "$ENVOY_CONFIG" ${ENVOY_EXTRA_ARGS:-}

elif [ "$RUN_MODE" = "agent" ]; then
  : "${CONSUL_CONFIG_DIR:=/consul/config}"
  exec consul agent -config-dir "$CONSUL_CONFIG_DIR" ${CONSUL_AGENT_EXTRA_ARGS:-}

else
  echo "Unknown RUN_MODE=$RUN_MODE" >&2
  exit 2
fi

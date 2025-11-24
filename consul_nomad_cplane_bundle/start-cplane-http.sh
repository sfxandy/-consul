#!/usr/bin/env bash
set -euo pipefail

ENVFILE="${HOME}/.env/cplaneadm.env"
CPLANEADM="${HOME}/.bin/cplaneadm"

SERVER_HTTP="http://127.0.0.1:8501"

echo "[cplane-http] Loading env from ${ENVFILE}"
if [[ -f "${ENVFILE}" ]]; then
  . "${ENVFILE}"
fi

echo "[cplane-http] Waiting for local Consul server at ${SERVER_HTTP}..."

until curl -sSf "${SERVER_HTTP}/v1/status/leader" >/dev/null 2>&1; do
  echo "[cplane-http] Server not ready, sleeping..."
  sleep 3
done

echo "[cplane-http] Local server is healthy, starting HTTP agent via cplaneadm"

export COMPOSE_PROFILES="agent-http"

exec "${CPLANEADM}" up

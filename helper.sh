
# ---------- Compose resolution ----------
is_abs(){ [[ "$1" == /* ]]; }

resolve_compose(){
  # 1) Normalize COMPOSE_DIR
  COMPOSE_DIR="$(expand_path "${COMPOSE_DIR}")"

  # If COMPOSE_DIR accidentally points to a file, treat it as the base file
  if [[ -f "${COMPOSE_DIR}" ]]; then
    # Only adopt this if the user did NOT explicitly set COMPOSE_BASE
    if [[ "${COMPOSE_BASE}" == "docker-compose.yml" ]]; then
      COMPOSE_BASE="$(basename -- "${COMPOSE_DIR}")"
    fi
    COMPOSE_DIR="$(dirname -- "${COMPOSE_DIR}")"
  fi

  # 2) Resolve base compose
  if is_abs "${COMPOSE_BASE}"; then
    _COMPOSE_BASE="$(expand_path "${COMPOSE_BASE}")"
  else
    _COMPOSE_BASE="$(expand_path "${COMPOSE_DIR%/}/${COMPOSE_BASE}")"
  fi

  # 3) Resolve secure overlay (optional)
  _COMPOSE_SECURE=""
  if [[ -n "${COMPOSE_SECURE}" ]]; then
    if is_abs "${COMPOSE_SECURE}"; then
      _COMPOSE_SECURE="$(expand_path "${COMPOSE_SECURE}")"
    else
      _COMPOSE_SECURE="$(expand_path "${COMPOSE_DIR%/}/${COMPOSE_SECURE}")"
    fi
    # Only keep it if it exists
    [[ -f "${_COMPOSE_SECURE}" ]] || _COMPOSE_SECURE=""
  fi

  # 4) Sanity checks + hints
  [[ -f "${_COMPOSE_BASE}" ]] || die "base compose not found: ${_COMPOSE_BASE}"
  if [[ -n "${_COMPOSE_SECURE}" ]]; then
    note "secure overlay detected: ${_COMPOSE_SECURE}"
  else
    if [[ "${SECURE_REQUIRED}" == "true" ]]; then
      die "secure overlay required but not found: ${COMPOSE_DIR}/${COMPOSE_SECURE}"
    else
      note "no secure overlay present (ok for initial bring-up)"
    fi
  fi
}

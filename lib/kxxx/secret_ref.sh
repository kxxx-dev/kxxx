#!/usr/bin/env bash

kxxx_secret_ref_random_id() {
  local bytes="${1:-16}"

  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$bytes"
    return 0
  fi

  if command -v od >/dev/null 2>&1; then
    od -An -N "$bytes" -tx1 /dev/urandom | tr -d '[:space:]'
    return 0
  fi

  kxxx_die "required command not found: openssl (or od)"
}

kxxx_secret_ref_create() {
  local backend="$1" id="${2:-}"

  [[ -n "$backend" ]] || kxxx_die "secret ref backend is required"
  [[ -n "$id" ]] || id="$(kxxx_secret_ref_random_id)"

  printf 'secretref:v1:%s:%s\n' "$backend" "$id"
}

kxxx_secret_ref_parse() {
  local ref="$1"
  local -n backend_ref="$2"
  local -n id_ref="$3"

  if [[ "$ref" =~ ^secretref:v1:([a-z0-9_]+):([A-Za-z0-9._-]+)$ ]]; then
    backend_ref="${BASH_REMATCH[1]}"
    id_ref="${BASH_REMATCH[2]}"
    return 0
  fi

  return 1
}

kxxx_secret_memory_reset() {
  unset KXXX_MEMORY_SECRET_STORE >/dev/null 2>&1 || true
  declare -gA KXXX_MEMORY_SECRET_STORE=()
}

kxxx_secret_memory_store() {
  local value="$1" id="${2:-}" out_var="${3:-}" secret_ref="" backend="memory"

  declare -p KXXX_MEMORY_SECRET_STORE >/dev/null 2>&1 || declare -gA KXXX_MEMORY_SECRET_STORE=()

  [[ -n "$id" ]] || id="$(kxxx_secret_ref_random_id)"
  secret_ref="$(kxxx_secret_ref_create "$backend" "$id")"
  KXXX_MEMORY_SECRET_STORE["$id"]="$value"

  [[ -n "$out_var" ]] || kxxx_die "memory backend store requires an output variable in the current shell"

  local -n out_ref="$out_var"
  out_ref="$secret_ref"
}

kxxx_secret_resolve() {
  local ref="$1"
  local -n value_ref="$2"
  local backend="" id=""

  if ! kxxx_secret_ref_parse "$ref" backend id; then
    return 1
  fi

  case "$backend" in
    memory)
      declare -p KXXX_MEMORY_SECRET_STORE >/dev/null 2>&1 || return 1
      [[ -v "KXXX_MEMORY_SECRET_STORE[$id]" ]] || return 1
      value_ref="${KXXX_MEMORY_SECRET_STORE[$id]}"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

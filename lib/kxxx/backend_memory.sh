#!/usr/bin/env bash

kxxx_backend_memory_reset() {
  unset KXXX_MEMORY_BACKEND_STORE >/dev/null 2>&1 || true
  declare -gA KXXX_MEMORY_BACKEND_STORE=()
}

kxxx_backend_memory_store_key() {
  local service="$1" account="$2"
  printf '%s\t%s' "$service" "$account"
}

kxxx_backend_memory_set() {
  local service="$1" account="$2" value="$3"
  local key=""

  declare -p KXXX_MEMORY_BACKEND_STORE >/dev/null 2>&1 || declare -gA KXXX_MEMORY_BACKEND_STORE=()
  key="$(kxxx_backend_memory_store_key "$service" "$account")"
  KXXX_MEMORY_BACKEND_STORE["$key"]="$value"
}

kxxx_backend_memory_get() {
  local service="$1" account="$2"
  local key=""

  declare -p KXXX_MEMORY_BACKEND_STORE >/dev/null 2>&1 || return 1
  key="$(kxxx_backend_memory_store_key "$service" "$account")"
  [[ -v "KXXX_MEMORY_BACKEND_STORE[$key]" ]] || return 1
  printf '%s\n' "${KXXX_MEMORY_BACKEND_STORE[$key]}"
}

kxxx_backend_memory_list_accounts() {
  local service="$1"
  local key="" account=""

  declare -p KXXX_MEMORY_BACKEND_STORE >/dev/null 2>&1 || return 0

  for key in "${!KXXX_MEMORY_BACKEND_STORE[@]}"; do
    [[ "${key%%$'\t'*}" == "$service" ]] || continue
    account="${key#*$'\t'}"
    printf '%s\n' "$account"
  done | sort -u
}

kxxx_backend_memory_set_ref() {
  local ref="$1" value="$2"
  local backend="" id=""

  kxxx_secret_ref_parse "$ref" backend id || return 1
  [[ "$backend" == "memory" ]] || return 1
  declare -p KXXX_MEMORY_SECRET_STORE >/dev/null 2>&1 || declare -gA KXXX_MEMORY_SECRET_STORE=()
  KXXX_MEMORY_SECRET_STORE["$id"]="$value"
}

kxxx_backend_memory_get_ref() {
  local ref="$1" value=""

  if ! kxxx_secret_resolve "$ref" value; then
    return 1
  fi

  printf '%s\n' "$value"
}

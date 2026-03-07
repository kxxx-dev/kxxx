#!/usr/bin/env bash

kxxx_backend_normalize_name() {
  local backend="${1:-auto}"

  case "$backend" in
    ""|auto)
      printf 'auto\n'
      ;;
    keychain|darwin-keychain)
      printf 'darwin-keychain\n'
      ;;
    encrypted-file|memory|secret-service|wincred)
      printf '%s\n' "$backend"
      ;;
    *)
      return 1
      ;;
  esac
}

kxxx_backend_ref_tag_for_backend() {
  local backend="$1"

  case "$backend" in
    darwin-keychain)
      printf 'keychain\n'
      ;;
    *)
      printf '%s\n' "$backend"
      ;;
  esac
}

kxxx_backend_impl_name_for_ref_backend() {
  local backend="$1"

  case "$backend" in
    keychain|darwin-keychain)
      printf 'darwin-keychain\n'
      ;;
    encrypted-file|memory|secret-service|wincred)
      printf '%s\n' "$backend"
      ;;
    *)
      return 1
      ;;
  esac
}

kxxx_backend_ref_account() {
  local ref="$1"
  local backend="" id=""

  kxxx_secret_ref_parse "$ref" backend id || return 1

  case "$(kxxx_backend_impl_name_for_ref_backend "$backend")" in
    darwin-keychain|encrypted-file|secret-service|wincred)
      printf 'ref/%s\n' "$id"
      ;;
    memory)
      return 1
      ;;
  esac
}

kxxx_backend_auto_name() {
  if [[ "${OSTYPE:-}" == darwin* ]] && { command -v security >/dev/null 2>&1 || command -v ks >/dev/null 2>&1; }; then
    printf 'darwin-keychain\n'
    return 0
  fi

  printf 'encrypted-file\n'
}

kxxx_backend_resolve_name() {
  local requested="${1:-}"
  local backend=""

  backend="$(kxxx_backend_normalize_name "${requested:-${KXXX_BACKEND:-auto}}")" || kxxx_die "unsupported backend: ${requested:-${KXXX_BACKEND:-auto}}"
  if [[ "$backend" == "auto" ]]; then
    kxxx_backend_auto_name
    return 0
  fi

  printf '%s\n' "$backend"
}

kxxx_backend_resolve_cli_name() {
  local backend=""

  backend="$(kxxx_backend_resolve_name "$1")"
  if [[ "$backend" == "memory" ]]; then
    kxxx_die "backend=memory is test-only and not supported through the CLI"
  fi

  printf '%s\n' "$backend"
}

kxxx_backend_capability_headless() {
  case "$1" in
    encrypted-file|memory)
      printf 'true\n'
      ;;
    darwin-keychain)
      printf 'false\n'
      ;;
    secret-service|wincred)
      printf 'unknown\n'
      ;;
  esac
}

kxxx_backend_capability_interactive_unlock() {
  case "$1" in
    darwin-keychain)
      printf 'possible\n'
      ;;
    encrypted-file|memory)
      printf 'false\n'
      ;;
    secret-service|wincred)
      printf 'unknown\n'
      ;;
  esac
}

kxxx_backend_fail_unimplemented() {
  local backend="$1"
  kxxx_die "backend is declared but not implemented yet: ${backend}"
}

kxxx_backend_set_account() {
  local backend="$1" service="$2" account="$3" value="$4"

  case "$backend" in
    darwin-keychain)
      kxxx_keychain_set "$service" "$account" "$value"
      ;;
    encrypted-file)
      kxxx_backend_encrypted_file_set "$service" "$account" "$value"
      ;;
    memory)
      kxxx_backend_memory_set "$service" "$account" "$value"
      ;;
    secret-service|wincred)
      kxxx_backend_fail_unimplemented "$backend"
      ;;
  esac
}

kxxx_backend_get_account() {
  local backend="$1" service="$2" account="$3"

  case "$backend" in
    darwin-keychain)
      kxxx_keychain_get "$service" "$account"
      ;;
    encrypted-file)
      kxxx_backend_encrypted_file_get "$service" "$account"
      ;;
    memory)
      kxxx_backend_memory_get "$service" "$account"
      ;;
    secret-service|wincred)
      kxxx_backend_fail_unimplemented "$backend"
      ;;
  esac
}

kxxx_backend_list_accounts() {
  local backend="$1" service="$2"

  case "$backend" in
    darwin-keychain)
      kxxx_keychain_list_accounts "$service"
      ;;
    encrypted-file)
      kxxx_backend_encrypted_file_list_accounts "$service"
      ;;
    memory)
      kxxx_backend_memory_list_accounts "$service"
      ;;
    secret-service|wincred)
      kxxx_backend_fail_unimplemented "$backend"
      ;;
  esac
}

kxxx_backend_get_ref() {
  local service="$1" ref="$2"
  local ref_backend="" id="" impl_backend="" account=""

  kxxx_secret_ref_parse "$ref" ref_backend id || return 1
  impl_backend="$(kxxx_backend_impl_name_for_ref_backend "$ref_backend")" || return 1

  if [[ "$impl_backend" == "memory" ]]; then
    kxxx_backend_memory_get_ref "$ref"
    return $?
  fi

  if [[ "$impl_backend" == "darwin-keychain" ]]; then
    kxxx_keychain_get_ref "$service" "$ref"
    return $?
  fi

  account="$(kxxx_backend_ref_account "$ref")" || return 1
  kxxx_backend_get_account "$impl_backend" "$service" "$account"
}

kxxx_backend_set_ref() {
  local service="$1" ref="$2" value="$3"
  local ref_backend="" id="" impl_backend="" account=""

  kxxx_secret_ref_parse "$ref" ref_backend id || return 1
  impl_backend="$(kxxx_backend_impl_name_for_ref_backend "$ref_backend")" || return 1

  if [[ "$impl_backend" == "memory" ]]; then
    kxxx_backend_memory_set_ref "$ref" "$value"
    return $?
  fi

  if [[ "$impl_backend" == "darwin-keychain" ]]; then
    kxxx_keychain_set_ref "$service" "$ref" "$value"
    return $?
  fi

  account="$(kxxx_backend_ref_account "$ref")" || return 1
  kxxx_backend_set_account "$impl_backend" "$service" "$account" "$value"
}

kxxx_backend_create_ref() {
  local backend="$1" id="${2:-}"
  local ref_backend=""

  ref_backend="$(kxxx_backend_ref_tag_for_backend "$backend")"
  kxxx_secret_ref_create "$ref_backend" "$id"
}

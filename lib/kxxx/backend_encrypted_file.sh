#!/usr/bin/env bash

kxxx_backend_encrypted_file_path() {
  if [[ -n "${KXXX_ENCRYPTED_FILE_PATH:-}" ]]; then
    printf '%s\n' "$KXXX_ENCRYPTED_FILE_PATH"
    return 0
  fi

  printf '%s/.local/state/kxxx/encrypted-file-store.enc\n' "$HOME"
}

kxxx_backend_encrypted_file_key() {
  [[ -n "${KXXX_ENCRYPTED_FILE_KEY:-}" ]] || kxxx_die "KXXX_ENCRYPTED_FILE_KEY is required for backend=encrypted-file"
  printf '%s\n' "$KXXX_ENCRYPTED_FILE_KEY"
}

kxxx_backend_encrypted_file_prepare_store_path() {
  local store_path="$1"
  local store_dir=""

  store_dir="$(dirname "$store_path")"
  mkdir -p "$store_dir" || return 1
}

kxxx_backend_base64_encode() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

kxxx_backend_base64_decode() {
  if base64 --decode >/dev/null 2>&1 <<<'Zg=='; then
    printf '%s' "$1" | base64 --decode
    return 0
  fi

  if base64 -d >/dev/null 2>&1 <<<'Zg=='; then
    printf '%s' "$1" | base64 -d
    return 0
  fi

  printf '%s' "$1" | base64 -D
}

kxxx_backend_encrypted_file_decrypt_to() {
  local destination="$1"
  local store_path=""

  kxxx_require_cmd openssl
  kxxx_backend_encrypted_file_key >/dev/null
  store_path="$(kxxx_backend_encrypted_file_path)"
  kxxx_backend_encrypted_file_prepare_store_path "$store_path" || return 1

  if [[ ! -f "$store_path" ]]; then
    : > "$destination"
    return 0
  fi

  if ! openssl enc -d -aes-256-cbc -pbkdf2 -md sha256 -pass env:KXXX_ENCRYPTED_FILE_KEY -in "$store_path" -out "$destination" 2>/dev/null; then
    kxxx_die "failed to decrypt encrypted-file backend store"
  fi
}

kxxx_backend_encrypted_file_encrypt_from() {
  local source="$1"
  local store_path="" tmp_path=""

  kxxx_require_cmd openssl
  kxxx_backend_encrypted_file_key >/dev/null
  store_path="$(kxxx_backend_encrypted_file_path)"
  kxxx_backend_encrypted_file_prepare_store_path "$store_path" || return 1
  tmp_path="$(mktemp "${store_path}.tmp.XXXXXX")" || return 1

  if ! openssl enc -aes-256-cbc -pbkdf2 -md sha256 -salt -pass env:KXXX_ENCRYPTED_FILE_KEY -in "$source" -out "$tmp_path" 2>/dev/null; then
    rm -f "$tmp_path"
    kxxx_die "failed to encrypt encrypted-file backend store"
  fi

  chmod 600 "$tmp_path" 2>/dev/null || true
  mv "$tmp_path" "$store_path"
}

kxxx_backend_encrypted_file_get() {
  local service="$1" account="$2"
  local tmp_plain="" line="" rec_service="" rec_account="" encoded_value=""

  tmp_plain="$(mktemp)"
  kxxx_backend_encrypted_file_decrypt_to "$tmp_plain"

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    IFS=$'\t' read -r rec_service rec_account encoded_value <<< "$line"
    if [[ "$rec_service" == "$service" && "$rec_account" == "$account" ]]; then
      rm -f "$tmp_plain"
      kxxx_backend_base64_decode "$encoded_value"
      return 0
    fi
  done < "$tmp_plain"

  rm -f "$tmp_plain"
  return 1
}

kxxx_backend_encrypted_file_set() {
  local service="$1" account="$2" value="$3"
  local tmp_plain="" tmp_next="" line="" rec_service="" rec_account="" encoded_value=""

  tmp_plain="$(mktemp)"
  tmp_next="$(mktemp)"
  kxxx_backend_encrypted_file_decrypt_to "$tmp_plain"

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    IFS=$'\t' read -r rec_service rec_account encoded_value <<< "$line"
    if [[ "$rec_service" == "$service" && "$rec_account" == "$account" ]]; then
      continue
    fi
    printf '%s\n' "$line" >> "$tmp_next"
  done < "$tmp_plain"

  printf '%s\t%s\t%s\n' \
    "$service" \
    "$account" \
    "$(kxxx_backend_base64_encode "$value")" >> "$tmp_next"

  kxxx_backend_encrypted_file_encrypt_from "$tmp_next"
  rm -f "$tmp_plain" "$tmp_next"
}

kxxx_backend_encrypted_file_list_accounts() {
  local service="$1"
  local tmp_plain="" line="" rec_service="" rec_account="" encoded_value=""

  tmp_plain="$(mktemp)"
  kxxx_backend_encrypted_file_decrypt_to "$tmp_plain"

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    IFS=$'\t' read -r rec_service rec_account encoded_value <<< "$line"
    [[ "$rec_service" == "$service" ]] || continue
    printf '%s\n' "$rec_account"
  done < "$tmp_plain" | sort -u

  rm -f "$tmp_plain"
}

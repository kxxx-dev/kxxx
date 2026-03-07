#!/usr/bin/env bash
set -euo pipefail

store_file="${KXXX_TEST_SECURITY_STORE:?}"
touch "$store_file"

security_add() {
  local service="" account="" value=""
  local tmp_file="" found=0

  while (($# > 0)); do
    case "$1" in
      -U)
        ;;
      -s)
        shift
        service="$1"
        ;;
      -a)
        shift
        account="$1"
        ;;
      -w)
        shift
        value="$1"
        ;;
    esac
    shift || true
  done

  tmp_file="$(mktemp)"
  while IFS=$'\t' read -r rec_service rec_account rec_value || [[ -n "$rec_service$rec_account$rec_value" ]]; do
    [[ -n "$rec_service$rec_account$rec_value" ]] || continue
    if [[ "$rec_service" == "$service" && "$rec_account" == "$account" ]]; then
      printf '%s\t%s\t%s\n' "$service" "$account" "$value" >>"$tmp_file"
      found=1
    else
      printf '%s\t%s\t%s\n' "$rec_service" "$rec_account" "$rec_value" >>"$tmp_file"
    fi
  done <"$store_file"

  if [[ "$found" -eq 0 ]]; then
    printf '%s\t%s\t%s\n' "$service" "$account" "$value" >>"$tmp_file"
  fi

  mv "$tmp_file" "$store_file"
}

security_find() {
  local service="" account=""

  while (($# > 0)); do
    case "$1" in
      -w)
        ;;
      -s)
        shift
        service="$1"
        ;;
      -a)
        shift
        account="$1"
        ;;
    esac
    shift || true
  done

  while IFS=$'\t' read -r rec_service rec_account rec_value || [[ -n "$rec_service$rec_account$rec_value" ]]; do
    [[ "$rec_service" == "$service" ]] || continue
    [[ "$rec_account" == "$account" ]] || continue
    printf '%s\n' "$rec_value"
    exit 0
  done <"$store_file"

  exit 44
}

security_dump() {
  while IFS=$'\t' read -r rec_service rec_account rec_value || [[ -n "$rec_service$rec_account$rec_value" ]]; do
    [[ -n "$rec_service$rec_account$rec_value" ]] || continue
    printf 'class: "genp"\n'
    printf '    "svce"<blob>="%s"\n' "$rec_service"
    printf '    "acct"<blob>="%s"\n' "$rec_account"
  done <"$store_file"
}

subcommand="${1:-}"
shift || true

case "$subcommand" in
  add-generic-password)
    security_add "$@"
    ;;
  find-generic-password)
    security_find "$@"
    ;;
  dump-keychain)
    security_dump
    ;;
  *)
    exit 64
    ;;
esac

#!/usr/bin/env bash

KXXX_DEFAULT_SERVICE="${KXXX_SERVICE:-kxxx.secrets}"

kxxx_die() {
  echo "kxxx: $*" >&2
  exit 2
}

kxxx_require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || kxxx_die "required command not found: $cmd"
}

kxxx_require_bash_version() {
  if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
    kxxx_die "kxxx requires Bash 4.3 or later"
  fi
}

kxxx_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

kxxx_shell_quote() {
  local value="$1"
  value="${value//\'/\'\"\'\"\'}"
  printf "'%s'" "$value"
}

kxxx_json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

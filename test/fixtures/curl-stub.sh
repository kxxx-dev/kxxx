#!/usr/bin/env bash
set -euo pipefail

output_file=""
config_file=""

while (($# > 0)); do
  case "$1" in
    --output)
      shift
      output_file="$1"
      ;;
    --config)
      shift
      config_file="$1"
      ;;
  esac
  shift || true
done

if [[ -n "${KXXX_TEST_PROVIDER_MARKER:-}" && -n "$config_file" ]]; then
  sed -n 's/^header = \"Authorization: Bearer \(.*\)\"$/\1/p' "$config_file" > "$KXXX_TEST_PROVIDER_MARKER"
fi

if [[ -n "$output_file" ]]; then
  printf '%s' '{"number":42,"html_url":"https://github.com/octo/repo/issues/42"}' > "$output_file"
fi

printf '201'

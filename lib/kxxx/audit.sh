#!/usr/bin/env bash

kxxx_audit_main() {
  local mode="summary" strict=0
  local -a provided_roots=()

  while (($# > 0)); do
    case "$1" in
      --summary)
        mode="summary"
        ;;
      --list)
        mode="list"
        ;;
      --strict)
        strict=1
        ;;
      -h|--help)
        cat <<'USAGE'
Usage: kxxx audit [--summary|--list] [--strict] [paths...]
USAGE
        return 0
        ;;
      *)
        provided_roots+=("$1")
        ;;
    esac
    shift || true
  done

  kxxx_require_cmd rg

  local -a roots=()
  if [[ ${#provided_roots[@]} -gt 0 ]]; then
    roots=("${provided_roots[@]}")
  else
    [[ -d "${HOME}/src" ]] && roots+=("${HOME}/src")
    [[ -d "${HOME}/.config" ]] && roots+=("${HOME}/.config")
  fi

  [[ ${#roots[@]} -gt 0 ]] || kxxx_die "no scan roots available"

  local -a patterns=(
    'AKIA[0-9A-Z]{16}'
    'ASIA[0-9A-Z]{16}'
    'sk-[A-Za-z0-9]{20,}'
    '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----'
    'gh[pousr]_[A-Za-z0-9_]{20,}'
    'github_pat_[A-Za-z0-9_]{20,}'
    'aws(.{0,20})?(secret|access)[^[:alnum:]]{0,3}key[^[:alnum:]]{0,3}[=:][[:space:]]*[A-Za-z0-9/+=]{40}'
  )

  local -a excludes=(
    '.git'
    'node_modules'
    'dist'
    '.next'
    'coverage'
    '.venv'
    'venv'
  )

  local allow_ssh_key="${HOME}/src/ssh/yyykn_work.pem"
  local file_path

  local tmp_matches tmp_filtered
  tmp_matches="$(mktemp)"
  tmp_filtered="$(mktemp)"

  local -a rg_cmd=(rg --line-number --with-filename --no-heading --color=never --hidden --no-ignore)
  local p e
  for p in "${patterns[@]}"; do rg_cmd+=(-e "$p"); done
  for e in "${excludes[@]}"; do rg_cmd+=(--glob "!**/${e}/**"); done
  rg_cmd+=(--)
  rg_cmd+=("${roots[@]}")

  "${rg_cmd[@]}" >"$tmp_matches" || {
    local rc=$?
    if [[ $rc -ne 1 ]]; then
      rm -f "$tmp_matches" "$tmp_filtered"
      return "$rc"
    fi
  }

  if [[ -s "$tmp_matches" ]]; then
    while IFS= read -r line; do
      file_path="${line%%:*}"
      [[ "$file_path" == "$allow_ssh_key" ]] && continue
      printf '%s\n' "$line" >> "$tmp_filtered"
    done < "$tmp_matches"
  fi

  local findings=0 files=0
  if [[ -s "$tmp_filtered" ]]; then
    findings="$(wc -l < "$tmp_filtered" | tr -d '[:space:]')"
    files="$(cut -d: -f1 "$tmp_filtered" | sort -u | wc -l | tr -d '[:space:]')"
  fi

  if [[ "$mode" == "list" && "$findings" -gt 0 ]]; then
    cat "$tmp_filtered"
  fi

  echo "Mode: $mode"
  echo "Strict: $strict"
  echo "Scanned roots: ${roots[*]}"
  echo "Findings: $findings"
  echo "Files with findings: $files"

  if [[ "$strict" -eq 1 && "$findings" -gt 0 ]]; then
    rm -f "$tmp_matches" "$tmp_filtered"
    return 1
  fi

  rm -f "$tmp_matches" "$tmp_filtered"
  return 0
}

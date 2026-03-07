#!/usr/bin/env bash

kxxx_collect_env_map() {
  local service="$1" repo="$2"
  local -n out_ref="$3"
  local -a accounts=()
  declare -A owned_bindings=()
  local account name value
  local global_key repo_key

  kxxx_identity_collect_env_map "$service" "$repo" out_ref owned_bindings
  mapfile -t accounts < <(kxxx_keychain_list_accounts "$service")

  for account in "${accounts[@]}"; do
    if [[ "$account" =~ ^env/([A-Za-z_][A-Za-z0-9_]*)$ ]]; then
      name="${BASH_REMATCH[1]}"
      global_key="global:$name"
      repo_key="repo:$repo:$name"
      [[ -n "${owned_bindings[$global_key]+x}" ]] && continue
      [[ -n "${owned_bindings[$repo_key]+x}" ]] && continue
      if value="$(kxxx_keychain_get "$service" "$account")"; then
        out_ref["$name"]="$value"
      fi
    fi
  done

  for account in "${accounts[@]}"; do
    if [[ "$account" =~ ^app/([^/]+)/([A-Za-z_][A-Za-z0-9_]*)$ ]]; then
      if [[ "${BASH_REMATCH[1]}" == "$repo" ]]; then
        name="${BASH_REMATCH[2]}"
        repo_key="repo:$repo:$name"
        [[ -n "${owned_bindings[$repo_key]+x}" ]] && continue
        if value="$(kxxx_keychain_get "$service" "$account")"; then
          out_ref["$name"]="$value"
        fi
      fi
    fi
  done
}

kxxx_emit_env() {
  local shell="$1"
  local -n env_ref="$2"
  local keys=() k

  for k in "${!env_ref[@]}"; do
    keys+=("$k")
  done
  IFS=$'\n' keys=($(sort <<<"${keys[*]}"))

  case "$shell" in
    zsh|bash)
      for k in "${keys[@]}"; do
        printf 'export %s=%s\n' "$k" "$(kxxx_shell_quote "${env_ref[$k]}")"
      done
      ;;
    dotenv)
      for k in "${keys[@]}"; do
        printf '%s=%s\n' "$k" "$(kxxx_shell_quote "${env_ref[$k]}")"
      done
      ;;
    json)
      local first=1
      printf '{'
      for k in "${keys[@]}"; do
        if [[ $first -eq 0 ]]; then
          printf ','
        fi
        first=0
        printf '"%s":"%s"' "$(kxxx_json_escape "$k")" "$(kxxx_json_escape "${env_ref[$k]}")"
      done
      printf '}\n'
      ;;
    *)
      kxxx_die "unsupported --shell: $shell"
      ;;
  esac
}

kxxx_env_main() {
  local repo="auto" shell="zsh" service="${KXXX_DEFAULT_SERVICE}" strict=0
  while (($# > 0)); do
    case "$1" in
      --repo)
        shift
        [[ $# -gt 0 ]] || kxxx_die "missing value for --repo"
        repo="$1"
        ;;
      --repo=*)
        repo="${1#*=}"
        [[ -n "$repo" ]] || kxxx_die "missing value for --repo"
        ;;
      --shell)
        shift
        [[ $# -gt 0 ]] || kxxx_die "missing value for --shell"
        shell="$1"
        ;;
      --shell=*)
        shell="${1#*=}"
        [[ -n "$shell" ]] || kxxx_die "missing value for --shell"
        ;;
      --service)
        shift
        [[ $# -gt 0 ]] || kxxx_die "missing value for --service"
        service="$1"
        ;;
      --service=*)
        service="${1#*=}"
        [[ -n "$service" ]] || kxxx_die "missing value for --service"
        ;;
      --strict)
        strict=1 ;;
      -h|--help)
        cat <<'USAGE'
Usage: kxxx env [--repo <auto|name>] [--shell <zsh|bash|dotenv|json>] [--service <name>] [--strict]
USAGE
        return 0 ;;
      *)
        kxxx_die "unknown option: $1" ;;
    esac
    shift || true
  done

  if [[ "$repo" == "auto" ]]; then
    repo="$(kxxx_repo_auto)"
  fi

  declare -A env_map=()
  if ! kxxx_collect_env_map "$service" "$repo" env_map; then
    [[ "$strict" -eq 1 ]] && return 1
  fi

  if [[ "${#env_map[@]}" -eq 0 && "$strict" -eq 1 ]]; then
    echo "kxxx: no variables resolved for repo=$repo service=$service" >&2
    return 1
  fi

  kxxx_emit_env "$shell" env_map
}

kxxx_run_main() {
  local repo="auto" service="${KXXX_DEFAULT_SERVICE}"
  while (($# > 0)); do
    case "$1" in
      --repo)
        shift
        [[ $# -gt 0 ]] || kxxx_die "missing value for --repo"
        repo="$1"
        ;;
      --repo=*)
        repo="${1#*=}"
        [[ -n "$repo" ]] || kxxx_die "missing value for --repo"
        ;;
      --service)
        shift
        [[ $# -gt 0 ]] || kxxx_die "missing value for --service"
        service="$1"
        ;;
      --service=*)
        service="${1#*=}"
        [[ -n "$service" ]] || kxxx_die "missing value for --service"
        ;;
      --)
        shift
        break
        ;;
      -h|--help)
        cat <<'USAGE'
Usage: kxxx run [--repo <auto|name>] [--service <name>] -- <command...>
USAGE
        return 0 ;;
      *)
        kxxx_die "unknown option: $1"
        ;;
    esac
    shift || true
  done

  [[ $# -gt 0 ]] || kxxx_die "missing command after --"

  if [[ "$repo" == "auto" ]]; then
    repo="$(kxxx_repo_auto)"
  fi

  declare -A env_map=()
  kxxx_collect_env_map "$service" "$repo" env_map

  declare -a env_args=()
  local key
  for key in "${!env_map[@]}"; do
    env_args+=("${key}=${env_map[$key]}")
  done

  env -- "${env_args[@]}" "$@"
}

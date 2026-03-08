#!/usr/bin/env bash

kxxx_migrate_required_accounts=(
  "env/ZAI_API_KEY"
  "env/LITELLM_MASTER_KEY"
  "env/GITHUB_MCP_TOKEN"
  "aws/maple-ogino/password"
  "aws/maple-ogino/console_login_link"
  "aws/maple-suzuki/password"
  "aws/maple-suzuki/access_key_id"
  "aws/maple-suzuki/secret_access_key"
  "aws/maple-suzuki/console_login_link"
  "aws/maple-ogino/access_key_id"
  "aws/maple-ogino/secret_access_key"
  "github/maple-ogino/recovery_codes"
)

kxxx_migrate_collect_import_accounts() {
  local keys_root="$1"
  local name value row link pw ak sk rc
  local -n accounts_ref="$2"
  local -n values_ref="$3"

  local secrets_file="${HOME}/.config/zsh/secrets.local.zsh"
  local credentials_csv="${keys_root}/credentials.csv"
  local suzuki_csv="${keys_root}/maple-suzuki.csv"
  local ogino_csv="${keys_root}/maplesys_maple-ogino.csv"
  local recovery_file="${keys_root}/maple-ogino.github-recovery-codes.txt"

  if [[ -f "$secrets_file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
      if [[ "$line" =~ ^export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        name="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
      elif [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        name="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
      else
        continue
      fi
      value="$(kxxx_trim "$value")"
      value="${value%\"}"
      value="${value#\"}"
      value="${value%\'}"
      value="${value#\'}"

      case "$name" in
        ZAI_API_KEY|LITELLM_MASTER_KEY|GITHUB_MCP_TOKEN)
          accounts_ref+=("env/${name}")
          values_ref+=("$value")
          ;;
      esac
    done < "$secrets_file"
  fi

  if [[ -f "$credentials_csv" ]]; then
    row="$(awk -F, 'NR==2 {print $2}' "$credentials_csv" | tr -d '\r')"
    link="$(awk -F, 'NR==2 {print $3}' "$credentials_csv" | tr -d '\r')"
    accounts_ref+=("aws/maple-ogino/password" "aws/maple-ogino/console_login_link")
    values_ref+=("$row" "$link")
  fi

  if [[ -f "$suzuki_csv" ]]; then
    pw="$(awk -F, 'NR==2 {print $2}' "$suzuki_csv" | tr -d '\r')"
    ak="$(awk -F, 'NR==2 {print $3}' "$suzuki_csv" | tr -d '\r')"
    sk="$(awk -F, 'NR==2 {print $4}' "$suzuki_csv" | tr -d '\r')"
    link="$(awk -F, 'NR==2 {print $5}' "$suzuki_csv" | tr -d '\r')"
    accounts_ref+=(
      "aws/maple-suzuki/password"
      "aws/maple-suzuki/access_key_id"
      "aws/maple-suzuki/secret_access_key"
      "aws/maple-suzuki/console_login_link"
    )
    values_ref+=("$pw" "$ak" "$sk" "$link")
  fi

  if [[ -f "$ogino_csv" ]]; then
    ak="$(awk -F, 'NR==2 {print $1}' "$ogino_csv" | tr -d '\r')"
    sk="$(awk -F, 'NR==2 {print $2}' "$ogino_csv" | tr -d '\r')"
    accounts_ref+=("aws/maple-ogino/access_key_id" "aws/maple-ogino/secret_access_key")
    values_ref+=("$ak" "$sk")
  fi

  if [[ -f "$recovery_file" ]]; then
    rc="$(awk 'NF {print $0}' "$recovery_file" | tr -d '\r')"
    accounts_ref+=("github/maple-ogino/recovery_codes")
    values_ref+=("$rc")
  fi
}

kxxx_migrate_import_main() {
  local mode="dry-run" service="${KXXX_DEFAULT_SERVICE}" backend="${KXXX_BACKEND:-auto}" keys_root="${HOME}/src/keys"
  while (($# > 0)); do
    case "$1" in
      --dry-run)
        mode="dry-run"
        ;;
      --apply)
        mode="apply"
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
      --backend)
        shift
        [[ $# -gt 0 ]] || kxxx_die "missing value for --backend"
        backend="$1"
        ;;
      --backend=*)
        backend="${1#*=}"
        [[ -n "$backend" ]] || kxxx_die "missing value for --backend"
        ;;
      --keys-root)
        shift
        [[ $# -gt 0 ]] || kxxx_die "missing value for --keys-root"
        keys_root="$1"
        ;;
      --keys-root=*)
        keys_root="${1#*=}"
        [[ -n "$keys_root" ]] || kxxx_die "missing value for --keys-root"
        ;;
      -h|--help)
        cat <<'USAGE'
Usage: kxxx migrate import [--dry-run|--apply] [--service <name>] [--backend <name>] [--keys-root <path>]
USAGE
        return 0
        ;;
      *)
        kxxx_die "unknown option: $1"
        ;;
    esac
    shift || true
  done

  declare -a accounts=()
  declare -a values=()
  kxxx_migrate_collect_import_accounts "$keys_root" accounts values

  local i account value found
  local ready=0 missing=0
  local resolved_backend=""
  resolved_backend="$(kxxx_backend_resolve_cli_name "$backend")" || return 1
  echo "Mode: $mode"
  echo "Service: $service"
  echo "Backend: $resolved_backend"

  for account in "${kxxx_migrate_required_accounts[@]}"; do
    found=0
    for i in "${!accounts[@]}"; do
      if [[ "${accounts[$i]}" == "$account" ]]; then
        value="${values[$i]}"
        if [[ -n "$value" && "$value" != KEYCHAIN_REF:* ]]; then
          echo "  [READY] $account"
          ready=$((ready + 1))
        else
          echo "  [MISSING] $account"
          missing=$((missing + 1))
        fi
        found=1
        break
      fi
    done
    if [[ "$found" -eq 0 ]]; then
      echo "  [MISSING] $account"
      missing=$((missing + 1))
    fi
  done

  echo "Summary: ready=$ready missing=$missing total=${#kxxx_migrate_required_accounts[@]}"

  if [[ "$mode" == "apply" ]]; then
    local imported=0 failed=0
    for i in "${!accounts[@]}"; do
      account="${accounts[$i]}"
      value="${values[$i]}"
      [[ -n "$value" && "$value" != KEYCHAIN_REF:* ]] || continue
      if kxxx_identity_store_descriptor "$service" "$account" "$value" "$resolved_backend"; then
        imported=$((imported + 1))
        echo "[IMPORTED] $account"
      else
        failed=$((failed + 1))
        echo "[FAILED] $account" >&2
      fi
    done
    echo "Apply summary: imported_ok=$imported imported_failed=$failed"
    [[ "$failed" -eq 0 ]]
  fi
}

kxxx_migrate_service_main() {
  local mode="dry-run" from_service="nil.secrets" to_service="${KXXX_DEFAULT_SERVICE}"
  local from_backend="auto" to_backend="auto"
  while (($# > 0)); do
    case "$1" in
      --dry-run)
        mode="dry-run"
        ;;
      --apply)
        mode="apply"
        ;;
      --from)
        shift
        [[ $# -gt 0 ]] || kxxx_die "missing value for --from"
        from_service="$1"
        ;;
      --from=*)
        from_service="${1#*=}"
        [[ -n "$from_service" ]] || kxxx_die "missing value for --from"
        ;;
      --to)
        shift
        [[ $# -gt 0 ]] || kxxx_die "missing value for --to"
        to_service="$1"
        ;;
      --to=*)
        to_service="${1#*=}"
        [[ -n "$to_service" ]] || kxxx_die "missing value for --to"
        ;;
      --from-backend)
        shift
        [[ $# -gt 0 ]] || kxxx_die "missing value for --from-backend"
        from_backend="$1"
        ;;
      --from-backend=*)
        from_backend="${1#*=}"
        [[ -n "$from_backend" ]] || kxxx_die "missing value for --from-backend"
        ;;
      --to-backend)
        shift
        [[ $# -gt 0 ]] || kxxx_die "missing value for --to-backend"
        to_backend="$1"
        ;;
      --to-backend=*)
        to_backend="${1#*=}"
        [[ -n "$to_backend" ]] || kxxx_die "missing value for --to-backend"
        ;;
      -h|--help)
        cat <<'USAGE'
Usage: kxxx migrate service [--from nil.secrets] [--to kxxx.secrets] [--from-backend <name>] [--to-backend <name>] [--dry-run|--apply]
USAGE
        return 0
        ;;
      *)
        kxxx_die "unknown option: $1"
        ;;
    esac
    shift || true
  done

  local resolved_from_backend="" resolved_to_backend=""
  resolved_from_backend="$(kxxx_backend_resolve_cli_name "$from_backend")" || return 1
  resolved_to_backend="$(kxxx_backend_resolve_cli_name "$to_backend")" || return 1

  mapfile -t accounts < <(kxxx_backend_list_accounts "$resolved_from_backend" "$from_service")
  echo "Mode: $mode"
  echo "From: $from_service"
  echo "To: $to_service"
  echo "From backend: $resolved_from_backend"
  echo "To backend: $resolved_to_backend"
  echo "Accounts: ${#accounts[@]}"

  local account value copied=0 failed=0
  for account in "${accounts[@]}"; do
    echo "  [PLAN] $account"
    if [[ "$mode" == "apply" ]]; then
      if value="$(kxxx_backend_get_account "$resolved_from_backend" "$from_service" "$account")" && kxxx_backend_set_account "$resolved_to_backend" "$to_service" "$account" "$value"; then
        copied=$((copied + 1))
      else
        failed=$((failed + 1))
      fi
    fi
  done

  if [[ "$mode" == "apply" ]]; then
    echo "Apply summary: copied=$copied failed=$failed"
    [[ "$failed" -eq 0 ]]
  fi
}

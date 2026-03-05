#!/usr/bin/env bash

kxxx_keychain_set() {
  local service="$1" account="$2" value="$3"
  if command -v security >/dev/null 2>&1; then
    if security add-generic-password -U -s "$service" -a "$account" -w "$value" >/dev/null; then
      return 0
    fi
  fi

  if command -v ks >/dev/null 2>&1; then
    ks rm "$account" >/dev/null 2>&1 || true
    if ks add "$account" "$value" >/dev/null; then
      return 0
    fi
    kxxx_die "failed to set account via ks: $account"
  fi

  kxxx_die "required command not found: security (or ks)"
}

kxxx_keychain_get_raw() {
  local service="$1" account="$2"
  security find-generic-password -w -s "$service" -a "$account" 2>/dev/null
}

kxxx_keychain_get() {
  local service="$1" account="$2" value=""
  if command -v security >/dev/null 2>&1; then
    if value="$(kxxx_keychain_get_raw "$service" "$account")"; then
      printf '%s\n' "$value"
      return 0
    fi
  fi

  if command -v ks >/dev/null 2>&1; then
    if value="$(ks show "$account" 2>/dev/null)"; then
      [[ -n "$value" ]] || return 1
      printf '%s\n' "$value"
      return 0
    fi
  fi

  if ! command -v security >/dev/null 2>&1 && ! command -v ks >/dev/null 2>&1; then
    kxxx_die "required command not found: security (or ks)"
  fi

  return 1
}

kxxx_keychain_list_accounts() {
  local service="$1"
  local security_dump
  if command -v security >/dev/null 2>&1; then
    if security_dump="$(security dump-keychain 2>/dev/null)"; then
      printf '%s\n' "$security_dump" | awk -v svc="$service" '
        function flush_item() {
          if (in_item && item_svc == svc && item_acct != "") {
            print item_acct
          }
          item_svc=""
          item_acct=""
        }
        /^class: / {
          flush_item()
          in_item=1
          next
        }
        {
          if (match($0, /"svce"<blob>="[^"]+"/)) {
            line=substr($0, RSTART, RLENGTH)
            sub(/^"svce"<blob>="/, "", line)
            sub(/"$/, "", line)
            item_svc=line
          }
          if (match($0, /"acct"<blob>="[^"]+"/)) {
            line=substr($0, RSTART, RLENGTH)
            sub(/^"acct"<blob>="/, "", line)
            sub(/"$/, "", line)
            item_acct=line
          }
        }
        END { flush_item() }
      ' | sort -u
      return 0
    fi
  fi

  if command -v ks >/dev/null 2>&1; then
    local -a accounts=()
    local -a matched_accounts=()
    local list_output
    if ! list_output="$(ks ls)"; then
      kxxx_die "failed to list accounts via ks"
    fi
    mapfile -t accounts <<< "$list_output"

    local account
    for account in "${accounts[@]}"; do
      account="${account%$'\r'}"
      [[ "${account#"$service"/}" != "$account" ]] && matched_accounts+=("$account")
    done
    printf '%s\n' "${matched_accounts[@]}" | sort -u
    return 0
  fi

  kxxx_die "required command not found: security (or ks)"
}

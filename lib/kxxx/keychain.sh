#!/usr/bin/env bash

kxxx_keychain_set() {
  local service="$1" account="$2" value="$3"
  kxxx_require_cmd security
  security add-generic-password -U -s "$service" -a "$account" -w "$value" >/dev/null
}

kxxx_keychain_get_raw() {
  local service="$1" account="$2"
  security find-generic-password -w -s "$service" -a "$account" 2>/dev/null
}

kxxx_keychain_get() {
  local service="$1" account="$2" value=""
  kxxx_require_cmd security
  if value="$(kxxx_keychain_get_raw "$service" "$account")"; then
    printf '%s\n' "$value"
    return 0
  fi

  if command -v ks >/dev/null 2>&1; then
    if value="$(ks show "$account" 2>/dev/null)"; then
      [[ -n "$value" ]] || return 1
      printf '%s\n' "$value"
      return 0
    fi
  fi
  return 1
}

kxxx_keychain_list_accounts() {
  local service="$1"
  kxxx_require_cmd security
  security dump-keychain 2>/dev/null | awk -v svc="$service" '
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
}

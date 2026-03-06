#!/usr/bin/env bash

kxxx_broker_home_dir() {
  local user_name=""
  user_name="$(id -un)"

  if command -v dscl >/dev/null 2>&1; then
    local home_dir=""
    home_dir="$(dscl . -read "/Users/${user_name}" NFSHomeDirectory 2>/dev/null | awk '/NFSHomeDirectory:/ {print $2}')"
    if [[ -n "$home_dir" ]]; then
      printf '%s\n' "$home_dir"
      return 0
    fi
  fi

  if command -v getent >/dev/null 2>&1; then
    local home_dir=""
    home_dir="$(getent passwd "$user_name" | cut -d: -f6)"
    if [[ -n "$home_dir" ]]; then
      printf '%s\n' "$home_dir"
      return 0
    fi
  fi

  printf '%s\n' "$HOME"
}

kxxx_broker_curl_config_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '"%s"' "$value"
}

kxxx_broker_json_extract_string() {
  local json="$1" field="$2"

  if [[ "$json" =~ \"$field\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

kxxx_broker_json_extract_number() {
  local json="$1" field="$2"

  if [[ "$json" =~ \"$field\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

kxxx_broker_repo_allowed() {
  local repo="$1" allowlist="$2" item
  local -a allow_items=()
  local old_ifs="$IFS"
  [[ -n "$repo" && -n "$allowlist" ]] || return 1

  IFS=','
  read -r -a allow_items <<< "$allowlist"
  IFS="$old_ifs"

  for item in "${allow_items[@]}"; do
    item="$(kxxx_trim "$item")"
    [[ "$item" == "$repo" ]] && return 0
  done

  return 1
}

kxxx_broker_policy_file() {
  local home_dir=""
  home_dir="$(kxxx_broker_home_dir)"
  printf '%s/.config/kxxx/broker/github.create_issue.repos\n' "$home_dir"
}

kxxx_broker_policy_load_github_create_issue_allow_repos() {
  local policy_file=""
  local line="" first=1

  policy_file="$(kxxx_broker_policy_file)"
  [[ -f "$policy_file" ]] || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(kxxx_trim "$line")"
    [[ -n "$line" ]] || continue
    [[ "$line" == \#* ]] && continue

    if [[ $first -eq 0 ]]; then
      printf ','
    fi
    first=0
    printf '%s' "$line"
  done < "$policy_file"

  [[ $first -eq 0 ]]
}

kxxx_broker_policy_allow() {
  local provider="$1" operation="$2" repo="$3"
  local allowlist=""

  [[ "$provider" == "github" ]] || return 1
  [[ "$operation" == "create_issue" ]] || return 1

  allowlist="$(kxxx_broker_policy_load_github_create_issue_allow_repos)" || return 1
  kxxx_broker_repo_allowed "$repo" "$allowlist"
}

kxxx_broker_emit_event() {
  local status="$1" provider="$2" operation="$3" repo="$4" ref="$5" detail="${6:-}"
  local sink="${KXXX_BROKER_AUDIT_LOG:-}"
  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local event
  event="$(printf '{"ts":"%s","kind":"broker","status":"%s","provider":"%s","operation":"%s","repo":"%s","secret_ref":"%s","detail":"%s"}' \
    "$(kxxx_json_escape "$timestamp")" \
    "$(kxxx_json_escape "$status")" \
    "$(kxxx_json_escape "$provider")" \
    "$(kxxx_json_escape "$operation")" \
    "$(kxxx_json_escape "$repo")" \
    "$(kxxx_json_escape "$ref")" \
    "$(kxxx_json_escape "$detail")")"

  if [[ -n "$sink" ]]; then
    printf '%s\n' "$event" >> "$sink"
  else
    printf '%s\n' "$event" >&2
  fi
}

kxxx_github_http_create_issue() {
  local token="$1" repo="$2" title="$3" body="$4"
  local -n response_ref="$5"
  local -n status_ref="$6"
  local payload tmp_body curl_rc=0

  kxxx_require_cmd curl

  payload="$(printf '{"title":"%s","body":"%s"}' \
    "$(kxxx_json_escape "$title")" \
    "$(kxxx_json_escape "$body")")"
  tmp_body="$(mktemp)"

  status_ref="$(
    curl \
      -q \
      --silent \
      --show-error \
      --output "$tmp_body" \
      --write-out '%{http_code}' \
      --config <(
        printf 'url = %s\n' "$(kxxx_broker_curl_config_escape "https://api.github.com/repos/${repo}/issues")"
        printf 'request = "POST"\n'
        printf 'header = %s\n' "$(kxxx_broker_curl_config_escape 'Accept: application/vnd.github+json')"
        printf 'header = %s\n' "$(kxxx_broker_curl_config_escape "Authorization: Bearer ${token}")"
        printf 'header = %s\n' "$(kxxx_broker_curl_config_escape 'X-GitHub-Api-Version: 2022-11-28')"
        printf 'header = %s\n' "$(kxxx_broker_curl_config_escape 'Content-Type: application/json')"
        printf 'data = %s\n' "$(kxxx_broker_curl_config_escape "$payload")"
      )
  )"
  curl_rc=$?

  response_ref="$(cat "$tmp_body")"
  rm -f "$tmp_body"

  if [[ $curl_rc -ne 0 ]]; then
    return 1
  fi

  [[ "$status_ref" =~ ^2[0-9][0-9]$ ]]
}

kxxx_broker_execute_github_create_issue() {
  local ref="$1" repo="$2" title="$3" body="$4"
  local token="" provider="github" operation="create_issue"
  local response="" http_status="" issue_number="" issue_url=""

  if ! kxxx_broker_policy_allow "$provider" "$operation" "$repo"; then
    kxxx_broker_emit_event "denied" "$provider" "$operation" "$repo" "$ref" "policy_denied"
    echo "kxxx: broker policy denied github.create_issue for repo=$repo" >&2
    return 1
  fi

  if ! kxxx_secret_resolve "$ref" token; then
    kxxx_broker_emit_event "error" "$provider" "$operation" "$repo" "$ref" "secret_ref_unresolved"
    echo "kxxx: secret ref could not be resolved" >&2
    return 1
  fi

  if ! kxxx_github_http_create_issue "$token" "$repo" "$title" "$body" response http_status; then
    kxxx_broker_emit_event "error" "$provider" "$operation" "$repo" "$ref" "provider_request_failed:${http_status:-transport}"
    echo "kxxx: broker provider request failed" >&2
    return 1
  fi

  issue_number="$(kxxx_broker_json_extract_number "$response" "number")"
  issue_url="$(kxxx_broker_json_extract_string "$response" "html_url")"

  kxxx_broker_emit_event "success" "$provider" "$operation" "$repo" "$ref" "http_status:${http_status}"

  printf '{"status":"ok","provider":"github","operation":"create_issue","repo":"%s"' \
    "$(kxxx_json_escape "$repo")"
  if [[ -n "$issue_number" ]]; then
    printf ',"issue_number":%s' "$issue_number"
  fi
  if [[ -n "$issue_url" ]]; then
    printf ',"issue_url":"%s"' "$(kxxx_json_escape "$issue_url")"
  fi
  printf '}\n'
}

kxxx_broker_usage() {
  cat <<'USAGE'
Usage:
  kxxx broker github.create_issue --ref <secret-ref> --repo <owner/repo> --title <title> [--body <body>]

Notes:
  - This MVP only supports github.create_issue.
  - Policy is loaded from ~/.config/kxxx/broker/github.create_issue.repos.
USAGE
}

kxxx_broker_main() {
  local operation="${1:-}" ref="" repo="" title="" body=""
  if [[ $# -eq 0 || "$operation" == "-h" || "$operation" == "--help" || "$operation" == "help" ]]; then
    kxxx_broker_usage
    return 0
  fi
  shift

  while (($# > 0)); do
    case "$1" in
      --ref)
        shift
        [[ $# -gt 0 ]] || kxxx_die "missing value for --ref"
        ref="$1"
        ;;
      --ref=*)
        ref="${1#*=}"
        ;;
      --repo)
        shift
        [[ $# -gt 0 ]] || kxxx_die "missing value for --repo"
        repo="$1"
        ;;
      --repo=*)
        repo="${1#*=}"
        ;;
      --title)
        shift
        [[ $# -gt 0 ]] || kxxx_die "missing value for --title"
        title="$1"
        ;;
      --title=*)
        title="${1#*=}"
        ;;
      --body)
        shift
        [[ $# -gt 0 ]] || kxxx_die "missing value for --body"
        body="$1"
        ;;
      --body=*)
        body="${1#*=}"
        ;;
      -h|--help)
        kxxx_broker_usage
        return 0
        ;;
      --*)
        kxxx_die "unknown option: $1"
        ;;
      *)
        kxxx_die "unexpected argument: $1"
        ;;
    esac
    shift || true
  done

  [[ -n "$ref" ]] || kxxx_die "--ref is required"
  [[ -n "$repo" ]] || kxxx_die "--repo is required"
  [[ -n "$title" ]] || kxxx_die "--title is required"

  case "$operation" in
    github.create_issue)
      kxxx_broker_execute_github_create_issue "$ref" "$repo" "$title" "$body"
      ;;
    *)
      kxxx_die "unsupported broker operation: $operation"
      ;;
  esac
}

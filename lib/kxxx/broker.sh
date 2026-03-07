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
  local repo="$1" allowlist="$2" item=""
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

kxxx_broker_policy_evaluate_github_create_issue() {
  local repo="$1"
  local -n decision_ref="$2"
  local -n reason_ref="$3"
  local -n rule_ref="$4"
  local -n source_ref="$5"
  local allowlist=""

  source_ref="$(kxxx_broker_policy_file)"
  rule_ref="github.create_issue.repo_allowlist_exact"

  if ! allowlist="$(kxxx_broker_policy_load_github_create_issue_allow_repos)"; then
    decision_ref="deny"
    reason_ref="policy_not_configured"
    return 1
  fi

  if kxxx_broker_repo_allowed "$repo" "$allowlist"; then
    decision_ref="allow"
    reason_ref="repo_allowlist_match"
    return 0
  fi

  decision_ref="deny"
  reason_ref="repo_not_allowlisted"
  return 1
}

kxxx_broker_default_audit_log_file() {
  local home_dir=""
  home_dir="$(kxxx_broker_home_dir)"
  printf '%s/.local/state/kxxx/broker.audit.jsonl\n' "$home_dir"
}

kxxx_broker_audit_log_file() {
  if [[ -n "${KXXX_BROKER_AUDIT_LOG:-}" ]]; then
    printf '%s\n' "$KXXX_BROKER_AUDIT_LOG"
    return 0
  fi

  kxxx_broker_default_audit_log_file
}

kxxx_broker_prepare_audit_log_file() {
  local sink="$1"
  local sink_dir=""

  [[ -n "$sink" ]] || return 1

  sink_dir="$(dirname "$sink")"
  mkdir -p "$sink_dir" || return 1
  touch "$sink" || return 1
  chmod 600 "$sink" 2>/dev/null || true
}

kxxx_broker_request_id() {
  kxxx_secret_ref_random_id 8
}

kxxx_broker_secret_backend_for_ref() {
  local ref="$1"
  local backend="" id=""

  if kxxx_secret_ref_parse "$ref" backend id; then
    printf '%s\n' "$backend"
    return 0
  fi

  printf 'unknown\n'
}

kxxx_broker_audit_secret_ref() {
  local ref="$1"
  local backend="" id=""

  if kxxx_secret_ref_parse "$ref" backend id; then
    printf '%s\n' "$ref"
    return 0
  fi

  printf 'invalid_secret_ref\n'
}

kxxx_broker_subject_user() {
  id -un 2>/dev/null || printf 'unknown\n'
}

kxxx_broker_subject_uid() {
  id -u 2>/dev/null || printf 'unknown\n'
}

kxxx_broker_emit_event() {
  local sink="$1" request_id="$2" event_name="$3" provider="$4" operation="$5" resource="$6" ref="$7" extra_fields="${8:-}"
  local timestamp=""
  local subject_user="" subject_uid="" subject_pid="" subject_ppid="" subject_argv0=""
  local event_json=""

  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  subject_user="$(kxxx_broker_subject_user)"
  subject_uid="$(kxxx_broker_subject_uid)"
  subject_pid="$$"
  subject_ppid="${PPID:-unknown}"
  subject_argv0="$0"

  event_json="$(printf '{"ts":"%s","kind":"broker_audit","request_id":"%s","event":"%s","tool":"kxxx","provider":"%s","operation":"%s","resource_type":"github_repo","resource":"%s","secret_ref":"%s","side_effect_class":"external_write","subject_type":"process","subject_user":"%s","subject_uid":"%s","subject_pid":"%s","subject_ppid":"%s","subject_argv0":"%s"' \
    "$(kxxx_json_escape "$timestamp")" \
    "$(kxxx_json_escape "$request_id")" \
    "$(kxxx_json_escape "$event_name")" \
    "$(kxxx_json_escape "$provider")" \
    "$(kxxx_json_escape "$operation")" \
    "$(kxxx_json_escape "$resource")" \
    "$(kxxx_json_escape "$ref")" \
    "$(kxxx_json_escape "$subject_user")" \
    "$(kxxx_json_escape "$subject_uid")" \
    "$(kxxx_json_escape "$subject_pid")" \
    "$(kxxx_json_escape "$subject_ppid")" \
    "$(kxxx_json_escape "$subject_argv0")")"

  if [[ -n "$extra_fields" ]]; then
    event_json="${event_json},${extra_fields}"
  fi

  event_json="${event_json}}"
  printf '%s\n' "$event_json" >> "$sink"
}

kxxx_github_http_create_issue() {
  local token="$1" repo="$2" title="$3" body="$4"
  local -n response_ref="$5"
  local -n status_ref="$6"
  local payload="" tmp_body="" curl_rc=0

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
  local sink="" request_id="" backend="" audit_ref=""
  local policy_decision="" policy_reason="" policy_rule="" policy_source=""
  local extra_fields=""

  sink="$(kxxx_broker_audit_log_file)"
  if ! kxxx_broker_prepare_audit_log_file "$sink"; then
    echo "kxxx: broker audit log write failed" >&2
    return 1
  fi

  audit_ref="$(kxxx_broker_audit_secret_ref "$ref")"
  request_id="$(kxxx_broker_request_id)"
  if ! kxxx_broker_emit_event "$sink" "$request_id" "request_received" "$provider" "$operation" "$repo" "$audit_ref"; then
    echo "kxxx: broker audit log write failed" >&2
    return 1
  fi

  if ! kxxx_broker_policy_evaluate_github_create_issue "$repo" policy_decision policy_reason policy_rule policy_source; then
    extra_fields="$(printf '"decision":"%s","policy_source":"%s","policy_rule":"%s","reason":"%s"' \
      "$(kxxx_json_escape "${policy_decision:-deny}")" \
      "$(kxxx_json_escape "$policy_source")" \
      "$(kxxx_json_escape "$policy_rule")" \
      "$(kxxx_json_escape "$policy_reason")")"
    if ! kxxx_broker_emit_event "$sink" "$request_id" "policy_decision" "$provider" "$operation" "$repo" "$audit_ref" "$extra_fields"; then
      echo "kxxx: broker audit log write failed" >&2
      return 1
    fi
    echo "kxxx: broker policy denied github.create_issue for repo=$repo" >&2
    return 1
  fi

  extra_fields="$(printf '"decision":"%s","policy_source":"%s","policy_rule":"%s","reason":"%s"' \
    "$(kxxx_json_escape "$policy_decision")" \
    "$(kxxx_json_escape "$policy_source")" \
    "$(kxxx_json_escape "$policy_rule")" \
    "$(kxxx_json_escape "$policy_reason")")"
  if ! kxxx_broker_emit_event "$sink" "$request_id" "policy_decision" "$provider" "$operation" "$repo" "$audit_ref" "$extra_fields"; then
    echo "kxxx: broker audit log write failed" >&2
    return 1
  fi

  backend="$(kxxx_broker_secret_backend_for_ref "$ref")"
  extra_fields="$(printf '"backend":"%s","result":"attempted"' \
    "$(kxxx_json_escape "$backend")")"
  if ! kxxx_broker_emit_event "$sink" "$request_id" "secret_backend_access" "$provider" "$operation" "$repo" "$audit_ref" "$extra_fields"; then
    echo "kxxx: broker audit log write failed" >&2
    return 1
  fi

  if ! kxxx_secret_resolve "$ref" token; then
    extra_fields="$(printf '"backend":"%s","result":"unresolved","reason":"secret_ref_unresolved"' \
      "$(kxxx_json_escape "$backend")")"
    if ! kxxx_broker_emit_event "$sink" "$request_id" "secret_resolution" "$provider" "$operation" "$repo" "$audit_ref" "$extra_fields"; then
      echo "kxxx: broker audit log write failed" >&2
      return 1
    fi
    echo "kxxx: secret ref could not be resolved" >&2
    return 1
  fi

  extra_fields="$(printf '"backend":"%s","result":"resolved"' \
    "$(kxxx_json_escape "$backend")")"
  if ! kxxx_broker_emit_event "$sink" "$request_id" "secret_resolution" "$provider" "$operation" "$repo" "$audit_ref" "$extra_fields"; then
    echo "kxxx: broker audit log write failed" >&2
    return 1
  fi

  if ! kxxx_github_http_create_issue "$token" "$repo" "$title" "$body" response http_status; then
    extra_fields="$(printf '"result":"error","http_status":"%s","reason":"provider_request_failed"' \
      "$(kxxx_json_escape "${http_status:-transport}")")"
    if ! kxxx_broker_emit_event "$sink" "$request_id" "provider_result" "$provider" "$operation" "$repo" "$audit_ref" "$extra_fields"; then
      echo "kxxx: broker audit log write failed" >&2
      return 1
    fi
    echo "kxxx: broker provider request failed" >&2
    return 1
  fi

  issue_number="$(kxxx_broker_json_extract_number "$response" "number")"
  issue_url="$(kxxx_broker_json_extract_string "$response" "html_url")"

  extra_fields="$(printf '"result":"success","http_status":"%s"' \
    "$(kxxx_json_escape "$http_status")")"
  if [[ -n "$issue_number" ]]; then
    extra_fields="${extra_fields},$(printf '"issue_number":"%s"' "$(kxxx_json_escape "$issue_number")")"
  fi
  if ! kxxx_broker_emit_event "$sink" "$request_id" "provider_result" "$provider" "$operation" "$repo" "$audit_ref" "$extra_fields"; then
    echo "kxxx: broker audit log write failed" >&2
    return 1
  fi

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

kxxx_broker_audit_usage() {
  cat <<'USAGE'
Usage:
  kxxx broker audit [--file <path>]
USAGE
}

kxxx_broker_audit_main() {
  local file=""

  while (($# > 0)); do
    case "$1" in
      --file)
        shift
        [[ $# -gt 0 ]] || kxxx_die "missing value for --file"
        file="$1"
        ;;
      --file=*)
        file="${1#*=}"
        ;;
      -h|--help)
        kxxx_broker_audit_usage
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

  [[ -n "$file" ]] || file="$(kxxx_broker_audit_log_file)"
  [[ -f "$file" ]] || return 0
  cat "$file"
}

kxxx_broker_usage() {
  cat <<'USAGE'
Usage:
  kxxx broker github.create_issue --ref <secret-ref> --repo <owner/repo> --title <title> [--body <body>]
  kxxx broker audit [--file <path>]

Notes:
  - This MVP only supports github.create_issue.
  - Policy is loaded from ~/.config/kxxx/broker/github.create_issue.repos.
  - Structured broker audit defaults to ~/.local/state/kxxx/broker.audit.jsonl.
USAGE
}

kxxx_broker_main() {
  local operation="${1:-}" ref="" repo="" title="" body=""
  if [[ $# -eq 0 || "$operation" == "-h" || "$operation" == "--help" || "$operation" == "help" ]]; then
    kxxx_broker_usage
    return 0
  fi

  if [[ "$operation" == "audit" ]]; then
    shift
    kxxx_broker_audit_main "$@"
    return $?
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

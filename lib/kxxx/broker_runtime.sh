#!/usr/bin/env bash

kxxx_broker_home_dir() {
  if [[ -n "${KXXX_BROKER_HOME:-}" ]]; then
    printf '%s\n' "$KXXX_BROKER_HOME"
    return 0
  fi

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

kxxx_broker_policy_file_for_operation() {
  local provider="$1" operation="$2"
  local home_dir=""
  home_dir="$(kxxx_broker_home_dir)"
  printf '%s/.config/kxxx/broker/%s.%s.repos\n' "$home_dir" "$provider" "$operation"
}

kxxx_broker_policy_load_allow_repos() {
  local provider="$1" operation="$2"
  local policy_file="" line="" first=1

  policy_file="$(kxxx_broker_policy_file_for_operation "$provider" "$operation")"
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

kxxx_broker_policy_evaluate() {
  local provider="$1" operation="$2" repo="$3"
  local -n decision_ref="$4"
  local -n reason_ref="$5"
  local -n rule_ref="$6"
  local -n source_ref="$7"
  local allowlist=""

  source_ref="$(kxxx_broker_policy_file_for_operation "$provider" "$operation")"
  rule_ref="${provider}.${operation}.repo_allowlist_exact"

  if ! allowlist="$(kxxx_broker_policy_load_allow_repos "$provider" "$operation")"; then
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

kxxx_broker_warn_post_provider_audit_failure() {
  echo "kxxx: broker audit log write failed after provider success" >&2
}

kxxx_broker_format_create_issue() {
  local response="$1" http_status="$2" repo="$3"
  local -n _fmt_audit="$4"
  local -n _fmt_json="$5"
  local issue_number="" issue_url=""

  issue_number="$(kxxx_broker_json_extract_number "$response" "number")"
  issue_url="$(kxxx_broker_json_extract_string "$response" "html_url")"

  _fmt_audit="$(printf '"result":"success","http_status":"%s"' "$(kxxx_json_escape "$http_status")")"
  if [[ -n "$issue_number" ]]; then
    _fmt_audit="${_fmt_audit},$(printf '"issue_number":"%s"' "$(kxxx_json_escape "$issue_number")")"
  fi

  _fmt_json="$(printf '{"status":"ok","provider":"github","operation":"create_issue","repo":"%s"' "$(kxxx_json_escape "$repo")")"
  if [[ -n "$issue_number" ]]; then
    _fmt_json="${_fmt_json}$(printf ',"issue_number":%s' "$issue_number")"
  fi
  if [[ -n "$issue_url" ]]; then
    _fmt_json="${_fmt_json}$(printf ',"issue_url":"%s"' "$(kxxx_json_escape "$issue_url")")"
  fi
  _fmt_json="${_fmt_json}}"
}

kxxx_broker_format_create_issue_comment() {
  local response="$1" http_status="$2" repo="$3"
  local -n _fmt_audit="$4"
  local -n _fmt_json="$5"
  shift 5
  local issue_number="$1"
  local comment_id="" comment_url=""

  comment_id="$(kxxx_broker_json_extract_number "$response" "id")"
  comment_url="$(kxxx_broker_json_extract_string "$response" "html_url")"

  _fmt_audit="$(printf '"result":"success","http_status":"%s"' "$(kxxx_json_escape "$http_status")")"
  if [[ -n "$comment_id" ]]; then
    _fmt_audit="${_fmt_audit},$(printf '"comment_id":"%s"' "$(kxxx_json_escape "$comment_id")")"
  fi

  _fmt_json="$(printf '{"status":"ok","provider":"github","operation":"create_issue_comment","repo":"%s","issue_number":%s' \
    "$(kxxx_json_escape "$repo")" \
    "$issue_number")"
  if [[ -n "$comment_id" ]]; then
    _fmt_json="${_fmt_json}$(printf ',"comment_id":%s' "$comment_id")"
  fi
  if [[ -n "$comment_url" ]]; then
    _fmt_json="${_fmt_json}$(printf ',"comment_url":"%s"' "$(kxxx_json_escape "$comment_url")")"
  fi
  _fmt_json="${_fmt_json}}"
}

kxxx_broker_format_close_issue() {
  local response="$1" http_status="$2" repo="$3"
  local -n _fmt_audit="$4"
  local -n _fmt_json="$5"
  shift 5
  local issue_number="$1"
  local result_number="" issue_url=""

  result_number="$(kxxx_broker_json_extract_number "$response" "number")"
  issue_url="$(kxxx_broker_json_extract_string "$response" "html_url")"

  _fmt_audit="$(printf '"result":"success","http_status":"%s"' "$(kxxx_json_escape "$http_status")")"
  if [[ -n "$result_number" ]]; then
    _fmt_audit="${_fmt_audit},$(printf '"issue_number":"%s"' "$(kxxx_json_escape "$result_number")")"
  fi

  _fmt_json="$(printf '{"status":"ok","provider":"github","operation":"close_issue","repo":"%s","issue_number":%s' \
    "$(kxxx_json_escape "$repo")" \
    "$issue_number")"
  if [[ -n "$issue_url" ]]; then
    _fmt_json="${_fmt_json}$(printf ',"issue_url":"%s"' "$(kxxx_json_escape "$issue_url")")"
  fi
  _fmt_json="${_fmt_json}}"
}

kxxx_broker_execute() {
  local provider="$1" operation="$2" service="$3" ref="$4" repo="$5"
  local provider_fn="$6" result_fn="$7"
  shift 7

  local token="" _bx_response="" _bx_http_status=""
  local sink="" request_id="" backend="" impl_backend="" audit_ref=""
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

  if ! kxxx_broker_policy_evaluate "$provider" "$operation" "$repo" policy_decision policy_reason policy_rule policy_source; then
    extra_fields="$(printf '"decision":"%s","policy_source":"%s","policy_rule":"%s","reason":"%s"' \
      "$(kxxx_json_escape "${policy_decision:-deny}")" \
      "$(kxxx_json_escape "$policy_source")" \
      "$(kxxx_json_escape "$policy_rule")" \
      "$(kxxx_json_escape "$policy_reason")")"
    if ! kxxx_broker_emit_event "$sink" "$request_id" "policy_decision" "$provider" "$operation" "$repo" "$audit_ref" "$extra_fields"; then
      echo "kxxx: broker audit log write failed" >&2
      return 1
    fi
    echo "kxxx: broker policy denied ${provider}.${operation} for repo=$repo" >&2
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
  if ! impl_backend="$(kxxx_backend_impl_name_for_ref_backend "$backend" 2>/dev/null)"; then
    impl_backend="unknown"
  fi
  extra_fields="$(printf '"backend":"%s","result":"attempted"' \
    "$(kxxx_json_escape "$backend")")"
  if ! kxxx_broker_emit_event "$sink" "$request_id" "secret_backend_access" "$provider" "$operation" "$repo" "$audit_ref" "$extra_fields"; then
    echo "kxxx: broker audit log write failed" >&2
    return 1
  fi

  if [[ "$impl_backend" != "memory" && "$impl_backend" != "unknown" && -z "$service" ]]; then
    extra_fields="$(printf '"backend":"%s","result":"unresolved","reason":"service_required_for_backend_ref"' \
      "$(kxxx_json_escape "$backend")")"
    if ! kxxx_broker_emit_event "$sink" "$request_id" "secret_resolution" "$provider" "$operation" "$repo" "$audit_ref" "$extra_fields"; then
      echo "kxxx: broker audit log write failed" >&2
      return 1
    fi
    echo "kxxx: --service is required for backend-managed secret refs" >&2
    return 1
  fi

  if ! token="$(kxxx_backend_get_ref "$service" "$ref")"; then
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

  if ! "$provider_fn" "$token" "$repo" "$@" _bx_response _bx_http_status; then
    extra_fields="$(printf '"result":"error","http_status":"%s","reason":"provider_request_failed"' \
      "$(kxxx_json_escape "${_bx_http_status:-transport}")")"
    if ! kxxx_broker_emit_event "$sink" "$request_id" "provider_result" "$provider" "$operation" "$repo" "$audit_ref" "$extra_fields"; then
      echo "kxxx: broker audit log write failed" >&2
      return 1
    fi
    echo "kxxx: broker provider request failed" >&2
    return 1
  fi

  local _result_audit="" _result_json=""
  "$result_fn" "$_bx_response" "$_bx_http_status" "$repo" _result_audit _result_json "$@"

  if ! kxxx_broker_emit_event "$sink" "$request_id" "provider_result" "$provider" "$operation" "$repo" "$audit_ref" "$_result_audit"; then
    kxxx_broker_warn_post_provider_audit_failure
  fi

  printf '%s\n' "$_result_json"
}

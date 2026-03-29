#!/usr/bin/env bash

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

kxxx_github_http_request() {
  local token="$1" method="$2" url="$3" payload="$4"
  local -n _gh_resp_ref="$5"
  local -n _gh_stat_ref="$6"
  local tmp_body="" curl_rc=0

  kxxx_require_cmd curl

  tmp_body="$(mktemp)"

  _gh_stat_ref="$(
    curl \
      -q \
      --silent \
      --show-error \
      --output "$tmp_body" \
      --write-out '%{http_code}' \
      --config <(
        printf 'url = %s\n' "$(kxxx_broker_curl_config_escape "$url")"
        printf 'request = "%s"\n' "$method"
        printf 'header = %s\n' "$(kxxx_broker_curl_config_escape 'Accept: application/vnd.github+json')"
        printf 'header = %s\n' "$(kxxx_broker_curl_config_escape "Authorization: Bearer ${token}")"
        printf 'header = %s\n' "$(kxxx_broker_curl_config_escape 'X-GitHub-Api-Version: 2022-11-28')"
        printf 'header = %s\n' "$(kxxx_broker_curl_config_escape 'Content-Type: application/json')"
        printf 'data = %s\n' "$(kxxx_broker_curl_config_escape "$payload")"
      )
  )"
  curl_rc=$?

  _gh_resp_ref="$(cat "$tmp_body")"
  rm -f "$tmp_body"

  if [[ $curl_rc -ne 0 ]]; then
    return 1
  fi

  [[ "$_gh_stat_ref" =~ ^2[0-9][0-9]$ ]]
}

kxxx_github_http_create_issue() {
  local token="$1" repo="$2" title="$3" body="$4"
  local _resp_var="$5" _stat_var="$6"
  local payload=""

  payload="$(printf '{"title":"%s","body":"%s"}' \
    "$(kxxx_json_escape "$title")" \
    "$(kxxx_json_escape "$body")")"

  kxxx_github_http_request "$token" "POST" \
    "https://api.github.com/repos/${repo}/issues" \
    "$payload" "$_resp_var" "$_stat_var"
}

kxxx_github_http_create_issue_comment() {
  local token="$1" repo="$2" issue_number="$3" body="$4"
  local _resp_var="$5" _stat_var="$6"
  local payload=""

  payload="$(printf '{"body":"%s"}' \
    "$(kxxx_json_escape "$body")")"

  kxxx_github_http_request "$token" "POST" \
    "https://api.github.com/repos/${repo}/issues/${issue_number}/comments" \
    "$payload" "$_resp_var" "$_stat_var"
}

kxxx_github_http_close_issue() {
  local token="$1" repo="$2" issue_number="$3"
  local _resp_var="$4" _stat_var="$5"
  local payload='{"state":"closed"}'

  kxxx_github_http_request "$token" "PATCH" \
    "https://api.github.com/repos/${repo}/issues/${issue_number}" \
    "$payload" "$_resp_var" "$_stat_var"
}

#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ./test_helper.bash

setup() {
  kxxx_test_reset_state
  export KXXX_BROKER_AUDIT_LOG
  KXXX_BROKER_AUDIT_LOG="$(mktemp)"
  export KXXX_TEST_PROVIDER_MARKER
  KXXX_TEST_PROVIDER_MARKER="$(mktemp)"
  : > "$KXXX_TEST_PROVIDER_MARKER"
}

teardown() {
  rm -f "$KXXX_BROKER_AUDIT_LOG" "$KXXX_TEST_PROVIDER_MARKER"
  unset KXXX_BROKER_AUDIT_LOG KXXX_TEST_PROVIDER_MARKER
  unset -f \
    kxxx_broker_policy_load_github_create_issue_allow_repos \
    kxxx_github_http_create_issue || true
}

@test "github.create_issue succeeds without exposing the secret" {
  local secret="github_pat_super_secret_value_123456789"
  local ref=""
  local audit_contents=""

  kxxx_secret_memory_store "$secret" "success-ref" ref

  kxxx_broker_policy_load_github_create_issue_allow_repos() {
    printf '%s' "octo/repo"
  }

  kxxx_github_http_create_issue() {
    local token="$1" repo="$2" title="$3" body="$4"
    local -n response_ref="$5"
    local -n status_ref="$6"

    printf '%s' "$token" > "$KXXX_TEST_PROVIDER_MARKER"
    [[ "$repo" == "octo/repo" ]]
    [[ "$title" == "hello" ]]
    [[ "$body" == "body" ]]
    response_ref='{"number":42,"html_url":"https://github.com/octo/repo/issues/42"}'
    status_ref="201"
    return 0
  }

  run --separate-stderr kxxx_broker_main github.create_issue --ref "$ref" --repo octo/repo --title "hello" --body "body"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *'"issue_number":42'* ]]
  [[ "$output" == *'"issue_url":"https://github.com/octo/repo/issues/42"'* ]]
  [[ "$output" != *"$secret"* ]]
  [[ -z "$stderr" ]]
  [[ "$(cat "$KXXX_TEST_PROVIDER_MARKER")" == "$secret" ]]

  audit_contents="$(cat "$KXXX_BROKER_AUDIT_LOG")"
  [[ "$audit_contents" == *'"status":"success"'* ]]
  [[ "$audit_contents" == *'"provider":"github"'* ]]
  [[ "$audit_contents" == *'"operation":"create_issue"'* ]]
  [[ "$audit_contents" == *'"repo":"octo/repo"'* ]]
  [[ "$audit_contents" != *"$secret"* ]]
}

@test "policy deny blocks provider execution" {
  local secret="github_pat_secret_for_deny_123456789"
  local ref=""
  local audit_contents=""

  kxxx_secret_memory_store "$secret" "deny-ref" ref

  kxxx_broker_policy_load_github_create_issue_allow_repos() {
    printf '%s' "octo/allowed"
  }

  kxxx_github_http_create_issue() {
    printf 'called' > "$KXXX_TEST_PROVIDER_MARKER"
    return 99
  }

  run --separate-stderr kxxx_broker_main github.create_issue --ref "$ref" --repo octo/denied --title "blocked"

  [ "$status" -ne 0 ]
  [[ -z "$output" ]]
  [[ "$stderr" == *'broker policy denied github.create_issue for repo=octo/denied'* ]]
  [[ "$stderr" != *"$secret"* ]]
  [[ ! -s "$KXXX_TEST_PROVIDER_MARKER" ]]

  audit_contents="$(cat "$KXXX_BROKER_AUDIT_LOG")"
  [[ "$audit_contents" == *'"status":"denied"'* ]]
  [[ "$audit_contents" == *'"detail":"policy_denied"'* ]]
  [[ "$audit_contents" != *"$secret"* ]]
}

@test "unknown SecretRef fails without leaking the secret" {
  local secret="github_pat_unused_secret_123456789"
  local known_ref=""
  local audit_contents=""

  kxxx_secret_memory_store "$secret" "known-ref" known_ref

  kxxx_broker_policy_load_github_create_issue_allow_repos() {
    printf '%s' "octo/repo"
  }

  run --separate-stderr kxxx_broker_main github.create_issue --ref "secretref:v1:memory:missing-ref" --repo octo/repo --title "hello"

  [ "$status" -ne 0 ]
  [[ -z "$output" ]]
  [[ "$stderr" == *'secret ref could not be resolved'* ]]
  [[ "$stderr" != *"$secret"* ]]

  audit_contents="$(cat "$KXXX_BROKER_AUDIT_LOG")"
  [[ "$audit_contents" == *'"status":"error"'* ]]
  [[ "$audit_contents" == *'"detail":"secret_ref_unresolved"'* ]]
  [[ "$audit_contents" != *"$secret"* ]]
}

@test "provider failure stays inside the broker boundary" {
  local secret="github_pat_provider_failure_secret_123456789"
  local upstream_leak="github_pat_upstream_should_not_leak"
  local ref=""
  local audit_contents=""

  kxxx_secret_memory_store "$secret" "provider-failure-ref" ref

  kxxx_broker_policy_load_github_create_issue_allow_repos() {
    printf '%s' "octo/repo"
  }

  kxxx_github_http_create_issue() {
    local token="$1"
    local -n response_ref="$5"
    local -n status_ref="$6"

    printf '%s' "$token" > "$KXXX_TEST_PROVIDER_MARKER"
    response_ref="{\"message\":\"provider failed\",\"debug\":\"${upstream_leak}\"}"
    status_ref="500"
    return 1
  }

  run --separate-stderr kxxx_broker_main github.create_issue --ref "$ref" --repo octo/repo --title "hello"

  [ "$status" -ne 0 ]
  [[ -z "$output" ]]
  [[ "$stderr" == *'broker provider request failed'* ]]
  [[ "$stderr" != *"$secret"* ]]
  [[ "$stderr" != *"$upstream_leak"* ]]
  [[ "$(cat "$KXXX_TEST_PROVIDER_MARKER")" == "$secret" ]]

  audit_contents="$(cat "$KXXX_BROKER_AUDIT_LOG")"
  [[ "$audit_contents" == *'"status":"error"'* ]]
  [[ "$audit_contents" == *'"detail":"provider_request_failed:500"'* ]]
  [[ "$audit_contents" != *"$secret"* ]]
}

@test "github HTTP transport disables user curl config with -q" {
  local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
  local response=""
  local status_code=""

  mkdir -p "$fake_bin"
  cat >"$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s' "$1" >"$KXXX_TEST_PROVIDER_MARKER"

output_file=""
while (($# > 0)); do
  case "$1" in
    --output)
      shift
      output_file="$1"
      ;;
  esac
  shift || true
done

printf '%s' '{"number":7,"html_url":"https://github.com/octo/repo/issues/7"}' >"$output_file"
printf '201'
EOF
  chmod +x "$fake_bin/curl"

  PATH="$fake_bin:$PATH" kxxx_github_http_create_issue "secret-token" "octo/repo" "hello" "body" response status_code

  [[ "$(cat "$KXXX_TEST_PROVIDER_MARKER")" == "-q" ]]
  [[ "$status_code" == "201" ]]
  [[ "$response" == *'"number":7'* ]]
}

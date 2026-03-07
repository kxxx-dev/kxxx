#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load ./test_helper.bash

broker_test_default_audit_log() {
  printf '%s/.local/state/kxxx/broker.audit.jsonl' "$KXXX_TEST_HOME"
}

broker_test_json_string() {
  local json="$1" field="$2"

  if [[ "$json" =~ \"$field\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

broker_test_load_audit_lines() {
  local audit_file="$1"
  mapfile -t BROKER_TEST_AUDIT_LINES < "$audit_file"
}

broker_test_assert_no_leaks() {
  local haystack="$1"
  shift

  local secret=""
  for secret in "$@"; do
    [[ "$haystack" != *"$secret"* ]]
  done
}

setup() {
  kxxx_test_reset_state
  export KXXX_TEST_PROVIDER_MARKER
  KXXX_TEST_PROVIDER_MARKER="$(mktemp)"
  export KXXX_TEST_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$KXXX_TEST_HOME"
  : > "$KXXX_TEST_PROVIDER_MARKER"
  unset KXXX_BROKER_AUDIT_LOG

  kxxx_broker_home_dir() {
    printf '%s' "$KXXX_TEST_HOME"
  }
}

teardown() {
  rm -f "$KXXX_TEST_PROVIDER_MARKER"
  rm -rf "$KXXX_TEST_HOME"
  unset KXXX_BROKER_AUDIT_LOG KXXX_TEST_PROVIDER_MARKER KXXX_TEST_HOME
  unset -f \
    kxxx_broker_home_dir \
    kxxx_broker_emit_event \
    kxxx_broker_policy_load_github_create_issue_allow_repos \
    kxxx_github_http_create_issue || true
}

@test "top-level help distinguishes safe path from compatibility path" {
  run "$ROOT_DIR/bin/kxxx" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Modes:"* ]]
  [[ "$output" == *"Safe path: \`kxxx broker ...\` is the preferred path for new integrations"* ]]
  [[ "$output" == *"Compatibility path: \`kxxx get\`, \`kxxx env\`, and \`kxxx run\` can materialize raw secrets"* ]]
  [[ "$output" == *"Threat model and invariants: https://github.com/kxxx-dev/kxxx/blob/main/docs/adr/0001-agent-safe-secret-runtime.md"* ]]
}

@test "broker help keeps MVP scope and links to the canonical invariants" {
  run "$ROOT_DIR/bin/kxxx" broker --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"\`broker\` is the preferred safe path for new integrations."* ]]
  [[ "$output" == *"This MVP only supports github.create_issue."* ]]
  [[ "$output" == *"Compatibility-path commands (\`get\`, \`env\`, \`run\`) can materialize raw secret values"* ]]
  [[ "$output" == *"Canonical threat model: https://github.com/kxxx-dev/kxxx/blob/main/docs/adr/0001-agent-safe-secret-runtime.md"* ]]
}

@test "github.create_issue emits structured audit sequence without exposing the secret" {
  local secret="github_pat_super_secret_value_123456789"
  local ref=""
  local audit_path=""
  local policy_file="$KXXX_TEST_HOME/.config/kxxx/broker/github.create_issue.repos"
  local request_id=""
  local combined_output=""

  kxxx_secret_memory_store "$secret" "success-ref" ref
  mkdir -p "$(dirname "$policy_file")"
  printf '%s\n' "octo/repo" > "$policy_file"

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
  [[ -z "$stderr" ]]
  [[ "$(cat "$KXXX_TEST_PROVIDER_MARKER")" == "$secret" ]]

  audit_path="$(broker_test_default_audit_log)"
  [ -f "$audit_path" ]
  broker_test_load_audit_lines "$audit_path"
  [ "${#BROKER_TEST_AUDIT_LINES[@]}" -eq 5 ]

  request_id="$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[0]}" "request_id")"
  [[ -n "$request_id" ]]

  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[0]}" "event")" == "request_received" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[1]}" "event")" == "policy_decision" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[2]}" "event")" == "secret_backend_access" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[3]}" "event")" == "secret_resolution" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[4]}" "event")" == "provider_result" ]]

  local line=""
  for line in "${BROKER_TEST_AUDIT_LINES[@]}"; do
    [[ "$(broker_test_json_string "$line" "kind")" == "broker_audit" ]]
    [[ "$(broker_test_json_string "$line" "request_id")" == "$request_id" ]]
    [[ "$(broker_test_json_string "$line" "tool")" == "kxxx" ]]
    [[ "$(broker_test_json_string "$line" "provider")" == "github" ]]
    [[ "$(broker_test_json_string "$line" "operation")" == "create_issue" ]]
    [[ "$(broker_test_json_string "$line" "resource_type")" == "github_repo" ]]
    [[ "$(broker_test_json_string "$line" "resource")" == "octo/repo" ]]
    [[ "$(broker_test_json_string "$line" "secret_ref")" == "$ref" ]]
    [[ "$(broker_test_json_string "$line" "side_effect_class")" == "external_write" ]]
    [[ "$(broker_test_json_string "$line" "subject_type")" == "process" ]]
    [[ -n "$(broker_test_json_string "$line" "subject_user")" ]]
    [[ -n "$(broker_test_json_string "$line" "subject_uid")" ]]
    [[ -n "$(broker_test_json_string "$line" "subject_pid")" ]]
    [[ -n "$(broker_test_json_string "$line" "subject_ppid")" ]]
    [[ -n "$(broker_test_json_string "$line" "subject_argv0")" ]]
  done

  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[1]}" "decision")" == "allow" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[1]}" "reason")" == "repo_allowlist_match" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[2]}" "backend")" == "memory" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[2]}" "result")" == "attempted" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[3]}" "backend")" == "memory" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[3]}" "result")" == "resolved" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[4]}" "result")" == "success" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[4]}" "http_status")" == "201" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[4]}" "issue_number")" == "42" ]]

  combined_output="$(printf '%s\n%s\n%s' "$output" "$stderr" "$(cat "$audit_path")")"
  broker_test_assert_no_leaks "$combined_output" "$secret"
}

@test "github.create_issue resolves keychain refs when service is provided" {
  local secret="github_pat_keychain_secret_value_123456789"
  local ref="secretref:v1:keychain:broker-ref"
  local audit_path="$BATS_TEST_TMPDIR/keychain-success.jsonl"
  local policy_file="$KXXX_TEST_HOME/.config/kxxx/broker/github.create_issue.repos"
  local combined_output=""

  export KXXX_BROKER_AUDIT_LOG="$audit_path"
  mkdir -p "$(dirname "$policy_file")"
  printf '%s\n' "octo/repo" > "$policy_file"

  kxxx_keychain_get_ref() {
    local service="$1" ref_arg="$2"
    [[ "$service" == "test.secrets" ]]
    [[ "$ref_arg" == "$ref" ]]
    printf '%s\n' "$secret"
  }

  kxxx_github_http_create_issue() {
    local token="$1"
    local -n response_ref="$5"
    local -n status_ref="$6"

    printf '%s' "$token" > "$KXXX_TEST_PROVIDER_MARKER"
    response_ref='{"number":52,"html_url":"https://github.com/octo/repo/issues/52"}'
    status_ref="201"
    return 0
  }

  run --separate-stderr kxxx_broker_main github.create_issue --service test.secrets --ref "$ref" --repo octo/repo --title "hello"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *'"issue_number":52'* ]]
  [[ "$output" == *'"issue_url":"https://github.com/octo/repo/issues/52"'* ]]
  [[ -z "$stderr" ]]
  [[ "$(cat "$KXXX_TEST_PROVIDER_MARKER")" == "$secret" ]]

  broker_test_load_audit_lines "$audit_path"
  [ "${#BROKER_TEST_AUDIT_LINES[@]}" -eq 5 ]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[2]}" "backend")" == "keychain" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[3]}" "backend")" == "keychain" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[3]}" "result")" == "resolved" ]]

  combined_output="$(printf '%s\n%s\n%s' "$output" "$stderr" "$(cat "$audit_path")")"
  broker_test_assert_no_leaks "$combined_output" "$secret"
}

@test "keychain secret refs require --service" {
  local ref="secretref:v1:keychain:missing-service"
  local audit_path="$BATS_TEST_TMPDIR/keychain-missing-service.jsonl"
  local policy_file="$KXXX_TEST_HOME/.config/kxxx/broker/github.create_issue.repos"

  export KXXX_BROKER_AUDIT_LOG="$audit_path"
  mkdir -p "$(dirname "$policy_file")"
  printf '%s\n' "octo/repo" > "$policy_file"

  kxxx_keychain_get_ref() {
    printf 'called' > "$KXXX_TEST_PROVIDER_MARKER"
    return 99
  }

  run --separate-stderr kxxx_broker_main github.create_issue --ref "$ref" --repo octo/repo --title "hello"

  [ "$status" -ne 0 ]
  [[ -z "$output" ]]
  [[ "$stderr" == *'--service is required for keychain secret refs'* ]]
  [[ ! -s "$KXXX_TEST_PROVIDER_MARKER" ]]

  broker_test_load_audit_lines "$audit_path"
  [ "${#BROKER_TEST_AUDIT_LINES[@]}" -eq 4 ]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[2]}" "backend")" == "keychain" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[3]}" "reason")" == "service_required_for_keychain_ref" ]]
}

@test "policy deny blocks secret resolution and provider execution" {
  local secret="github_pat_secret_for_deny_123456789"
  local ref=""
  local audit_path="$BATS_TEST_TMPDIR/policy-deny.jsonl"
  local policy_file="$KXXX_TEST_HOME/.config/kxxx/broker/github.create_issue.repos"
  local combined_output=""

  export KXXX_BROKER_AUDIT_LOG="$audit_path"
  kxxx_secret_memory_store "$secret" "deny-ref" ref
  mkdir -p "$(dirname "$policy_file")"
  printf '%s\n' "octo/allowed" > "$policy_file"

  kxxx_github_http_create_issue() {
    printf 'called' > "$KXXX_TEST_PROVIDER_MARKER"
    return 99
  }

  run --separate-stderr kxxx_broker_main github.create_issue --ref "$ref" --repo octo/denied --title "blocked"

  [ "$status" -ne 0 ]
  [[ -z "$output" ]]
  [[ "$stderr" == *'broker policy denied github.create_issue for repo=octo/denied'* ]]
  [[ ! -s "$KXXX_TEST_PROVIDER_MARKER" ]]

  broker_test_load_audit_lines "$audit_path"
  [ "${#BROKER_TEST_AUDIT_LINES[@]}" -eq 2 ]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[0]}" "event")" == "request_received" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[1]}" "event")" == "policy_decision" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[1]}" "decision")" == "deny" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[1]}" "reason")" == "repo_not_allowlisted" ]]

  combined_output="$(printf '%s\n%s\n%s' "$output" "$stderr" "$(cat "$audit_path")")"
  broker_test_assert_no_leaks "$combined_output" "$secret"
}

@test "unknown SecretRef is audited as unresolved without calling the provider" {
  local secret="github_pat_unused_secret_123456789"
  local known_ref=""
  local audit_path="$BATS_TEST_TMPDIR/unknown-ref.jsonl"
  local policy_file="$KXXX_TEST_HOME/.config/kxxx/broker/github.create_issue.repos"
  local combined_output=""

  export KXXX_BROKER_AUDIT_LOG="$audit_path"
  kxxx_secret_memory_store "$secret" "known-ref" known_ref
  mkdir -p "$(dirname "$policy_file")"
  printf '%s\n' "octo/repo" > "$policy_file"

  kxxx_github_http_create_issue() {
    printf 'called' > "$KXXX_TEST_PROVIDER_MARKER"
    return 99
  }

  run --separate-stderr kxxx_broker_main github.create_issue --ref "secretref:v1:memory:missing-ref" --repo octo/repo --title "hello"

  [ "$status" -ne 0 ]
  [[ -z "$output" ]]
  [[ "$stderr" == *'secret ref could not be resolved'* ]]
  [[ ! -s "$KXXX_TEST_PROVIDER_MARKER" ]]

  broker_test_load_audit_lines "$audit_path"
  [ "${#BROKER_TEST_AUDIT_LINES[@]}" -eq 4 ]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[0]}" "event")" == "request_received" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[1]}" "event")" == "policy_decision" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[1]}" "decision")" == "allow" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[2]}" "event")" == "secret_backend_access" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[2]}" "backend")" == "memory" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[2]}" "result")" == "attempted" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[3]}" "event")" == "secret_resolution" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[3]}" "result")" == "unresolved" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[3]}" "reason")" == "secret_ref_unresolved" ]]

  combined_output="$(printf '%s\n%s\n%s' "$output" "$stderr" "$(cat "$audit_path")")"
  broker_test_assert_no_leaks "$combined_output" "$secret"
}

@test "provider failure is audited without leaking upstream secret-looking content" {
  local secret="github_pat_provider_failure_secret_123456789"
  local upstream_leak="github_pat_upstream_should_not_leak"
  local ref=""
  local audit_path="$BATS_TEST_TMPDIR/provider-failure.jsonl"
  local policy_file="$KXXX_TEST_HOME/.config/kxxx/broker/github.create_issue.repos"
  local combined_output=""

  export KXXX_BROKER_AUDIT_LOG="$audit_path"
  kxxx_secret_memory_store "$secret" "provider-failure-ref" ref
  mkdir -p "$(dirname "$policy_file")"
  printf '%s\n' "octo/repo" > "$policy_file"

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
  [[ "$(cat "$KXXX_TEST_PROVIDER_MARKER")" == "$secret" ]]

  broker_test_load_audit_lines "$audit_path"
  [ "${#BROKER_TEST_AUDIT_LINES[@]}" -eq 5 ]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[4]}" "event")" == "provider_result" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[4]}" "result")" == "error" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[4]}" "http_status")" == "500" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[4]}" "reason")" == "provider_request_failed" ]]

  combined_output="$(printf '%s\n%s\n%s' "$output" "$stderr" "$(cat "$audit_path")")"
  broker_test_assert_no_leaks "$combined_output" "$secret" "$upstream_leak"
}

@test "provider success remains successful if the final audit append fails" {
  local secret="github_pat_success_audit_failure_secret_123456789"
  local ref=""
  local policy_file="$KXXX_TEST_HOME/.config/kxxx/broker/github.create_issue.repos"

  kxxx_secret_memory_store "$secret" "success-audit-failure-ref" ref
  mkdir -p "$(dirname "$policy_file")"
  printf '%s\n' "octo/repo" > "$policy_file"

  kxxx_github_http_create_issue() {
    local token="$1"
    local -n response_ref="$5"
    local -n status_ref="$6"

    printf '%s' "$token" > "$KXXX_TEST_PROVIDER_MARKER"
    response_ref='{"number":77,"html_url":"https://github.com/octo/repo/issues/77"}'
    status_ref="201"
    return 0
  }

  kxxx_broker_emit_event() {
    local event_name="$3"

    if [[ "$event_name" == "provider_result" ]]; then
      return 1
    fi

    return 0
  }

  run --separate-stderr kxxx_broker_main github.create_issue --ref "$ref" --repo octo/repo --title "hello"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *'"issue_number":77'* ]]
  [[ "$stderr" == *'broker audit log write failed after provider success'* ]]
  [[ "$(cat "$KXXX_TEST_PROVIDER_MARKER")" == "$secret" ]]
  broker_test_assert_no_leaks "$(printf '%s\n%s' "$output" "$stderr")" "$secret"
}

@test "invalid secret-like ref input is redacted from structured audit" {
  local raw_ref="github_pat_not_a_secretref_but_should_not_be_logged"
  local audit_path="$BATS_TEST_TMPDIR/invalid-ref.jsonl"
  local policy_file="$KXXX_TEST_HOME/.config/kxxx/broker/github.create_issue.repos"
  local combined_output=""

  export KXXX_BROKER_AUDIT_LOG="$audit_path"
  mkdir -p "$(dirname "$policy_file")"
  printf '%s\n' "octo/repo" > "$policy_file"

  kxxx_github_http_create_issue() {
    printf 'called' > "$KXXX_TEST_PROVIDER_MARKER"
    return 99
  }

  run --separate-stderr kxxx_broker_main github.create_issue --ref "$raw_ref" --repo octo/repo --title "hello"

  [ "$status" -ne 0 ]
  [[ -z "$output" ]]
  [[ "$stderr" == *'secret ref could not be resolved'* ]]
  [[ ! -s "$KXXX_TEST_PROVIDER_MARKER" ]]

  broker_test_load_audit_lines "$audit_path"
  [ "${#BROKER_TEST_AUDIT_LINES[@]}" -eq 4 ]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[0]}" "secret_ref")" == "invalid_secret_ref" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[2]}" "backend")" == "unknown" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[3]}" "secret_ref")" == "invalid_secret_ref" ]]
  [[ "$(broker_test_json_string "${BROKER_TEST_AUDIT_LINES[3]}" "result")" == "unresolved" ]]

  combined_output="$(printf '%s\n%s\n%s' "$output" "$stderr" "$(cat "$audit_path")")"
  broker_test_assert_no_leaks "$combined_output" "$raw_ref"
}

@test "broker audit exports the default structured audit sink" {
  local secret="github_pat_audit_export_secret_123456789"
  local ref=""
  local audit_path=""

  local policy_file="$KXXX_TEST_HOME/.config/kxxx/broker/github.create_issue.repos"
  kxxx_secret_memory_store "$secret" "export-default-ref" ref
  mkdir -p "$(dirname "$policy_file")"
  printf '%s\n' "octo/repo" > "$policy_file"

  kxxx_github_http_create_issue() {
    local -n response_ref="$5"
    local -n status_ref="$6"

    response_ref='{"number":9,"html_url":"https://github.com/octo/repo/issues/9"}'
    status_ref="201"
    return 0
  }

  run --separate-stderr kxxx_broker_main github.create_issue --ref "$ref" --repo octo/repo --title "hello"
  [ "$status" -eq 0 ]

  audit_path="$(broker_test_default_audit_log)"
  run kxxx_broker_main audit

  [ "$status" -eq 0 ]
  [[ "$output" == "$(cat "$audit_path")" ]]
}

@test "broker audit supports explicit file override and missing files" {
  local explicit_file="$BATS_TEST_TMPDIR/explicit-broker-audit.jsonl"
  local missing_file="$BATS_TEST_TMPDIR/missing-broker-audit.jsonl"

  printf '%s\n' '{"kind":"broker_audit","event":"request_received"}' > "$explicit_file"

  run kxxx_broker_main audit --file "$explicit_file"

  [ "$status" -eq 0 ]
  [[ "$output" == '{"kind":"broker_audit","event":"request_received"}' ]]

  run kxxx_broker_main audit --file "$missing_file"

  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
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

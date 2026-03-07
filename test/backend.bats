#!/usr/bin/env bats

load ./test_helper.bash

setup() {
  export KXXX_BIN="$BATS_TEST_DIRNAME/../bin/kxxx"
  export KXXX_TEST_HOME="$BATS_TEST_TMPDIR/home"
  export KXXX_TEST_BIN="$BATS_TEST_TMPDIR/bin"
  export KXXX_TEST_SECURITY_STORE="$BATS_TEST_TMPDIR/security-store.tsv"
  export KXXX_ORIG_PATH="$PATH"
  export KXXX_TEST_PROVIDER_MARKER=""

  mkdir -p "$KXXX_TEST_HOME" "$KXXX_TEST_BIN"
  : > "$KXXX_TEST_SECURITY_STORE"
  cp "$BATS_TEST_DIRNAME/fixtures/security-stub.sh" "$KXXX_TEST_BIN/security"
  cp "$BATS_TEST_DIRNAME/fixtures/curl-stub.sh" "$KXXX_TEST_BIN/curl"
  chmod +x "$KXXX_TEST_BIN/security" "$KXXX_TEST_BIN/curl"
  kxxx_test_reset_state
}

run_kxxx_linux_encrypted() {
  run env \
    HOME="$KXXX_TEST_HOME" \
    KXXX_BROKER_HOME="$KXXX_TEST_HOME" \
    PATH="$KXXX_TEST_BIN:$KXXX_ORIG_PATH" \
    OSTYPE="linux-gnu" \
    KXXX_ENCRYPTED_FILE_KEY="test-master-key" \
    "$KXXX_BIN" \
    "$@"
}

run_kxxx_keychain_override() {
  run env \
    HOME="$KXXX_TEST_HOME" \
    KXXX_BROKER_HOME="$KXXX_TEST_HOME" \
    PATH="$KXXX_TEST_BIN:$KXXX_ORIG_PATH" \
    KXXX_BACKEND="encrypted-file" \
    KXXX_ENCRYPTED_FILE_KEY="test-master-key" \
    "$KXXX_BIN" \
    "$@"
}

run_kxxx_default() {
  run env \
    HOME="$KXXX_TEST_HOME" \
    KXXX_BROKER_HOME="$KXXX_TEST_HOME" \
    PATH="$KXXX_TEST_BIN:$KXXX_ORIG_PATH" \
    "$KXXX_BIN" \
    "$@"
}

seed_keychain_account() {
  local service="$1" account="$2" value="$3"
  printf '%s\t%s\t%s\n' "$service" "$account" "$value" >> "$KXXX_TEST_SECURITY_STORE"
}

@test "memory backend remains available for same-process dispatcher tests" {
  local ref=""

  kxxx_backend_memory_set "test.secrets" "env/MEMORY_ONLY" "alpha"
  [ "$(kxxx_backend_memory_get "test.secrets" "env/MEMORY_ONLY")" = "alpha" ]

  ref="$(kxxx_backend_create_ref memory "memory-ref")"
  [ "$ref" = "secretref:v1:memory:memory-ref" ]

  kxxx_backend_set_ref "test.secrets" "$ref" "beta"
  [ "$(kxxx_backend_get_ref "test.secrets" "$ref")" = "beta" ]

  run bash -lc 'printf "%s\n" "${KXXX_MEMORY_BACKEND_STORE[*]-}"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "auto selects encrypted-file for non-darwin environments and supports env/run flows" {
  local encrypted_file="$KXXX_TEST_HOME/.local/state/kxxx/encrypted-file-store.enc"

  run_kxxx_linux_encrypted set env/API_TOKEN --service test.secrets --value encrypted-value
  [ "$status" -eq 0 ]
  [ -f "$encrypted_file" ]

  run_kxxx_linux_encrypted get env/API_TOKEN --service test.secrets
  [ "$status" -eq 0 ]
  [ "$output" = "encrypted-value" ]

  run_kxxx_linux_encrypted list --service test.secrets --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"env/API_TOKEN"'* ]]

  run_kxxx_linux_encrypted env --service test.secrets --repo demo --shell json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"API_TOKEN":"encrypted-value"'* ]]

  run_kxxx_linux_encrypted run --service test.secrets --repo demo -- /bin/sh -c 'printf "%s" "${API_TOKEN:-}"'
  [ "$status" -eq 0 ]
  [ "$output" = "encrypted-value" ]
}

@test "explicit backend flag overrides env and auto selection" {
  run_kxxx_keychain_override set env/OVERRIDE_TOKEN --service test.secrets --backend darwin-keychain --value from-keychain
  [ "$status" -eq 0 ]

  run cat "$KXXX_TEST_SECURITY_STORE"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'test.secrets\tref/'* ]]

  run_kxxx_keychain_override get env/OVERRIDE_TOKEN --service test.secrets --backend darwin-keychain
  [ "$status" -eq 0 ]
  [ "$output" = "from-keychain" ]
}

@test "read flows enforce the selected backend for indexed descriptors" {
  run_kxxx_keychain_override set env/ISOLATED_TOKEN --service test.secrets --backend darwin-keychain --value keychain-value
  [ "$status" -eq 0 ]

  run_kxxx_linux_encrypted get env/ISOLATED_TOKEN --service test.secrets --backend encrypted-file
  [ "$status" -ne 0 ]

  run_kxxx_linux_encrypted env --service test.secrets --repo demo --backend encrypted-file --shell json
  [ "$status" -eq 0 ]
  [[ "$output" != *"ISOLATED_TOKEN"* ]]
}

@test "resetting an existing descriptor honors a new backend selection" {
  local secret_ref=""

  run_kxxx_keychain_override set env/MOVE_TOKEN --service test.secrets --backend darwin-keychain --value keychain-value
  [ "$status" -eq 0 ]

  run_kxxx_linux_encrypted set env/MOVE_TOKEN --service test.secrets --backend encrypted-file --value encrypted-value
  [ "$status" -eq 0 ]

  run_kxxx_linux_encrypted ref env/MOVE_TOKEN --service test.secrets --backend encrypted-file
  [ "$status" -eq 0 ]
  secret_ref="$output"
  [[ "$secret_ref" == secretref:v1:encrypted-file:* ]]

  run_kxxx_linux_encrypted get env/MOVE_TOKEN --service test.secrets --backend encrypted-file
  [ "$status" -eq 0 ]
  [ "$output" = "encrypted-value" ]
}

@test "migrate import can write secrets through encrypted-file backend" {
  mkdir -p "$KXXX_TEST_HOME/.config/zsh" "$BATS_TEST_TMPDIR/keys"
  printf '%s\n' 'export GITHUB_MCP_TOKEN=from-encrypted-import' > "$KXXX_TEST_HOME/.config/zsh/secrets.local.zsh"

  run_kxxx_linux_encrypted migrate import --apply --service test.secrets --backend encrypted-file --keys-root "$BATS_TEST_TMPDIR/keys"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[IMPORTED] env/GITHUB_MCP_TOKEN"* ]]

  run_kxxx_linux_encrypted get env/GITHUB_MCP_TOKEN --service test.secrets --backend encrypted-file
  [ "$status" -eq 0 ]
  [ "$output" = "from-encrypted-import" ]
}

@test "migrate service copies accounts from darwin-keychain to encrypted-file" {
  seed_keychain_account "legacy.secrets" "env/LEGACY_TOKEN" "legacy-value"

  run_kxxx_linux_encrypted migrate service --from legacy.secrets --to modern.secrets --from-backend darwin-keychain --to-backend encrypted-file --apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"Apply summary: copied=1 failed=0"* ]]

  run_kxxx_linux_encrypted get env/LEGACY_TOKEN --service modern.secrets --backend encrypted-file
  [ "$status" -eq 0 ]
  [ "$output" = "legacy-value" ]
}

@test "broker resolves encrypted-file-backed refs without exposing the secret" {
  local policy_file="$KXXX_TEST_HOME/.config/kxxx/broker/github.create_issue.repos"
  local provider_marker="$BATS_TEST_TMPDIR/provider-token"
  local secret_ref=""

  mkdir -p "$(dirname "$policy_file")"
  printf '%s\n' "octo/repo" > "$policy_file"
  export KXXX_TEST_PROVIDER_MARKER="$provider_marker"

  run_kxxx_linux_encrypted set env/GITHUB_TOKEN --service test.secrets --backend encrypted-file --value broker-secret
  [ "$status" -eq 0 ]

  run_kxxx_linux_encrypted ref env/GITHUB_TOKEN --service test.secrets --backend encrypted-file
  [ "$status" -eq 0 ]
  secret_ref="$output"
  [[ "$secret_ref" == secretref:v1:encrypted-file:* ]]

  run_kxxx_linux_encrypted broker github.create_issue --service test.secrets --ref "$secret_ref" --repo octo/repo --title "hello" --body "body"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" != *'broker-secret'* ]]
  [ "$(cat "$provider_marker")" = "broker-secret" ]
}

@test "unsupported backends fail with a clear error" {
  run_kxxx_default set env/NOPE --service test.secrets --backend secret-service --value value
  [ "$status" -eq 2 ]
  [[ "$output" == *"backend is declared but not implemented yet: secret-service"* ]]

  run_kxxx_default set env/NOPE --service test.secrets --backend wincred --value value
  [ "$status" -eq 2 ]
  [[ "$output" == *"backend is declared but not implemented yet: wincred"* ]]
}

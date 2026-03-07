#!/usr/bin/env bats

setup() {
  export KXXX_BIN="$BATS_TEST_DIRNAME/../bin/kxxx"
  export KXXX_TEST_HOME="$BATS_TEST_TMPDIR/home"
  export KXXX_TEST_BIN="$BATS_TEST_TMPDIR/bin"
  export KXXX_TEST_SECURITY_STORE="$BATS_TEST_TMPDIR/security-store.tsv"
  export KXXX_ORIG_PATH="$PATH"

  mkdir -p "$KXXX_TEST_HOME" "$KXXX_TEST_BIN"
  : > "$KXXX_TEST_SECURITY_STORE"
  cp "$BATS_TEST_DIRNAME/fixtures/security-stub.sh" "$KXXX_TEST_BIN/security"
  chmod +x "$KXXX_TEST_BIN/security"
}

seed_legacy_account() {
  local service="$1" account="$2" value="$3"
  printf '%s\t%s\t%s\n' "$service" "$account" "$value" >> "$KXXX_TEST_SECURITY_STORE"
}

index_file() {
  printf '%s/.local/state/kxxx/secret-index.tsv' "$KXXX_TEST_HOME"
}

single_ref_account() {
  awk -F '\t' -v svc="$1" '$1 == svc && $2 ~ /^ref\// {print $2}' "$KXXX_TEST_SECURITY_STORE"
}

run_kxxx() {
  run env HOME="$KXXX_TEST_HOME" KXXX_BROKER_HOME="$KXXX_TEST_HOME" KXXX_BACKEND="darwin-keychain" PATH="$KXXX_TEST_BIN:$KXXX_ORIG_PATH" "$KXXX_BIN" "$@"
}

install_curl_stub() {
  cp "$BATS_TEST_DIRNAME/fixtures/curl-stub.sh" "$KXXX_TEST_BIN/curl"
  chmod +x "$KXXX_TEST_BIN/curl"
}

test_set_stores_new_values_under_an_opaque_ref_and_records_the_descriptor_mapping() { #@test
  run_kxxx set env/OPENAI_API_KEY --service test.secrets --value secret-one
  [ "$status" -eq 0 ]

  run cat "$KXXX_TEST_SECURITY_STORE"
  [ "$status" -eq 0 ]
  [[ "$output" != *$'test.secrets\tenv/OPENAI_API_KEY\t'* ]]
  [[ "$output" == *$'test.secrets\tref/'* ]]

  run cat "$(index_file)"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'test.secrets\tsecretref:v1:keychain:'* ]]
  [[ "$output" == *$'\tenv/OPENAI_API_KEY\tglobal\t\tOPENAI_API_KEY'* ]]
}

test_repeated_set_reuses_the_same_opaque_ref_for_a_descriptor() { #@test
  run_kxxx set env/OPENAI_API_KEY --service test.secrets --value first-value
  [ "$status" -eq 0 ]
  first_ref="$(single_ref_account test.secrets)"

  run_kxxx set env/OPENAI_API_KEY --service test.secrets --value second-value
  [ "$status" -eq 0 ]
  second_ref="$(single_ref_account test.secrets)"

  [ "$first_ref" = "$second_ref" ]

  run_kxxx get env/OPENAI_API_KEY --service test.secrets
  [ "$status" -eq 0 ]
  [ "$output" = "second-value" ]
}

test_get_prefers_indexed_refs_and_still_resolves_legacy_direct_accounts() { #@test
  run_kxxx set env/OPENAI_API_KEY --service test.secrets --value indexed-value
  [ "$status" -eq 0 ]

  seed_legacy_account test.secrets env/OPENAI_API_KEY legacy-shadow
  seed_legacy_account test.secrets env/LEGACY_ONLY legacy-only

  run_kxxx get env/OPENAI_API_KEY --service test.secrets
  [ "$status" -eq 0 ]
  [ "$output" = "indexed-value" ]

  run_kxxx get env/LEGACY_ONLY --service test.secrets
  [ "$status" -eq 0 ]
  [ "$output" = "legacy-only" ]
}

test_stale_indexed_refs_do_not_fall_back_to_legacy_direct_accounts() { #@test
  run_kxxx set env/OPENAI_API_KEY --service test.secrets --value indexed-value
  [ "$status" -eq 0 ]

  seed_legacy_account test.secrets env/OPENAI_API_KEY legacy-shadow
  awk -F '\t' '!($1 == "test.secrets" && index($2, "ref/") == 1)' "$KXXX_TEST_SECURITY_STORE" > "$KXXX_TEST_SECURITY_STORE.tmp"
  mv "$KXXX_TEST_SECURITY_STORE.tmp" "$KXXX_TEST_SECURITY_STORE"

  run_kxxx get env/OPENAI_API_KEY --service test.secrets
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

test_list_shows_logical_descriptors_and_legacy_accounts_but_hides_internal_ref_accounts() { #@test
  run_kxxx set env/OPENAI_API_KEY --service test.secrets --value indexed-value
  [ "$status" -eq 0 ]
  run_kxxx set aws/maple/password --service test.secrets --value aws-secret
  [ "$status" -eq 0 ]

  seed_legacy_account test.secrets env/LEGACY_ONLY legacy-only
  seed_legacy_account test.secrets ref/orphan should-hide

  run_kxxx list --service test.secrets --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"env/OPENAI_API_KEY"'* ]]
  [[ "$output" == *'"aws/maple/password"'* ]]
  [[ "$output" == *'"env/LEGACY_ONLY"'* ]]
  [[ "$output" != *'"ref/orphan"'* ]]
}

test_env_and_run_use_indexed_bindings_first_and_legacy_bindings_as_fallback() { #@test
  run_kxxx set env/GLOBAL_TOKEN --service test.secrets --value indexed-global
  [ "$status" -eq 0 ]
  run_kxxx set app/demo/REPO_TOKEN --service test.secrets --value indexed-repo
  [ "$status" -eq 0 ]

  seed_legacy_account test.secrets env/GLOBAL_TOKEN legacy-shadow
  seed_legacy_account test.secrets env/LEGACY_ONLY legacy-only

  run_kxxx env --service test.secrets --repo demo --shell json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"GLOBAL_TOKEN":"indexed-global"'* ]]
  [[ "$output" == *'"REPO_TOKEN":"indexed-repo"'* ]]
  [[ "$output" == *'"LEGACY_ONLY":"legacy-only"'* ]]

  run_kxxx run --service test.secrets --repo demo -- /bin/sh -c 'printf "%s|%s|%s" "${GLOBAL_TOKEN:-}" "${REPO_TOKEN:-}" "${LEGACY_ONLY:-}"'
  [ "$status" -eq 0 ]
  [ "$output" = "indexed-global|indexed-repo|legacy-only" ]
}

test_legacy_repo_bindings_override_indexed_globals_when_no_indexed_repo_binding_exists() { #@test
  run_kxxx set env/SHARED_TOKEN --service test.secrets --value indexed-global
  [ "$status" -eq 0 ]

  seed_legacy_account test.secrets app/demo/SHARED_TOKEN legacy-repo

  run_kxxx env --service test.secrets --repo demo --shell json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"SHARED_TOKEN":"legacy-repo"'* ]]

  run_kxxx run --service test.secrets --repo demo -- /bin/sh -c 'printf "%s" "${SHARED_TOKEN:-}"'
  [ "$status" -eq 0 ]
  [ "$output" = "legacy-repo" ]
}

test_migrate_import_apply_writes_imported_secrets_through_opaque_refs_instead_of_raw_env_accounts() { #@test
  mkdir -p "$KXXX_TEST_HOME/.config/zsh"
  printf '%s\n' 'export GITHUB_MCP_TOKEN=from-dotfile' > "$KXXX_TEST_HOME/.config/zsh/secrets.local.zsh"
  mkdir -p "$BATS_TEST_TMPDIR/keys"

  run_kxxx migrate import --apply --service test.secrets --keys-root "$BATS_TEST_TMPDIR/keys"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[IMPORTED] env/GITHUB_MCP_TOKEN"* ]]

  run cat "$KXXX_TEST_SECURITY_STORE"
  [ "$status" -eq 0 ]
  [[ "$output" != *$'test.secrets\tenv/GITHUB_MCP_TOKEN\t'* ]]
  [[ "$output" == *$'test.secrets\tref/'* ]]

  run cat "$(index_file)"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\tenv/GITHUB_MCP_TOKEN\tglobal\t\tGITHUB_MCP_TOKEN'* ]]

  run_kxxx get env/GITHUB_MCP_TOKEN --service test.secrets
  [ "$status" -eq 0 ]
  [ "$output" = "from-dotfile" ]
}

test_ref_returns_the_managed_secret_ref() { #@test
  run_kxxx set env/GITHUB_TOKEN --service test.secrets --value broker-secret
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run_kxxx ref env/GITHUB_TOKEN --service test.secrets --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *'"service":"test.secrets"'* ]]
  [[ "$output" == *'"account":"env/GITHUB_TOKEN"'* ]]
  [[ "$output" == *'"secret_ref":"secretref:v1:keychain:'* ]]
}

test_broker_resolves_keychain_secret_refs_from_ref_without_exposing_the_secret() { #@test
  local policy_file="$KXXX_TEST_HOME/.config/kxxx/broker/github.create_issue.repos"
  local provider_marker="$BATS_TEST_TMPDIR/provider-token"
  local secret_ref=""

  install_curl_stub
  export KXXX_TEST_PROVIDER_MARKER="$provider_marker"
  mkdir -p "$(dirname "$policy_file")"
  printf '%s\n' "octo/repo" > "$policy_file"

  run_kxxx set env/GITHUB_TOKEN --service test.secrets --value broker-secret
  [ "$status" -eq 0 ]

  run_kxxx ref env/GITHUB_TOKEN --service test.secrets
  [ "$status" -eq 0 ]
  secret_ref="$output"
  [[ "$secret_ref" == secretref:v1:keychain:* ]]

  run_kxxx broker github.create_issue --service test.secrets --ref "$secret_ref" --repo octo/repo --title "hello" --body "body"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status":"ok"'* ]]
  [[ "$output" == *'"provider":"github"'* ]]
  [[ "$output" == *'"operation":"create_issue"'* ]]
  [[ "$output" == *'"repo":"octo/repo"'* ]]
  [[ "$output" == *'"issue_number":42'* ]]
  [[ "$output" == *'"issue_url":"https://github.com/octo/repo/issues/42"'* ]]
  [[ "$output" != *'broker-secret'* ]]
  [[ "$(cat "$provider_marker")" == "broker-secret" ]]
}

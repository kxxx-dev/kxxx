#!/usr/bin/env bash

if [[ -n "${BATS_TEST_DIRNAME:-}" ]]; then
  ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
else
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

kxxx_test_require_bash_version() {
  local required_major=4 required_minor=3
  local current_major="${BASH_VERSINFO[0]:-0}" current_minor="${BASH_VERSINFO[1]:-0}"

  if (( current_major > required_major || (current_major == required_major && current_minor >= required_minor) )); then
    return 0
  fi

  cat >&2 <<'EOF'
kxxx tests require Bash 4.3 or later.

macOS `bats` can pick `/bin/bash` 3.2 for `#!/usr/bin/env bash` test files even when Homebrew Bash is installed.
Run the suite with `bin/test`, or prepend a modern Bash to PATH before running `bats test`.
EOF
  exit 1
}

kxxx_test_require_bash_version

# shellcheck source=/dev/null
source "$ROOT_DIR/lib/kxxx/common.sh"
# shellcheck source=/dev/null
source "$ROOT_DIR/lib/kxxx/secret_ref.sh"
# shellcheck source=/dev/null
source "$ROOT_DIR/lib/kxxx/keychain.sh"
# shellcheck source=/dev/null
source "$ROOT_DIR/lib/kxxx/backend_memory.sh"
# shellcheck source=/dev/null
source "$ROOT_DIR/lib/kxxx/backend_encrypted_file.sh"
# shellcheck source=/dev/null
source "$ROOT_DIR/lib/kxxx/backend.sh"
# shellcheck source=/dev/null
source "$ROOT_DIR/lib/kxxx/broker.sh"

kxxx_test_reset_state() {
  kxxx_secret_memory_reset
  kxxx_backend_memory_reset
}

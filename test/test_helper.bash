#!/usr/bin/env bash

if [[ -n "${BATS_TEST_DIRNAME:-}" ]]; then
  ROOT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
else
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# shellcheck source=/dev/null
source "$ROOT_DIR/lib/kxxx/common.sh"
# shellcheck source=/dev/null
source "$ROOT_DIR/lib/kxxx/secret_ref.sh"
# shellcheck source=/dev/null
source "$ROOT_DIR/lib/kxxx/broker.sh"

kxxx_test_reset_state() {
  kxxx_secret_memory_reset
}

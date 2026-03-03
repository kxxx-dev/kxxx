#!/usr/bin/env bash

kxxx_repo_auto() {
  local root
  if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    basename "$root"
    return 0
  fi
  basename "$PWD"
}

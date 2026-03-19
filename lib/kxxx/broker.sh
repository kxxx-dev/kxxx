#!/usr/bin/env bash

_kxxx_broker_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_kxxx_broker_dir}/provider_github.sh"
# shellcheck source=/dev/null
source "${_kxxx_broker_dir}/broker_runtime.sh"
unset _kxxx_broker_dir

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
  kxxx broker github.create_issue [--service <name>] --ref <secret-ref> --repo <owner/repo> --title <title> [--body <body>]
  kxxx broker audit [--file <path>]

Notes:
  - `broker` is the preferred safe path for new integrations.
  - This MVP only supports github.create_issue.
  - Compatibility-path commands (`get`, `env`, `run`) can materialize raw secret values and remain explicit exceptions.
  - Policy is loaded from ~/.config/kxxx/broker/github.create_issue.repos.
  - Structured broker audit defaults to ~/.local/state/kxxx/broker.audit.jsonl.
  - Canonical threat model: https://github.com/kxxx-dev/kxxx/blob/main/docs/adr/0001-agent-safe-secret-runtime.md
USAGE
}

kxxx_broker_main() {
  local operation="${1:-}" service="" ref="" repo="" title="" body=""
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
      --service)
        shift
        [[ $# -gt 0 ]] || kxxx_die "missing value for --service"
        service="$1"
        ;;
      --service=*)
        service="${1#*=}"
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
      kxxx_broker_execute_github_create_issue "$service" "$ref" "$repo" "$title" "$body"
      ;;
    *)
      kxxx_die "unsupported broker operation: $operation"
      ;;
  esac
}

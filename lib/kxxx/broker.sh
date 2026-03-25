#!/usr/bin/env bash

_kxxx_broker_source_path="${BASH_SOURCE[0]}"
while [ -L "$_kxxx_broker_source_path" ]; do
  _kxxx_broker_link_dir="$(cd "$(dirname "$_kxxx_broker_source_path")" && pwd)"
  _kxxx_broker_source_path="$(readlink "$_kxxx_broker_source_path")"
  [[ "$_kxxx_broker_source_path" != /* ]] && _kxxx_broker_source_path="${_kxxx_broker_link_dir}/$_kxxx_broker_source_path"
done

_kxxx_broker_dir="$(cd "$(dirname "$_kxxx_broker_source_path")" && pwd)"
# shellcheck source=/dev/null
source "${_kxxx_broker_dir}/provider_github.sh" || return 1
# shellcheck source=/dev/null
source "${_kxxx_broker_dir}/broker_runtime.sh" || return 1
unset _kxxx_broker_dir _kxxx_broker_link_dir _kxxx_broker_source_path

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
  kxxx broker github.create_issue_comment [--service <name>] --ref <secret-ref> --repo <owner/repo> --issue <number> --body <body>
  kxxx broker audit [--file <path>]

Notes:
  - `broker` is the preferred safe path for new integrations.
  - Supported operations: github.create_issue, github.create_issue_comment.
  - Compatibility-path commands (`get`, `env`, `run`) can materialize raw secret values and remain explicit exceptions.
  - Policy is loaded from ~/.config/kxxx/broker/github.create_issue.repos.
  - Policy is loaded from ~/.config/kxxx/broker/github.create_issue_comment.repos.
  - Structured broker audit defaults to ~/.local/state/kxxx/broker.audit.jsonl.
  - Canonical threat model: https://github.com/kxxx-dev/kxxx/blob/main/docs/adr/0001-agent-safe-secret-runtime.md
USAGE
}

kxxx_broker_main() {
  local operation="${1:-}" service="" ref="" repo="" title="" body="" issue=""
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
      --issue)
        shift
        [[ $# -gt 0 ]] || kxxx_die "missing value for --issue"
        issue="$1"
        ;;
      --issue=*)
        issue="${1#*=}"
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

  case "$operation" in
    github.create_issue)
      [[ -n "$title" ]] || kxxx_die "--title is required"
      kxxx_broker_execute_github_create_issue "$service" "$ref" "$repo" "$title" "$body"
      ;;
    github.create_issue_comment)
      [[ -n "$issue" ]] || kxxx_die "--issue is required"
      [[ -n "$body" ]] || kxxx_die "--body is required"
      kxxx_broker_execute_github_create_issue_comment "$service" "$ref" "$repo" "$issue" "$body"
      ;;
    *)
      kxxx_die "unsupported broker operation: $operation"
      ;;
  esac
}

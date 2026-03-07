# Safe Path MVP Brief

This slice adds the first brokered safe path to `kxxx` without changing the legacy compatibility commands.

The canonical threat model and v1 security invariants live in [ADR 0001: Agent-safe secret runtime](adr/0001-agent-safe-secret-runtime.md). This brief is intentionally narrower: it describes the current MVP boundary and should not be treated as the source of truth for broader security policy or long-term non-goals.

## What It Adds

- provider: GitHub
- operation: `github.create_issue`
- `SecretRef`: opaque identity in the form `secretref:v1:<backend>:<id>`
- supported refs: `kxxx`-managed `secretref:v1:keychain:<id>` for CLI-visible flows and `secretref:v1:memory:<id>` for tests/internal spikes
- minimum policy gate: provider must be `github`, operation must be `create_issue`, and repo must be allowlisted
- minimal audit trail: sanitized structured broker events with no raw secret material

## Runtime Boundary

The caller provides only a `SecretRef` plus the brokered operation arguments.
`kxxx` checks policy at the broker boundary, resolves the raw secret internally, and performs the provider call behind that boundary.
The broker result and structured audit events never include the raw secret.

This MVP implements the ADR invariants that the safe path keeps raw secret material behind the broker boundary, treats compatibility-path commands as explicit exceptions, and evaluates policy before secret resolution when policy exists.
Compatibility-path commands still exist, but they are not part of this safe-path boundary.

`kxxx broker audit` exports the broker runtime JSONL log from `~/.local/state/kxxx/broker.audit.jsonl` by default.
If `KXXX_BROKER_AUDIT_LOG` or `--file <path>` is provided, that path is used instead.
This is separate from the legacy `kxxx audit` command, which remains a filesystem secret scanner.

## Request Shape

Supported entrypoint:

`kxxx broker github.create_issue [--service <name>] --ref <secret-ref> --repo <owner/repo> --title <title> [--body <body>]`

- `--service` is required for `secretref:v1:keychain:<id>` refs and optional for `secretref:v1:memory:<id>` refs
- `--ref` is required and may be a `secretref:v1:keychain:<id>` from `kxxx ref <descriptor> --service <name>` or a `secretref:v1:memory:<id>` for tests and internal spikes
- `--repo` is required and identifies the target repository in `owner/repo` form
- `--title` is required
- `--body` is optional

## Response Shape

- success returns exit code `0` and stdout JSON with `status`, `provider`, `operation`, and `repo`
- success may also include `issue_number` and `issue_url` when the provider returns them
- success shape is effectively `{"status":"ok","provider":"github","operation":"create_issue","repo":"owner/repo","issue_number":42,"issue_url":"https://github.com/owner/repo/issues/42"}`
- failure returns a non-zero exit code, no stdout payload, and stderr-only errors such as:
  - `kxxx: broker audit log write failed`
  - `kxxx: broker policy denied github.create_issue for repo=<owner/repo>`
  - `kxxx: --service is required for keychain secret refs`
  - `kxxx: secret ref could not be resolved`
  - `kxxx: broker provider request failed`
- post-provider audit append failure is a warning-only stderr event, `kxxx: broker audit log write failed after provider success`, and does not turn a successful provider result into a failed command
- raw secrets are not emitted to stdout, stderr, or structured audit events on the happy path or in the tested failure paths

## Test Plan

Proof-oriented coverage lives in `test/broker.bats` and should continue to verify:

- allowed success path with a sanitized five-event audit sequence and returned issue metadata
- policy deny before secret resolution or provider execution
- unresolved `SecretRef`
- provider failure with upstream secret-like content redacted
- post-provider audit append failure preserving the successful broker result
- broker audit export for the default sink and explicit file override

## Intentionally Out of Scope

- multiple providers
- policy DSLs
- generalized persistent safe-path backends beyond the existing managed keychain path
- cross-platform keychain abstractions
- refactoring existing compatibility commands

## Current Limitations

- keychain-backed refs are broker-usable when they exist in the local secret index created by `kxxx set` or `migrate import --apply`, and the caller supplies the matching `--service`
- the in-memory backend remains process-local for tests and internal APIs
- the safe path is limited to GitHub issue creation
- policy configuration is intentionally minimal and loaded from `~/.config/kxxx/broker/github.create_issue.repos`
- structured audit viewing/export is intentionally narrow and only exposes raw JSONL broker events
- desktop keychain behavior should not be read as a guarantee that the same backend assumptions are safe in headless or CI contexts

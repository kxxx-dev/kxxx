# Safe Path MVP Brief

This slice adds the first brokered safe path to `kxxx` without changing the legacy compatibility commands.

## What It Adds

- provider: GitHub
- operation: `github.create_issue`
- `SecretRef`: opaque identity in the form `secretref:v1:memory:<id>`
- in-memory backend: test/local-spike storage for `SecretRef -> secret material`
- minimum policy gate: provider must be `github`, operation must be `create_issue`, and repo must be allowlisted
- minimal audit trail: sanitized structured broker events with no raw secret material

## Runtime Boundary

The caller provides only a `SecretRef` plus the brokered operation arguments.
`kxxx` checks policy at the broker boundary, resolves the raw secret internally, and performs the provider call behind that boundary.
The broker result and structured audit events never include the raw secret.

`kxxx broker audit` exports the broker runtime JSONL log from `~/.local/state/kxxx/broker.audit.jsonl` by default.
If `KXXX_BROKER_AUDIT_LOG` or `--file <path>` is provided, that path is used instead.
This is separate from the legacy `kxxx audit` command, which remains a filesystem secret scanner.

## Request Shape

Supported entrypoint:

`kxxx broker github.create_issue --ref <secret-ref> --repo <owner/repo> --title <title> [--body <body>]`

- `--ref` is required and must be a `secretref:v1:memory:<id>` for this MVP slice
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
- persistent safe-path backends
- cross-platform keychain abstractions
- refactoring existing compatibility commands

## Current Limitations

- the in-memory backend is process-local, so this MVP is primarily proven through tests and internal APIs
- the safe path is limited to GitHub issue creation
- policy configuration is intentionally minimal and loaded from `~/.config/kxxx/broker/github.create_issue.repos`
- structured audit viewing/export is intentionally narrow and only exposes raw JSONL broker events

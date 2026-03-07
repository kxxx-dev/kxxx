# Safe Path MVP Brief

This slice adds the first brokered safe path to `kxxx` without changing the legacy compatibility commands.

## What It Adds

- `SecretRef`: opaque identity in the form `secretref:v1:memory:<id>`
- in-memory backend: test/local-spike storage for `SecretRef -> secret material`
- one brokered operation: `github.create_issue`
- one minimal policy gate: provider must be `github`, operation must be `create_issue`, and repo must be allowlisted
- one minimal audit trail: sanitized structured broker events with no raw secret material

## Runtime Boundary

The caller provides only a `SecretRef`.
`kxxx` checks policy at the broker boundary, resolves the raw secret internally, and performs the provider call behind that boundary.
The broker result and structured audit events never include the raw secret.

`kxxx broker audit` exports the broker runtime JSONL log from `~/.local/state/kxxx/broker.audit.jsonl` by default.
If `KXXX_BROKER_AUDIT_LOG` or `--file <path>` is provided, that path is used instead.
This is separate from the legacy `kxxx audit` command, which remains a filesystem secret scanner.

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

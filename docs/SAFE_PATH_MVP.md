# Safe Path MVP Brief

This slice adds the first brokered safe path to `kxxx` without changing the legacy compatibility commands.

## What It Adds

- `SecretRef`: opaque identity in the form `secretref:v1:memory:<id>`
- in-memory backend: test/local-spike storage for `SecretRef -> secret material`
- one brokered operation: `github.create_issue`
- one minimal policy gate: provider must be `github`, operation must be `create_issue`, and repo must be allowlisted
- one minimal audit trail: structured JSONL broker events with no raw secret material

## Runtime Boundary

The caller provides only a `SecretRef`.
`kxxx` checks policy at the broker boundary, resolves the raw secret internally, and performs the provider call behind that boundary.
The broker result and audit event never include the raw secret.
Structured audit events are exported with `kxxx broker audit`; the legacy `kxxx audit` command remains the compatibility-path filesystem scanner.

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
- broker audit defaults to `~/.local/state/kxxx/broker.audit.jsonl` and can be overridden with `KXXX_BROKER_AUDIT_LOG` or `kxxx broker audit --file`

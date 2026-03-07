# kxxx

`kxxx` is a secret runtime that now includes an experimental brokered safe path while keeping compatibility commands for existing secret-loading workflows.

Safe path is preferred for new integrations, and new integrations should prefer brokered execution when possible. In the safe path, `kxxx` resolves secret material internally and returns only the brokered result. Compatibility-path commands remain available for existing workflows, but they can materialize raw secrets to the caller or child process environment and are therefore less safe.

The canonical threat model and v1 security invariants live in [docs/adr/0001-agent-safe-secret-runtime.md](docs/adr/0001-agent-safe-secret-runtime.md). In short: the safe path keeps raw secret values behind the broker boundary, compatibility-path commands remain explicit legacy mode, secret identity is distinct from env bindings, and current v1 audit intentionally keeps sanitized metadata such as opaque refs, backend names, target resources, and process context. The current narrow MVP is `kxxx broker github.create_issue`, and [docs/SAFE_PATH_MVP.md](docs/SAFE_PATH_MVP.md) defines only that slice boundary and its current limitations.

## Safe Path vs Compatibility Path

- Preferred safe path: `kxxx broker github.create_issue` accepts an opaque `SecretRef`, applies a minimal repo allowlist policy, records structured broker audit events, then (if allowed) resolves the secret internally and performs the provider call without returning the raw secret.
- Safe path audit: `kxxx broker audit` exports the structured broker event log from `~/.local/state/kxxx/broker.audit.jsonl` by default, or from `KXXX_BROKER_AUDIT_LOG` / `--file <path>` when overridden.
- Compatibility path: `get`, `env`, and `run` remain available for existing workflows and can still materialize raw secret values to the caller or child process environment.
- Legacy audit path: `kxxx audit` still scans files for leaked secrets; it does not read or format the broker runtime audit log.

This MVP keeps the new safe path intentionally narrow:

- only `github.create_issue` is brokered
- broker-visible refs are limited to `kxxx`-managed `secretref:v1:keychain:*` and `secretref:v1:encrypted-file:*` identities, plus process-local `secretref:v1:memory:*` refs for tests and internal APIs
- policy is a minimal exact-match allowlist loaded from `~/.config/kxxx/broker/github.create_issue.repos`
- structured broker audit events are stored as JSONL and never include raw secret material

## Threat Model Summary

- The preferred safe path never requires the caller or an LLM/agent to see the raw secret value; the caller supplies only a `SecretRef` plus operation arguments.
- Compatibility-path commands remain explicit and secondary. `get`, `env`, and `run` can still materialize raw secrets for existing workflows.
- When a brokered operation has policy, policy is evaluated before secret resolution or provider execution.
- Raw secret values must not be emitted to stdout, stderr, or structured broker audit events.
- The current v1 audit trail may still retain opaque refs, backend identifiers, target resources, and process metadata. Further metadata minimization is deferred until after the MVP.
- Interactive desktop keyrings and headless/CI execution are different trust environments and should not be treated as interchangeable backend assumptions. The current implementation does not claim broader headless-safe backend support.

## Backend Strategy

- `auto` is the default backend selection. Today it is platform-based: it resolves to `darwin-keychain` on supported macOS environments and to `encrypted-file` everywhere else.
- `darwin-keychain` preserves the current `security` / `ks` behavior behind the new backend layer.
- `encrypted-file` is the headless-safe persistent backend. It requires `KXXX_ENCRYPTED_FILE_KEY` and optionally accepts `KXXX_ENCRYPTED_FILE_PATH`.
- On headless or non-interactive macOS environments, prefer `--backend encrypted-file` or `KXXX_BACKEND=encrypted-file` explicitly instead of relying on `auto`.
- `memory` remains internal/test-only and is not intended as a normal CLI backend.
- `secret-service` and `wincred` are named backend targets, but they currently fail explicitly until real platform adapters exist.

## Install (Homebrew tap)

```bash
brew tap kxxx-dev/kxxx
brew install kxxx
```

## Commands

```bash
kxxx set <account> [--value <value>|--stdin] [--json] [--service <name>] [--backend <name>]
kxxx ref <account> [--service <name>] [--backend <name>] [--json]
kxxx get <account> [--service <name>] [--backend <name>] [--fallback-service <name>]
kxxx list [--service <name>] [--backend <name>] [--json]
kxxx env [--repo <auto|name>] [--shell <zsh|bash|dotenv|json>] [--service <name>] [--backend <name>] [--strict]
kxxx run [--repo <auto|name>] [--service <name>] [--backend <name>] -- <command...>
kxxx broker github.create_issue [--service <name>] --ref <secret-ref> --repo <owner/repo> --title <title> [--body <body>]
kxxx broker audit [--file <path>]
kxxx migrate import [--dry-run|--apply] [--service <name>] [--backend <name>] [--keys-root <path>]
kxxx migrate service [--from nil.secrets] [--to kxxx.secrets] [--from-backend <name>] [--to-backend <name>] [--dry-run|--apply]
kxxx audit [--summary|--list] [--strict] [paths...]
```

LLM-friendly output:
```bash
kxxx list --service kxxx.secrets --json
kxxx set env/OPENAI_API_KEY --value secret-value --json
```

## Defaults

- service: `kxxx.secrets`
- backend: `auto`
- repo detection: `git rev-parse --show-toplevel` basename, fallback to current directory basename
- audit roots (auto): `~/src`, `~/.config`

## Typical usage

```bash
# preferred safe path today: look up an opaque ref and pass only that ref to the broker
ref="$(kxxx ref env/GITHUB_TOKEN --service kxxx.secrets)"
kxxx broker github.create_issue --service kxxx.secrets --ref "$ref" --repo octo/repo --title "hello"

# current MVP note: process-local memory refs are still mainly for tests and internal APIs
# see docs/SAFE_PATH_MVP.md for the current slice boundary and limitations

# set global env secret
kxxx set env/OPENAI_API_KEY --stdin < ~/.secrets/openai

# headless-safe persistent backend example
export KXXX_ENCRYPTED_FILE_KEY="replace-me"
kxxx set env/GITHUB_TOKEN --service kxxx.secrets --backend encrypted-file --stdin < ~/.secrets/github-token

# compatibility path: run app command with injected vars
kxxx run --repo auto -- npm run dev

# compatibility path: print export lines for current shell
eval "$(kxxx env --repo auto --shell zsh)"

# one-time service migration for existing users
kxxx migrate service --from nil.secrets --to kxxx.secrets --dry-run
kxxx migrate service --from nil.secrets --to kxxx.secrets --apply
```

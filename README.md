# kxxx

`kxxx` is a macOS Keychain-first CLI for secret loading and migration.

## Install (Homebrew tap)

```bash
brew tap kxxx-dev/kxxx
brew install kxxx
```

## Commands

```bash
kxxx set <account> [--value <value>|--stdin] [--json] [--service <name>]
kxxx get <account> [--service <name>] [--fallback-service <name>]
kxxx list [--service <name>] [--json]
kxxx env [--repo <auto|name>] [--shell <zsh|bash|dotenv|json>] [--service <name>] [--strict]
kxxx run [--repo <auto|name>] [--service <name>] -- <command...>
kxxx broker github.create_issue --ref <secret-ref> --repo <owner/repo> --title <title> [--body <body>]
kxxx migrate import [--dry-run|--apply] [--service <name>] [--keys-root <path>]
kxxx migrate service [--from nil.secrets] [--to kxxx.secrets] [--dry-run|--apply]
kxxx audit [--summary|--list] [--strict] [paths...]
```

LLM-friendly output:
```bash
kxxx list --service kxxx.secrets --json
kxxx set env/OPENAI_API_KEY --value secret-value --json
```

## Defaults

- service: `kxxx.secrets`
- repo detection: `git rev-parse --show-toplevel` basename, fallback to current directory basename
- audit roots (auto): `~/src`, `~/.config`

## Typical usage

```bash
# set global env secret
kxxx set env/OPENAI_API_KEY --stdin < ~/.secrets/openai

# run app command with injected vars
kxxx run --repo auto -- npm run dev

# print export lines for current shell
eval "$(kxxx env --repo auto --shell zsh)"

# one-time service migration for existing users
kxxx migrate service --from nil.secrets --to kxxx.secrets --dry-run
kxxx migrate service --from nil.secrets --to kxxx.secrets --apply
```

## Safe Path vs Compatibility Path

- Safe path: `kxxx broker github.create_issue` accepts an opaque `SecretRef`, applies a minimal repo allowlist policy, then (if allowed) resolves the secret internally and performs the provider call without returning the raw secret.
- Compatibility path: `get`, `env`, and `run` remain available for existing workflows and can still materialize secret values to the caller or child process environment.

This MVP keeps the new safe path intentionally narrow:

- only `github.create_issue` is brokered
- only an in-memory `SecretRef` backend is included
- policy is a minimal exact-match allowlist loaded from `~/.config/kxxx/broker/github.create_issue.repos`

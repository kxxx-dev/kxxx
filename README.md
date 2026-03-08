# kxxx

`kxxx` is a secret runtime for local developer workflows that is being repositioned around an agent-safe execution model.

Today, it can still do familiar compatibility-path work such as resolving secrets, exporting env vars, and launching child processes with injected secrets. But the intended direction is different: new integrations should prefer a brokered safe path where `kxxx` remains the policy and secret-resolution boundary, and the caller receives only the minimum result metadata needed to continue.

That distinction matters because a “better keychain CLI” is not the real goal. The project is moving toward a model where storage backend choice, secret identity, policy, and audit all support safer agent/tool execution by default. The threat model and invariants that define that direction live in [ADR 0001](docs/adr/0001-agent-safe-secret-runtime.md). This README is the contributor-facing overview of what exists today and what direction the project is taking.

## What kxxx Solves Today

- It stores and retrieves secrets for local workflows.
- It separates logical secret descriptors such as `env/OPENAI_API_KEY` from opaque `SecretRef` identifiers.
- It supports backend selection behind a common CLI surface.
- It exposes one narrow brokered safe path today: `kxxx broker github.create_issue`.
- It keeps existing compatibility flows available for users who still need env-materializing behavior.

## What It Is Moving Toward

The long-term direction is an agent-safe secret runtime, not just a storage abstraction layer.

- The preferred safe path should avoid showing raw secret values to an LLM, agent, or other tool-using caller.
- Secret identity should stay distinct from env var naming so policy and audit can reason about explicit references instead of implicit process state.
- Backend/provider strategy should support both interactive desktop workflows and headless/non-interactive environments without treating macOS keychain behavior as the architecture.
- Policy and audit should be part of the runtime boundary, not bolt-ons after storage is generalized.

The current brokered GitHub issue flow is a proof point for that direction, not the finished product.

## Safe Path vs Compatibility Path

`kxxx` currently has two clearly different usage modes.

### Safe Path

The preferred safe path is broker-oriented.

- The caller passes an opaque `SecretRef` and operation arguments.
- `kxxx` evaluates policy before resolving the secret or performing the provider action.
- `kxxx` resolves the secret internally and returns only brokered result metadata.
- Structured broker audit records capture the action without emitting the raw secret.

Today, the narrow safe-path MVP is:

```bash
ref="$(kxxx ref env/GITHUB_TOKEN --service kxxx.secrets)"
kxxx broker github.create_issue \
  --service kxxx.secrets \
  --ref "$ref" \
  --repo octo/repo \
  --title "hello"
```

This flow is intentionally limited to one provider operation, one policy shape, and one audit format. See [docs/SAFE_PATH_MVP.md](docs/SAFE_PATH_MVP.md) for the exact slice boundary.

### Compatibility Path

Compatibility-path commands remain available for existing workflows:

- `kxxx get`
- `kxxx env`
- `kxxx run`

These commands can materialize raw secret values to stdout or to a child-process environment. They remain supported because users still need them, but they are not the preferred direction for new integrations.

Example compatibility flow:

```bash
kxxx run --repo auto -- npm run dev
```

## Backend And Provider Model

`kxxx` now routes persistent storage through a backend layer instead of calling macOS keychain helpers directly from business logic.

Current backend state:

- `auto` is the default selection.
- `darwin-keychain` preserves the current `security` / `ks` behavior on supported macOS environments.
- `encrypted-file` is the current headless-safe persistent backend and requires `KXXX_ENCRYPTED_FILE_KEY`.
- `memory` exists for tests and internal same-process scenarios only; it is not intended as a normal CLI backend.
- `secret-service` and `wincred` are named backend targets but are not implemented yet.

Important caveat:

- `auto` is platform-based today, not fully headless-aware. On headless or non-interactive macOS environments, prefer `--backend encrypted-file` or `KXXX_BACKEND=encrypted-file` explicitly.

The safe path also has a provider side, but that layer is intentionally narrow right now. The only brokered provider operation currently exposed is `github.create_issue`.

## Secret Identity Is Not Env Binding

One of the core architectural changes in `kxxx` is that secret identity is no longer tied to env var names.

- A descriptor such as `env/OPENAI_API_KEY` or `app/my-repo/API_TOKEN` is a logical binding used for compatibility and migration.
- A `SecretRef` such as `secretref:v1:encrypted-file:...` is the opaque identity used by the safe path.
- This split allows policy, audit, and backend choice to reason about secrets without making env var naming the primary storage model.

That distinction is already visible in the CLI:

```bash
kxxx set env/OPENAI_API_KEY --stdin < ~/.secrets/openai
kxxx ref env/OPENAI_API_KEY --service kxxx.secrets
```

## Threat Model Summary

The full threat model lives in [ADR 0001](docs/adr/0001-agent-safe-secret-runtime.md). The short version is:

- The preferred safe path should not require the caller, LLM, or child process to see the raw secret value.
- Compatibility-path commands are explicit exceptions and remain secondary.
- If a brokered operation has policy, policy is evaluated before secret resolution or provider execution.
- Raw secret values must not appear in stdout, stderr, or structured safe-path audit events.
- Audit may still contain sanitized metadata such as opaque refs, backend identifiers, target resources, and process context.
- Interactive desktop keyrings and headless/non-interactive environments have different trust assumptions and should not be conflated.

## Migration Notes For Existing Users

Existing users do not need to abandon current workflows all at once.

- If you already use `get`, `env`, or `run`, those commands still exist and remain the compatibility path.
- If you previously thought in terms of env-style secret names only, start by using `kxxx ref` to discover the corresponding opaque `SecretRef`.
- If you need a persistent backend in CI or other headless environments, prefer `encrypted-file` and supply `KXXX_ENCRYPTED_FILE_KEY`.
- If you are moving from older keychain service names, continue using `migrate service` and `migrate import` to consolidate into the current layout.

Example headless-safe persistent setup:

```bash
export KXXX_ENCRYPTED_FILE_KEY="replace-me"
kxxx set env/GITHUB_TOKEN --service kxxx.secrets --backend encrypted-file --stdin < ~/.secrets/github-token
```

## CLI Surface

The CLI now has three main groups:

- secret management and compatibility flows: `set`, `ref`, `get`, `list`, `env`, `run`
- brokered safe-path flows: `broker github.create_issue`, `broker audit`
- migration and scanning flows: `migrate import`, `migrate service`, `audit`

Defaults:

- service: `kxxx.secrets`
- backend: `auto`
- repo detection: `git rev-parse --show-toplevel` basename, fallback to current directory basename
- audit roots (auto): `~/src`, `~/.config`

For the exact command syntax, use `kxxx --help`.

## Roadmap And Open Questions

`kxxx` is still early in the transition from “developer secrets CLI” to “agent-safe secret runtime.”

What exists now:

- threat model and invariants
- opaque secret references
- backend abstraction with a headless-safe persistent option
- one brokered provider operation with policy and audit

What remains open:

- broader provider coverage beyond `github.create_issue`
- richer policy models beyond the current exact repo allowlist
- real platform implementations for `secret-service` and `wincred`
- clearer headless strategy on macOS when `auto` selection is not sufficient
- how far compatibility-path flows should continue to evolve versus stabilize

## Supporting Docs

- [ADR 0001: Agent-safe secret runtime](docs/adr/0001-agent-safe-secret-runtime.md)
- [Safe Path MVP Brief](docs/SAFE_PATH_MVP.md)
- [Migration from dotfiles keychain scripts](docs/MIGRATION_FROM_DOTFILES.md)

## Install

```bash
brew tap kxxx-dev/kxxx
brew install kxxx
```

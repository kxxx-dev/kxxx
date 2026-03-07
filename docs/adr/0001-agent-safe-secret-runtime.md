# ADR 0001: Agent-safe secret runtime

- Status: Accepted
- Date: 2026-03-07

## Context

`kxxx` currently sits at the overlap of three related product shapes:

1. a local developer secrets CLI
2. an agent-safe runtime and broker
3. a future identity-aware secret infrastructure

Those shapes share mechanics, but they do not share trust boundaries. Without a canonical threat model, follow-up work can accidentally optimize for storage backend convenience and slide back toward raw env injection as the default behavior. This ADR defines the security model that follow-up issues must inherit.

## Decision

`kxxx` treats agent-safe execution as the primary direction and raw env injection as a compatibility path. The safe path is broker-oriented: the caller provides an opaque `SecretRef` plus operation arguments, `kxxx` evaluates policy at the broker boundary, resolves the secret internally, and returns only brokered result metadata.

Compatibility-path commands remain available for existing workflows, but they are explicit exceptions to the preferred model because they can materialize raw secrets in the caller or child-process environment.

## Actors And Trust Boundaries

| Actor | Role | Trust boundary |
| --- | --- | --- |
| User | Human operator configuring secrets, services, and policy | Trusted to choose intent, but configuration mistakes are still part of the threat model. |
| Calling process / child process | Local shell, app, or tool invocation | Outside the safe boundary unless using a brokered path. Compatibility commands may expose raw secrets here. |
| LLM / agent | Tool-using model, automation, or planner | Must be treated as untrusted with raw secret material. The safe path should expose only opaque refs and minimal result metadata. |
| Broker / tool wrapper (`kxxx broker`) | Policy and secret-resolution boundary | Trusted to evaluate policy, resolve secrets internally, redact outputs, and enforce safe-path behavior. |
| Storage backend | Secret persistence layer | Trusted to store and return secret bytes, but backend metadata and backend-specific quirks are not assumed secret or portable. |
| OS keyring service | Platform keychain or secret service | Trusted only within platform constraints such as login-session presence or interactive unlock. |
| Headless / CI runner | Non-interactive execution environment | Distinct trust environment from desktop keyring usage. It must not inherit assumptions about prompts, login sessions, or user presence. |
| Provider API | Remote system such as GitHub | Receives the raw secret only inside the broker boundary when policy allows the operation. Provider responses are untrusted input. |

## Primary Attack And Failure Modes

- Prompt or tool-output injection causing unintended tool use.
  `kxxx` must assume the LLM or agent can be manipulated. Safe-path operations therefore require explicit broker commands and policy checks at the operation boundary.
- Secret disclosure through stdout, stderr, logs, traces, or test artifacts.
  Raw secret values are never valid safe-path output and must not be copied into structured audit events.
- Metadata leakage through backend lookup fields or audit records.
  `kxxx` uses opaque `SecretRef` identifiers instead of env-style names as the primary secret identity. Limited metadata exposure still exists in v1 audit records and is treated as an explicit tradeoff, not an accident.
- Over-privileged tool access.
  When policy exists, deny-by-default applies before secret resolution or provider execution. The current MVP enforces this with an exact repo allowlist.
- Cross-context mixups across repo, agent, or session boundaries.
  Secret identity stays separate from descriptors and env bindings so future policy and audit work can scope access by explicit context rather than implicit env names.
- Backend-specific assumptions leaking into the architecture.
  Interactive keychain behavior and headless execution are not interchangeable. Backend/provider work must document those differences instead of treating macOS-style unlock behavior as universal.
- Provider responses reflecting sensitive-looking content.
  Provider output is untrusted and safe-path behavior must continue to redact or drop raw secret-like content from user-visible error paths.

## V1 Security Invariants

- The preferred safe path never requires the LLM, caller, or child process to see the raw secret value.
- Compatibility-path commands are explicit and secondary. `get`, `env`, and `run` remain available for existing workflows, but new integrations should prefer `broker`.
- Secret identity and env binding are distinct concepts. `SecretRef` is the primary opaque identifier; descriptors such as `env/OPENAI_API_KEY` are logical bindings.
- If a brokered operation has policy, policy is evaluated before secret resolution or provider execution. Missing or non-matching policy fails closed.
- Raw secret values must not be emitted in stdout, stderr, or structured audit events on the safe path.
- Safe-path output should return only the minimum result metadata needed by the caller.
- V1 audit may retain opaque secret refs, backend identifiers, target resources, and process metadata. Raw secret values and direct env-style secret names are out of bounds.
- Headless and interactive environments have different trust assumptions and must be documented separately in backend/provider work.

## Explicit Non-goals For V1

- full enterprise IAM, OBO, or workload identity integration
- multiple brokered providers at once
- full cross-platform backend parity in the first broker MVP
- a generalized policy DSL
- immediate removal of compatibility-path commands
- exhaustive metadata minimization for every audit field
- solving every CI, remote, or distributed secret workflow in v1

## Consequences For Follow-up Work

- Issue `#6` should continue to frame the roadmap around the safe path, not around storage backend generalization by itself.
- Issue `#9` must describe backend capabilities in terms of these trust boundaries, especially headless versus interactive assumptions.
- Issue `#12` must keep README and CLI wording aligned with the safe path versus compatibility path distinction defined here.
- Issue `#13` must preserve opaque refs, deny-before-resolution, and sanitized outputs as its proof points for the brokered MVP.

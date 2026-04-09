# Runtime Observability

This document defines the current diagnostics and logging model for AgentIsland.

Related docs:

- [Docs Index](./README.md)
- [Unified Agent Protocol v1](./unified-agent-protocol.md)
- [Multi-Agent Architecture](./multi-agent-architecture.md)

## Goal

Diagnostics should help developers answer three questions quickly:

- what event reached the app
- how the runtime interpreted it
- why a provider-specific action was allowed, denied, or downgraded

The logging model should be explicit, configurable, and low-noise by default.

## Current Sources

AgentIsland currently emits diagnostics from two layers:

- Swift runtime logs through `os.Logger`
- Rust bridge logs through the bundled `agent-island-bridge`

Critical Swift runtime paths can also be mirrored into a dedicated file log.
Current app-side file coverage includes:

- hook socket ingest and responses
- capability dispatch
- session state transitions
- debounced transcript sync scheduling
- Claude and Codex interrupt watchers
- subagent agent-file watchers

## Logging Policy

### Default behavior

- bridge file logging is enabled by default
- default bridge file log level is `info`
- app file logging is disabled by default
- app runtime logs continue to use `os.Logger`

### User controls

The settings menu exposes:

- `Bridge File Logging`
- `Bridge Log Level`
- `App File Logging`
- `App Log Level`

Supported bridge levels:

- `off`
- `error`
- `info`
- `debug`
- `trace`

When bridge logging is turned off, the Rust bridge no longer appends to `bridge.log`.
When app logging is turned off, AgentIsland no longer appends to `app.log`.

## Bridge Log Path

The bridge log file is written under:

```text
~/Library/Application Support/AgentIsland/Logs/bridge.log
```

The path can still be overridden through the bridge launch environment, but the app now manages the standard location and level through persisted settings.

The app-side diagnostics file is written under:

```text
~/Library/Application Support/AgentIsland/Logs/app.log
```

## Runtime Support Directories

Runtime support files now converge on:

```text
~/Library/Application Support/AgentIsland/Runtime/
```

Key runtime paths:

- `Runtime/bridge-profiles`
- `approval-policies.json`

The shared hook bridge binary remains under:

```text
~/.agent-island/hooks/agent-island-bridge
```

Bridge launch now passes the profile path explicitly from the new runtime directory.
Legacy `~/.agent-island` paths are treated only as one-way migration sources.
At startup, AgentIsland migrates old runtime files into `Application Support/AgentIsland`, while keeping the shared hook bridge binary under `~/.agent-island/hooks`.

## Bridge Log Semantics

The Rust bridge logs structured single-line events such as:

- process start
- process exit
- process error
- hook payload received
- permission response emitted
- adapter downgrade notes

Log emission is filtered by configured level:

- `error`
  process and dispatch failures
- `info`
  lifecycle and normal permission responses
- `debug`
  richer event metadata
- `trace`
  full request body hashes and verbose bridge details

## Design Rules

- Logging configuration belongs to product settings, not per-provider hardcoding.
- The bridge should decide whether to write a line before opening the file.
- Provider adapters may emit downgrade diagnostics, but they should not bypass level filtering.
- The UI should only expose stable settings terminology, not environment variable names.

## Future Work

- optional in-app export for recent diagnostics
- broader app-side coverage beyond the current hook, dispatcher, and session hot paths
- provider-specific diagnostics filters once more integrations are added

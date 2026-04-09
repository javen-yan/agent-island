<div align="center">
  <img src="AgentIsland/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Logo" width="100" height="100">
  <h1 align="center">AgentIsland</h1>
  <p align="center">
    macOS menu bar companion for Claude, Codex, and Gemini sessions.
    <br>
    Unified runtime visibility, approvals, and chat history in one place.
  </p>
  <p align="center">
    <a href="https://github.com/javen-yan/agent-island/releases/latest" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/github/v/release/javen-yan/agent-island?style=rounded&color=white&labelColor=000000&label=release" alt="Latest Release">
    </a>
    <a href="https://javen-yan.github.io/agent-island/appcast.xml" target="_blank" rel="noopener noreferrer">
      <img alt="Sparkle Appcast" src="https://img.shields.io/badge/appcast-Sparkle-white?style=rounded&labelColor=000000">
    </a>
  </p>
</div>

[Chinese README](./README.zh.md)

More documentation: [Docs Index](./docs/README.md)

## What It Is

AgentIsland is a macOS menu bar app for terminal-based AI agents. It pulls session state, tool activity, approval status, and recent conversation history into a single surface so you do not need to keep jumping between terminals.

It currently supports:

- Claude
- Codex
- Gemini

## Current Product Design

AgentIsland is now organized around one shared runtime:

- Agent-specific hooks and transcripts are ingested through provider adapters.
- The Rust bridge normalizes provider events into a stable internal payload.
- Swift runtime state is centered on `SessionStore`, `SessionTranscriptProvider`, and unified event handling.
- The UI renders one common session model instead of separate product flows per agent.

Important current behavior:

- Claude supports app-managed approvals and transcript-backed history.
- Codex surfaces terminal confirmations in the app, but the actual approval still happens in the terminal.
- Codex dangerous command confirmation now uses both built-in rules and user-configurable regex extensions.
- Large tool outputs are kept as previews in memory and loaded lazily from transcripts when needed.

## Current Capabilities

- Menu bar / notch entry point
- Multi-session visibility
- Tool execution timeline
- Unified approval state
- Transcript-backed history
- Lazy full-output loading for large tool results
- Hook install, repair, and bridge redistribution workflow
- Bridge and app diagnostics controls
- Sparkle release + appcast publishing flow

## Supported Agents

| Agent | Integration Model | Approval Model | History Model | Status |
| --- | --- | --- | --- | --- |
| Claude | Official hooks + JSONL transcript parsing | App-managed approvals | Transcript-backed | Verified |
| Codex | Official hooks + transcript parsing | Terminal confirmation surfaced in app | Transcript-backed | Verified |
| Gemini | Official hooks + bridge adapter | Provider-driven approval flow | Runtime-integrated | Integrated |

## Architecture

AgentIsland currently uses four practical layers:

1. Provider layer
   Claude, Codex, and Gemini each keep their own official hook semantics.

2. Bridge layer
   `bridge-rs` maps provider-native events into a stable runtime payload.

3. Runtime layer
   Swift services manage sessions, transcript sync, approvals, tool state, and memory-bounded chat history.

4. UI layer
   Notch, chat, session list, and settings all render from the shared runtime state.

Start with these docs:

- [Current Product Overview](./docs/current-product-overview.md)
- [Unified Agent Protocol v1](./docs/unified-agent-protocol.md)
- [Multi-Agent Architecture](./docs/multi-agent-architecture.md)
- [Runtime Observability](./docs/runtime-observability.md)

## Quick Start

### Requirements

- macOS 15.6+
- Xcode 17+
- Rust toolchain
- Claude Code CLI
- Optional: Codex CLI, Gemini CLI

### Local Build

```bash
./scripts/build.sh
```

Skip signing locally:

```bash
AGENT_ISLAND_NO_SIGN=1 ./scripts/build.sh
```

### Local Release Build

```bash
./scripts/create-release.sh
```

This packages the app, prepares Sparkle artifacts, and aligns local release behavior with CI.

## Release Flow

Tag builds publish through GitHub Actions and now keep appcast history instead of replacing it with a single item.

Current release flow includes:

- build app and bundled bridge
- package dmg / zip artifacts
- publish GitHub release assets
- regenerate and merge Sparkle `appcast.xml`
- deploy appcast to GitHub Pages

Reference:

- [GitHub appcast](https://javen-yan.github.io/agent-island/appcast.xml)

## Diagnostics

View app logs:

```bash
log stream --level debug --predicate 'subsystem == "com.agentisland"'
```

View hook logs only:

```bash
log stream --level debug --predicate 'subsystem == "com.agentisland" AND category == "Hooks"'
```

Common checks:

- If Codex approvals appear stuck, confirm whether the CLI is waiting for terminal confirmation.
- If session history feels heavy, inspect whether a session contains many large tool outputs and verify lazy loading behavior.
- If the app state does not match provider behavior, inspect bridge logs before debugging UI code.
- If release metadata looks wrong, verify the tag version, project version, and generated appcast payload together.

## Repository Layout

- `AgentIsland/`: macOS app
- `bridge-rs/`: Rust bridge runtime
- `docs/`: architecture, runtime, and integration docs
- `scripts/`: build, packaging, and release scripts

## Acknowledgements

This project evolved from [farouqaldori/claude-island](https://github.com/farouqaldori/claude-island), while extending its bridge and notification ideas into a broader multi-agent runtime.

## License

Apache 2.0

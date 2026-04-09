# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build, test, and development commands

### Main app (macOS SwiftUI)

- Build app + bridge (default local flow):
  - `./scripts/build.sh`
- Build app in unsigned mode (CI-style / local without signing):
  - `AGENT_ISLAND_NO_SIGN=1 ./scripts/build.sh`
- Build in Xcode via CLI (Debug):
  - `xcodebuild build -project AgentIsland.xcodeproj -scheme AgentIsland -configuration Debug`
- Resolve Swift package dependencies:
  - `xcodebuild -resolvePackageDependencies -project AgentIsland.xcodeproj -scheme AgentIsland`

### Rust bridge (`bridge-rs`)

- Build release bridge binary:
  - `./scripts/build-rust-bridge.sh`
  - or `cargo build --release --manifest-path bridge-rs/Cargo.toml`
- Run bridge tests:
  - `cargo test --manifest-path bridge-rs/Cargo.toml`
- Run a single Rust test:
  - `cargo test --manifest-path bridge-rs/Cargo.toml <test_name>`

### Lint / analysis

This repo does not define a dedicated lint script. Use platform-native checks:

- Swift static analysis:
  - `xcodebuild analyze -project AgentIsland.xcodeproj -scheme AgentIsland -configuration Debug`
- Rust linting / formatting checks:
  - `cargo clippy --manifest-path bridge-rs/Cargo.toml --all-targets -- -D warnings`
  - `cargo fmt --manifest-path bridge-rs/Cargo.toml --check`

### Packaging / release helpers

- Local release packaging workflow (notarization/DMG/appcast/release automation helper):
  - `./scripts/create-release.sh`

## High-level architecture

AgentIsland is a macOS menu bar runtime that normalizes hook events from multiple CLI agents (Claude, Codex, Gemini) into one internal protocol and one shared UI/state engine.

### Core runtime layers

1. Official hook protocols (agent-specific)
   - Each agent emits its own hook/event format.

2. Rust bridge normalization (`bridge-rs`)
   - Entrypoint: `bridge-rs/src/main.rs`
   - Dispatch: `bridge-rs/src/dispatcher.rs`
   - Shared payload model: `bridge-rs/src/protocol.rs`
   - Agent adapters: `bridge-rs/src/adapter/{claude,codex,gemini}.rs`
   - Output is a normalized `HookPayload` with stable fields used by Swift.

3. Swift ingress and state engine
   - Socket ingress server: `AgentIsland/Services/Hooks/HookSocketServer.swift`
   - Central state machine: `AgentIsland/Services/State/SessionStore.swift`
   - Event bus scaffold: `AgentIsland/Services/Shared/AgentEventBus.swift`

4. UI layer
   - App/bootstrap: `AgentIsland/App/AppDelegate.swift`
   - Notch/menu/chat views under `AgentIsland/UI/**`

### Internal protocol contract (important)

UI/state logic should prefer normalized fields from bridge payloads over raw official event names:

- `internal_event` (primary business event)
- `permission_mode` (approval handling mode)
- `extra` (agent-specific passthrough)

Reference: `docs/unified-agent-protocol.md`.

### Permission and hook installation model

- Plugin-based hook installation/repair/uninstall is implemented in:
  - `AgentIsland/Services/Hooks/AgentHookPlugin.swift`
- Hooks are installed for Claude/Codex/Gemini and call the shared `agent-island-bridge` binary.
- Bridge binary distribution target is under `~/.agent-island/hooks/agent-island-bridge`.

### Session and transcript model

- `SessionStore` is the single source of truth for session lifecycle, phase transitions, tool timeline, permission state, and chat item state.
- Transcript/history capability is agent-aware via transcript providers (wired through session services); incremental file sync updates feed back into `SessionStore`.
- Subagent (`Task`) tool tracking is integrated into session state and chat tool items.

### Release/CI shape

- CI workflow: `.github/workflows/ci-build.yml`
- CI builds app unsigned (`AGENT_ISLAND_NO_SIGN=1`), packages DMG/ZIP artifacts, and creates tag-based releases.
- `scripts/build.sh` is the canonical local build entrypoint; it ensures Rust bridge availability and embeds `agent-island-bridge` into the app bundle resources.

## Project map (high signal only)

- `AgentIsland/` — Swift app/runtime/UI
- `bridge-rs/` — Rust multi-agent hook bridge
- `docs/` — protocol + architecture + extension docs
- `scripts/` — build/release/signing helper scripts

## Docs to read before non-trivial changes

1. `docs/internal-hook-protocol.md`
2. `docs/multi-agent-architecture.md`
3. `docs/agent-extension-guide.md`

# Current Product Overview

This document describes the current implemented design of AgentIsland rather than an aspirational architecture.

Related docs:

- [Docs Index](./README.md)
- [Unified Agent Protocol v1](./unified-agent-protocol.md)
- [Multi-Agent Architecture](./multi-agent-architecture.md)
- [Runtime Observability](./runtime-observability.md)

## Product Goal

AgentIsland is a menu bar companion for terminal-based AI agents on macOS.

Its job is to give one stable surface for:

- session visibility
- approval state
- tool execution state
- transcript-backed history
- runtime diagnostics

The product is intentionally organized around a shared runtime instead of separate product modes for Claude, Codex, and Gemini.

## Current Runtime Path

The main runtime path today is:

`Provider hooks / transcripts -> Rust bridge -> Swift runtime services -> shared session state -> UI`

In practical terms:

1. The provider emits hook events and transcript updates.
2. `bridge-rs` normalizes official provider payloads into a stable internal payload.
3. Swift services ingest those events and reconcile them with transcript history.
4. `SessionStore` owns the session state used by the app.
5. Notch, chat, session list, and settings all render from that shared model.

## Current Provider Behavior

### Claude

- Hook events drive approvals and runtime transitions.
- JSONL transcript parsing provides history and tool result recovery.
- Claude is the most complete app-managed integration.

### Codex

- The bridge watches `Bash`-related hook activity and transcript state.
- Terminal confirmation is surfaced in the app as a waiting state.
- The actual allow or deny still happens in the terminal, not in AgentIsland.
- Dangerous command confirmation is driven by both built-in rules and user-configurable regex extensions.

### Gemini

- Gemini is integrated through the same bridge/runtime model.
- Provider-specific approval behavior is preserved instead of being forced into Claude-style controls.

## Current Session Model

The product centers on a shared session state that keeps:

- provider identity
- runtime phase
- tool timeline
- approval state
- transcript-backed conversation metadata
- chat items used by the UI

The important design choice is that the UI consumes session state, not provider-native event names.

## Tool Results and Memory Model

Large tool outputs are no longer kept fully expanded in normal in-memory history state.

Current behavior:

- preview content is stored in memory
- long tool outputs are truncated before they become steady-state chat data
- full output is loaded lazily from transcripts when the user requests details

This keeps the interaction record intact while reducing steady-state memory pressure for long-running sessions.

## Approval Model

AgentIsland now treats approval display and approval control as separate concerns.

Examples:

- Claude approvals can be app-managed.
- Codex terminal confirmations are displayed by the app but resolved in the terminal.
- Provider differences stay visible through capability and adapter logic instead of being flattened into one fake control model.

## Settings and Diagnostics

The settings surface now owns:

- provider integration install / repair
- bridge log controls
- app log controls
- Codex custom dangerous command regex patterns
- chat history retention limit

Diagnostics are split between:

- Swift runtime logging
- Rust bridge logging
- transcript-backed debugging and reconciliation

## Release and Update Model

The release path now includes:

- local build and packaging scripts
- CI tag builds
- GitHub release asset publishing
- Sparkle appcast generation and merge
- GitHub Pages deployment for appcast hosting

The appcast flow is designed to preserve release history instead of replacing the feed with only the newest item.

## Where To Look In Code

- Runtime state: `AgentIsland/Services/State/SessionStore.swift`
- Transcript providers: `AgentIsland/Services/Session/SessionTranscriptProvider.swift`
- Transcript parsing: `AgentIsland/Services/Session/ConversationParser.swift`
- Hook and bridge profile generation: `AgentIsland/Services/Hooks/AgentHookPlugin.swift`
- Shared session models: `AgentIsland/Models/SessionState.swift`
- Tool result rendering: `AgentIsland/UI/Views/ToolResultViews.swift`
- Bridge adapters: `bridge-rs/src/adapter`

## Summary

The current design is best understood as:

- one shared runtime
- multiple provider adapters
- transcript-backed recovery
- capability-aware approval behavior
- bounded in-memory history with lazy detail loading

That is the baseline to document against when changing the product from here.

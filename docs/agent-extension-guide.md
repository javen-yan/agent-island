# Agent Extension Guide

This guide explains how to add another agent integration using the current shared runtime design.

Related docs:

- [Docs Index](./README.md)
- [Current Product Overview](./current-product-overview.md)
- [Multi-Agent Architecture](./multi-agent-architecture.md)
- [Unified Agent Protocol v1](./unified-agent-protocol.md)

## Goal

A new agent should feel like another integration on top of the existing product runtime, not like a brand-new product mode.

That means:

- provider-specific protocol handling stays at the adapter boundary
- shared session state stays provider-agnostic where possible
- the UI continues to render one common model
- unsupported capabilities are expressed explicitly instead of hidden

## Current Extension Layers

When adding a provider, work through these layers in order:

1. Provider runtime and hook model
2. Rust bridge adapter
3. Swift hook plugin and capability declaration
4. Transcript / history integration
5. Runtime state reconciliation
6. UI verification and docs

## 1. Define the Provider Contract

Before touching code, decide:

- what official hook or event surfaces exist
- what transcript or history source exists
- whether approvals are app-managed, terminal-managed, provider-managed, or unavailable
- whether the provider emits enough metadata for stable session tracking

Do not start from UI requirements first. Start from the provider's real runtime contract.

## 2. Add a Bridge Adapter

Create a new adapter under:

```text
bridge-rs/src/adapter/
```

Current examples:

- `bridge-rs/src/adapter/claude.rs`
- `bridge-rs/src/adapter/codex.rs`
- `bridge-rs/src/adapter/gemini.rs`

Your adapter is responsible for:

- parsing official provider payloads
- normalizing tool name, tool id, session id, cwd, and message fields
- mapping provider-native events into stable internal runtime semantics
- preserving provider-specific metadata in `extra`
- encoding provider-native permission responses when supported

Register the adapter in:

- `bridge-rs/src/adapter/mod.rs`

If the provider needs protocol-level additions, also update:

- `bridge-rs/src/protocol.rs`
- `bridge-rs/src/dispatcher.rs`

## 3. Decide the Approval Model

This is one of the most important extension decisions.

Pick the real behavior:

- app-managed approval
- terminal confirmation surfaced in app
- provider-managed approval with limited app control
- no approval surface

Do not fake native approvals if the provider actually expects terminal confirmation.

Codex is the current reference for terminal-managed confirmation:

- the app shows waiting state
- the terminal still owns the final decision

Claude is the current reference for app-managed approvals.

## 4. Add Hook Plugin and Capabilities

Update:

```text
AgentIsland/Services/Hooks/AgentHookPlugin.swift
```

You need to define:

- availability detection
- install / repair / uninstall behavior
- derived bridge profile behavior
- supported events
- approval source
- whether the provider supports transcript history
- whether the provider supports permission decisions

The goal is for the provider to declare capabilities clearly enough that product logic does not branch on provider name unless absolutely necessary.

## 5. Extend Agent Models

Update the shared agent model surfaces only where needed:

- `AgentIsland/Models/AgentPlatform.swift`
- `AgentIsland/Services/Hooks/AgentPermissionAdapter.swift`
- `AgentIsland/Models/UnifiedAgentProtocol.swift`

Keep these changes minimal.

If something is only useful for one provider, keep it in adapter metadata instead of promoting it into the global model too early.

## 6. Add Transcript Support

If the provider has a persistent transcript or event log, connect it through:

```text
AgentIsland/Services/Session/SessionTranscriptProvider.swift
```

If needed, also add parsing support near:

```text
AgentIsland/Services/Session/ConversationParser.swift
```

Transcript support should cover:

- initial history load
- incremental sync
- conversation metadata
- tool result recovery
- lazy detail loading for large tool outputs

If the provider does not support transcripts, keep that limitation explicit instead of simulating history.

## 7. Reconcile Runtime State

The shared runtime ultimately flows through:

```text
AgentIsland/Services/State/SessionStore.swift
```

Your integration should work with the existing session model for:

- tool start and completion
- approval waiting state
- interrupted sessions
- transcript backfill
- session summaries
- memory-bounded chat history

Try to make the new provider fit the runtime rather than adding provider-only paths inside the core state machine.

## 8. Verify Tool Result Behavior

Current product behavior stores only preview-sized tool outputs in steady-state memory and loads full detail lazily from transcripts.

A new provider should preserve that behavior where possible.

Check:

- preview truncation works
- lazy detail loading works
- very large tool output does not blow up the chat view
- missing transcript detail degrades gracefully

## 9. Add Tests

At minimum, add:

### Bridge tests

Verify:

- event mapping
- approval state mapping
- permission mode mapping
- provider-specific metadata preservation
- permission response encoding

Typical location:

```text
bridge-rs/src/dispatcher.rs
```

### Runtime tests or validation paths

Verify:

- plugin install and repair path
- history load path
- approval state rendering
- transcript detail loading if supported

## 10. Update User-Facing Docs

When the provider is real enough to ship, update:

- `README.md`
- `README.zh.md`
- `docs/README.md`
- `docs/README.zh.md`
- this extension guide
- any architecture doc that needs a new runtime example

Document at least:

- integration model
- approval model
- history model
- validation status

## Practical Checklist

Use this order:

1. Confirm official provider behavior.
2. Add the Rust adapter.
3. Add bridge tests.
4. Add hook plugin and capabilities.
5. Add transcript support if available.
6. Verify runtime reconciliation.
7. Verify large tool output behavior.
8. Update docs.

## Summary

The rule of thumb is simple:

- keep provider-specific logic near the adapter
- keep runtime semantics shared
- keep approval behavior honest
- keep large history bounded

If a new integration preserves those four properties, it will fit AgentIsland's current design.

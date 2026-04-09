# Agent Extension Guide

This guide explains how to add a new provider to AgentIsland without teaching the UI a new raw protocol.

Related docs:

- [Docs Index](./README.md)
- [Unified Agent Protocol v1](./unified-agent-protocol.md)
- [Multi-Agent Architecture](./multi-agent-architecture.md)
- [Agent Integration Checklist](./agent-integration-checklist.md)

## Design Rule

New providers must integrate through the same layered model:

1. official provider runtime
2. provider-specific adapter
3. unified event and action mapping
4. shared Swift runtime and UI

Do not wire a new provider directly into UI logic through raw official event names unless there is no viable unified mapping.

## What Must Stay Stable

The UI and session engine should continue to rely on:

- semantic event kinds
- semantic action payloads
- explicit provider capabilities

If you are unsure whether a field belongs in the stable contract, keep it inside provider-specific payload metadata until there is a stronger cross-provider need.

## Integration Checklist

For the execution-order checklist, use:

- [Agent Integration Checklist](./agent-integration-checklist.md)

### 1. Add a Rust adapter

Create a new file under:

```text
bridge-rs/src/adapter/
```

A starter skeleton now lives at:

```text
bridge-rs/src/adapter/provider_template.rs.example
```

Typical shape:

- parse official payload
- translate into unified event kinds
- compute shared runtime status
- build provider payload metadata
- build official permission response JSON

Then register it in:

- `bridge-rs/src/adapter/mod.rs`
- `bridge-rs/src/protocol.rs`

### 2. Map official events to unified events

Your adapter should emit semantic events such as:

- `session.started`
- `session.ended`
- `turn.input_submitted`
- `turn.completed`
- `tool.pending`
- `tool.started`
- `tool.completed`
- `tool.failed`
- `permission.requested`
- `notification`

If the new provider exposes a permission flow, its capability descriptor should also make the approval model explicit.

### 3. Define permission behavior

Decide:

- what official event starts approval
- whether approval is native, terminal-backed, or unsupported
- how to generate the official response JSON

The response format must remain provider-specific. Only the unified action model is shared.

### 4. Add installer support

Update:

```text
AgentIsland/Services/Hooks/AgentHookPlugin.swift
```

Tasks:

- add the new plugin
- define official hook event registration
- define install / repair / uninstall behavior
- define capability metadata

### 5. Add Swift runtime support

Update the agent enum and capability surfaces where needed, but keep Swift business logic aligned to the unified protocol.

Important files:

- `AgentIsland/Models/AgentPlatform.swift`
- `AgentIsland/Services/Hooks/AgentPermissionAdapter.swift`
- `AgentIsland/Services/Hooks/HookSocketServer.swift`
- `AgentIsland/Models/UnifiedAgentProtocol.swift`

### 6. Use provider payload carefully

Provider payload is the escape hatch for provider-specific metadata.

Good examples:

- official event metadata
- matcher names
- command text
- escalation hints
- provider-specific debug fields

Bad examples:

- normalized business meaning
- canonical approval state
- fields already represented in the stable protocol

### 7. Add tests

At minimum, add:

#### Event mapping tests

In `bridge-rs`, add dispatch tests that verify:

- official event name is preserved
- unified event kind is correct
- capability-relevant approval metadata is correct
- important provider payload fields are present

#### Permission response tests

Also verify:

- allow response shape
- deny response shape
- no-response cases if the provider expects them

### 8. Update docs

When a new provider is added, update:

- `README.md`
- `README.zh.md`
- `docs/README.md`
- `docs/README.zh.md`
- `docs/agent-extension-guide.md`

At minimum, document:

- official hook entry points
- approval entry point
- unified event mapping
- validation status

## Recommended Implementation Order

1. Add Rust adapter
2. Add dispatch tests
3. Add permission response tests
4. Add installer support
5. Connect Swift runtime
6. Validate build
7. Update docs

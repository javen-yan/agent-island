# Agent Integration Checklist

Use this checklist when adding a new agent/provider to AgentIsland. The goal is to keep integration work predictable and stop provider-specific logic from leaking into UI code.

## Principle

A new agent should be added by filling in four fixed layers:

1. `AgentPlatform` product profile
2. Rust bridge adapter
3. Swift runtime support
4. Validation and docs

If a task cannot be mapped into one of those layers, it is a sign the architecture should be adjusted before more provider-specific code is added.

## Phase 1. Product Profile

- [ ] Add a new `case` to [/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Models/AgentPlatform.swift](/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Models/AgentPlatform.swift)
- [ ] Fill in one `AgentBehaviorProfile`
- [ ] Decide:
  - display name key
  - accent color
  - icon symbol
  - terminal control profile
  - `autoRevealOnTurnCompletion`
  - `supportsPostTurnFollowUpInIsland`
  - `showsLastReplyInCompletionSummary`
- [ ] Add localization keys only for product-owned labels, not provider raw output

Acceptance:

- The new provider can be rendered in lists and settings without adding UI `if provider == ...` branches.

## Phase 2. Rust Adapter

- [ ] Add `bridge-rs/src/adapter/<provider>.rs`
- [ ] Register it in [/Users/javen/Documents/Workspace/private/helper/claude-island/bridge-rs/src/adapter/mod.rs](/Users/javen/Documents/Workspace/private/helper/claude-island/bridge-rs/src/adapter/mod.rs)
- [ ] Parse:
  - hook event name
  - session id
  - cwd
  - transcript path
  - tool name
  - tool use id
  - message
  - command text
  - escalation hints
- [ ] Implement:
  - `should_emit_event`
  - `status_for_event`
  - `process_info`
  - `requires_approval`
  - `internal_event`
  - `permission_mode`
  - `extra_payload`
  - `permission_response`

Acceptance:

- The adapter can convert official input into one normalized runtime event shape.

## Phase 3. Hook Installation

- [ ] Add installer/repair/uninstall support in [/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Services/Hooks/AgentHookPlugin.swift](/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Services/Hooks/AgentHookPlugin.swift)
- [ ] Define:
  - official config path
  - hook registration payload
  - availability detection
  - install preconditions
  - bridge profile generation
- [ ] Keep provider-specific file mutations inside the plugin layer

Acceptance:

- The provider can be installed, repaired, and refreshed without touching UI code.

## Phase 4. Swift Runtime

- [ ] Extend transcript support in [/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Services/Session/SessionTranscriptProvider.swift](/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Services/Session/SessionTranscriptProvider.swift) if history exists
- [ ] Extend runtime observation in [/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Services/Session/AgentRuntimeObserver.swift](/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Services/Session/AgentRuntimeObserver.swift) if live signals exist
- [ ] Update [/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Models/UnifiedAgentProtocol.swift](/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Models/UnifiedAgentProtocol.swift) baseline capabilities
- [ ] Update [/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Services/Hooks/AgentPermissionAdapter.swift](/Users/javen/Documents/Workspace/private/helper/claude-island/AgentIsland/Services/Hooks/AgentPermissionAdapter.swift) only if the provider really requires a custom response wait strategy

Acceptance:

- The provider can participate in session state, history, and message continuation using existing unified runtime paths.

## Phase 5. UI Validation

- [ ] Confirm the provider works in:
  - settings
  - Island list
  - chat view
  - approval bar
  - diagnostics
- [ ] Remove any provider-name conditionals that can be replaced by behavior flags
- [ ] Keep provider-specific copy in localization and provider capabilities, not inline view code

Acceptance:

- UI additions are capability-driven, not provider-name driven.

## Phase 6. Tests

- [ ] Add bridge dispatch tests in [/Users/javen/Documents/Workspace/private/helper/claude-island/bridge-rs/src/dispatcher.rs](/Users/javen/Documents/Workspace/private/helper/claude-island/bridge-rs/src/dispatcher.rs)
- [ ] Add permission response tests in `bridge-rs`
- [ ] Add unified runtime tests in [/Users/javen/Documents/Workspace/private/helper/claude-island/UnifiedRuntimePackage/Tests/UnifiedRuntimeKitTests/UnifiedRuntimeKitTests.swift](/Users/javen/Documents/Workspace/private/helper/claude-island/UnifiedRuntimePackage/Tests/UnifiedRuntimeKitTests/UnifiedRuntimeKitTests.swift) if the provider changes semantic phase behavior
- [ ] Build the app target

Acceptance:

- `cargo test`
- `swift test`
- `xcodebuild -quiet -project AgentIsland.xcodeproj -scheme AgentIsland`

all pass.

## Phase 7. Documentation

- [ ] Update [/Users/javen/Documents/Workspace/private/helper/claude-island/docs/agent-extension-guide.md](/Users/javen/Documents/Workspace/private/helper/claude-island/docs/agent-extension-guide.md)
- [ ] Update [/Users/javen/Documents/Workspace/private/helper/claude-island/docs/agent-extension-guide.zh.md](/Users/javen/Documents/Workspace/private/helper/claude-island/docs/agent-extension-guide.zh.md)
- [ ] Update [/Users/javen/Documents/Workspace/private/helper/claude-island/docs/README.md](/Users/javen/Documents/Workspace/private/helper/claude-island/docs/README.md) if the new doc surface changed
- [ ] Document:
  - official hook boundary
  - transcript support
  - runtime observation support
  - continuation model
  - current limitations

## Recommended Order

1. Product profile
2. Rust adapter
3. Hook installation
4. Swift runtime
5. Tests
6. UI polish
7. Docs

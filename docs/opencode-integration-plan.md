# OpenCode Integration Plan

This document defines the integration plan for adding OpenCode as a first-class provider in AgentIsland.

Related docs:

- [Docs Index](./README.md)
- [Unified Agent Protocol v1](./unified-agent-protocol.md)
- [Agent Extension Guide](./agent-extension-guide.md)

## Why OpenCode

OpenCode is an open source coding agent that runs in terminal, IDE, and desktop surfaces. Its official docs position it as:

- multi-session
- provider-flexible
- MCP-capable
- config-driven

That makes it a strong fit for AgentIsland's provider-translation architecture.

## Official Documentation Signals

From the official OpenCode docs:

- the product is positioned as a terminal, desktop, and IDE coding agent
- providers are configured through `opencode.json`
- credentials are added through `/connect`
- MCP servers are configured and added through OpenCode commands and config
- OpenCode uses config-driven provider and runtime setup rather than the exact Claude/Codex/Gemini hook model

Key official sources used for this plan:

- [OpenCode home](https://opencode.ai/)
- [Providers](https://opencode.ai/docs/providers)
- [CLI](https://opencode.ai/docs/cli/)
- [MCP servers](https://dev.opencode.ai/docs/mcp-servers/)
- [Config](https://opencode.ai/docs/ja/config/)

## Integration Assumption

OpenCode should be integrated as a provider adapter, not as a special product mode.

That means AgentIsland should absorb OpenCode through:

`OpenCode runtime -> OpenCode ingress adapter -> Unified Agent Event -> AgentIsland core`

## What We Need To Adapt

### 1. Session identity

We need stable extraction for:

- session id
- cwd
- transcript or conversation path if available
- pid and tty if exposed

### 2. Tool lifecycle

We need a way to detect:

- tool pending
- tool started
- tool completed
- tool failed

### 3. Permission and approval model

We need to understand whether OpenCode exposes:

- pre-tool approval hooks
- config-level allowlists or denylists
- terminal-only confirmation flows
- model or agent intervention points

### 4. Messaging and transcript history

We need to determine:

- whether AgentIsland can request history directly
- whether transcript files exist
- whether message injection is supported

### 5. Capability surface

We need a baseline capability declaration covering:

- permissions
- transcript history
- runtime observation
- messaging
- MCP tool visibility

## Proposed Adapter Strategy

### Preferred path

If OpenCode exposes structured runtime events or hook-like callbacks, build a native Rust adapter in:

```text
bridge-rs/src/adapter/opencode.rs
```

### Fallback path

If OpenCode is primarily transcript/config driven, integrate in two stages:

1. transcript/runtime observation first
2. interactive approvals second

That still fits the unified protocol as a partial-capability provider.

## Capability Target

Initial target capability matrix:

- `interactiveApproval`
  unknown
- `toolLevelApproval`
  unknown
- `transcriptHistory`
  likely yes
- `runtimeObservation`
  likely yes
- `mcpVisibility`
  likely yes
- `messageInjection`
  unknown

Until official docs confirm otherwise, OpenCode should be modeled as a partial-capability provider.

## Implementation Checklist

- [ ] Confirm official runtime event or hook entry points
- [ ] Confirm config file discovery and project-local precedence
- [ ] Confirm transcript/history source and format
- [ ] Confirm approval mechanism and possible response payloads
- [ ] Confirm MCP server/tool metadata that can be surfaced in UI
- [ ] Add `AgentPlatform.opencode`
- [ ] Add provider capability baseline
- [ ] Add Rust adapter skeleton
- [ ] Add installer/bootstrap support if OpenCode supports installable hooks
- [ ] Add history/runtime adapter if hook callbacks are not available
- [ ] Add UI icon and accent color
- [ ] Add dispatch tests and permission response tests

## Recommended Build Order

1. Documentation and capability assumptions
2. Runtime observation
3. Transcript/history
4. Permission/approval handling
5. MCP metadata visibility
6. UI polish and diagnostics

## Risks

- OpenCode may not expose the same approval callback depth as Claude/Codex/Gemini.
- Config and transcript semantics may matter more than hook semantics.
- MCP support may expose richer tool metadata than current UI expects.

## Product Decision

OpenCode should be treated as:

- a first-class provider
- a partial-capability provider until proven otherwise
- an adapter-owned integration, not a UI-owned exception

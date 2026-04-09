# Design Refresh Checklist

This checklist tracks the post-migration cleanup and product polish work after the unified runtime landing.

## 1. Documentation Refresh

- [x] Rewrite docs index around the unified runtime architecture
- [x] Add runtime observability document
- [x] Add OpenCode integration plan
- [x] Rewrite extension guidance to target unified protocol and capability-based adapters
- [x] Remove obsolete internal hook protocol docs
- [x] Remove obsolete terminal interaction docs

## 2. Logging Controls

- [x] Add persisted settings for bridge file logging
- [x] Add persisted settings for bridge log level
- [x] Extend bridge profiles with logging configuration
- [x] Pass logging configuration through the bridge launch command
- [x] Gate Rust bridge file writes by enabled flag and log level
- [x] Expose logging controls in the settings menu

## 3. Provider Brand Icons

- [x] Add official-style Claude icon asset
- [x] Add official-style Codex icon asset
- [x] Add official-style Gemini icon asset
- [x] Route provider icons through the shared icon registry

## 4. OpenCode Planning

- [x] Review official OpenCode documentation
- [x] Document the integration strategy
- [x] Document the capability assumptions and implementation checklist

## 5. Validation

- [x] `swift test` in `UnifiedRuntimePackage`
- [x] `cargo test` in `bridge-rs`
- [x] `xcodebuild -quiet -project AgentIsland.xcodeproj -scheme AgentIsland`

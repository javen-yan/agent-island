# I18N Migration Checklist

## Goal

Add localization support that:

- follows the system language by default
- allows a manual language override
- falls back to English when no supported language matches

## Scope

Phase 1 focuses on the Settings window so the language architecture is proven in one contained surface before the island/chat UI is migrated.

## Plan

- [x] Audit existing localization usage and confirm there is no current strings catalog
- [x] Define target behavior: `system`, `english`, `simplified chinese`
- [ ] Add a lightweight localization manager with supported-language resolution
- [ ] Add a persisted app language setting
- [ ] Add a language picker to Settings
- [ ] Add localized string resources for Settings window copy
- [ ] Migrate `SettingsWindowView.swift` to localized lookups
- [ ] Verify system-language auto detection
- [ ] Verify manual override to English
- [ ] Verify manual override to Simplified Chinese
- [ ] Verify unsupported system locale falls back to English

## Notes

- Use English as the source and fallback language.
- Start with Settings only; migrate Island, chat, tool results, and diagnostics copy later.
- Keep localization keys semantic and stable; do not use raw English sentences as keys.

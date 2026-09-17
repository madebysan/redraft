# Changelog

All notable changes to Companion are documented here.

## [0.3.1] - 2026-09-17

### Fixed

- Capsule clicks are checked against the panel bounds before outside-click dismissal, and buttons accept the first activation click.
- Focus transitions during a Capsule click no longer immediately cancel the action.
- First-run provider selection now configures both grammar and custom instructions for the chosen provider.
- Typing an API key enables Get Started immediately; local-only setup opens provider configuration when no local model is selected.
- Missing Accessibility permission, missing provider setup, and expired selection sessions show an actionable explanation.

## [0.3.0] - 2026-09-15

### Changed

- Replaced the large command palette with a two-action Capsule: Fix Grammar and custom instructions.
- Added native Liquid Glass on macOS 26+, with native material fallback on earlier supported macOS versions.
- Reduced loading, completion, and error feedback to small indicators; retained keyboard navigation and Reduce Motion support.
- Replaced the saved-action editor with Writing settings. Grammar and macOS Services now share one prompt and model configuration.
- Added direct OpenRouter support and paid DeepSeek V4.1 Flash as the writing default and explicit local-model fallback.
- Moved API keys into Keychain with verified migration.
- Moved history saves off the UI thread and preserved older records while displaying the latest 500.

### Fixed

- Rewrites replace the original selection through native Paste and remain on the clipboard. Native editor Undo remains available.
- Improved capture when Accessibility omits selected text and released custom-input focus before replacement.
- Blocked incomplete, refused, and empty responses from overwriting source text.
- Fixed cancellation and stale completion timers; refreshed stale model catalogs when Providers opens.

### Upgrade notes

- Existing grammar prompt/model and custom-instruction routing are preserved.
- Retired presets are exported to a readable local recovery file before their preferences are removed.
- Model service accounts and API usage are separate from Companion; an OpenRouter key is required for the new default.
- macOS may ask for Accessibility or Input Monitoring permissions again after updating.

## [0.2.3] - 2026-08-13

### Fixed

- Restored fal/OpenRouter cloud generation after its model ID format changed.
- Migrated existing remote routes away from the retired `~` prefix automatically.
- Replaced retired Claude aliases with current OpenRouter model IDs.

## [0.2.2] - 2026-07-03

Initial public release.

### Added

- Menu bar command palette for running writing actions in other Mac apps.
- Saved actions for grammar fixes, writing cleanup, humanizing, shortening, formal tone, and email drafts.
- One-off custom prompts for selected text or new text at the cursor.
- Provider routes for LM Studio, fal/OpenRouter, OpenAI, Claude, and DeepSeek.
- Per-action model routing, local-to-remote fallback, and local generated-result history.
- Image attachments for routes that support image input.
- Settings panes for providers, actions, history, shortcut, and macOS permissions.

### Release

- Published `Companion-0.2.2.dmg`.
- Signed, notarized, stapled, and verified the app and DMG.

# Changelog

All notable changes to Redraft (formerly Companion) are documented here.

## [0.5.8] - 2026-10-21

### Changed

- The menu bar icon is an owl in reading glasses instead of the magnifying glass. While Redraft rewrites, the owl's eyes move left and right, replacing the three-dot animation.

## [0.5.7] - 2026-10-20

### Fixed

- OpenRouter models that require reasoning, such as Gemini 3.8 Flash, no longer fail with "HTTP 400: Reasoning is mandatory for this endpoint and cannot be disabled." Redraft retries them once with low reasoning effort and hides the reasoning, then remembers the model for the rest of the session.

## [0.5.6] - 2026-10-18

### Changed

- App icon: the document lines are 10% larger inside the tile.
- The menu bar menu is shorter. "Open Command Palette" is now "Redraft Selection" and shows the saved shortcut. "Status: Ready" is gone; a single line appears only while Accessibility is missing and opens System Settings. "Using: …" is now a Model submenu where Local and Cloud can be switched directly. Icons are removed and items regroup: use, configure, app, quit.

## [0.5.5] - 2026-10-18

### Changed

- Settings is one page. The sidebar and the General, History, Shortcut and Permissions pages are gone. Local or Cloud stays at the top; the shortcut, Launch at login and a new "Keep a history of results on this Mac" switch sit below it. Version and credits live in About. An Accessibility warning shows only while the permission is missing.
- The OpenRouter catalog is a menu grouped by vendor instead of a 470-row table with a search field. The API key is checked automatically after typing; the Check key button is gone. Image input and the server address for local models sit behind More options.
- History opens in its own window from Settings or the menu bar. Turning the history switch off stops saving new results and keeps the old ones until Clear.
- About shows the real app icon and a current tagline.

## [0.5.4] - 2026-10-17

### Added

- A Mac App Store edition, built from the same code with `REDRAFT_APP_STORE=1` (`script/build_app_store.sh`). It runs in the App Sandbox, so it checks the selection by copying it again before pasting instead of using the Accessibility API, asks once per cloud provider before sending any text, keeps its keys in its own Keychain entry, and gets updates from the App Store instead of Sparkle. Submitted for review on 2026-10-16 as "Redraft for Mac". The DMG edition is unchanged.

### Changed

- The Capsule is one instruction field. The two-icon view, the General → Open with setting, the Fix Grammar preset and shortcut, and the Services menu item are removed; nothing is injected into prompts that the user didn't type. Return runs what was typed, and Escape closes.
- New app icon: a white document with an orange highlighted line.
- Renamed from Companion to Redraft: app name, menus, windows, notifications, DMG and docs. The bundle ID, saved settings, history folder and Keychain entries keep the old name, so an existing install keeps its keys and permissions. If Companion.app is in Applications, quit it and move it to the Trash after installing Redraft.
- Companion no longer asks for Input Monitoring. The shortcut uses the system's hotkey service, which works in every app without it; only Companion's own permission check needed it, and that check was what made macOS ask. Accessibility is the one permission left. An existing Input Monitoring grant can be removed in System Settings → Privacy & Security.

## [0.5.3] - 2026-10-09

### Changed

- Fix Grammar is now a preset instruction that runs through the same path as anything typed in the Capsule, on the single configured model. The separate grammar prompt, its editor in Settings → Writing, and the second model route are gone. Settings → Writing is removed; its migration notice moved to General. "Recommended" in Settings → Models is now one model, Gemini Flash Lite; DeepSeek Flash remains the fallback when a local model fails.
- In the Capsule's instruction field, Return with nothing typed runs Fix Grammar. The placeholder says so.
- When the result can't be pasted in place, because the app doesn't let Companion verify the selection, the selection changed, or the original app couldn't be brought back, Companion no longer opens the "Your rewrite" panel. The result is copied to the clipboard, the Capsule shows a brief clipboard icon, and a notification says to paste with ⌘V. The panel could be left on screen in some apps with no way to close it.

## [0.5.0] - 2026-10-08

### Changed

- Settings → Providers and the model half of Settings → Writing are now one pane, Settings → Models, with a single Local or Cloud switch. Only the chosen branch is shown: Local has a connection status, one model menu and the cloud fallback; Cloud has one provider, one API key and one model. "Recommended" keeps the tested Gemini Flash Lite + DeepSeek Flash pair. Saved keys and model choices are preserved; an older setup with two different OpenRouter models shows as "Custom" until a new choice is made.
- Onboarding asks Local or Cloud first. Local opens Settings → Models to connect LM Studio; Cloud asks for one provider and one key.
- The fal gateway appears as a provider only when a fal key already exists.
- The menu bar shows what the next rewrite will use, for example "Using: Cloud · OpenRouter · Recommended" or "Using: Local · qwen3-8b". Click it to open Models.
- When a local model fails, the fallback uses the saved Cloud choice when its key exists, then the tested OpenRouter model as before.

### Added

- "Check key" in Settings → Models confirms an OpenRouter, OpenAI, Claude or DeepSeek key with a free read-only request.

## [0.4.1] - 2026-10-06

### Fixed

- Local models work with whatever LM Studio setup a Mac has. Server addresses typed without `http://`, with a trailing slash, or ending in `/v1` are normalized instead of producing a broken request URL, and servers reached through a DNS name (VPN or Tailscale) are no longer blocked by App Transport Security.
- Local requests wait up to 180 seconds instead of 60, so a model that is still loading on a slower Mac is not reported as "not reachable." Timeouts, missing models, and connection failures now each say what to fix.
- Thinking models (Qwen, DeepSeek R1, LFM) no longer paste `<think>` reasoning into the document, and a missing `finish_reason` from a local server is accepted.
- When a local model fails and no OpenRouter key exists for the fallback, the error shows the local failure instead of asking for an OpenRouter key.
- Loading the local model list in Settings → Providers now points Fix Grammar and Custom instruction at the local model when their current route has no API key, so a local-only setup works without a trip to Settings → Writing.

## [0.4.0] - 2026-09-18

### Added

- Optional typing-first entry through General → Open with → Instruction field.
- Web search when a typed instruction includes “use web search,” with source links saved separately in History.
- Request duration in History and source-free copying of search results.

### Changed

- New installations use Gemini 3.5 Flash Lite for typed instructions and DeepSeek V4.1 Flash for grammar via OpenRouter.
- Speed-prioritized provider routing with price caps, disabled DeepSeek reasoning, and minimum Gemini reasoning.
- Simpler instruction guidance and a non-activating panel that avoids activating Companion over the source app.

### Upgrade notes

- Quit the previous app before replacing it in Applications. Saved model choices, prompts, keys, and history remain intact.
- Use Providers → Use recommended models to adopt the new model pair explicitly.
- Other Macs need their own key and permissions; permissions may need re-granting after an update.
- Universal app and DMG signed, notarized, and stapled. Forty-six offline tests passed; an opt-in live search test passed separately.
- Search grounding does not guarantee accuracy, and percentage-length instructions remain approximate.

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

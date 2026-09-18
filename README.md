<p><img src="assets/app-icon.png" width="128" height="128" alt="Companion app icon"></p>

<h1>Companion</h1>

<p>Select text, say what you want changed, and replace it in place.<br>
Use your own cloud API key or a local model.</p>

<p><strong>Version 0.4.0</strong> · macOS 13+ · Apple Silicon & Intel</p>

<p>
  <img src="https://img.shields.io/badge/Swift-f05138" alt="Swift">
  <img src="https://img.shields.io/badge/AppKit-0066cc" alt="AppKit">
  <img src="https://img.shields.io/badge/macOS-000000" alt="macOS">
</p>

<p><a href="https://github.com/madebysan/companion/releases/latest">Download Companion</a></p>

![Companion Capsule](assets/screenshots/capsule.png)

Companion is a menu bar app for quick writing tasks in Mail, Notes, Notion, Slack, browsers, code editors, and most places where you can select or enter text. Its small glass capsule offers two actions: fix grammar or write an instruction.

## How it works

Select text in another app and press `Cmd + Shift + E`. Press Return or click the grammar icon to fix the text. Press Tab or click the pencil to type an instruction such as `make this warmer and shorter`, then Return to run it. Companion uses the model configured in Settings, replaces the selection, and keeps the result on your clipboard. Loading and completion use a small glass indicator that disappears when finished.

Prefer to skip the icons? Choose **Settings → General → Open with → Instruction field**. With nothing selected, use the field to create new text at the cursor. Escape returns to the icons; Escape again closes the capsule. Open Settings through the menu bar or `Cmd + ,`.

Use ordinary instructions such as “make this warmer,” “translate to Spanish,” or “summarize in three bullets.” Review important facts and numbers in AI output; exact percentage lengths are not guaranteed.

## Models and privacy

New installations default to paid DeepSeek V4.1 Flash for grammar and Gemini 3.5 Flash Lite for typed instructions, both through OpenRouter. Existing saved model choices are preserved. Settings → Writing contains their model choices and the grammar prompt. The Capsule and macOS Services use the same grammar configuration. Settings → Providers → Use recommended models applies this pair without changing the grammar prompt. Local fallback uses DeepSeek, never an arbitrary configured frontier model.

Optional routes include LM Studio, the legacy fal gateway, OpenAI, Anthropic, and DeepSeek. The remote model catalog uses direct OpenRouter and refreshes when it is over 24 hours old and the Providers pane opens. A failed refresh preserves the saved catalog.

DeepSeek V4.1 Flash requests prioritize OpenRouter hosts by generation throughput, retain same-model provider fallbacks, and require support for the supplied parameters (including disabled reasoning). Provider rates are capped at $0.30 per million input tokens and $1.20 per million output tokens. If no eligible host meets the cap, the request fails rather than silently paying more or changing models.

Gemini 3.5 Flash Lite uses minimum reasoning (the model rejects reasoning-off), throughput routing, and caps of $0.30/M input and $2.50/M output tokens.

Include `use web search` in your typed instruction to enable one OpenRouter/Exa Fast search (up to three results). Without that phrase, requests remain search-free. Matching is case-insensitive; `do not use web search`, `don't use web search`, and `never use web search` disable it. Selected text alone cannot enable search. The grammar icon never searches. Search requires a direct OpenRouter route and adds provider search charges and latency. Explicitly enabling it allows the prompt and selected content to be processed for search; avoid including private details. Returned source links are shown beneath the result in History, while automatic insertion and Copy Result use the generated text only. Missing usable source metadata stops insertion rather than silently falling back to an ungrounded response. Sources aid verification but do not guarantee factual accuracy or an exact product match.


The former saved-action presets and editor have been retired. Your grammar prompt/model and custom-instruction route migrate to the focused Writing settings. Old presets are exported to a readable JSON recovery file before their preferences are removed; Writing includes a button to reveal that file. If the export fails, old preferences remain intact.

There is no Companion backend or analytics. Cloud requests send the selected text and instruction to the provider route you chose; provider data policies apply. Search adds an external search service. LM Studio generation stays on your Mac when remote fallback is disabled, although opening Providers may contact OpenRouter to refresh the model catalog. Keys are stored in macOS Keychain. Existing preference keys are removed only after secure storage succeeds; a migration failure leaves the old value recoverable and reports an error.

Companion uses the target editor's native Paste operation so its normal Undo command applies. The rewrite remains on the clipboard after Undo. A changed or unverifiable target, or an incomplete model response, leaves the original text untouched and provides the generated text for manual recovery. Undo depends on the receiving editor supporting normal paste undo.

History is stored locally and displays the latest 500 results. Older entries remain on disk; Clear History moves records to a recovery archive rather than securely deleting them. History includes results, routing metadata, and search sources. The original selection and image bytes are not separately recorded, but generated results can repeat sensitive input.

## Install

1. Download the DMG from [Releases](https://github.com/madebysan/companion/releases/latest).
2. Drag `Companion.app` to Applications and open it from the menu bar.
3. Choose a provider during onboarding or configure one later in Settings.
4. Grant Accessibility and Input Monitoring when macOS asks, then relaunch Companion.

Accessibility lets Companion copy a selection and paste the result. Input Monitoring lets the shortcut work while another app is focused. If macOS keeps an old permission entry after an update, remove Companion from both permission lists, add it again, and relaunch.

On a different Mac, grant these permissions again and enter your provider key in setup or Settings → Providers. Provider keys are device-local and are never embedded in the DMG. Setup applies your chosen provider to both writing actions. If setup or permissions are missing, Companion shows an explanation with access to Settings.

## Upgrading an existing installation

Quit the old Companion from its menu bar before replacing it. Drag the new app into Applications, choose Replace, and launch it from Applications. Eject the DMG; do not run a second copy from Downloads or the disk image. About Companion should report 0.4.0. Saved settings, Keychain keys, and history remain on that Mac. An older saved model choice is not automatically switched to Gemini; use Providers → Use recommended models if desired. Permissions may need re-granting after an update. A separate Mac always needs its own API key and permissions.

## Build from source

Use a Swift 5.9-compatible toolchain or newer and a macOS 26+ SDK for the Liquid Glass APIs. The app targets macOS 13+ with runtime availability checks.

```bash
git clone https://github.com/madebysan/companion.git
cd companion
swift build --package-path Companion
swift test --package-path Companion
./script/build_and_run.sh --preview
```

The preview is an isolated UI development build; it does not replace the installed app or use production credentials. The paid web-search smoke test is skipped unless explicitly opted in.

The maintainer's release scripts use a configured Developer ID identity and a `notarytool` Keychain profile. Configure your own signing setup before running `./script/build_dmg.sh --notarize` for distribution. This notarizes and staples the app and disk image, verifies Gatekeeper acceptance, and copies the DMG to the Desktop. Packaging does not replace the installed app. Existing versioned artifacts are never overwritten.

Companion requires macOS 13 or later on Apple Silicon or Intel. LM Studio and cloud provider keys are optional; at least one local or remote model route is required to generate text.

## Tech stack

Development notes: [interface rules](DESIGN.md).

For an isolated local preview, run `./script/build_and_run.sh --preview`.

- Swift and AppKit
- Swift Package Manager
- [HotKey](https://github.com/soffes/HotKey) for global shortcuts
- LM Studio and OpenAI-compatible chat routes
- Anthropic Messages API for direct Claude support

## Feedback

[Open an issue](https://github.com/madebysan/companion/issues) with your macOS version, Companion version, and the app you were editing. Do not include API keys or private selected text. See the [changelog](CHANGELOG.md) for release details.

## License

[MIT](LICENSE)

Made by [santiagoalonso.com](https://santiagoalonso.com)

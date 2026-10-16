<p><img src="assets/app-icon.png" width="128" height="128" alt="Redraft app icon"></p>

<h1>Redraft</h1>

<p>Select text. Say what you want changed. Keep writing.<br>
Writing Tools for every Mac: rewrite selected text in any app with your own or a local model.</p>

<p><strong>Version 0.5.3</strong> · macOS 13+ · Apple Silicon & Intel</p>

<p>
  <img src="https://img.shields.io/badge/Swift-f05138" alt="Swift">
  <img src="https://img.shields.io/badge/AppKit-0066cc" alt="AppKit">
  <img src="https://img.shields.io/badge/macOS-000000" alt="macOS">
</p>

<p><a href="https://github.com/madebysan/redraft/releases/latest">Download Redraft</a></p>

![Redraft Capsule](assets/screenshots/capsule.png)

A small menu bar app for fixing grammar, rewriting, translating, and summarizing text where you already work. No separate chat window to copy things back from.

## One shortcut, two choices

Select text and press **⌘⇧E**. Fix grammar immediately, or type an instruction: “make this warmer,” “translate to Spanish,” “summarize in three bullets.”

The result replaces your selection and stays on the clipboard. Your editor's normal **⌘Z** undoes the paste. If Redraft can't safely verify the selection, it leaves your text alone, copies the result to the clipboard, and tells you to paste it with **⌘V**.

Prefer typing? Skip the icons with **Settings → General → Open with → Instruction field**. With nothing selected, write something new at the cursor.

## Search when you need it

Add **“use web search”** to your instruction to look things up. Sources stay in History, not in the inserted text. Otherwise, no search runs.

Search adds cost and delay, and sends context to a search provider. Review important claims; AI output isn't guaranteed accurate.

## Bring your own model

Pick Local or Cloud in Settings → Models. Local runs a model on your Mac through LM Studio. Cloud uses one provider, one API key and one model; the recommended choice is Gemini Flash Lite through OpenRouter.

Keys live in macOS Keychain. No Redraft backend or analytics. Cloud usage is billed separately; results and history stay saved on your Mac.

## Permissions, plainly

macOS asks you to allow one thing. Here is what Redraft does with it:

- **Accessibility** lets Redraft read the text you selected, open its panel next to it, and press **⌘C** and **⌘V** for you to copy the selection and paste the result. It does this only when you call Redraft. If you cancel, your previous clipboard comes back.

The shortcut works in every app without Input Monitoring, so Redraft doesn't ask for it.

## Get started

Download the signed, notarized DMG, drag Redraft into Applications, configure a provider, and grant Accessibility.

**Upgrading?** Quit the old app before replacing it. Your settings and keys are preserved; permissions may need re-granting.

[Release notes](CHANGELOG.md) · [Report an issue](https://github.com/madebysan/redraft/issues) · [MIT license](LICENSE) · [Third-party notices](THIRD_PARTY_NOTICES.md)

Made by [santiagoalonso.com](https://santiagoalonso.com)

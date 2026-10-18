<p><img src="assets/app-icon.png" width="128" height="128" alt="Redraft app icon"></p>

<h1>Redraft</h1>

<p>Writing Tools for every Mac, including Intel and macOS 13.<br>
Select text in any app, type what to change, and it's replaced in place.</p>

<p><strong>Version 0.5.5</strong> · macOS 13+ · Apple Silicon & Intel</p>

<p>
  <img src="https://img.shields.io/badge/Swift-f05138" alt="Swift">
  <img src="https://img.shields.io/badge/AppKit-0066cc" alt="AppKit">
  <img src="https://img.shields.io/badge/macOS-000000" alt="macOS">
</p>

<p><a href="https://github.com/madebysan/redraft/releases/latest">Download Redraft</a></p>

![Redraft's capsule: one field that asks what should change](assets/screenshots/capsule.png)

Redraft is a menu bar app for fixing grammar, rewriting, translating and summarizing text where you already write, with no chat window to copy back from.

- Press `⌘⇧E` on a selection, then type what should change: "fix grammar", "make this warmer", "translate to Spanish".
- The result replaces your text, and your editor's `⌘Z` undoes it.
- Use your own cloud key or a local model through LM Studio.

## How it works

With nothing selected, Redraft writes something new at the cursor. Add "use web search" to an instruction to look things up; the sources stay in History, not in your text. If Redraft can't safely confirm the selection, it leaves your text alone and puts the result on the clipboard. The full behavior is in [docs/how-it-works.md](docs/how-it-works.md).

## Privacy

Redraft asks for one permission, Accessibility, to read your selection and copy and paste for you, and only when you call it. Cloud keys stay in the macOS Keychain, and there's no Redraft server or analytics. Web search sends context to a search provider. Redraft checks for updates through [Sparkle](https://sparkle-project.org).

## Install

Download the signed, notarized DMG from the [latest release](https://github.com/madebysan/redraft/releases/latest), drag Redraft to Applications, choose a model in Settings and allow Accessibility. When upgrading, quit the old app first; settings and keys carry over. Changes are in the [release notes](CHANGELOG.md).

---

[MIT](LICENSE). Third-party components and their licenses are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Made by [santiagoalonso.com](https://santiagoalonso.com)

# How Redraft works

The shortcut, web search, model choices and the one permission it needs, in full. The short version is the [README](../README.md).

## One shortcut, one field

Select text and press **⌘⇧E**, then type what should change: “fix grammar,” “make this warmer,” “translate to Spanish,” “summarize in three bullets.” Return runs it.

The result replaces your selection and stays on the clipboard. Your editor's normal **⌘Z** undoes the paste. If Redraft can't safely verify the selection, it leaves your text alone, copies the result to the clipboard, and tells you to paste it with **⌘V**.

With nothing selected, write something new at the cursor.

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

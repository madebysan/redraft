# App Review notes

Hello App Review team.

Redraft is a menu bar app that rewrites selected text in any app with an AI model the user brings: a free local model (LM Studio) or the user's own cloud API key (OpenRouter, OpenAI, Anthropic, DeepSeek). Redraft has no account and no server, and sells nothing, so it has no built-in model or demo key.

The attached screen recording shows the full flow with a local model, from selecting text to the replaced result.

To test it yourself:
1. Install LM Studio (free, lmstudio.ai), download any small chat model (for example gemma-3-4b) and turn on its local server. Or use any OpenRouter, OpenAI or Anthropic API key.
2. Open Redraft. It appears in the menu bar (sparkle and magnifying glass icon). Onboarding asks Local or Cloud: choose Local (or Cloud and paste a key) and click Get Started.
3. macOS asks for permission under Privacy & Security → Accessibility. Turn on Redraft. This is the "post keyboard events" permission: Redraft presses ⌘C to copy the selection and ⌘V to paste the result, only when the user presses the Redraft shortcut. Redraft does not use the Accessibility API (AXUIElement) and does not read the screen.
4. Open TextEdit, type a sentence with a typo, select it, press ⌘⇧E.
5. Press Return to fix grammar, or type an instruction such as "make this formal" and press Return.
6. With a cloud key, the first time Redraft asks before sending text to that provider (guideline 5.1.2(i)). Click Allow.
7. The selection is replaced. ⌘Z in TextEdit undoes it. History is in the menu bar menu → Settings... → History.

Without a model or key, steps 2–4 still work and the panel explains that a model must be chosen in Settings → Models.

Why keystrokes: the app's only job is to replace text the user selected, at the user's request. Copy and paste are the only sandbox-compatible way to read and replace a selection in another app. Before pasting, Redraft copies again to confirm the same text is still selected; if not, it leaves the document alone and puts the result on the clipboard.

Other:
- App Transport Security allows plain HTTP only so users can reach their own LM Studio server on their network.
- No account, no developer server, no analytics, no in-app purchases.
- Updates come only from the Mac App Store.

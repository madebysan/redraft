# App Review notes (draft)

Hello App Review team.

Redraft is a menu bar app that rewrites selected text in any app with an AI model the user chooses.
Login: none. To test with a cloud model, use the OpenRouter key below (prepaid test key, limited credit). [ADD KEY IN APP STORE CONNECT ONLY]

Main review flow:
1. Open Redraft. It appears in the menu bar (sparkle and magnifying glass icon). Onboarding asks Local or Cloud: choose Cloud, OpenRouter, paste the test key, click Get Started.
2. macOS asks for permission under Privacy & Security → Accessibility. Turn on Redraft. This is the "post keyboard events" permission: Redraft presses ⌘C to copy the selection and ⌘V to paste the result, only when the user presses the Redraft shortcut. Redraft does not use the Accessibility API (AXUIElement) and does not read the screen.
3. Open TextEdit, type a sentence with a typo, select it, press ⌘⇧E.
4. Press Return to fix grammar, or type an instruction such as "make this formal" and press Return.
5. The first time, Redraft asks before sending text to OpenRouter (guideline 5.1.2(i)). Click Allow.
6. The selection is replaced. ⌘Z in TextEdit undoes it. History is in the menu bar menu → Settings... → History.

Why keystrokes: the app's only job is to replace text the user selected, at the user's request. Copy and paste are the only sandbox-compatible way to read and replace a selection in another app. Before pasting, Redraft copies again to confirm the same text is still selected; if not, it leaves the document alone and puts the result on the clipboard.

Other:
- App Transport Security allows plain HTTP only so users can reach their own LM Studio server on their network.
- No account, no developer server, no analytics, no in-app purchases.
- Updates come only from the Mac App Store.

A screen recording of this flow is attached.

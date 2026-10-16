# Redraft: Mac App Store listing (store edition)

Draft 2026-10-16. Free. First submission, manual release after approval.

| Field | Value |
| --- | --- |
| Name | Redraft for Mac ("Redraft" is taken on the App Store) |
| Subtitle (30 max) | Rewrite text in any app |
| Bundle ID | com.santiagoalonso.redraft (the DMG keeps com.santiagoalonso.companion) |
| SKU | redraft-mac |
| Category | Productivity (secondary: Utilities) |
| Price | Free |
| Age rating | 4+ (no objectionable content; the user writes the instructions) |
| Export compliance | HTTPS only, exempt (`ITSAppUsesNonExemptEncryption` = false) |
| Copyright | 2026 Santiago Alonso |
| Support URL | https://santiagoalonso.com/redraft/support (page written in personal-portfolio, not yet deployed) |
| Privacy policy URL | https://santiagoalonso.com/redraft/privacy (same) |

## Promotional text (170 max)

Select text in any Mac app, press ⌘⇧E, and say how to change it. Fix grammar, rewrite, translate or summarize with your own AI model.

## Description

Redraft rewrites selected text right where you write: Mail, Notes, Pages, Slack, your browser.

Select text and press ⌘⇧E. Fix grammar with one key, or type an instruction: "make this warmer," "translate to Spanish," "summarize in three bullets." The result replaces your selection, and your app's normal Undo brings the original back. With nothing selected, Redraft writes new text at the cursor.

Bring your own model
• Local: run a model on your Mac with LM Studio. Nothing leaves your Mac.
• Cloud: use your own key for OpenRouter, OpenAI, Anthropic or DeepSeek. Keys stay in your Mac's Keychain.

Search when you ask
Add "use web search" to an instruction to look things up (OpenRouter). Sources are kept in History, not pasted into your text.

Careful by design
Before replacing anything, Redraft checks that the same text is still selected. If it isn't, it leaves your text alone and copies the result so you can paste it yourself.

Private
No account, no Redraft server, no analytics. Redraft asks before sending text to a cloud provider for the first time. Results are saved in History on your Mac.

Redraft needs one permission, listed under Privacy & Security → Accessibility, so it can press ⌘C and ⌘V for you when you call it. Cloud model usage is billed by your provider.

## Keywords (100 max)

rewrite,grammar,writing,AI,translate,proofread,summarize,LLM,OpenRouter,LM Studio,local,shortcut

## App Privacy answers

- Data collected by the developer: none. Redraft has no server and no analytics.
- Recommended declaration (matches what WunderType declares): **User Content → Other User Content**, not linked to identity, not used for tracking, purpose App Functionality. Reason: selected text is sent to the AI provider the user chooses, with the user's own key. Choosing "Data Not Collected" is defensible but riskier at review.

## Screenshots

Mac sizes: 2880 × 1800 (or 1440 × 900, 2560 × 1600, 1280 × 800). 3 to 5, real app states:

1. The Capsule next to selected text in Mail or Notes.
2. Typing an instruction ("make this warmer").
3. The replaced text in place.
4. Settings → Models: Local or Cloud.
5. History with web-search sources.

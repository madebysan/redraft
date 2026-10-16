# Redraft interface

Redraft is a frequent, keyboard-first writing utility. The command palette should appear immediately, accept an action, and return the user to their text.

## Palette

Version 0.4.0 uses a non-activating panel and does not activate Redraft when presenting it. General → Open with selects action icons or a directly focused instruction field (existing default remains icons). Hover tracking also works while the source app is active. This behavior has automated coverage and was included in the locally installed build tested by san; cross-machine and older-OS interaction still require device testing.

- Selected direction: **Capsule**, approved by san on September 15, 2026. The floating AppKit `NSPanel` contains one 80 × 36-point glass pill with two 36-point action targets: Fix Grammar and Custom Instruction.
- Use native `NSGlassEffectView` clear glass on macOS 26+, grouped in `NSGlassEffectContainerView`. Follow system appearance. On macOS 13–25 use a native popover material fallback. No painted white background or forced Light Aqua.
- Use SF Symbols at 16 points for actions and 13 points for feedback, with quiet hover feedback, labels for accessibility, and precise tooltips.
- Icon buttons have no blue focus ring. Logical keyboard focus and shortcuts remain active. The instruction field releases focus before native replacement; success feedback must not reactivate Redraft.
- Return or Command-1 runs Fix Grammar. Tab, the pencil, or Command-2 opens the instruction field. Left/Right moves between the two actions. Command-comma opens Settings. Provider choices stay in Settings and the menu bar.
- The instruction field expands only on request to 320 × 40 points. Return submits; Escape returns to the two actions while retaining the draft, then Escape closes the palette.
- Loading, completion, and collapsed error feedback use one 30-point glass circle. Click loading or press Escape to cancel. A checkmark disappears after 700 ms. Error details and Settings are available on demand from the error icon.
- State content fades over 160 ms with ease-out. Opening and keyboard action selection are immediate. Reduce Motion removes the fade and uses static dots instead of a spinner. Progress stops when hidden.
- The transparent window reserves a 10-point inset around the glass. Position beside the selection, expanding from the same leading edge and clamping to the screen.
- Successful rewrites use direct replacement. A separate 360 × 234-point recovery surface appears only when insertion cannot safely finish.
- Recovery also covers a changed/unverifiable selection or an incomplete provider response. The generated text stays on the clipboard; incomplete results cannot be automatically pasted.

## Provider and history settings

- Web search has no extra palette button. The explicit typed phrase `use web search` opts a request in. History shows a Web search marker and a secondary source-link list beneath the result in the existing scroll area. Copy Result and native replacement exclude this source list. Search status must not add a larger floating surface.

- Models is one pane with a Local or Cloud switch at the top; only the chosen branch is visible. Local: a status line with Refresh, one model menu, the image-input checkbox, the cloud fallback checkbox, and the server address behind an Advanced link. Cloud: one provider menu, one secure key field with Check key and a Get-a-key link, and one model control. For OpenRouter that control is a menu whose first entry is Recommended (the tested Gemini 3.5 Flash Lite + DeepSeek V4.1 Flash pair) plus a searchable catalog list to pick one model for both actions; for OpenAI, Claude and DeepSeek it is a text field with the default filled in. Both Capsule actions follow the single choice. No side-by-side provider grids, no enable-many model table.
- Fix Grammar is a preset instruction on the single configured model; there is no separate grammar prompt. No action picker, naming, add/remove, or reordering controls.
- Preserve saved keys and routes on upgrade. The mode is derived from the saved grammar route, the cloud provider from the saved instruction route. A setup the new pane cannot express (two different OpenRouter models) shows as Custom and keeps working until a new choice is made.
- Preserve retired presets in a verified JSON recovery file before removing their preferences; expose recovery from Writing. Keep only a small compatibility reader, not an active saved-action system.
- The legacy fal gateway appears as a provider only when a fal key exists. Other providers remain optional.
- The menu bar shows one line with the current mode, provider and model; clicking it opens Models.
- Show credential storage failures rather than silently reporting a successful save.
- History displays the latest 500 records. Older records are retained; clearing the visible list creates a recovery archive.

## References

Primary reference: the approved native Capsule exploration (September 15, 2026). All three alternatives, including the selected design, are kept in the project's local prototype history. The earlier screenshot in `assets/social-preview.png` records the prior large palette and is not the current layout reference.

## Verification and development

`./script/build_and_run.sh --preview` builds a separate, ad-hoc-signed development app. It does not replace the installed app. Preview preferences and history are separate from production.

Debug preview arguments include `--palette-loading-preview`, `--palette-error-preview`, `--palette-success-preview`, and `--reduce-motion-preview`. With `--snapshot=/absolute/path.png`, the app exports its rendered palette content and exits. Exported content does not include the native window shadow.

The September 15 integration inspected rendered capsule, instruction, loading, completion, and reduced-motion states. Tests cover two-action composition, instruction focus, icon-sized feedback, and the old-completion/new-palette race. Preview bundles remain visible when an inspection tool changes focus; normal app palettes still dismiss on deactivation. The native design lab was tested interactively before selection.

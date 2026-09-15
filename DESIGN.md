# Companion interface

Companion is a frequent, keyboard-first writing utility. The command palette should appear immediately, accept an action, and return the user to their text.

## Palette

- Selected direction: **Capsule**, approved by san on September 15, 2026. The floating AppKit `NSPanel` contains one 80 × 36-point glass pill with two 36-point action targets: Fix Grammar and Custom Instruction.
- Use native `NSGlassEffectView` clear glass on macOS 26+, grouped in `NSGlassEffectContainerView`. Follow system appearance. On macOS 13–25 use a native popover material fallback. No painted white background or forced Light Aqua.
- Use SF Symbols at 16 points for actions and 13 points for feedback, with quiet hover feedback, labels for accessibility, and precise tooltips.
- Icon buttons have no blue focus ring. Logical keyboard focus and shortcuts remain active. The instruction field releases focus before native replacement; success feedback must not reactivate Companion.
- Return or Command-1 runs Fix Grammar. Tab, the pencil, or Command-2 opens the instruction field. Left/Right moves between the two actions. Command-comma opens Settings. Provider choices stay in Settings and the menu bar.
- The instruction field expands only on request to 320 × 40 points. Return submits; Escape returns to the two actions while retaining the draft, then Escape closes the palette.
- Loading, completion, and collapsed error feedback use one 30-point glass circle. Click loading or press Escape to cancel. A checkmark disappears after 700 ms. Error details and Settings are available on demand from the error icon.
- State content fades over 160 ms with ease-out. Opening and keyboard action selection are immediate. Reduce Motion removes the fade and uses static dots instead of a spinner. Progress stops when hidden.
- The transparent window reserves a 10-point inset around the glass. Position beside the selection, expanding from the same leading edge and clamping to the screen.
- Successful rewrites use direct replacement. A separate 360 × 234-point recovery surface appears only when insertion cannot safely finish.
- Recovery also covers a changed/unverifiable selection or an incomplete provider response. The generated text stays on the clipboard; incomplete results cannot be automatically pasted.

## Provider and history settings

- Writing replaces the old Actions pane. It contains model choices for Fix Grammar and Custom Instruction, a shared grammar prompt used by both Capsule and Services, and the inexpensive local-fallback toggle. No action picker, naming, add/remove, or reordering controls.
- Keep the paid writing default in Providers: DeepSeek V4.1 Flash via direct OpenRouter, a secure key field, and one explicit action to reapply it to both writing operations without changing the grammar prompt.
- Preserve retired presets in a verified JSON recovery file before removing their preferences; expose recovery from Writing. Keep only a small compatibility reader, not an active saved-action system.
- Distinguish direct OpenRouter from legacy fal billing. Other providers remain optional.
- Show credential storage failures rather than silently reporting a successful save.
- History displays the latest 500 records. Older records are retained; clearing the visible list creates a recovery archive.

## References

Primary reference: the approved native Capsule exploration. All three alternatives, including the selected design, are preserved at [glass action history](prototypes/history/glass-actions-2026-09-15/README.md). The earlier screenshot in `assets/social-preview.png` records the prior large palette and is not the current layout reference.

## Verification and development

`./script/build_and_run.sh --preview` builds a separate, ad-hoc-signed development app. It does not replace the installed app. Preview preferences and history are separate from production.

Debug preview arguments include `--palette-loading-preview`, `--palette-error-preview`, `--palette-success-preview`, and `--reduce-motion-preview`. With `--snapshot=/absolute/path.png`, the app exports its rendered palette content and exits. Exported content does not include the native window shadow.

The September 15 integration inspected rendered capsule, instruction, loading, completion, and reduced-motion states. Tests cover two-action composition, instruction focus, icon-sized feedback, and the old-completion/new-palette race. Preview bundles remain visible when an inspection tool changes focus; normal app palettes still dismiss on deactivation. The native design lab was tested interactively before selection.

# App icon smoke test, 2026-10-12

First run of the `app-icon` skill: eight concepts in eight styles for Companion. Five were rendered with Magnific Nano Banana Pro at 2K (command-line route, about 75 credits each by Magnific's published price, about 375 in total). Three were drawn as SVG. The prompts are in `prompts/`, raw 2K renders in `renders/`, 1024 masters in `masters/`, and review sheets in `review/` (`all-eight.jpg` is the overview).

| # | Concept (type) | Style | Route | Result |
|---|---|---|---|---|
| 1 | Binary star (name picture) | 18 Dark premium glow | Magnific | Strongest. Followed the style closely, holds up at 16 px. Reads as a planet and moon rather than a binary star. On dark backgrounds the near-black tile edge disappears. |
| 2 | Correction tape (tool object) | 01 Tactile object | Magnific | High craft, true to the style. The object reads clearly at 64 px and becomes an orange blob at 16 px. |
| 3 | Cursor in a circular arrow (action) | 05 Gradient + white glyph | SVG | Very legible at every size, but reads as "refresh I" or history, not as replacing text. |
| 4 | Glass capsule over a line (interface fragment) | 20 Frosted glass | Magnific | The glass is good, but the navy doodle background was copied from reference `20B`, overriding the requested pale palette. |
| 5 | C holding a cursor (letterform) | 15 Flat letterform | SVG | Reads as the letters "CI". The cursor is indistinguishable from a capital I. |
| 6 | Scribble to smooth line (abstract) | 29 Monoline | SVG | Distinctive, but the zigzag reads as a W and the meaning isn't obvious. Thin at 16 px. |
| 7 | Bird on a cursor (character + action) | 23 Soft clay | Magnific | Charming and on-style, but again reads as a bird on a letter I. Tall, narrow composition. |
| 8 | Night desk scene (scene) | 26 Illustrated scene | Magnific | On-style and atmospheric. Muddy at 32 px and below, as expected for scenes. Uses the pen, a category default. |

## Findings

- **Nano Banana Pro follows the style references well** for rendering, material and lighting (1, 2, 7, 8), and respected the full-bleed square instruction every time: no baked-in rounded corners or device frames.
- **Busy reference backgrounds leak.** Reference `20B` has a patterned navy backdrop that replaced the requested palette in result 4. Prefer references with plain backgrounds and state the background explicitly in the prompt.
- **Shapes that double as letters get read as letters.** The I-beam cursor read as a capital I in three directions (3, 5, 7), and the zigzag as a W (6).
- **The SVG route was the weakest.** It was legible but generic and flat next to the generated results. Decision (san): drop the SVG route and focus the skill on image generation.
- **Small sizes:** only the simplest silhouettes (1, and the SVG ones) survive 16 px. Detailed styles need a simplified small version.

## Next

- Build the prompt-idea step (the app-icon studio), then compare models and settings on the same prompts.
- Replace or crop reference `20B` so its background stops leaking.

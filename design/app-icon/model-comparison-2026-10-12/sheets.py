#!/usr/bin/env python3
"""Build the blind scoring sheet (letters only) and the reveal sheet (model names).

The letter-to-model key is written to review/blind-key.json; the order is shuffled per prompt.
"""
import json, random, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path.home() / ".agents/skills/app-icon/scripts"))
import app_icon as A  # noqa: E402

HERE = Path(__file__).resolve().parent
LABELS = {"d1-binary-star": "1  Binary star · 18 Dark premium glow", "d2-correction-tape": "2  Correction tape · 01 Tactile object",
          "d4-glass-capsule": "3  Glass capsule · 20 Frosted glass", "d7-clay-bird": "4  Bird on a cursor · 23 Soft clay 3D",
          "d8-night-desk": "5  Night desk · 26 Illustrated scene", "d9-bauhaus-c": "6  C and companion dot · 08 Bauhaus geometric"}
MODELS = ["nano-banana-pro", "nano-banana-pro-flash", "seedream-v5-pro", "seedream-v5-lite", "seedream-v4-5"]
NAMES = {"nano-banana-pro": "Nano Banana Pro", "nano-banana-pro-flash": "Nano Banana Pro Flash",
         "seedream-v5-pro": "Seedream 5 Pro", "seedream-v5-lite": "Seedream 5 Lite", "seedream-v4-5": "Seedream 4.5"}
CELL, BIG, HEAD = 300, 260, 34
font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 20)
bold = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 30)
rng = random.Random(20261012)


def build(reveal, key):
    rows = list(LABELS)
    sheet = Image.new("RGB", (40 + CELL * 5, len(rows) * (CELL + 110 + HEAD) + 20), (246, 246, 244))
    d = ImageDraw.Draw(sheet)
    for r, pid in enumerate(rows):
        y0 = 10 + r * (CELL + 110 + HEAD)
        d.text((20, y0 + 4), LABELS[pid], fill=(20, 20, 20), font=font)
        for c, (letter, model) in enumerate(key[pid]):
            x = 20 + c * CELL
            y = y0 + HEAD
            files = sorted((HERE / "renders").glob(f"{pid}__{model}.*"))
            if not files:
                d.text((x + 20, y + 100), "missing", fill=(200, 0, 0), font=font); continue
            im = A.load(str(files[0]), 1024)
            m = A.masked(im, BIG); sheet.paste(m, (x + (CELL - BIG) // 2, y), m)
            strip = Image.new("RGB", (BIG, 80), (242, 242, 247)); px = 8
            for s in (64, 32, 16):
                t = A.masked(im, s); strip.paste(t, (px, (80 - s) // 2), t); px += s + 14
            for s in (32,):  # magnified 32 for a closer look
                t = A.masked(im, s).resize((64, 64), Image.NEAREST); strip.paste(t, (px + 6, 8), t)
            sheet.paste(strip, (x + (CELL - BIG) // 2, y + BIG + 8))
            tag = NAMES[model] if reveal else letter
            d.text((x + (CELL - BIG) // 2, y + BIG + 92), tag, fill=(20, 20, 20), font=bold if not reveal else font)
    return sheet


key_path = HERE / "review/blind-key.json"
if key_path.exists():
    key = {k: [tuple(p) for p in v] for k, v in json.loads(key_path.read_text()).items()}
else:
    key = {}
    for pid in LABELS:
        order = MODELS[:]; rng.shuffle(order)
        key[pid] = list(zip("ABCDE", order))
    key_path.write_text(json.dumps(key, indent=2))
build(False, key).save(HERE / "review/blind-sheet.jpg", quality=90)
build(True, key).save(HERE / "review/reveal-sheet.jpg", quality=90)
print("sheets written")

#!/usr/bin/env python3
"""Model comparison runner: same prompts and style references, only the model changes.

Resumable: an existing output is skipped. Usage: run.py [--prompts d1,d2] [--models key,key]
Run with the magnific-cli virtualenv; uses the magnific skill's generate.py client.
"""
import argparse, hashlib, json, shutil, sys, time
from pathlib import Path
import requests

sys.path.insert(0, str(Path.home() / ".agents/skills/magnific"))
import generate as g  # noqa: E402

HERE = Path(__file__).resolve().parent
REFS = Path.home() / ".agents/skills/app-icon/references/styles"
SMOKE = HERE.parent / "smoke-test-2026-10-12/renders"
GUIDE = "Style reference only: copy the rendering, material, lighting and palette, not the subject."
PROMPTS = {
    "d1-binary-star": ("18A-dark-premium-glow.png", "18B-dark-premium-glow.png"),
    "d2-correction-tape": ("01A-tactile-object.png", "01B-tactile-object.png"),
    "d4-glass-capsule": ("20A-frosted-glass.png", "20B-frosted-glass.png"),
    "d7-clay-bird": ("23A-soft-clay-3d.jpg", "23B-soft-clay-3d.png"),
    "d8-night-desk": ("26A-illustrated-scene.png", "26B-illustrated-scene.png"),
    "d9-bauhaus-c": ("08A-bauhaus-geometric.png", "08B-bauhaus-geometric.jpg"),
}
MODELS = {"nano-banana-pro": "2K", "nano-banana-pro-flash": "2K", "seedream-v5-pro": "2k",
          "seedream-v5-lite": None, "seedream-v4-5": None}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompts", default=",".join(PROMPTS))
    ap.add_argument("--models", default=",".join(MODELS))
    args = ap.parse_args()
    manifest_path = HERE / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else []
    key = g.get_key()
    for pid in args.prompts.split(","):
        prompt = (HERE / "prompts" / f"{pid}.txt").read_text().strip()
        phash = hashlib.sha256(prompt.encode()).hexdigest()[:12]
        refs = [str(REFS / r) for r in PROMPTS[pid]]
        for mkey in args.models.split(","):
            res = MODELS[mkey]
            stem = HERE / "renders" / f"{pid}__{mkey}"
            if list(stem.parent.glob(stem.name + ".*")):
                print(f"skip {stem.name} (exists)"); continue
            entry = {"prompt_id": pid, "prompt_sha256_12": phash, "model": mkey, "label": g.MODELS[mkey].label,
                     "resolution": res, "references": list(PROMPTS[pid]), "aspect": "1:1",
                     "reference_text": GUIDE if g.MODELS[mkey].reference_format == "objects" else None,
                     "credits_estimate": g.MODELS[mkey].cost_for(res)}
            smoke = SMOKE / f"{pid}.png"
            if mkey == "nano-banana-pro" and smoke.exists():
                shutil.copy(smoke, stem.with_suffix(".png"))
                entry.update(file=stem.with_suffix(".png").name, reused="smoke test, identical prompt and settings", seconds=None)
                manifest.append(entry); manifest_path.write_text(json.dumps(manifest, indent=2))
                print(f"reused {stem.name}"); continue
            print(f"generating {stem.name} ...", flush=True)
            t = time.time()
            with requests.Session() as s:
                try:
                    resolved = g.resolve_references(s, key, refs)
                    endpoint, body = g.build_body(mkey, prompt, "1:1", res, resolved, GUIDE)
                    error, path = g.generate_one(s, key, endpoint, body, stem)
                except Exception as exc:  # record and continue with the next model
                    error, path = str(exc), None
            entry.update(seconds=round(time.time() - t), error=error, file=path.name if path else None)
            manifest.append(entry); manifest_path.write_text(json.dumps(manifest, indent=2))
            print(f"  {'saved ' + path.name if path else 'ERROR ' + str(error)} ({entry['seconds']}s)", flush=True)


if __name__ == "__main__":
    main()

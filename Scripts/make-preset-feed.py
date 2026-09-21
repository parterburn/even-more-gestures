#!/usr/bin/env python3
"""Wrap bundled app presets in the versioned, data-only public feed."""

import json
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: make-preset-feed.py REVISION OUTPUT.json")
    revision = int(sys.argv[1])
    if revision < 1:
        raise SystemExit("revision must be positive")

    source = Path(__file__).resolve().parents[1] / "Sources/GestureCore/Resources/presets.json"
    presets = json.loads(source.read_text())
    for preset in presets:
        preset.pop("verification", None)
    feed = {"schemaVersion": 1, "revision": revision, "minimumBuild": 3, "presets": presets}
    output = Path(sys.argv[2])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(feed, indent=2, sort_keys=True, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()

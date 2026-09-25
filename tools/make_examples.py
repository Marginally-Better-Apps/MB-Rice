"""Build three original stored-ZIP Ricepack examples with no dependencies."""
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "examples"
OUT.mkdir(exist_ok=True)
license_text = (ROOT / "LICENSE").read_bytes()

themes = [
    ("paper-sample", "Paper Sample", "#F4F0E8", "#24231F", "#B69D73", "A quieter day"),
    ("dusk-sample", "Dusk Sample", "#352D4D", "#F7E9E3", "#E9A6A0", "Slow down a little"),
    ("geometry-sample", "Geometry Sample", "#101923", "#F2F6F7", "#44C5B5", "Find your angle"),
]

for theme_id, name, bg, fg, accent, caption in themes:
    manifest = {
        "schemaVersion": 1, "id": theme_id, "name": name, "version": "0.1.0",
        "author": "Marginally Better Apps", "license": "LICENSES/MIT.txt", "requires": [],
        "tokens": {"background": bg, "foreground": fg, "accent": accent}, "assets": [],
        "components": [{
            "id": "clock", "kind": "widget", "name": "Main Clock", "privacy": "public",
            "families": ["systemSmall", "systemMedium", "systemLarge", "accessoryRectangular"],
            "background": "background",
            "root": {"type": "stack", "axis": "vertical", "spacing": 5, "children": [
                {"type": "text", "text": caption, "token": "accent", "fontSize": 12},
                {"type": "clock", "text": "time", "token": "foreground", "fontSize": 42},
                {"type": "clock", "text": "date", "token": "foreground", "fontSize": 15},
            ]},
        }],
        "slots": [{"role": "main-clock", "component": "clock", "surface": "home"}],
    }
    entries = {
        "manifest.json": json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode(),
        "LICENSES/MIT.txt": license_text,
    }
    with zipfile.ZipFile(OUT / f"{theme_id}.ricepack", "w", compression=zipfile.ZIP_STORED) as archive:
        for path, content in sorted(entries.items()):
            info = zipfile.ZipInfo(path, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_STORED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, content)

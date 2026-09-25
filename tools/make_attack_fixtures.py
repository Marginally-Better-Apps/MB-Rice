"""Generate non-extracting importer fixtures. Uses Python only during development."""
import hashlib
import json
import struct
import warnings
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Tests/Fixtures"
OUT.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(ROOT / "examples/paper-sample.ricepack") as source:
    base = json.loads(source.read("manifest.json"))
    license_text = source.read("LICENSES/MIT.txt")


def encoded(manifest):
    return json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode()


def pack(name, manifest=None, extras=(), compression=zipfile.ZIP_STORED, include_license=True, raw_manifest=None):
    entries = [("manifest.json", raw_manifest if raw_manifest is not None else encoded(manifest or base))]
    if include_license:
        entries.append(("LICENSES/MIT.txt", license_text))
    entries.extend(extras)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", UserWarning)
        with zipfile.ZipFile(OUT / f"{name}.ricepack", "w", compression=compression) as archive:
            for path, content in entries:
                info = zipfile.ZipInfo(path, date_time=(2026, 1, 1, 0, 0, 0))
                info.compress_type = compression
                info.external_attr = 0o100644 << 16
                archive.writestr(info, content)


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


pixels = b"\x00" + b"\xff\x80\x20" * 2 + b"\x00" + b"\xff\x80\x20" * 2
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 2, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b"")

pack("traversal", extras=[("assets/../escape.txt", b"bad")])
pack("duplicate-member", extras=[("manifest.json", encoded(base))])
pack("duplicate-json-key", raw_manifest=encoded(base)[:-1] + b',"id":"shadow"}')
script = json.loads(encoded(base))
script["components"][0]["root"]["children"][0]["type"] = "script"
pack("script-node", script)
unknown = json.loads(encoded(base))
unknown["requires"] = ["remote-code"]
pack("unknown-capability", unknown)
pack("compressed", compression=zipfile.ZIP_DEFLATED)
pack("missing-license", include_license=False)
pack("case-collision", extras=[("LICENSES/mit.txt", b"bad")])
deep = json.loads(encoded(base))
node = {"type": "text", "text": "Deep", "token": "foreground"}
for _ in range(27):
    node = {"type": "stack", "axis": "vertical", "children": [node]}
deep["components"][0]["root"] = node
pack("deep-tree", deep)
image = json.loads(encoded(base))
image["assets"] = [{"id": "pixel", "path": "assets/pixel.png", "mimeType": "image/png", "length": len(png),
                    "sha256": hashlib.sha256(png).hexdigest(), "license": "LICENSES/MIT.txt"}]
image["components"][0]["root"]["children"].append({"type": "image", "asset": "pixel"})
pack("valid-image", image, extras=[("assets/pixel.png", png)])
image["assets"][0]["sha256"] = "0" * 64
pack("hash-mismatch", image, extras=[("assets/pixel.png", png)])
image["assets"][0]["sha256"] = hashlib.sha256(png).hexdigest()
pack("missing-asset", image)
malformed = b"not a PNG"
bad_image = json.loads(encoded(image))
bad_image["assets"][0]["length"] = len(malformed)
bad_image["assets"][0]["sha256"] = hashlib.sha256(malformed).hexdigest()
pack("malformed-image", bad_image, extras=[("assets/pixel.png", malformed)])
fake_length = bytearray((OUT / "valid-image.ricepack").read_bytes())
central = fake_length.index(b"PK\x01\x02")
struct.pack_into("<I", fake_length, central + 24, len(png) + 1)
(OUT / "fake-length.ricepack").write_bytes(fake_length)
with zipfile.ZipFile(OUT / "symlink.ricepack", "w", compression=zipfile.ZIP_STORED) as archive:
    for path, content, mode in [("manifest.json", encoded(image), 0o100644),
                                ("LICENSES/MIT.txt", license_text, 0o100644),
                                ("assets/pixel.png", png, 0o120777)]:
        info = zipfile.ZipInfo(path, date_time=(2026, 1, 1, 0, 0, 0))
        info.external_attr = mode << 16
        archive.writestr(info, content)

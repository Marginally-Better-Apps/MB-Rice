# Ricepack development format

Version 1 is still a development schema. A `.ricepack` is a UTF-8 ZIP archive with stored, uncompressed members. Its root contains `manifest.json`, a referenced license text under `LICENSES/`, and declared raster files under `assets/`. ZIP deflate, encryption, data descriptors, nested archives, scripts and undeclared members are rejected by this build.

The manifest has required keys `schemaVersion`, `id`, `name`, `version`, `author`, `license`, `requires`, `tokens`, `assets`, `components`, and `slots`. `requires` must currently be empty. Colors use six-digit RGB hex. Component kinds are `widget`, `wallpaper`, and `icon`; only widget scenes render in this build. Widget nodes are finite `canvas`, `stack`, `text`, `clock`, `symbol`, `shape`, `gradient`, `image`, and `spacer` values. Clock modes are `time`, `date`, and `weekday`. Symbol names use the fixed allowlist in `RiceValidator.symbols`. Text and clock nodes can set `fontDesign` to `default`, `rounded`, `serif`, or `monospaced`; text nodes can set `textAlignment` to `leading`, `center`, or `trailing`. Any node can set `opacity` from 0 to 1. A `canvas` places each child using optional normalized `x`, `y`, `width`, and `height` values between 0 and 1. Width and height must be at least 0.05; coordinates remain within the canvas.

Example:

```json
{
  "schemaVersion": 1,
  "id": "my-paper",
  "name": "My Paper",
  "version": "0.1.0",
  "author": "A creator",
  "license": "LICENSES/CC0.txt",
  "requires": [],
  "tokens": {"background":"#F4F0E8","foreground":"#24231F","accent":"#B69D73"},
  "assets": [],
  "components": [{
    "id":"clock","kind":"widget","name":"Clock","privacy":"public",
    "families":["systemSmall","systemMedium","accessoryRectangular"],
    "background":"background",
    "root":{"type":"stack","axis":"vertical","children":[
      {"type":"clock","text":"time","token":"foreground","fontSize":42},
      {"type":"clock","text":"date","token":"accent","fontSize":16}
    ]}
  }],
  "slots": [{"role":"main-clock","component":"clock","surface":"home"}]
}
```

Each asset declares `id`, `path`, `mimeType`, `length`, `sha256`, and `license`. SHA-256 checks bytes, not author identity or rights. The app accepts a single-frame PNG, JPEG, or static WebP with at most 16 million decoded pixels and 8192 pixels per edge. Files and license text stay local. Exports contain public theme data; slot bindings and App Group state stay on the device.

Initial limits: 50 MiB archive, 150 MiB total expanded bytes, 512 ZIP entries, 20 MiB per entry, 1 MiB manifest, 512 scene nodes, 24 scene levels, and eight distinct image assets per component. Some limits matter less while only stored ZIP entries are supported. See `RiceLimits` and `RiceValidator` for the executable policy.

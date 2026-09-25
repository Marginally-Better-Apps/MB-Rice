"""Generate the original Rice app icon. Development tool; not shipped in the app."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

SIZE = 1024
SCALE = 4
out = Path(__file__).resolve().parents[1] / "Apps/Rice/Assets.xcassets/AppIcon.appiconset"
out.mkdir(parents=True, exist_ok=True)

image = Image.new("RGB", (SIZE * SCALE, SIZE * SCALE), "#302946")
draw = ImageDraw.Draw(image)
for radius in [390, 312, 235, 158]:
    box = [512 - radius, 512 - radius, 512 + radius, 512 + radius]
    draw.ellipse([v * SCALE for v in box], outline="#F8C05A", width=9 * SCALE)

draw.ellipse([v * SCALE for v in [430, 430, 594, 594]], fill="#715C85")
font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Georgia Bold.ttf", 430 * SCALE)
bounds = draw.textbbox((0, 0), "R", font=font)
width, height = bounds[2] - bounds[0], bounds[3] - bounds[1]
draw.text(((SIZE * SCALE - width) / 2 - bounds[0], (SIZE * SCALE - height) / 2 - bounds[1] - 42 * SCALE), "R", fill="#FCF9D4", font=font)
image.resize((SIZE, SIZE), Image.Resampling.LANCZOS).save(out / "AppIcon.png")
(out / "Contents.json").write_text('''{
  "images" : [{ "filename" : "AppIcon.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }],
  "info" : { "author" : "xcode", "version" : 1 }
}
''')

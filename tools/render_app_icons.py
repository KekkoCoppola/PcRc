"""Rasterizza le icone SVG dei processi monitorati in PNG per l'app.

L'SVG di Antigravity usa maschere e sfocature gaussiane (feGaussianBlur) che
flutter_svg non supporta: lo rende Chrome headless, poi si ritaglia e si
centra su un quadrato trasparente.

Uso:  python tools/render_app_icons.py
Input:  tools/icons/{claude,antigravity}.svg
Output: PcRc/assets/icons/{claude,antigravity}.png (192x192 RGBA)
"""

import subprocess
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = ROOT / "tools" / "icons"
OUT_DIR = ROOT / "PcRc" / "assets" / "icons"

CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
RENDER_PX = 512
OUT_PX = 192
PADDING = 0.04  # margine trasparente attorno al disegno, frazione del lato

# nome -> colore che sostituisce `currentColor` (None = SVG gia' a colori)
ICONS = {
    "claude": "#D27354",
    "antigravity": None,
}


def render(svg_text: str, workdir: Path) -> Image.Image:
    svg_file = workdir / "icon.svg"
    svg_file.write_text(svg_text, encoding="utf-8")
    html = workdir / "icon.html"
    html.write_text(
        "<html><body style='margin:0;background:transparent'>"
        f"<img src='icon.svg' style='display:block;width:{RENDER_PX}px;height:{RENDER_PX}px'>"
        "</body></html>",
        encoding="utf-8",
    )
    png = workdir / "icon.png"
    subprocess.run(
        [
            CHROME,
            "--headless=new",
            "--disable-gpu",
            "--hide-scrollbars",
            "--default-background-color=00000000",
            f"--window-size={RENDER_PX},{RENDER_PX}",
            f"--screenshot={png}",
            html.as_uri(),
        ],
        check=True,
        capture_output=True,
    )
    return Image.open(png).convert("RGBA")


def square_trim(img: Image.Image) -> Image.Image:
    """Ritaglia sul disegno e lo centra in un quadrato, cosi' le icone hanno
    lo stesso ingombro visivo anche se gli SVG hanno margini diversi."""
    box = img.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    art = img.crop(box)
    side = round(max(art.size) * (1 + 2 * PADDING))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(art, ((side - art.width) // 2, (side - art.height) // 2))
    return canvas.resize((OUT_PX, OUT_PX), Image.LANCZOS)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, color in ICONS.items():
        svg = (SRC_DIR / f"{name}.svg").read_text(encoding="utf-8")
        if color:
            svg = svg.replace("currentColor", color)
        with tempfile.TemporaryDirectory() as tmp:
            icon = square_trim(render(svg, Path(tmp)))
        out = OUT_DIR / f"{name}.png"
        icon.save(out, optimize=True)
        print(f"written: {out} ({out.stat().st_size / 1024:.1f} KB)")


if __name__ == "__main__":
    main()

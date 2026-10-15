"""Genera l'icona launcher Android di PcRc dal logo SVG.

Il logo usa sfocature (feGaussianBlur, feDropShadow) e pattern che i
VectorDrawable non supportano: lo rende Chrome headless in grande, poi Pillow
scala ogni densita'.

Dal SVG (512x512, il primo <rect> figlio della radice e' lo sfondo) produce:
- ic_launcher_background.png  sfondo adattivo a tutto campo (108dp)
- ic_launcher_foreground.png  disegno senza sfondo, nella zona sicura di 66dp
- ic_launcher_monochrome.png  solo le linee chiare, per le icone a tema (Android 13+)
- ic_launcher.png             icona legacy (pre Android 8) = SVG cosi' com'e'
piu' tools/logo/{1024,play_store_512}.png e un'anteprima con le maschere.

Uso:  python tools/render_launcher_icon.py
Input:  tools/logo/pcrc_logo.svg
Output: app/android/app/src/main/res/mipmap-*/ic_launcher*.png,
        tools/logo/{1024,play_store_512,preview}.png
"""

import copy
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
LOGO_DIR = ROOT / "tools" / "logo"
SRC = LOGO_DIR / "pcrc_logo.svg"
RES_DIR = ROOT / "app" / "android" / "app" / "src" / "main" / "res"

CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
RENDER_PX = 1728  # 108dp x 16
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

# Inquadratura del primo piano, in unita' SVG: centro del disegno e lato del
# quadrato che diventa il canvas adattivo di 108dp. Il disegno (dalla cima
# dell'arco esterno, y~11, ai piedini, y~462) sta in un cerchio di raggio ~232
# unita' -> ~33dp, cioe' dentro la zona sicura (66dp di diametro).
FG_CENTER = (261, 236)
FG_SIDE = 760

# Monocromo: luminanza (sul nero) fino a questa soglia -> trasparente, cosi' i
# riempimenti scuri del case spariscono e restano linee e bagliori.
MONO_FLOOR = 48

SVG_NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG_NS)
RECT = f"{{{SVG_NS}}}rect"
DEFS = f"{{{SVG_NS}}}defs"


def render(svg: ET.Element, workdir: Path) -> Image.Image:
    svg_file = workdir / "icon.svg"
    svg_file.write_bytes(ET.tostring(svg, encoding="utf-8"))
    html = workdir / "icon.html"
    html.write_text(
        "<html><body style='margin:0;background:transparent'>"
        f"<img src='icon.svg' style='display:block;width:{RENDER_PX}px;height:{RENDER_PX}px'>"
        "</body></html>",
        encoding="utf-8",
    )
    png = workdir / "icon.png"
    png.unlink(missing_ok=True)
    subprocess.run(
        [
            CHROME,
            "--headless=new",
            "--disable-gpu",
            "--hide-scrollbars",
            "--default-background-color=00000000",
            "--force-device-scale-factor=1",
            f"--window-size={RENDER_PX},{RENDER_PX}",
            f"--screenshot={png}",
            html.as_uri(),
        ],
        check=True,
        capture_output=True,
    )
    img = Image.open(png).convert("RGBA")
    if img.size != (RENDER_PX, RENDER_PX):
        raise RuntimeError(f"render {img.size}, atteso {RENDER_PX}x{RENDER_PX}")
    return img


def split_layers(root: ET.Element) -> tuple[ET.Element, ET.Element]:
    """(primo piano, sfondo) inquadrati sul canvas adattivo."""
    x0 = FG_CENTER[0] - FG_SIDE / 2
    y0 = FG_CENTER[1] - FG_SIDE / 2
    view = f"{x0:g} {y0:g} {FG_SIDE} {FG_SIDE}"

    fg = copy.deepcopy(root)
    fg.remove(fg.find(RECT))
    fg.set("viewBox", view)

    bg = copy.deepcopy(root)
    rect = bg.find(RECT)
    for child in list(bg):
        if child is not rect and child.tag != DEFS:
            bg.remove(child)
    for attr in ("rx", "ry"):
        rect.attrib.pop(attr, None)
    rect.attrib.update(x=f"{x0:g}", y=f"{y0:g}", width=str(FG_SIDE), height=str(FG_SIDE))
    bg.set("viewBox", view)
    return fg, bg


def monochrome(fg: Image.Image) -> Image.Image:
    on_black = Image.alpha_composite(Image.new("RGBA", fg.size, (0, 0, 0, 255)), fg)
    alpha = on_black.convert("L").point(
        lambda v: 0 if v <= MONO_FLOOR else round((v - MONO_FLOOR) * 255 / (255 - MONO_FLOOR))
    )
    mono = Image.new("RGBA", fg.size, (255, 255, 255, 0))
    mono.putalpha(alpha)
    return mono


def mask(side: int, shape: str) -> Image.Image:
    """Parte visibile del canvas adattivo: 72dp su 108dp, centrata."""
    m = Image.new("L", (side, side), 0)
    inset = side * 18 / 108
    box = (inset, inset, side - inset, side - inset)
    if shape == "circle":
        ImageDraw.Draw(m).ellipse(box, fill=255)
    else:
        ImageDraw.Draw(m).rounded_rectangle(box, radius=(box[2] - box[0]) * 0.3, fill=255)
    return m


def preview(bg: Image.Image, fg: Image.Image, mono: Image.Image, legacy: Image.Image) -> Image.Image:
    """Cerchio, squircle, icona a tema, legacy; su sfondo chiaro e scuro."""
    s = 432
    bg, fg, mono = (i.resize((s, s), Image.LANCZOS) for i in (bg, fg, mono))
    full = Image.alpha_composite(bg, fg)
    themed = Image.new("RGBA", (s, s), (214, 227, 255, 255))
    glyph = Image.new("RGBA", (s, s), (0, 26, 65, 255))
    glyph.putalpha(mono.getchannel("A"))
    themed.alpha_composite(glyph)

    tiles = []
    for img, shape in ((full, "circle"), (full, "squircle"), (themed, "circle")):
        tile = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        tile.paste(img, (0, 0), ImageChops.multiply(mask(s, shape), img.getchannel("A")))
        tiles.append(tile)
    tile = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    tile.alpha_composite(legacy.resize((288, 288), Image.LANCZOS), (72, 72))
    tiles.append(tile)

    pad = 24
    width = pad + len(tiles) * (s + pad)
    sheet = Image.new("RGBA", (width, 2 * (s + 2 * pad)), (238, 238, 238, 255))
    sheet.paste((30, 30, 30, 255), (0, s + 2 * pad, width, sheet.height))
    for row in range(2):
        for i, t in enumerate(tiles):
            sheet.alpha_composite(t, (pad + i * (s + pad), pad + row * (s + 2 * pad)))
    return sheet


def main():
    root = ET.parse(SRC).getroot()
    if root.find(RECT) is None:
        raise SystemExit(f"{SRC}: manca il <rect> di sfondo come figlio della radice")
    fg_svg, bg_svg = split_layers(root)
    with tempfile.TemporaryDirectory() as tmp:
        fg = render(fg_svg, Path(tmp))
        bg = render(bg_svg, Path(tmp))
        legacy = render(root, Path(tmp))
    mono = monochrome(fg)

    for name, scale in DENSITIES.items():
        folder = RES_DIR / f"mipmap-{name}"
        layer = round(108 * scale)
        for img, kind in ((fg, "foreground"), (bg, "background"), (mono, "monochrome")):
            img.resize((layer, layer), Image.LANCZOS).save(folder / f"ic_launcher_{kind}.png", optimize=True)
        legacy.resize((round(48 * scale),) * 2, Image.LANCZOS).save(folder / "ic_launcher.png", optimize=True)
        print(f"written: mipmap-{name} ({layer}px)")

    legacy.resize((1024, 1024), Image.LANCZOS).save(LOGO_DIR / "1024.png", optimize=True)
    legacy.resize((512, 512), Image.LANCZOS).save(LOGO_DIR / "play_store_512.png", optimize=True)
    preview(bg, fg, mono, legacy).save(LOGO_DIR / "preview.png", optimize=True)
    print(f"written: {LOGO_DIR / 'preview.png'}")


if __name__ == "__main__":
    main()

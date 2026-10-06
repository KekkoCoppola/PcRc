"""Prepara l'asset del case PC per l'app Flutter.

1. Scontorna la foto (sfondo bianco da studio) -> WebP con trasparenza.
2. Ripulisce l'alone bianco sui bordi (decontaminazione colore).
3. Misura la striscia LED a "L" e stampa le costanti normalizzate per
   `PcLedGeometry` in PcRc/lib/widgets/pc_led_painter.dart.

Uso:  python tools/prepare_pc_asset.py
Input:  tools/pc_case_source.jpg
Output: PcRc/assets/images/pc_case.webp
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "tools" / "pc_case_source.jpg"
OUT = ROOT / "PcRc" / "assets" / "images" / "pc_case.webp"

BG_LUM_MIN = 215      # sopra questa luminanza un pixel puo' essere sfondo
BG_SAT_MAX = 30       # ... se anche poco saturo
FLOOR_Y_MIN = 1300    # sotto questa riga (sorgente) c'e' solo base scura + pavimento
FLOOR_LUM_MIN = 125   # ombra grigia del pavimento tra i piedini
FLOOR_EDGE_LUM = 50   # bordo inferiore nero del case: sotto c'e' solo ombra a terra
FLOOR_EDGE_X_MIN = 590  # solo sotto il pannello frontale (sul fianco l'ombra ha rumore scuro)
EDGE_BAND_PX = 2      # banda sul bordo dove si stima l'alpha parziale
CROP_MARGIN_PX = 6
CASE_SEED = (560, 1000)  # punto sicuramente dentro il case (coordinate sorgente)


def _shift_reduce(mask: np.ndarray, radius: int, reduce) -> np.ndarray:
    """Erosione (np.minimum) o dilatazione (np.maximum) quadrata senza scipy."""
    out = mask.copy()
    padded = np.pad(mask, radius, mode="edge")
    h, w = mask.shape
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            out = reduce(out, padded[radius + dy:radius + dy + h, radius + dx:radius + dx + w])
    return out


def _flood(mask: np.ndarray, seeds) -> np.ndarray:
    """Regione di `mask` connessa ai `seeds` (flood fill PIL)."""
    # .copy(): un'immagine da fromarray e' read-only, floodfill non la modificherebbe.
    img = Image.fromarray(np.where(mask, 255, 0).astype(np.uint8), "L").copy()
    for x, y in seeds:
        if img.getpixel((x, y)) == 255:
            ImageDraw.floodfill(img, (x, y), 128)
    return np.asarray(img) == 128


def _below_case_edge(lum: np.ndarray) -> np.ndarray:
    """Ombra a terra: in ogni colonna, cio' che sta sotto l'ultimo pixel nero
    del bordo inferiore del case. Una soglia di luminanza non basta: l'ombra
    (60-125) ha gli stessi valori della carenatura e della mesh."""
    below = np.zeros(lum.shape, dtype=bool)
    dark = lum[FLOOR_Y_MIN:] < FLOOR_EDGE_LUM
    for x in range(FLOOR_EDGE_X_MIN, lum.shape[1]):
        ys = np.flatnonzero(dark[:, x])
        if ys.size:
            below[FLOOR_Y_MIN + ys[-1] + 1:, x] = True
    return below


def cutout(rgb: np.ndarray) -> np.ndarray:
    lum = rgb.mean(axis=2)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    h, w = lum.shape

    candidate = (lum > BG_LUM_MIN) & (sat < BG_SAT_MAX)
    floor = (lum > FLOOR_LUM_MIN) & (sat < BG_SAT_MAX)
    floor[:FLOOR_Y_MIN] = False
    candidate |= floor | _below_case_edge(lum)
    border = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)] \
        + [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]
    background = _flood(candidate, border)

    # Solo il componente connesso del case: via polvere e macchie isolate.
    foreground = _flood(~background, [CASE_SEED])

    # Colore dello sfondo stimato dai pixel di sfondo (bianco leggermente freddo).
    bg_color = rgb[background].mean(axis=0)
    bg_lum = bg_color.mean()

    # Banda di bordo: pixel del case entro EDGE_BAND_PX dallo sfondo.
    eroded = _shift_reduce(foreground, EDGE_BAND_PX, np.minimum)
    band = foreground & ~eroded

    # Colore "pieno" locale del case: il pixel piu' scuro nell'intorno.
    dark_near = _shift_reduce(np.where(foreground, lum, 255.0), 3, np.minimum)
    denom = np.maximum(bg_lum - dark_near, 1.0)
    alpha_band = np.clip((bg_lum - lum) / denom, 0.0, 1.0)

    alpha = np.where(foreground, 1.0, 0.0)
    alpha = np.where(band, alpha_band, alpha)
    alpha[alpha < 0.04] = 0.0

    # Decontaminazione: C = (I - (1 - a) * B) / a  -> niente alone bianco.
    a3 = alpha[..., None]
    safe_a = np.maximum(a3, 1e-3)
    clean = (rgb - (1.0 - a3) * bg_color) / safe_a
    clean = np.where(a3 > 0, np.clip(clean, 0, 255), 0)

    return np.dstack([clean, alpha * 255.0]).round().astype(np.uint8)


def crop_box(rgba: np.ndarray):
    ys, xs = np.where(rgba[..., 3] > 0)
    h, w = rgba.shape[:2]
    return (max(xs.min() - CROP_MARGIN_PX, 0), max(ys.min() - CROP_MARGIN_PX, 0),
            min(xs.max() + CROP_MARGIN_PX + 1, w), min(ys.max() + CROP_MARGIN_PX + 1, h))


def _ridge_x(lum: np.ndarray, y: int, x_guess: float, half: int = 9, thresh: float = 110.0):
    """Centro (pesato) della striscia chiara sulla riga y vicino a x_guess."""
    x0 = int(round(x_guess)) - half
    row = lum[y, x0:x0 + 2 * half + 1]
    weights = np.clip(row - thresh, 0, None)
    if weights.sum() == 0:
        return None
    return x0 + float((weights * np.arange(len(row))).sum() / weights.sum())


def measure_strip(lum: np.ndarray):
    """Fit lineare dei due tratti della striscia (coordinate sorgente)."""
    vert = [(y, _ridge_x(lum, y, 975, half=5)) for y in range(440, 800, 4)]
    vert = [(y, x) for y, x in vert if x is not None]
    vy, vx = np.array(vert).T
    v_fit = np.polyfit(vy, vx, 1)            # x = a*y + b

    diag = []
    guess = lambda y: 948 + (y - 860) * (621 - 948) / (1424 - 860)
    for y in range(880, 1420, 4):
        x = _ridge_x(lum, y, guess(y), half=6)
        if x is not None:
            diag.append((y, x))
    dy, dx = np.array(diag).T
    d_fit = np.polyfit(dy, dx, 1)

    # Piega = intersezione delle due rette.
    bend_y = (d_fit[1] - v_fit[1]) / (v_fit[0] - d_fit[0])
    bend = (np.polyval(v_fit, bend_y), bend_y)
    top_y, end_y = 403.0, 1446.0             # estremi misurati sul profilo
    top = (np.polyval(v_fit, top_y), top_y)
    end = (np.polyval(d_fit, end_y), end_y)
    return top, bend, end


def main():
    rgb = np.asarray(Image.open(SRC).convert("RGB")).astype(np.float64)
    rgba = cutout(rgb)
    x0, y0, x1, y1 = crop_box(rgba)
    cropped = Image.fromarray(rgba[y0:y1, x0:x1], "RGBA")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    cropped.save(OUT, "WEBP", quality=90, method=6)

    w, h = cropped.size
    top, bend, end = measure_strip(rgb.mean(axis=2))
    norm = lambda p: ((p[0] - x0) / w, (p[1] - y0) / h)
    alpha = rgba[y0:y1, x0:x1, 3]
    foot_y = (np.where(alpha.any(axis=1))[0].max()) / h

    print(f"crop source box: {(x0, y0, x1, y1)}  ->  {w}x{h}")
    print(f"written: {OUT}  ({OUT.stat().st_size / 1024:.0f} KB)")
    print("// --- PcLedGeometry constants ---")
    print(f"static const double aspectRatio = {w} / {h};")
    for name, p in (("top", top), ("bend", bend), ("end", end)):
        nx, ny = norm(p)
        print(f"static const Offset {name} = Offset({nx:.4f}, {ny:.4f});  // src {p[0]:.1f},{p[1]:.1f}")
    print(f"static const double stripWidth = {6.0 / w:.4f};  // ~6 px sorgente")
    print(f"static const double footY = {foot_y:.4f};")


if __name__ == "__main__":
    main()

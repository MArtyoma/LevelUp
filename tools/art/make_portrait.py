#!/usr/bin/env python3
"""Портрет для окна диалога — из той же картинки, что и спрайт на карте.

Отдельная генерация дала бы похожего, но другого человека. Поэтому портрет
вырезается из исходника 512x512 (raw_NN.png из art_out/), который уже выбран
для спрайта: голова и плечи, уменьшенные тем же способом, что и спрайт.

    python3 tools/art/make_portrait.py art_out/npc_kim/raw_01.png \\
        assets/portraits/emp_kim_placeholder.png

Хромакей и допуск берутся из meta.json рядом с исходником.
Требует: pip install Pillow
"""

import argparse
import json
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pixelize  # noqa: E402

GAME = Path(__file__).resolve().parents[2]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("raw", help="raw_NN.png из art_out/<имя>/")
    ap.add_argument("out")
    ap.add_argument("--size", type=int, default=48, help="сторона портрета, px (по умолчанию 48)")
    ap.add_argument("--head", type=float, default=0.55,
                    help="какая доля высоты фигуры идёт в кадр (0.55 — голова и плечи)")
    a = ap.parse_args()

    raw_path = Path(a.raw)
    meta_path = raw_path.parent / "meta.json"
    meta = json.loads(meta_path.read_text(encoding="utf-8")) if meta_path.exists() else {}
    raw = Image.open(raw_path)
    img = pixelize.remove_background(raw, tol=meta.get("bg_tol", 40), chroma=meta.get("bg"))
    img = pixelize.drop_specks(img, min_area=max(16, raw.width * raw.height // 4000))
    box = img.getbbox()
    if box is None:
        raise SystemExit("на картинке не найден персонаж")

    # Квадрат по центру головы: центр берём по верхней пятой фигуры, где
    # только голова, — руки и папка в руках его не сдвигают.
    x0, y0, x1, y1 = box
    side = int((y1 - y0) * a.head)
    top = img.crop((x0, y0, x1, y0 + (y1 - y0) // 5)).getbbox()
    cx = x0 + (top[0] + top[2]) // 2 if top else (x0 + x1) // 2
    crop = img.crop((cx - side // 2, y0, cx - side // 2 + side, y0 + side))

    palette_path = GAME / "assets/palette.hex"
    palette = pixelize.load_palette(palette_path) if palette_path.exists() else None
    small = pixelize.to_grid(pixelize.quantize(crop, palette), a.size, a.size, whole=True,
                             dark_share=0.25)
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    small.save(a.out)
    print("портрет %dx%d: %s" % (a.size, a.size, a.out))


if __name__ == "__main__":
    main()

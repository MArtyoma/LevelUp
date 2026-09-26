#!/usr/bin/env python3
"""Значки над головой: «!» — у человека есть для тебя задание, «?» — иди к нему
(или к предмету) за текущим шагом задания. Как в WoW: игроки узнают их без объяснений.

    python3 tools/art/draw_markers.py              # перезаписать значки
    python3 tools/art/draw_markers.py --preview    # плюс увеличенный показ в art_out/

Рисуется кодом, а не нейросетью: это два символа по пять пикселей шириной,
и каждый пиксель в них важен. Цвета — из `assets/palette.hex`.

Лист — одна строка кадров: кадр 0 «!», кадр 1 «?». Его читает
src/actors/quest_marker.gd. Свой рисунок художника кладётся рядом как
`assets/ui/quest_markers.png` (без `_placeholder`) — игра сразу берёт его.
Размер кадра любой, но кадров — два, в одну строку.
Требует: pip install Pillow
"""

import argparse
from pathlib import Path

from PIL import Image

from draw_tiles import load_palette, read_tile_size

GAME = Path(__file__).resolve().parents[2]
OUT = GAME / "assets/ui/quest_markers_placeholder.png"
PREVIEW = GAME / "art_out/ui/quest_markers_preview.png"

# Заливка символа: # — цвет, . — пусто. Контур дорисовывается сам.
GLYPHS = {
    "new": [
        ".###.",
        ".###.",
        ".###.",
        ".###.",
        ".###.",
        "..#..",
        ".....",
        ".###.",
        ".###.",
    ],
    "step": [
        ".###.",
        "##.##",
        "...##",
        "..##.",
        ".##..",
        ".##..",
        ".....",
        ".##..",
        ".##..",
    ],
}
ORDER = ["new", "step"]


def draw_glyph(rows, colors):
    """Символ с тёмным контуром: заливка, тень снизу у каждого штриха, блик сверху."""
    w, h = len(rows[0]), len(rows)
    img = Image.new("RGBA", (w + 2, h + 2), (0, 0, 0, 0))
    px = img.load()
    filled = {(x, y) for y, row in enumerate(rows) for x, c in enumerate(row) if c == "#"}
    for x, y in filled:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                px[x + 1 + dx, y + 1 + dy] = colors["ink"]
    for x, y in filled:
        # Нижний пиксель штриха темнее — у знака появляется объём.
        shade = (x, y + 1) not in filled
        px[x + 1, y + 1] = colors["orange"] if shade else colors["yellow"]
    top_left = min(filled, key=lambda p: (p[1], p[0]))
    px[top_left[0] + 1, top_left[1] + 1] = colors["white"]
    return img


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--preview", action="store_true")
    args = parser.parse_args()

    colors = load_palette()
    frames = [draw_glyph(GLYPHS[name], colors) for name in ORDER]
    fw, fh = frames[0].size
    sheet = Image.new("RGBA", (fw * len(frames), fh), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        sheet.paste(frame, (i * fw, 0))

    # Тайл крупнее 16 — значок растёт целым числом раз, как атлас тайлов.
    scale = max(1, read_tile_size() // 16)
    if scale > 1:
        sheet = sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT)
    print(f"{OUT.relative_to(GAME)}: {len(frames)} кадра по {fw * scale}x{fh * scale}")

    if args.preview:
        PREVIEW.parent.mkdir(parents=True, exist_ok=True)
        bg = Image.new("RGBA", sheet.size, colors["floor"])
        bg.alpha_composite(sheet)
        bg.resize((bg.width * 12, bg.height * 12), Image.NEAREST).save(PREVIEW)
        print(f"показ: {PREVIEW.relative_to(GAME)}")


if __name__ == "__main__":
    main()

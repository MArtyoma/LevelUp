#!/usr/bin/env python3
"""Лист ходьбы персонажа из трёх поз: спереди, сбоку (лицом влево) и со спины.

Генератор (gen_sprite.py) рисует только отдельные позы, кадров анимации он не
умеет. Здесь из позы делается простой шаг:

* спереди и со спины — в кадрах 1 и 3 поднимается то левая, то правая нога
  на пиксель, а корпус чуть приседает;
* сбоку — в кадрах 1 и 3 ноги расходятся «ножницами»: передняя вперёд, задняя
  (чуть темнее) назад, корпус на пиксель ниже. Без этого вид сбоку — самый
  частый в коридоре — скользит по полу, как на коньках.

Для 16x32 этого хватает; настоящие кадры нарисует художник.

    python3 tools/art/make_sheet.py assets/sprites/player_placeholder.png \\
        --front art_out/player/sprite_01.png \\
        --side art_out/player_side/sprite_02.png \\
        --back art_out/player_back/sprite_01.png

    # NPC стоят на месте и «дышат»: одна поза, в кадре 1 плечи и голова ниже на пиксель.
    python3 tools/art/make_sheet.py assets/sprites/npc/emp_kim_placeholder.png \\
        --front art_out/npc_kim/sprite_01.png --idle

Ряды сверху вниз — вниз, влево, вправо, вверх (как в src/core/grid.gd);
вид вправо — зеркало вида влево. Кадров в ряду — 4.
Требует: pip install Pillow
"""

import argparse
from pathlib import Path

from PIL import Image, ImageOps

FRAMES = 4
LEG_ROWS = 5          # сколько нижних строк спрайта считаются ногами


def lift(img: Image.Image, left: bool) -> Image.Image:
    """Кадр шага: одна нога поднята на пиксель, корпус опущен на пиксель."""
    w, h = img.size
    box = img.getbbox()
    if box is None:
        return img.copy()
    feet = box[3]
    top_of_legs = feet - LEG_ROWS
    mid = (box[0] + box[2]) // 2
    legs = img.crop((0, top_of_legs, w, feet))
    # Поднятая нога: её половина ног встаёт на пиксель выше, остальные — на месте.
    split = (0, mid) if left else (mid, w)
    out = Image.new("RGBA", img.size)
    for x0, x1 in ((0, mid), (mid, w)):
        up = 1 if (x0, x1) == split else 0
        out.alpha_composite(legs.crop((x0, 0, x1, LEG_ROWS)), (x0, top_of_legs - up))
    # Корпус — на пиксель ниже, так шаг «пружинит»; верх ног он при этом закрывает.
    out.alpha_composite(img.crop((0, 0, w, top_of_legs)), (0, 1))
    return out


STRIDE_ROWS = 6       # от бедра до пола, строк: столько ног перерисовывается в шаге сбоку
STRIDE_REACH = 3      # на сколько пикселей стопа уходит вперёд и назад от бедра


def _colors(img: Image.Image, top: int, bottom: int) -> list:
    """Непрозрачные цвета полосы строк, от частого к редкому."""
    counts = {}
    px = img.load()
    for y in range(top, bottom):
        for x in range(img.width):
            if px[x, y][3] > 0:
                counts[px[x, y]] = counts.get(px[x, y], 0) + 1
    return sorted(counts, key=counts.get, reverse=True)


def stride(img: Image.Image) -> Image.Image:
    """Кадр шага сбоку (лицом влево): ноги нарисованы заново «ножницами» —
    передняя уходит вперёд, задняя (темнее) назад, у каждой ботинок и контур.
    Цвета брюк, ботинок и контура берутся из самой позы. Корпус — на пиксель ниже."""
    w, h = img.size
    box = img.getbbox()
    if box is None:
        return img.copy()
    feet = box[3]
    top = feet - STRIDE_ROWS
    ink = min(_colors(img, 0, h), key=lambda c: sum(c[:3]))
    pants = next(c for c in _colors(img, top, feet - 2) if c != ink)
    shoe = next((c for c in _colors(img, feet - 2, feet) if c != ink), ink)
    cols = [x for x in range(w) if img.getpixel((x, top))[3] > 0]
    hip = (min(cols) + max(cols) + 1) / 2 if cols else w / 2

    def dark(c):
        return tuple(int(v * .7) for v in c[:3]) + (255,)

    layer = Image.new("RGBA", img.size)
    lp = layer.load()
    # Сначала задняя нога, потом передняя поверх.
    for direction, tint in ((1, dark), (-1, lambda c: c)):
        for y in range(STRIDE_ROWS):
            t = y / (STRIDE_ROWS - 1)
            x0 = round(hip - 1 + direction * STRIDE_REACH * t)
            is_shoe = y >= STRIDE_ROWS - 2
            width = 3 if is_shoe else 2
            # Носок ботинка смотрит вперёд (влево), у обеих ног.
            start = x0 - 1 if is_shoe else x0
            for x in range(start, start + width):
                if 0 <= x < w:
                    lp[x, top + y] = tint(shoe if is_shoe else pants)
    # Контур вокруг ног — там, где прозрачно; строка бедра остаётся открытой.
    outline = layer.copy()
    op = outline.load()
    for y in range(top, feet):
        for x in range(w):
            if lp[x, y][3]:
                continue
            near = any(0 <= x + dx < w and top <= y + dy < feet and lp[x + dx, y + dy][3]
                       for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if near:
                op[x, y] = ink
    out = Image.new("RGBA", img.size)
    out.alpha_composite(outline)
    out.alpha_composite(img.crop((0, 0, w, top)), (0, 1))
    return out


def breathe(img: Image.Image) -> Image.Image:
    """Кадр вдоха-выдоха: всё, что выше ног, на пиксель ниже; ноги на месте."""
    w, h = img.size
    box = img.getbbox()
    if box is None:
        return img.copy()
    top_of_legs = box[3] - LEG_ROWS
    out = Image.new("RGBA", img.size)
    out.alpha_composite(img.crop((0, top_of_legs, w, h)), (0, top_of_legs))
    out.alpha_composite(img.crop((0, 0, w, top_of_legs)), (0, 1))
    return out


def row(pose: Image.Image, mode: str, side: bool = False) -> list:
    if mode == "still":
        return [pose] * FRAMES
    if mode == "idle":
        # src/actors/npc/npc.gd листает кадры по кругу, медленно: вдох — один кадр из четырёх.
        return [pose, breathe(pose), pose, pose]
    if side:
        return [pose, stride(pose), pose, stride(pose)]
    return [pose, lift(pose, True), pose, lift(pose, False)]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out")
    ap.add_argument("--front", required=True, help="поза спереди (обязательна)")
    ap.add_argument("--side", help="поза сбоку, лицом влево; нет — берётся передняя")
    ap.add_argument("--back", help="поза со спины; нет — берётся передняя")
    ap.add_argument("--still", action="store_true", help="без кадров шага, все клетки одинаковые")
    ap.add_argument("--idle", action="store_true", help="NPC: вместо шага — «дыхание» (кадр 1)")
    a = ap.parse_args()

    front = Image.open(a.front).convert("RGBA")
    side = Image.open(a.side).convert("RGBA") if a.side else front
    back = Image.open(a.back).convert("RGBA") if a.back else front
    w, h = front.size
    for name, im in (("side", side), ("back", back)):
        if im.size != front.size:
            raise SystemExit("размер позы %s %s не совпадает с передней %s" % (name, im.size, front.size))

    sheet = Image.new("RGBA", (w * FRAMES, h * 4))
    mode = "idle" if a.idle else "still" if a.still else "walk"
    # Вид вправо — зеркало готовых кадров вида влево, а не отдельный шаг:
    # «ножницы» рисуются в сторону взгляда, и зеркало разворачивает их сами.
    rows = [row(front, mode), row(side, mode, side=a.side is not None),
            [ImageOps.mirror(f) for f in row(side, mode, side=a.side is not None)],
            row(back, mode)]
    for r, frames in enumerate(rows):
        for c, frame in enumerate(frames):
            sheet.paste(frame, (c * w, r * h))
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    sheet.save(a.out)
    print("лист %dx%d: %s" % (sheet.width, sheet.height, a.out))


if __name__ == "__main__":
    main()

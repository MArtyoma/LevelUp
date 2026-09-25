#!/usr/bin/env python3
"""Лист ходьбы персонажа из трёх поз: спереди, сбоку (лицом влево) и со спины.

Генератор (gen_sprite.py) рисует только отдельные позы, кадров анимации он не
умеет. Здесь из позы делается простой шаг: в кадрах 1 и 3 поднимается то левая,
то правая нога на пиксель, а корпус чуть приседает. Для 16x32 этого хватает,
чтобы персонаж не «скользил» по полу; настоящие кадры нарисует художник.

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


def row(pose: Image.Image, mode: str) -> list:
    if mode == "still":
        return [pose] * FRAMES
    if mode == "idle":
        # src/actors/npc/npc.gd листает кадры по кругу, медленно: вдох — один кадр из четырёх.
        return [pose, breathe(pose), pose, pose]
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

    rows = [front, side, ImageOps.mirror(side), back]
    sheet = Image.new("RGBA", (w * FRAMES, h * len(rows)))
    for r, pose in enumerate(rows):
        mode = "idle" if a.idle else "still" if a.still else "walk"
        for c, frame in enumerate(row(pose, mode)):
            sheet.paste(frame, (c * w, r * h))
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    sheet.save(a.out)
    print("лист %dx%d: %s" % (sheet.width, sheet.height, a.out))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Генератор временного арта для LevelUp.

Зачем он есть. Арт — узкое место команды: у artist 2-3 часа в неделю, а
вертикальный срез должен собираться уже сейчас. Эти PNG заведомо некрасивые
и существуют ровно для того, чтобы код, карта и квесты не ждали картинок.
Как только artist кладёт свои файлы с теми же именами и той же сеткой —
ничего в коде и сценах менять не надо.

Размеры берутся из project.godot (раздел `levelup/grid`), то есть из того же
места, что и весь остальной проект. Поменяли там 16 на 32 — запустили этот
скрипт, и заглушки стали 32.

    python3 tools/make_placeholder_art.py
    python3 tools/make_placeholder_art.py --tile 32 --char 32x64   # разово, не меняя настроек

Требует: pip install Pillow

Что получается:
  assets/tiles/office_placeholder.png    атлас 8 колонок x 2 ряда — только с --tiles.
                                         Обычный атлас рисует tools/art/draw_tiles.py
  assets/sprites/person_placeholder.png  лист: кадры ходьбы x 4 направления,
                                         ряды сверху вниз — вниз, влево, вправо, вверх
"""

import argparse
import re
from pathlib import Path

from PIL import Image, ImageDraw

GAME = Path(__file__).resolve().parent.parent
PROJECT_FILE = GAME / "project.godot"
OUT_TILES = GAME / "assets/tiles/office_placeholder.png"
OUT_PERSON = GAME / "assets/sprites/person_placeholder.png"

# Тайлсет рисуется в этом размере, а потом увеличивается целым числом раз.
# Рисовать заново под каждый размер смысла нет: это заглушка, и «крупные
# пиксели» на ней — честный признак того, что настоящий арт ещё не пришёл.
BASE_TILE = 16

# Ограниченная палитра — та самая дисциплина, которая экономит недели
# (решение команды: палитра 16–24 цвета, один файл).
PALETTE = {
    "carpet":     (74, 85, 104),
    "carpet_dot": (85, 96, 115),
    "floor":      (203, 213, 224),
    "floor_line": (180, 190, 200),
    "wall":       (45, 55, 72),
    "wall_top":   (74, 85, 104),
    "wood":       (160, 118, 90),
    "wood_dark":  (120, 88, 66),
    "chair":      (43, 108, 176),
    "plant":      (47, 133, 90),
    "door":       (183, 121, 31),
    "metal":      (113, 128, 150),
    "water":      (99, 179, 237),
    "paper":      (237, 242, 247),
    "shadow":     (26, 32, 44),
    "skin":       (222, 184, 156),
    "shirt":      (226, 232, 240),
    "trousers":   (56, 66, 84),
}


def read_grid() -> dict:
    """Читает размеры из project.godot — того же файла, что использует игра."""
    defaults = {
        "tile_size": 16,
        "character_frame_width": 16,
        "character_frame_height": 16,
        "walk_frames": 4,
    }
    if not PROJECT_FILE.exists():
        return defaults
    text = PROJECT_FILE.read_text(encoding="utf-8")
    for key in defaults:
        found = re.search(rf"^grid/{key}\s*=\s*(\d+)\s*$", text, re.MULTILINE)
        if found:
            defaults[key] = int(found.group(1))
    return defaults


def box(draw, x, y, w, h, fill, outline=None):
    draw.rectangle([x, y, x + w - 1, y + h - 1], fill=fill, outline=outline)


# --------------------------------------------------------------------------- #
# Тайлсет                                                                       #
# --------------------------------------------------------------------------- #

def make_tileset(tile: int) -> Image.Image:
    """8x2 тайла. Клетка в атласе = то, что пишут в инспекторе как atlas_cell."""
    t = BASE_TILE
    img = Image.new("RGBA", (t * 8, t * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def at(col, row):
        return col * t, row * t

    # 0,0 — ковролин
    x, y = at(0, 0)
    box(d, x, y, t, t, PALETTE["carpet"])
    for dy in range(0, t, 4):
        for dx in range(0, t, 4):
            d.point((x + dx + (dy // 4) % 2 * 2, y + dy), PALETTE["carpet_dot"])

    # 1,0 — плитка
    x, y = at(1, 0)
    box(d, x, y, t, t, PALETTE["floor"])
    d.line([x, y + t - 1, x + t - 1, y + t - 1], fill=PALETTE["floor_line"])
    d.line([x + t - 1, y, x + t - 1, y + t - 1], fill=PALETTE["floor_line"])

    # 2,0 — стена (непроходимая)
    x, y = at(2, 0)
    box(d, x, y, t, t, PALETTE["wall"])
    d.line([x, y, x + t - 1, y], fill=PALETTE["wall_top"])

    # 3,0 — верх стены (декоративная кромка)
    x, y = at(3, 0)
    box(d, x, y, t, t, PALETTE["wall_top"])
    d.line([x, y + t - 1, x + t - 1, y + t - 1], fill=PALETTE["wall"])

    # 4,0 — стол
    x, y = at(4, 0)
    box(d, x, y, t, t, PALETTE["carpet"])
    box(d, x + 1, y + 3, t - 2, t - 6, PALETTE["wood"], PALETTE["wood_dark"])
    box(d, x + 3, y + 5, 6, 4, PALETTE["paper"])

    # 5,0 — стул
    x, y = at(5, 0)
    box(d, x, y, t, t, PALETTE["carpet"])
    box(d, x + 4, y + 4, 8, 8, PALETTE["chair"], PALETTE["shadow"])

    # 6,0 — растение
    x, y = at(6, 0)
    box(d, x, y, t, t, PALETTE["carpet"])
    box(d, x + 6, y + 10, 4, 4, PALETTE["wood_dark"])
    d.ellipse([x + 3, y + 2, x + 12, y + 11], fill=PALETTE["plant"])

    # 7,0 — дверь
    x, y = at(7, 0)
    box(d, x, y, t, t, PALETTE["wall"])
    box(d, x + 2, y + 1, t - 4, t - 2, PALETTE["door"], PALETTE["wood_dark"])
    d.point((x + t - 5, y + 8), PALETTE["paper"])

    # 0,1 — шкаф
    x, y = at(0, 1)
    box(d, x, y, t, t, PALETTE["carpet"])
    box(d, x + 1, y + 1, t - 2, t - 2, PALETTE["metal"], PALETTE["shadow"])
    d.line([x + 2, y + 8, x + t - 3, y + 8], fill=PALETTE["shadow"])

    # 1,1 — кулер
    x, y = at(1, 1)
    box(d, x, y, t, t, PALETTE["carpet"])
    box(d, x + 5, y + 2, 6, 6, PALETTE["water"], PALETTE["shadow"])
    box(d, x + 5, y + 8, 6, 6, PALETTE["paper"], PALETTE["shadow"])

    # 2,1 — принтер
    x, y = at(2, 1)
    box(d, x, y, t, t, PALETTE["carpet"])
    box(d, x + 2, y + 5, t - 4, 7, PALETTE["metal"], PALETTE["shadow"])
    box(d, x + 5, y + 2, 6, 3, PALETTE["paper"])

    # 3,1 — ковёр-акцент (переговорная)
    x, y = at(3, 1)
    box(d, x, y, t, t, PALETTE["floor"])
    box(d, x + 1, y + 1, t - 2, t - 2, (155, 44, 44), (120, 30, 30))

    # 4,1..7,1 — пусто, место под то, что добавит artist

    if tile != BASE_TILE:
        # NEAREST, а не сглаживание: сглаженный пиксель-арт перестаёт быть
        # пиксель-артом, и на нём не видно, где настоящая граница тайла.
        img = img.resize((tile * 8, tile * 2), Image.NEAREST)
    return img


# --------------------------------------------------------------------------- #
# Человек                                                                       #
# --------------------------------------------------------------------------- #

def make_person(frame_w: int, frame_h: int, frames: int) -> Image.Image:
    """Лист ходьбы: `frames` кадров x 4 направления.

    Фигура рисуется долями кадра, а не пикселями, поэтому 16x16, 16x32 и
    32x64 получаются одним и тем же кодом. Спрайт нарочно почти серый: цвет
    сотрудника задаётся в data/company.json полем "palette" и накладывается
    движком через modulate. Это приём «один базовый спрайт + смена палитры =
    пятнадцать разных людей» — так договорилась команда.
    """
    img = Image.new("RGBA", (frame_w * frames, frame_h * 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def px(value: float) -> int:
        return int(round(value))

    step_shift = max(1, px(frame_w * 0.07))

    def person(col, row, direction, step):
        x0, y0 = col * frame_w, row * frame_h

        # Тень под ногами — привязывает фигуру к полу на виде сверху.
        d.ellipse([x0 + px(frame_w * 0.25), y0 + px(frame_h * 0.86),
                   x0 + px(frame_w * 0.75), y0 + px(frame_h * 0.97)], fill=(0, 0, 0, 70))

        # Голова.
        head_x0, head_x1 = x0 + px(frame_w * 0.28), x0 + px(frame_w * 0.72)
        head_y0, head_y1 = y0 + px(frame_h * 0.10), y0 + px(frame_h * 0.45)
        d.rectangle([head_x0, head_y0, head_x1 - 1, head_y1 - 1], fill=PALETTE["skin"])
        # Волосы — верхняя полоска головы; по ней видно, куда человек повёрнут.
        hair = max(1, px(frame_h * 0.06))
        d.rectangle([head_x0, head_y0, head_x1 - 1, head_y0 + hair - 1], fill=PALETTE["shadow"])
        if direction == "up":
            d.rectangle([head_x0, head_y0, head_x1 - 1, head_y1 - 1], fill=PALETTE["shadow"])
        else:
            eye_y = y0 + px(frame_h * 0.26)
            eye = max(1, px(frame_w * 0.07))
            for eye_x in (x0 + px(frame_w * 0.36), x0 + px(frame_w * 0.58)):
                d.rectangle([eye_x, eye_y, eye_x + eye - 1, eye_y + eye - 1],
                            fill=PALETTE["shadow"])

        # Корпус.
        d.rectangle([x0 + px(frame_w * 0.22), y0 + px(frame_h * 0.44),
                     x0 + px(frame_w * 0.78) - 1, y0 + px(frame_h * 0.78) - 1],
                    fill=PALETTE["shirt"], outline=PALETTE["trousers"])

        # Ноги: два кадра шага, два кадра стойки.
        shift = {0: (0, 0), 1: (-step_shift, step_shift),
                 2: (0, 0), 3: (step_shift, -step_shift)}[step % 4]
        leg_w = max(1, px(frame_w * 0.16))
        leg_y0, leg_y1 = y0 + px(frame_h * 0.76), y0 + px(frame_h * 0.94)
        for index, leg_x in enumerate((x0 + px(frame_w * 0.30), x0 + px(frame_w * 0.54))):
            d.rectangle([leg_x + shift[index], leg_y0,
                         leg_x + shift[index] + leg_w - 1, leg_y1 - 1],
                        fill=PALETTE["trousers"])

    for row, direction in enumerate(["down", "left", "right", "up"]):
        for step in range(frames):
            person(step, row, direction, step)
    return img


def main() -> None:
    grid = read_grid()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tile", type=int, default=grid["tile_size"],
                        help="размер тайла; по умолчанию из project.godot")
    parser.add_argument("--char", default="%dx%d" % (grid["character_frame_width"],
                                                     grid["character_frame_height"]),
                        help="размер кадра человека, например 16x32")
    parser.add_argument("--frames", type=int, default=grid["walk_frames"],
                        help="кадров в цикле ходьбы")
    parser.add_argument("--tiles", action="store_true",
                        help="перерисовать и атлас тайлов — серыми квадратами. Обычно не нужно: "
                             "атлас рисует tools/art/draw_tiles.py, и этот флаг его затрёт")
    args = parser.parse_args()

    frame_w, _, frame_h = args.char.partition("x")
    frame_w, frame_h = int(frame_w), int(frame_h)

    OUT_TILES.parent.mkdir(parents=True, exist_ok=True)
    OUT_PERSON.parent.mkdir(parents=True, exist_ok=True)
    make_person(frame_w, frame_h, args.frames).save(OUT_PERSON)

    print("Заглушки перерисованы:")
    if args.tiles:
        make_tileset(args.tile).save(OUT_TILES)
        print("  %s — тайл %dx%d, атлас %dx%d"
              % (OUT_TILES.relative_to(GAME), args.tile, args.tile, args.tile * 8, args.tile * 2))
    print("  %s — кадр %dx%d, %d кадров ходьбы x 4 направления"
          % (OUT_PERSON.relative_to(GAME), frame_w, frame_h, args.frames))
    if args.tiles:
        print("\nДальше: godot --headless --script tools/build_tileset.gd")


if __name__ == "__main__":
    main()

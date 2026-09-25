#!/usr/bin/env python3
"""Генератор временного арта для LevelUp.

Зачем он есть. Арт — узкое место команды: у artist 2-3 часа в неделю, а вертикальный
срез (недели 3-4) должен собираться уже сейчас. Эти PNG заведомо некрасивые и
существуют ровно для того, чтобы код, карта и квесты не ждали картинок. Как только
artist кладёт свои файлы с теми же именами и той же сеткой 16x16 — ничего в коде
и сценах менять не надо.

Запуск:  python3 tools/make_placeholder_art.py
Требует: pip install Pillow

Сетка, которую нельзя менять без правки сцен:
  * тайл             — 16x16 (решение D-011)
  * атлас тайлов     — 8 колонок, 2 ряда  -> 128x32
  * спрайт человека  — 4 кадра x 4 направления -> 64x64,
                       ряды сверху вниз: вниз, влево, вправо, вверх
"""

from PIL import Image, ImageDraw

TILE = 16
OUT_TILES = "assets/tiles/office_placeholder.png"
OUT_PERSON = "assets/sprites/person_placeholder.png"

# Ограниченная палитра — та самая дисциплина, которая экономит недели (см. docs/roles.md).
PALETTE = {
    "carpet":    (74, 85, 104),
    "carpet_dot":(85, 96, 115),
    "floor":     (203, 213, 224),
    "floor_line":(180, 190, 200),
    "wall":      (45, 55, 72),
    "wall_top":  (74, 85, 104),
    "wood":      (160, 118, 90),
    "wood_dark": (120, 88, 66),
    "chair":     (43, 108, 176),
    "plant":     (47, 133, 90),
    "door":      (183, 121, 31),
    "metal":     (113, 128, 150),
    "water":     (99, 179, 237),
    "paper":     (237, 242, 247),
    "shadow":    (26, 32, 44),
    "skin":      (222, 184, 156),
    "shirt":     (226, 232, 240),
    "trousers":  (56, 66, 84),
}


def box(draw, x, y, w, h, fill, outline=None):
    draw.rectangle([x, y, x + w - 1, y + h - 1], fill=fill, outline=outline)


def make_tileset() -> Image.Image:
    """8x2 тайла. Номер тайла = индекс в атласе, он же координата в TileSet Godot."""
    img = Image.new("RGBA", (TILE * 8, TILE * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def at(col, row):
        return col * TILE, row * TILE

    # 0,0 — ковролин
    x, y = at(0, 0)
    box(d, x, y, TILE, TILE, PALETTE["carpet"])
    for dy in range(0, TILE, 4):
        for dx in range(0, TILE, 4):
            d.point((x + dx + (dy // 4) % 2 * 2, y + dy), PALETTE["carpet_dot"])

    # 1,0 — плитка
    x, y = at(1, 0)
    box(d, x, y, TILE, TILE, PALETTE["floor"])
    d.line([x, y + TILE - 1, x + TILE - 1, y + TILE - 1], fill=PALETTE["floor_line"])
    d.line([x + TILE - 1, y, x + TILE - 1, y + TILE - 1], fill=PALETTE["floor_line"])

    # 2,0 — стена (непроходимая)
    x, y = at(2, 0)
    box(d, x, y, TILE, TILE, PALETTE["wall"])
    d.line([x, y, x + TILE - 1, y], fill=PALETTE["wall_top"])

    # 3,0 — верх стены (декоративная кромка)
    x, y = at(3, 0)
    box(d, x, y, TILE, TILE, PALETTE["wall_top"])
    d.line([x, y + TILE - 1, x + TILE - 1, y + TILE - 1], fill=PALETTE["wall"])

    # 4,0 — стол
    x, y = at(4, 0)
    box(d, x, y, TILE, TILE, PALETTE["carpet"])
    box(d, x + 1, y + 3, TILE - 2, TILE - 6, PALETTE["wood"], PALETTE["wood_dark"])
    box(d, x + 3, y + 5, 6, 4, PALETTE["paper"])

    # 5,0 — стул
    x, y = at(5, 0)
    box(d, x, y, TILE, TILE, PALETTE["carpet"])
    box(d, x + 4, y + 4, 8, 8, PALETTE["chair"], PALETTE["shadow"])

    # 6,0 — растение
    x, y = at(6, 0)
    box(d, x, y, TILE, TILE, PALETTE["carpet"])
    box(d, x + 6, y + 10, 4, 4, PALETTE["wood_dark"])
    d.ellipse([x + 3, y + 2, x + 12, y + 11], fill=PALETTE["plant"])

    # 7,0 — дверь
    x, y = at(7, 0)
    box(d, x, y, TILE, TILE, PALETTE["wall"])
    box(d, x + 2, y + 1, TILE - 4, TILE - 2, PALETTE["door"], PALETTE["wood_dark"])
    d.point((x + TILE - 5, y + 8), PALETTE["paper"])

    # 0,1 — шкаф
    x, y = at(0, 1)
    box(d, x, y, TILE, TILE, PALETTE["carpet"])
    box(d, x + 1, y + 1, TILE - 2, TILE - 2, PALETTE["metal"], PALETTE["shadow"])
    d.line([x + 2, y + 8, x + TILE - 3, y + 8], fill=PALETTE["shadow"])

    # 1,1 — кулер
    x, y = at(1, 1)
    box(d, x, y, TILE, TILE, PALETTE["carpet"])
    box(d, x + 5, y + 2, 6, 6, PALETTE["water"], PALETTE["shadow"])
    box(d, x + 5, y + 8, 6, 6, PALETTE["paper"], PALETTE["shadow"])

    # 2,1 — принтер
    x, y = at(2, 1)
    box(d, x, y, TILE, TILE, PALETTE["carpet"])
    box(d, x + 2, y + 5, TILE - 4, 7, PALETTE["metal"], PALETTE["shadow"])
    box(d, x + 5, y + 2, 6, 3, PALETTE["paper"])

    # 3,1 — ковёр-акцент (для переговорной)
    x, y = at(3, 1)
    box(d, x, y, TILE, TILE, PALETTE["floor"])
    box(d, x + 1, y + 1, TILE - 2, TILE - 2, (155, 44, 44), (120, 30, 30))

    # 4,1..7,1 — пусто, место под то, что добавит artist
    return img


def make_person() -> Image.Image:
    """64x64: 4 кадра ходьбы x 4 направления.

    Спрайт нарочно почти серый: цвет сотрудника задаётся в data/company.json
    полем "palette" и накладывается движком через modulate. Это и есть приём
    «один базовый спрайт + смена палитры = 15 разных людей» из docs/roles.md.
    """
    img = Image.new("RGBA", (TILE * 4, TILE * 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def person(col, row, direction, step):
        x, y = col * TILE, row * TILE
        # тень под ногами — привязывает фигуру к полу на виде сверху
        d.ellipse([x + 4, y + 13, x + 11, y + 15], fill=(0, 0, 0, 60))
        # голова
        box(d, x + 5, y + 2, 6, 5, PALETTE["skin"])
        if direction != "up":
            d.point((x + 6, y + 4), PALETTE["shadow"])
            d.point((x + 9, y + 4), PALETTE["shadow"])
        # волосы
        d.line([x + 5, y + 2, x + 10, y + 2], fill=PALETTE["shadow"])
        # корпус
        box(d, x + 4, y + 7, 8, 5, PALETTE["shirt"], PALETTE["trousers"])
        # ноги: два кадра шага, два кадра стойки
        offset = {0: (0, 0), 1: (-1, 1), 2: (0, 0), 3: (1, -1)}[step]
        box(d, x + 5 + offset[0], y + 12, 2, 3, PALETTE["trousers"])
        box(d, x + 9 + offset[1], y + 12, 2, 3, PALETTE["trousers"])

    for row, direction in enumerate(["down", "left", "right", "up"]):
        for step in range(4):
            person(step, row, direction, step)
    return img


def main() -> None:
    make_tileset().save(OUT_TILES)
    make_person().save(OUT_PERSON)
    print("готово:", OUT_TILES, OUT_PERSON)


if __name__ == "__main__":
    main()

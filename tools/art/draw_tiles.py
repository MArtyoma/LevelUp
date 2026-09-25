#!/usr/bin/env python3
"""Атлас тайлов офиса, нарисованный кодом по палитре проекта.

Зачем кодом, а не нейросетью: генератор (gen_sprite.py) не умеет тайлы,
стыкующиеся краями, — пол и стены у него выходят с «швами». Здесь каждый
пиксель задан явно, поэтому пол бесшовный, а цвета берутся ровно из
`assets/palette.hex`.

    python3 tools/art/draw_tiles.py              # перезаписать атлас
    python3 tools/art/draw_tiles.py --preview    # плюс увеличенный показ в art_out/

Раскладка: 8 колонок x 4 ряда, клетки — из tools/build_tileset.gd. Ряды 0–1 рисует
этот файл, ряды 2–3 — предметы отделов (сервер, сейф, глобус...): их рисует нейросеть
(gen_sprite.py --kind prop), а сюда они вклеиваются из `assets/props/<имя>.png`
(или `<имя>_placeholder.png`). Заменить предмет — положить свой PNG 16x16 и перезапустить.
Файл остаётся `office_placeholder.png`: это черновик до арта художника команды.

Мебель рисуется на прозрачном фоне — она стоит на слое Walls поверх пола.
Рисуется всё в 16x16; если в project.godot тайл другой, атлас увеличивается
целым числом раз. После запуска: godot --headless --script tools/build_tileset.gd
Требует: pip install Pillow
"""

import argparse
import random
import re
from pathlib import Path

from PIL import Image

GAME = Path(__file__).resolve().parents[2]
OUT = GAME / "assets/tiles/office_placeholder.png"
PREVIEW = GAME / "art_out/tiles/preview.png"
T = 16

# Имена цветов палитры (порядок строк в assets/palette.hex).
NAMES = ["ink", "plum", "red", "orange", "yellow", "lime", "green", "teal",
         "navy", "blue", "sky", "cyan", "white", "steel", "slate", "dusk",
         "skin", "tan", "wood", "wood_dark", "hair_dark", "floor", "floor_line", "lilac"]


def load_palette() -> dict:
    colors = []
    for line in (GAME / "assets/palette.hex").read_text(encoding="utf-8").splitlines():
        line = line.split(";")[0].strip()
        if len(line) == 6:
            colors.append(tuple(int(line[i:i + 2], 16) for i in (0, 2, 4)) + (255,))
    if len(colors) < len(NAMES):
        raise SystemExit("в assets/palette.hex меньше %d цветов" % len(NAMES))
    return dict(zip(NAMES, colors))


def read_tile_size() -> int:
    """Размер тайла из project.godot (levelup/grid/tile_size) — как у игры."""
    found = re.search(r"^grid/tile_size\s*=\s*(\d+)\s*$",
                      (GAME / "project.godot").read_text(encoding="utf-8"), re.MULTILINE)
    return int(found.group(1)) if found else T


class Cell:
    """Рисование внутри одной клетки атласа, координаты 0..15."""

    def __init__(self, img, col, row, pal):
        self.img, self.x0, self.y0, self.p = img, col * T, row * T, pal

    def px(self, x, y, color):
        if 0 <= x < T and 0 <= y < T:
            self.img.putpixel((self.x0 + x, self.y0 + y), self.p[color])

    def rect(self, x, y, w, h, color):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.px(xx, yy, color)

    def frame(self, x, y, w, h, color):
        for xx in range(x, x + w):
            self.px(xx, y, color)
            self.px(xx, y + h - 1, color)
        for yy in range(y, y + h):
            self.px(x, yy, color)
            self.px(x + w - 1, yy, color)


def carpet(c):
    # Кабинеты: светлый ламинат. Доски по 4 px, стыки вразбежку, — так повтор
    # тайла 16x16 не складывается в заметную сетку. Швы низкого контраста: пол —
    # фон, на нём должны читаться люди и мебель, а не доски.
    c.rect(0, 0, T, T, "floor_line")
    for y in (3, 7, 11, 15):
        c.rect(0, y, T, 1, "tan")
    for x, y in ((5, 0), (13, 4), (2, 8), (9, 12)):
        c.rect(x, y, 1, 3, "tan")


def corridor(c):
    # Коридор: холодная светлая плитка 16x16 — отличается от кабинетов с первого
    # взгляда. Шов справа и снизу: соседние тайлы дают сетку без двойных линий.
    c.rect(0, 0, T, T, "white")
    c.rect(0, T - 1, T, 1, "steel")
    c.rect(T - 1, 0, 1, T, "steel")


def wall(c):
    # Стена сверху — ровная заливка без кромок: стены на карте лежат сплошными
    # массивами, и любая кромка у тайла превращается в полосы через каждые 16 px.
    c.rect(0, 0, T, T, "dusk")


def wall_top(c):
    c.rect(0, 0, T, T, "slate")
    c.rect(0, T - 2, T, 2, "dusk")


def desk(c):
    # Белый офисный стол: на деревянном полу коричневый стол терялся.
    c.rect(0, 3, T, 9, "white")          # столешница
    c.rect(0, 11, T, 2, "steel")         # передний торец
    c.frame(0, 3, T, 10, "slate")
    c.rect(1, 13, 1, 2, "slate")         # ножки
    c.rect(14, 13, 1, 2, "slate")
    c.rect(5, 1, 7, 5, "ink")            # монитор
    c.rect(6, 2, 5, 3, "blue")
    c.px(6, 2, "sky")
    c.rect(8, 6, 1, 1, "ink")            # ножка монитора
    c.rect(5, 8, 6, 2, "dusk")           # клавиатура
    c.rect(2, 6, 3, 4, "floor")          # бумаги
    c.px(3, 7, "steel")
    c.px(3, 8, "steel")
    c.rect(12, 7, 2, 2, "red")           # кружка
    c.px(12, 7, "orange")


def chair(c):
    c.rect(4, 3, 8, 3, "ink")            # спинка
    c.rect(5, 3, 6, 1, "dusk")
    c.rect(3, 6, 10, 6, "dusk")          # сиденье
    c.rect(4, 6, 8, 1, "slate")
    c.frame(3, 6, 10, 6, "ink")
    for x in (3, 7, 12):                 # колёсики
        c.px(x, 13, "ink")


def plant(c):
    leaves = [
        ".....gg.........",
        "...gGGgg..g.....",
        "..gGGLGgggGg....",
        ".gGGLLGGgGGGg...",
        ".gGLLGGgGGLGg...",
        "..gGGGgGGLLGGg..",
        ".ggGGgGGGLGGg...",
        "..gtggGGGGgg....",
        "...gtgGGgtg.....",
        "....ttgttt......",
    ]
    colors = {"g": "teal", "G": "green", "L": "lime", "t": "teal"}
    for y, line in enumerate(leaves):
        for x, ch in enumerate(line):
            if ch in colors:
                c.px(x + 1, y + 1, colors[ch])
    c.rect(5, 11, 6, 4, "white")          # горшок
    c.rect(5, 14, 6, 1, "steel")
    c.rect(10, 11, 1, 4, "steel")
    c.rect(5, 11, 6, 1, "wood_dark")      # земля


def door(c):
    c.rect(0, 0, T, T, "dusk")
    c.rect(2, 1, 12, 15, "wood")
    c.frame(2, 1, 12, 15, "wood_dark")
    c.rect(4, 3, 8, 5, "tan")             # филёнки
    c.rect(4, 9, 8, 5, "tan")
    c.frame(4, 3, 8, 5, "wood")
    c.frame(4, 9, 8, 5, "wood")
    c.px(11, 8, "yellow")                 # ручка
    c.rect(0, 6, 2, 3, "ink")             # считыватель пропусков
    c.px(0, 7, "lime")


def cabinet(c):
    c.rect(1, 0, 14, T, "steel")
    c.frame(1, 0, 14, T, "slate")
    c.rect(2, 1, 12, 1, "white")
    for y in (5, 10):
        c.rect(2, y, 12, 1, "slate")
    for y in (3, 8, 13):
        c.rect(6, y, 4, 1, "dusk")
    c.rect(1, T - 1, 14, 1, "dusk")


def cooler(c):
    c.rect(5, 1, 6, 5, "cyan")            # бутыль
    c.rect(6, 1, 1, 4, "white")
    c.rect(9, 2, 1, 4, "sky")
    c.rect(6, 0, 4, 1, "sky")
    c.rect(4, 6, 8, 9, "white")           # корпус
    c.rect(10, 6, 2, 9, "steel")
    c.rect(4, 14, 8, 1, "slate")
    c.px(6, 8, "red")                     # краники
    c.px(9, 8, "blue")
    c.rect(5, 11, 5, 1, "dusk")           # поддон


def printer(c):
    c.rect(4, 2, 8, 3, "white")           # лист в лотке
    c.px(5, 3, "steel")
    c.px(7, 3, "steel")
    c.rect(1, 4, 14, 8, "steel")          # корпус
    c.rect(1, 4, 14, 1, "white")
    c.rect(3, 6, 10, 1, "dusk")           # щель выдачи
    c.rect(1, 11, 14, 1, "slate")
    c.px(12, 9, "lime")                   # лампочка
    c.px(10, 9, "dusk")


def rug(c):
    c.rect(0, 0, T, T, "red")
    c.frame(0, 0, T, T, "plum")
    c.frame(2, 2, T - 4, T - 4, "orange")


def box(c):
    # 4,1 — коробка с ноутбуком: предмет квеста, чтобы он не выглядел мебелью.
    c.rect(2, 5, 12, 9, "tan")
    c.rect(2, 5, 12, 1, "floor")
    c.frame(2, 5, 12, 9, "wood")
    c.rect(7, 5, 2, 9, "wood")            # скотч
    c.rect(4, 8, 2, 2, "white")           # наклейка
    c.rect(2, 14, 12, 1, "wood_dark")


def folder(c):
    # 5,1 — папка с документами.
    c.rect(3, 4, 10, 10, "blue")
    c.frame(3, 4, 10, 10, "navy")
    c.rect(4, 3, 4, 1, "blue")
    c.rect(5, 6, 6, 1, "white")
    c.rect(5, 8, 6, 1, "white")
    c.rect(3, 14, 10, 1, "ink")


def wall_face(c):
    # 6,1 — стена, к которой обращён пол: вид «три четверти», как в большинстве
    # игр сверху. Ставится не руками, а скриптом уровня (src/levels/wall_faces.gd).
    c.rect(0, 0, T, T, "steel")
    c.rect(0, 0, T, 1, "slate")           # стык с верхом стены
    c.rect(0, 1, T, 1, "white")           # блик под потолком
    c.rect(0, 12, T, 3, "slate")          # плинтус
    c.rect(0, 12, T, 1, "dusk")
    c.rect(0, T - 1, T, 1, "dusk")        # тень на полу


# Предметы отделов: клетка атласа -> имя файла в assets/props/.
PROPS = {
    (0, 2): "server", (1, 2): "safe", (2, 2): "coffee", (3, 2): "globe",
    (4, 2): "bookshelf", (5, 2): "flipchart", (6, 2): "trophy", (7, 2): "sofa",
}
# Висят на стене: клеятся поверх «лица стены» (6,1), чтобы плинтус оставался виден.
WALL_PROPS = {(0, 3): "notice_board"}
PROPS_DIR = GAME / "assets/props"
ROWS = 4


def load_prop(name):
    for suffix in ("", "_placeholder"):
        path = PROPS_DIR / f"{name}{suffix}.png"
        if path.exists():
            return Image.open(path).convert("RGBA")
    print(f"нет assets/props/{name}.png — клетка останется пустой")
    return None


def paste_props(img, pal):
    for (col, row), name in PROPS.items():
        prop = load_prop(name)
        if prop is not None:
            img.alpha_composite(prop, (col * T + (T - prop.width) // 2, row * T + (T - prop.height)))
    for (col, row), name in WALL_PROPS.items():
        wall_face(Cell(img, col, row, pal))
        prop = load_prop(name)
        if prop is not None:
            # Над плинтусом (он с 12-й строки): по центру, верхний край — на 2-й строке.
            img.alpha_composite(prop, (col * T + (T - prop.width) // 2, row * T + 2))


DRAW = {
    (0, 0): carpet, (1, 0): corridor, (2, 0): wall, (3, 0): wall_top,
    (4, 0): desk, (5, 0): chair, (6, 0): plant, (7, 0): door,
    (0, 1): cabinet, (1, 1): cooler, (2, 1): printer, (3, 1): rug,
    (4, 1): box, (5, 1): folder, (6, 1): wall_face,
}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--preview", action="store_true", help="сохранить увеличенный показ в art_out/tiles/")
    args = ap.parse_args()

    pal = load_palette()
    img = Image.new("RGBA", (T * 8, T * ROWS), (0, 0, 0, 0))
    for (col, row), draw in DRAW.items():
        draw(Cell(img, col, row, pal))
    paste_props(img, pal)
    tile = read_tile_size()
    if tile != T:
        # Рисуем в 16 и увеличиваем целым числом раз, NEAREST — без сглаживания.
        img = img.resize((tile * 8, tile * ROWS), Image.NEAREST)
    img.save(OUT)
    print("атлас: %s" % OUT.relative_to(GAME))

    if args.preview:
        PREVIEW.parent.mkdir(parents=True, exist_ok=True)
        # Мебель показываем на ковролине — так, как она стоит в игре.
        show = Image.new("RGBA", img.size)
        for col in range(8):
            for row in range(ROWS):
                show.paste(img.crop((0, 0, T, T)), (col * T, row * T))
        show.alpha_composite(img)
        show.resize((img.width * 6, img.height * 6), Image.NEAREST).save(PREVIEW)
        print("показ: %s" % PREVIEW.relative_to(GAME))


if __name__ == "__main__":
    main()

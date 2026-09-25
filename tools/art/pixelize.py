#!/usr/bin/env python3
"""Превращает картинку «в пиксельном стиле» в настоящий спрайт под сетку игры.

Зачем. Нейросеть рисует 512x512, где один «пиксель» арта — это пятно 6-10
настоящих пикселей с размытыми краями, сотней оттенков и нарисованной
шахматкой вместо прозрачности. В Godot такое не положишь. Здесь четыре шага:

  1. фон      — заливка от краёв картинки: всё, что связано с рамкой и похоже
                на её цвета или на оттенок хромакея (--chroma green/magenta),
                становится прозрачным; зелёная кайма по краю фигуры обдирается;
  2. обрезка  — по границам спрайта;
  3. палитра  — все цвета приводятся к палитре проекта (или к N своим);
  4. сетка    — уменьшение до целевого размера: каждый пиксель результата
                берёт самый частый цвет своей клетки (или средний: --method avg),
                а прозрачным становится, если в клетке больше половины фона.

Персонаж ставится ногами на нижний край (так его удобно ставить на тайл),
предмет — по центру.

Запуск отдельно (для любой картинки, не только из генератора):
  python3 tools/art/pixelize.py raw.png out.png --size 16x32 --palette assets/palette.hex
Требует только Pillow.
"""

import argparse
from collections import Counter, deque
from pathlib import Path

from PIL import Image


# --- палитра ----------------------------------------------------------------

def load_palette(path):
    """Файл .hex (строка = цвет RRGGBB, как в Lospec) или картинка-палитра .png."""
    path = Path(path)
    if path.suffix.lower() == ".png":
        img = Image.open(path).convert("RGBA")
        return sorted({c[:3] for c in img.getdata() if c[3] > 0})
    colors = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.split(";")[0].strip().lstrip("#")
        if len(line) == 6:
            colors.append(tuple(int(line[i:i + 2], 16) for i in (0, 2, 4)))
    if not colors:
        raise SystemExit(f"в палитре {path} нет ни одного цвета RRGGBB")
    return colors


def quantize(img_rgba, colors=None, n_colors=16):
    """Приводит непрозрачные пиксели к палитре. Прозрачные не трогает.
    colors=None — палитра подбирается по самой картинке (n_colors цветов).
    Без дизеринга: в пиксель-арте он даёт шум, а не полутона.
    Каждый пиксель сопоставляется с палитрой напрямую, без предварительного
    сжатия: median cut до сопоставления склеивал синий костюм с чёрным,
    а красный галстук с коричневым (проверено 25.09 на спрайтах NPC).
    """
    px = list(img_rgba.getdata())
    opaque = [p[:3] for p in px if p[3] > 0]
    if not opaque:
        return img_rgba
    if colors is None:
        strip = Image.new("RGB", (len(opaque), 1))
        strip.putdata(opaque)
        q = strip.quantize(colors=n_colors, method=Image.Quantize.MEDIANCUT,
                           dither=Image.Dither.NONE)
        pal = q.getpalette()[:3 * n_colors]
        colors = sorted({tuple(pal[i:i + 3]) for i in range(0, len(pal), 3)})
    near = nearest_in(colors)
    out = Image.new("RGBA", img_rgba.size)
    out.putdata([(*near(p), p[3]) if p[3] else p for p in px])
    return out


def _lab(c):
    """sRGB -> CIELAB. Ближайший цвет палитры ищем здесь, а не в RGB: в RGB бледная
    кожа ближе к белому, чем к телесному, и лица становились белыми пятнами."""
    def lin(u):
        u /= 255
        return ((u + 0.055) / 1.055) ** 2.4 if u > 0.04045 else u / 12.92
    r, g, b = (lin(v) for v in c[:3])
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.9505
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.089
    f = lambda t: t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    fx, fy, fz = f(x), f(y), f(z)
    return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)


def nearest_in(colors):
    """Функция цвет -> ближайший цвет палитры по Lab, с кешем."""
    labs = [(_lab(c), tuple(c)) for c in colors]
    cache = {}

    def near(p):
        key = p[:3]
        if key not in cache:
            l = _lab(key)
            cache[key] = min(labs, key=lambda e: sum((u - v) ** 2 for u, v in zip(l, e[0])))[1]
        return cache[key]
    return near


def _luma(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


# --- фон ----------------------------------------------------------------------

def _dist2(a, b):
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2


# Хромакей: генератор просит у модели сплошной фон ядовитого цвета, которого нет
# в офисной одежде. У LoRA он выходит неровным (градиент, тени под ногами), поэтому
# «фон» — это не один цвет, а оттенок: зелёный канал сильно больше двух других.
CHROMA = {
    "green": lambda r, g, b, t: g - max(r, b) > t,
    "magenta": lambda r, g, b, t: min(r, b) - g > t,
}


def remove_background(img, tol=40, keys=4, chroma=None, chroma_tol=30):
    """Делает прозрачным фон, связанный с краем картинки.

    Фоном считается пиксель, похожий на один из `keys` самых частых цветов рамки
    (у шахматки их два, у сплошного фона один), или — если задан chroma — любой
    пиксель нужного оттенка. Заливка идёт от рамки и останавливается на контуре
    спрайта, поэтому зелёный галстук внутри фигуры уцелеет, а касающийся фона —
    нет: для зелёных предметов берите chroma="magenta".
    """
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    border = [px[x, y][:3] for x in range(w) for y in (0, h - 1)]
    border += [px[x, y][:3] for y in range(h) for x in (0, w - 1)]
    # Группируем близкие цвета рамки, чтобы шум не забил собой все `keys` мест.
    bg = []
    for c, _ in Counter((r // 8 * 8, g // 8 * 8, b // 8 * 8) for r, g, b in border).most_common():
        if all(_dist2(c, k) > tol * tol for k in bg):
            bg.append(c)
        if len(bg) == keys:
            break
    t2 = tol * tol
    key = CHROMA.get(chroma)

    def is_bg(c):
        return (key is not None and key(*c, chroma_tol)) or any(_dist2(c, k) <= t2 for k in bg)

    seen = bytearray(w * h)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            q.append((x, y))
    while q:
        x, y = q.popleft()
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        if not is_bg(px[x, y][:3]):
            continue
        px[x, y] = (0, 0, 0, 0)
        if x > 0: q.append((x - 1, y))
        if x < w - 1: q.append((x + 1, y))
        if y > 0: q.append((x, y - 1))
        if y < h - 1: q.append((x, y + 1))
    if key is not None:
        # Замкнутые просветы (между рукой и телом) заливка от края не достаёт.
        # Их берём по сильному оттенку где угодно — порог втрое строже обычного.
        for y in range(h):
            for x in range(w):
                if px[x, y][3] and key(*px[x, y][:3], chroma_tol * 3):
                    px[x, y] = (0, 0, 0, 0)
        # Кайма: сглаженный край — смесь фона и фигуры, по оттенку он ещё
        # «чуть зелёный». Две обдирки по одному пикселю с мягким порогом.
        for _ in range(2):
            edge = [(x, y) for y in range(h) for x in range(w)
                    if px[x, y][3] and key(*px[x, y][:3], 8) and any(
                        0 <= nx < w and 0 <= ny < h and px[nx, ny][3] == 0
                        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))]
            for x, y in edge:
                px[x, y] = (0, 0, 0, 0)
    return img


def drop_specks(img, min_area):
    """Убирает мелкие непрозрачные островки (крошки фона, отлетевшие искры)."""
    w, h = img.size
    px = img.load()
    seen = bytearray(w * h)
    for sy in range(h):
        for sx in range(w):
            if seen[sy * w + sx] or px[sx, sy][3] == 0:
                continue
            comp, q = [], deque([(sx, sy)])
            seen[sy * w + sx] = 1
            while q:
                x, y = q.popleft()
                comp.append((x, y))
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and px[nx, ny][3]:
                        seen[ny * w + nx] = 1
                        q.append((nx, ny))
            if len(comp) < min_area:
                for x, y in comp:
                    px[x, y] = (0, 0, 0, 0)
    return img


# --- сетка ----------------------------------------------------------------------

def to_grid(img, tw, th, anchor="bottom", margin=0, method="mode", dark_share=2.0, dark_luma=70,
            whole=False):
    """Уменьшает до tw x th: клетка берёт самый частый цвет (mode) или средний (avg).

    mode хорош, когда палитра уже приведена: цвета остаются чистыми, но тонкое
    (глаза, пальцы) пропадает. avg сохраняет тонкое как полутон, а чистоту цветов
    потом возвращает quantize — для уменьшения в 5 раз и больше он обычно лучше.

    Сохраняет пропорции спрайта: он вписывается в (tw-2m) x (th-2m) и ставится
    по нижнему краю (anchor=bottom, для персонажей) или по центру.

    dark_share (только для mode): если тёмных пикселей (яркость < dark_luma) в клетке
    не меньше этой доли, клетка берёт тёмный цвет. Так переживают уменьшение глаза
    и контур — в клетке они всегда в меньшинстве и при чистом mode пропадают.
    0.25 — глаза есть, лицо не чернеет (25.09, исходники в упрощённом стиле).
    >1 — выключено; так по умолчанию, см. process().

    whole=True — уменьшать весь кадр как есть, не обрезая по фигуре (портреты).
    """
    box = (0, 0, *img.size) if whole else img.getbbox()
    if box is None:
        return Image.new("RGBA", (tw, th))
    src = img.crop(box)
    sw, sh = src.size
    aw, ah = tw - 2 * margin, th - 2 * margin
    scale = min(aw / sw, ah / sh)
    ow, oh = max(1, round(sw * scale)), max(1, round(sh * scale))
    spx = src.load()
    small = Image.new("RGBA", (ow, oh))
    dpx = small.load()
    for oy in range(oh):
        y0, y1 = int(oy * sh / oh), max(int(oy * sh / oh) + 1, int((oy + 1) * sh / oh))
        for ox in range(ow):
            x0, x1 = int(ox * sw / ow), max(int(ox * sw / ow) + 1, int((ox + 1) * sw / ow))
            cnt, dark, opaque, total = Counter(), Counter(), 0, 0
            for y in range(y0, y1):
                for x in range(x0, x1):
                    p = spx[x, y]
                    total += 1
                    if p[3] > 127:
                        opaque += 1
                        cnt[p[:3]] += 1
                        if _luma(p) < dark_luma:
                            dark[p[:3]] += 1
            if opaque * 2 > total:
                if method == "avg":
                    n = sum(cnt.values())
                    dpx[ox, oy] = (*(round(sum(c[i] * k for c, k in cnt.items()) / n) for i in range(3)), 255)
                elif dark and sum(dark.values()) >= dark_share * opaque:
                    dpx[ox, oy] = (*dark.most_common(1)[0][0], 255)
                else:
                    dpx[ox, oy] = (*cnt.most_common(1)[0][0], 255)
    out = Image.new("RGBA", (tw, th))
    x = (tw - ow) // 2
    y = th - margin - oh if anchor == "bottom" else (th - oh) // 2
    out.paste(small, (x, y))
    return out


def add_outline(img, color):
    """Обводка в 1 пиксель снаружи силуэта (4-связная). Размер не меняется."""
    w, h = img.size
    px = img.load()
    out = img.copy()
    opx = out.load()
    for y in range(h):
        for x in range(w):
            if px[x, y][3]:
                continue
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3]:
                    opx[x, y] = (*color, 255)
                    break
    return out


def darkest(colors):
    return min(colors, key=lambda c: 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2])


# --- просмотр -------------------------------------------------------------------

def preview(img, scale=8):
    """Увеличенная копия на шахматке — чтобы глазами (или агенту) видеть прозрачность."""
    w, h = img.size
    bg = Image.new("RGBA", (w * scale, h * scale))
    cell = max(scale, 4)
    bpx = bg.load()
    for y in range(h * scale):
        for x in range(w * scale):
            bpx[x, y] = (205, 205, 215, 255) if (x // cell + y // cell) % 2 else (235, 235, 240, 255)
    big = img.resize((w * scale, h * scale), Image.Resampling.NEAREST)
    bg.alpha_composite(big)
    return bg


def contact_sheet(images, labels=None, pad=8):
    """Склейка нескольких превью в одну картинку (одна картинка — один просмотр)."""
    from PIL import ImageDraw
    w = max(i.width for i in images)
    h = max(i.height for i in images)
    sheet = Image.new("RGBA", (len(images) * (w + pad) + pad, h + pad * 2 + 12), (40, 40, 48, 255))
    d = ImageDraw.Draw(sheet)
    for n, im in enumerate(images):
        x = pad + n * (w + pad)
        sheet.alpha_composite(im, (x, pad + 12))
        d.text((x, 1), labels[n] if labels else str(n), fill=(255, 255, 255, 255))
    return sheet


# --- весь конвейер ---------------------------------------------------------------

def process(raw, size, palette=None, n_colors=16, anchor="bottom", outline=False,
            bg_tol=40, margin=0, chroma=None, method="mode", dark_share=2.0):
    """raw (любая PIL-картинка) -> спрайт size=(w, h) RGBA.

    dark_share — см. to_grid; по умолчанию выключен (2.0). Включать (0.25) только для
    исходников в упрощённом стиле — «dot eyes, flat colors», как у --kind character
    в gen_sprite.py. На детальных исходниках очки и глаза превращаются в чёрное
    пятно, у предметов темнеют заливки (проверено 25.09).
    """
    img = remove_background(raw, tol=bg_tol, chroma=chroma)
    img = drop_specks(img, min_area=max(16, raw.width * raw.height // 4000))
    m = 1 if outline else margin
    if method == "avg":
        img = quantize(to_grid(img, *size, anchor=anchor, margin=m, method="avg"), palette, n_colors)
    else:
        img = to_grid(quantize(img, palette, n_colors), *size, anchor=anchor, margin=m,
                      dark_share=dark_share)
    if outline:
        cols = palette or [p[:3] for p in img.getdata() if p[3]]
        if cols:
            img = add_outline(img, darkest(cols))
    return img


def parse_size(s):
    w, h = s.lower().split("x")
    return int(w), int(h)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--size", default="16x32", help="ШxВ результата, по умолчанию 16x32 (персонаж)")
    ap.add_argument("--palette", help=".hex или .png; без неё палитра подбирается сама")
    ap.add_argument("--colors", type=int, default=16, help="цветов, если --palette не задана")
    ap.add_argument("--anchor", choices=["bottom", "center"], default="bottom")
    ap.add_argument("--outline", action="store_true", help="дорисовать тёмную обводку в 1 px")
    ap.add_argument("--bg-tol", type=int, default=40, help="допуск цвета фона (0-441)")
    ap.add_argument("--chroma", choices=list(CHROMA), help="цвет фона-хромакея, если картинка на нём")
    ap.add_argument("--method", choices=["avg", "mode"], default="mode", help="как уменьшать, см. to_grid")
    ap.add_argument("--preview", action="store_true", help="рядом положить *.preview.png x8")
    a = ap.parse_args()
    pal = load_palette(a.palette) if a.palette else None
    out = process(Image.open(a.src), parse_size(a.size), pal, a.colors, a.anchor, a.outline, a.bg_tol,
                  chroma=a.chroma, method=a.method)
    out.save(a.dst)
    if a.preview:
        preview(out).save(Path(a.dst).with_suffix(".preview.png"))


if __name__ == "__main__":
    main()

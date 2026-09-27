class_name Grid
extends RefCounted

## Единственное место, где записаны размеры всего, что видно на экране.
##
## Владелец: lead. Значения правятся **не здесь**, а в настройках проекта:
## Godot → Проект → Настройки проекта → вкладка «Основные» → раздел `levelup/grid`.
## Там же их увидит и поменяет любой участник, не открывая код.
##
## Зачем это отдельный файл. Размер тайла разошёлся бы по проекту двумя десятками
## чисел: коллизия игрока, радиус, с которого он дотягивается до NPC, смещение
## спрайта, положение подписи над головой, размер окна, регион в атласе тайлов,
## скорость ходьбы. Поменять 16 на 32 означало бы найти их все — и одно
## обязательно потерялось бы, причём проявилось бы через неделю как «игрок
## почему-то проходит сквозь угол стола».
##
## Здесь все они выражены через один размер тайла. Меняется одно число —
## сходится всё.
##
## **Как поменять размер по-настоящему** (три шага, см. `docs/conventions.md`):
##
##     1. Настройки проекта → levelup/grid/tile_size → 32
##     2. python3 tools/make_placeholder_art.py          # перерисовать заглушки
##     3. godot --headless --script tools/build_tileset.gd
##
## Если карта уже собрана вручную, её позиции надо пересчитать:
##
##     godot --headless --script tools/rescale_level.gd -- --from=16 --to=32

# --- Ключи настроек и значения по умолчанию -----------------------------------
# Значения по умолчанию продублированы здесь, чтобы игра работала, даже если
# кто-то снёс секцию в project.godot.

const KEY_TILE := "levelup/grid/tile_size"
const KEY_FRAME_WIDTH := "levelup/grid/character_frame_width"
const KEY_FRAME_HEIGHT := "levelup/grid/character_frame_height"
const KEY_WALK_FRAMES := "levelup/grid/walk_frames"
const KEY_VISIBLE_X := "levelup/grid/visible_tiles_x"
const KEY_VISIBLE_Y := "levelup/grid/visible_tiles_y"

const DEFAULT_TILE := 16
const DEFAULT_FRAME := Vector2i(16, 16)
const DEFAULT_WALK_FRAMES := 4
const DEFAULT_VISIBLE := Vector2i(30, 17)

## Направлений в спрайт-листе: вниз, влево, вправо, вверх. Всегда четыре —
## это вид сверху, пятого направления не бывает.
const SHEET_ROWS := 4

## Скорость ходьбы в тайлах в секунду. Задана в тайлах, а не в пикселях,
## нарочно: при смене размера тайла игрок должен проходить комнату за то же
## время, иначе все тексты, рассчитанные на 15–20 минут прохождения, поедут.
const TILES_PER_SECOND := 3.75

# Настройки читаются один раз: они не меняются по ходу игры, а обращений много.
static var _cache: Dictionary = {}


## Размер тайла в пикселях. 16, 32, 64 — любое число больше нуля.
static func tile_size() -> int:
	return maxi(1, _setting(KEY_TILE, DEFAULT_TILE))


## Размер одного кадра в спрайт-листе человека.
## Высота больше ширины — нормально: 16x32 означает, что голова торчит над
## линией тайла, и персонаж читается лучше. Ширина при этом остаётся тайлом.
static func character_frame() -> Vector2i:
	return Vector2i(
		maxi(1, _setting(KEY_FRAME_WIDTH, DEFAULT_FRAME.x)),
		maxi(1, _setting(KEY_FRAME_HEIGHT, DEFAULT_FRAME.y)))


## Кадров в цикле ходьбы (колонок в листе).
static func walk_frames() -> int:
	return maxi(1, _setting(KEY_WALK_FRAMES, DEFAULT_WALK_FRAMES))


## Сколько тайлов помещается на экран. Отсюда считается размер окна, поэтому
## при смене размера тайла игрок видит ровно столько же офиса, сколько видел.
static func visible_tiles() -> Vector2i:
	return Vector2i(
		maxi(1, _setting(KEY_VISIBLE_X, DEFAULT_VISIBLE.x)),
		maxi(1, _setting(KEY_VISIBLE_Y, DEFAULT_VISIBLE.y)))


## Разрешение, в котором рисуется мир, до растяжения на весь экран.
static func viewport_size() -> Vector2i:
	return visible_tiles() * tile_size()


# --- Производные размеры ------------------------------------------------------
# Всё ниже — доли тайла. Числа подобраны один раз на 16x16 и с тех пор
# выражены отношениями, а не пикселями.

## Смещение спрайта, чтобы ноги стояли на нижней границе тайла,
## а не парили над ним и не тонули в нём.
static func character_sprite_offset() -> Vector2:
	return Vector2(0.0, (float(tile_size()) - float(character_frame().y)) * 0.5)


## Сидящий за столом ниже стоящего на столько пикселей: стол в клетке под ним
## (столешница с 3-й строки тайла, tools/art/draw_tiles.py) закрывает ноги,
## над столом — корпус и голова.
static func seated_drop() -> float:
	return float(tile_size()) * 0.625


## Откуда можно заговорить с сидящим за столом: вокруг него и через стол, от
## переднего края. Круга, как у стоящего, не хватает: между игроком перед столом
## и сидящим две клетки, а дотянуться можно на полторы.
static func desk_reach_rect() -> Rect2:
	var radius := interactable_radius()
	return Rect2(-radius, -radius, radius * 2.0, float(tile_size()) * 1.5 + radius)


## Коробка столкновений человека: только ноги, не весь спрайт. При виде сверху
## тело должно заходить на тайл за спиной, иначе персонаж «толстый» и застревает
## в дверях.
static func body_collision_size() -> Vector2:
	var tile := float(tile_size())
	return Vector2(tile * 0.625, tile * 0.375)


## На сколько коробка столкновений опущена вниз от центра тайла.
static func body_collision_offset() -> Vector2:
	return Vector2(0.0, float(tile_size()) * 0.3125)


## С какого расстояния игрок дотягивается до NPC, двери или предмета.
static func reach_radius() -> float:
	return float(tile_size()) * 0.875


## Насколько близко надо подойти, чтобы NPC считался целью. Чуть меньше, чем
## радиус игрока: иначе в тесной комнате целью становится сосед за стеной.
static func interactable_radius() -> float:
	return float(tile_size()) * 0.625


## Где рисуется подпись с именем: прямоугольник над головой.
static func caption_rect() -> Rect2:
	var tile := float(tile_size())
	var head_top := tile * 0.5 - float(character_frame().y)
	return Rect2(-tile * 2.5, head_top - tile * 0.9, tile * 5.0, tile * 0.875)


## Размер шрифта подписи. Растёт вместе с тайлом, иначе на 64x64 имена
## превращаются в муравьёв.
static func caption_font_size() -> int:
	return maxi(6, roundi(float(tile_size()) * 0.5))


## Скорость ходьбы в пикселях в секунду.
static func player_speed() -> float:
	return TILES_PER_SECOND * float(tile_size())


# --- Интерфейс ----------------------------------------------------------------

## Высота окна, под которую нарисованы сцены интерфейса. Выводится из значений
## по умолчанию, а не пишется числом: иначе при правке DEFAULT_VISIBLE
## интерфейс молча начнёт масштабироваться относительно несуществующего окна.
const UI_REFERENCE_HEIGHT := float(DEFAULT_VISIBLE.y * DEFAULT_TILE)

## Во сколько раз текущее окно выше эталонного. При тайле 16 и 30x17 тайлах
## на экран это единица; при тайле 32 — больше, и интерфейс растёт вместе
## с окном, а не съёживается в угол.
static func ui_scale() -> float:
	return float(viewport_size().y) / UI_REFERENCE_HEIGHT


## Размер шрифта интерфейса. `base` — то, как он выглядит при эталонном окне.
static func ui_font_size(base: int) -> int:
	return maxi(6, roundi(float(base) * ui_scale()))


## Отступ или размер элемента интерфейса, заданный для эталонного окна.
static func ui_length(base: float) -> float:
	return base * ui_scale()


## Прямоугольник одной клетки в атласе тайлов — для спрайтов дверей и предметов,
## которые берут картинку из того же PNG, что и карта.
static func atlas_region(cell: Vector2i) -> Rect2:
	var tile := float(tile_size())
	return Rect2(float(cell.x) * tile, float(cell.y) * tile, tile, tile)


# --- Внутреннее ---------------------------------------------------------------

static func _setting(key: String, fallback: int) -> int:
	if _cache.has(key):
		return _cache[key]
	var value := int(ProjectSettings.get_setting(key, fallback))
	_cache[key] = value
	return value


## Сбросить кеш. Нужно только тестам, которые подменяют размеры на лету.
static func forget_cache() -> void:
	_cache.clear()

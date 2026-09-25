extends SceneTree

## Собирает `assets/tiles/office_placeholder.tres` под текущий размер тайла.
##
##     godot --headless --script tools/build_tileset.gd
##
## Запускать после любой смены `levelup/grid/tile_size` в настройках проекта
## и после того, как artist положит свой атлас вместо заглушки.
##
## Зачем скриптом. В файле тайлсета размер клетки и все коробки столкновений
## записаны числами в пикселях. Поменять 16 на 32 руками — это восемнадцать
## правок в файле, который читать невозможно, и одна опечатка даёт стену,
## сквозь которую проходят. Здесь всё это — доли тайла в одной таблице.

const ATLAS_PATH := "res://assets/tiles/office_placeholder.png"
const OUTPUT_PATH := "res://assets/tiles/office_placeholder.tres"
const SURFACE_LAYER := "surface"

## Тайлы атласа: клетка, название, коробка столкновений в долях тайла.
## `Vector2.ZERO` — сквозь тайл проходят. `surface` — по чему идёт игрок: от этого
## зависит звук шага (src/autoload/sound.gd, assets/sfx/step_<surface>*.wav).
const TILES := [
	{ "cell": Vector2i(0, 0), "name": "ковролин",  "solid": Vector2.ZERO, "surface": "carpet" },
	{ "cell": Vector2i(1, 0), "name": "плитка",    "solid": Vector2.ZERO, "surface": "tile" },
	{ "cell": Vector2i(2, 0), "name": "стена",     "solid": Vector2(1.0, 1.0) },
	{ "cell": Vector2i(3, 0), "name": "верх стены","solid": Vector2.ZERO },
	{ "cell": Vector2i(4, 0), "name": "стол",      "solid": Vector2(1.0, 0.625) },
	{ "cell": Vector2i(5, 0), "name": "стул",      "solid": Vector2.ZERO },
	{ "cell": Vector2i(6, 0), "name": "растение",  "solid": Vector2(0.625, 0.75) },
	{ "cell": Vector2i(7, 0), "name": "дверь",     "solid": Vector2.ZERO },
	{ "cell": Vector2i(0, 1), "name": "шкаф",      "solid": Vector2(1.0, 1.0) },
	{ "cell": Vector2i(1, 1), "name": "кулер",     "solid": Vector2(0.5, 0.875) },
	{ "cell": Vector2i(2, 1), "name": "принтер",   "solid": Vector2(0.875, 0.5) },
	{ "cell": Vector2i(3, 1), "name": "ковёр",     "solid": Vector2.ZERO, "surface": "carpet" },
	{ "cell": Vector2i(4, 1), "name": "коробка",   "solid": Vector2.ZERO },
	{ "cell": Vector2i(5, 1), "name": "папка",     "solid": Vector2.ZERO },
	{ "cell": Vector2i(6, 1), "name": "лицо стены","solid": Vector2(1.0, 1.0) },
]


func _initialize() -> void:
	var texture: Texture2D = load(ATLAS_PATH)
	if texture == null:
		push_error("Не найден атлас %s. Сначала: python3 tools/make_placeholder_art.py"
			% ATLAS_PATH)
		quit(1)
		return

	var tile := Grid.tile_size()
	var expected_width := 8 * tile
	if texture.get_width() != expected_width:
		push_error("Атлас %dx%d не сходится с размером тайла %d (ожидалось %dx%d). "
			% [texture.get_width(), texture.get_height(), tile, expected_width, 2 * tile]
			+ "Перерисуйте заглушки: python3 tools/make_placeholder_art.py")
		quit(1)
		return

	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(tile, tile)
	tile_set.add_physics_layer(0)
	# Слой 1 — «Стены»: с ним сталкивается игрок (см. project.godot, layer_names).
	tile_set.set_physics_layer_collision_layer(0, 1)
	tile_set.set_physics_layer_collision_mask(0, 0)
	# Слой данных «surface»: его видно и в редакторе, в свойствах тайла.
	tile_set.add_custom_data_layer(0)
	tile_set.set_custom_data_layer_name(0, SURFACE_LAYER)
	tile_set.set_custom_data_layer_type(0, TYPE_STRING)

	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(tile, tile)
	# Источник добавляется в тайлсет ДО создания тайлов: слои столкновений
	# живут в тайлсете, и до этого момента у тайла их просто нет.
	tile_set.add_source(source, 0)

	var solid_count := 0
	for entry: Dictionary in TILES:
		source.create_tile(entry["cell"])
		if entry.has("surface"):
			source.get_tile_data(entry["cell"], 0).set_custom_data(SURFACE_LAYER, entry["surface"])
		var solid: Vector2 = entry["solid"]
		if solid == Vector2.ZERO:
			continue
		var data := source.get_tile_data(entry["cell"], 0)
		data.add_collision_polygon(0)
		data.set_collision_polygon_points(0, 0, _box(solid))
		solid_count += 1

	if ResourceSaver.save(tile_set, OUTPUT_PATH) != OK:
		push_error("Не удалось сохранить %s" % OUTPUT_PATH)
		quit(1)
		return
	print("Тайлсет собран: %s — тайл %dx%d, %d тайлов, из них непроходимых %d"
		% [OUTPUT_PATH, tile, tile, TILES.size(), solid_count])
	quit(0)


## Коробка столкновений по центру тайла. Размер задан в долях тайла,
## поэтому при смене размера ничего пересчитывать не надо.
func _box(fraction: Vector2) -> PackedVector2Array:
	var half := fraction * float(Grid.tile_size()) * 0.5
	return PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])

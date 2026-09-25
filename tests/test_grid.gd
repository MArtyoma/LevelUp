extends TestCase

## Тесты размерной сетки.
##
## Смысл этих тестов не в арифметике, а в одном обещании: **проект переживает
## смену размера тайла.** Проверяем его на 16, 32 и 64 сразу, потому что
## поломка тут молчаливая — игра запускается, просто персонаж парит над полом
## или застревает в дверях, и виноватым назначают «кривую физику Godot».

const SIZES := [16, 32, 64]


func after_each() -> void:
	# Тесты подменяют настройки проекта. Если не вернуть их на место,
	# все следующие тесты будут считать, что тайл 64.
	_set_grid(16, Vector2i(16, 16), Vector2i(30, 17))


func test_viewport_keeps_the_same_piece_of_office() -> void:
	# Главное обещание: при любом размере тайла на экран влезает одинаковое
	# число тайлов. Иначе на 64 игрок видит четверть комнаты и теряется.
	for tile: int in SIZES:
		_set_grid(tile, Vector2i(tile, tile), Vector2i(30, 17))
		equals(Grid.viewport_size(), Vector2i(30 * tile, 17 * tile),
			"размер окна при тайле %d" % tile)


func test_walking_speed_does_not_depend_on_tile_size() -> void:
	# Прохождение рассчитано на 15–20 минут: столько же контрольная группа
	# смотрит презентацию. Если при смене тайла игрок начнёт ходить вдвое
	# медленнее, сравнивать группы станет не с чем.
	for tile: int in SIZES:
		_set_grid(tile, Vector2i(tile, tile), Vector2i(30, 17))
		var tiles_per_second := Grid.player_speed() / float(tile)
		equals(snappedf(tiles_per_second, 0.01), Grid.TILES_PER_SECOND,
			"тайлов в секунду при тайле %d" % tile)


func test_character_stands_on_the_tile() -> void:
	# Ноги должны стоять на нижней границе тайла — и при кадре 16x16,
	# и при высоком кадре 16x32, где голова торчит над линией тайла.
	for frame_height: int in [16, 32, 48]:
		_set_grid(16, Vector2i(16, frame_height), Vector2i(30, 17))
		var offset := Grid.character_sprite_offset()
		var feet := offset.y + float(frame_height) * 0.5
		equals(feet, 8.0, "нижний край спрайта при кадре 16x%d" % frame_height)


func test_body_is_narrower_than_the_tile() -> void:
	# Коробка столкновений шире тайла означает, что персонаж не пройдёт
	# в дверной проём шириной в одну клетку.
	for tile: int in SIZES:
		_set_grid(tile, Vector2i(tile, tile), Vector2i(30, 17))
		var body := Grid.body_collision_size()
		check(body.x < float(tile), "коробка шире тайла при тайле %d" % tile)
		check(body.y < float(tile), "коробка выше тайла при тайле %d" % tile)


func test_atlas_region_follows_tile_size() -> void:
	for tile: int in SIZES:
		_set_grid(tile, Vector2i(tile, tile), Vector2i(30, 17))
		equals(Grid.atlas_region(Vector2i(2, 1)),
			Rect2(2.0 * tile, 1.0 * tile, tile, tile), "регион атласа при тайле %d" % tile)


func test_reach_is_bigger_than_npc_radius() -> void:
	# Радиус игрока должен быть больше радиуса NPC, иначе до собеседника
	# невозможно дотянуться вплотную к столу.
	for tile: int in SIZES:
		_set_grid(tile, Vector2i(tile, tile), Vector2i(30, 17))
		check(Grid.reach_radius() > Grid.interactable_radius(),
			"радиус игрока не больше радиуса NPC при тайле %d" % tile)


func test_ui_scales_with_the_window() -> void:
	_set_grid(16, Vector2i(16, 16), Vector2i(30, 17))
	equals(Grid.ui_scale(), 1.0, "при эталонном окне масштаб интерфейса должен быть 1")
	var base_font := Grid.ui_font_size(8)

	_set_grid(32, Vector2i(32, 32), Vector2i(30, 17))
	check(Grid.ui_font_size(8) > base_font, "шрифт интерфейса не вырос вместе с окном")


func test_broken_settings_do_not_break_the_game() -> void:
	# Кто-то вписал ноль. Игра должна работать, а не делить на ноль.
	_set_grid(0, Vector2i(0, 0), Vector2i(0, 0))
	check(Grid.tile_size() >= 1, "нулевой тайл не был исправлен")
	check(Grid.viewport_size().x >= 1, "нулевое окно не было исправлено")


func _set_grid(tile: int, frame: Vector2i, visible: Vector2i) -> void:
	ProjectSettings.set_setting(Grid.KEY_TILE, tile)
	ProjectSettings.set_setting(Grid.KEY_FRAME_WIDTH, frame.x)
	ProjectSettings.set_setting(Grid.KEY_FRAME_HEIGHT, frame.y)
	ProjectSettings.set_setting(Grid.KEY_VISIBLE_X, visible.x)
	ProjectSettings.set_setting(Grid.KEY_VISIBLE_Y, visible.y)
	Grid.forget_cache()

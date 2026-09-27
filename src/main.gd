extends Node2D

## Точка входа: собирает уровень, игрока и интерфейс.
##
## Владелец: lead.
##
## Сцена нарочно почти пустая. Всё, что здесь есть, — сборка: какой уровень открыть,
## куда поставить игрока, какой интерфейс подключить. Логики игры тут нет и быть
## не должно: иначе в `main.tscn` будут лезть все сразу, а это единственная сцена,
## которую невозможно поделить между владельцами.
##
## Если данные не загрузились — игра не начинается, а показывает, что именно
## сломано. Это важнее, чем кажется: на демо и на замере нужен не «чёрный экран»,
## а строка «data/company.json, строка 42: забыта запятая».

## Какой уровень открыть. Меняется в инспекторе — новый уровень не требует кода.
@export_file("*.tscn") var level_scene: String = "res://src/levels/office_demo.tscn"

const PLAYER_SCENE := preload("res://src/actors/player/player.tscn")

## Сколько ждём второго нажатия Esc, прежде чем выйти.
const QUIT_CONFIRM_MS := 2000

@onready var _world: Node2D = $World

# Когда в последний раз нажали Esc вне разговора. Выход — только по второму нажатию.
var _quit_requested_at: int = -QUIT_CONFIRM_MS * 10


func _ready() -> void:
	# Размер окна считается из размера тайла: сколько тайлов помещается на экран,
	# записано в настройках проекта и не зависит от того, 16 там или 64.
	get_window().content_scale_size = Grid.viewport_size()

	if not GameData.is_loaded:
		_show_data_error()
		return

	var level: Node = (load(level_scene) as PackedScene).instantiate()
	_world.add_child(level)

	var player: Player = PLAYER_SCENE.instantiate()
	player.global_position = _spawn_position(level)
	_world.add_child(player)
	_limit_camera_to_level(level, player)
	Sound.play_music("office")

	EventBus.game_finished.connect(_on_game_finished)
	print("LevelUp: компания %s, данные из %s" % [
		GameData.company_info.get("name", "?"), GameData.data_dir])


## Где начинает игрок. На карте это узел Marker2D с именем PlayerSpawn —
## его ставит level designer, кода для этого не нужно.
func _spawn_position(level: Node) -> Vector2:
	var marker := level.get_node_or_null("PlayerSpawn")
	if marker is Node2D:
		return marker.global_position
	push_warning("В уровне нет узла PlayerSpawn — игрок появится в начале координат")
	return Vector2.ZERO


## Камера упирается в края карты, а не показывает серую пустоту за стенами.
## Границы берутся из слоя тайлов — значит, level designer расширил карту, и камера
## подстроилась сама, без правки кода.
func _limit_camera_to_level(level: Node, player: Player) -> void:
	var ground := level.find_child("Ground", true, false)
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if not (ground is TileMapLayer) or camera == null:
		return

	var used: Rect2i = (ground as TileMapLayer).get_used_rect()
	var tile: Vector2i = (ground as TileMapLayer).tile_set.tile_size
	camera.limit_left = used.position.x * tile.x
	camera.limit_top = used.position.y * tile.y
	camera.limit_right = used.end.x * tile.x
	camera.limit_bottom = used.end.y * tile.y


func _on_game_finished(reason: String) -> void:
	print("Прохождение закончено (%s). Сводка: %s" % [reason, Telemetry.summary()])


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# Escape посреди разговора закрывает разговор, а не игру. Иначе участник
	# замера, нажавший привычное «выйти из диалога», выходит из эксперимента,
	# и прохождение приходится начинать заново.
	if DialogueRunner.is_running:
		DialogueRunner.stop()
		get_viewport().set_input_as_handled()
		return
	# По той же причине вне разговора выход — только со второго нажатия:
	# Esc жмут по привычке, чтобы «закрыть что-нибудь», а прохождение
	# участника замера с середины не продолжить.
	var now := Time.get_ticks_msec()
	if now - _quit_requested_at > QUIT_CONFIRM_MS:
		_quit_requested_at = now
		EventBus.hint_shown.emit("Нажми Esc ещё раз, чтобы выйти из игры")
		get_viewport().set_input_as_handled()
		return
	EventBus.game_finished.emit("quit")
	get_tree().quit()


## Экран ошибки данных. Нарочно уродливый и нарочно подробный.
func _show_data_error() -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.anchors_preset = Control.PRESET_FULL_RECT
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.add_theme_font_size_override("font_size", Grid.ui_font_size(8))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = (
		"Игра не запустилась: данные не проходят проверку.\n\n%s\n\n"
		+ "Почините файлы в data/ и запустите снова.\n"
		+ "Проверить вручную: godot --headless --script tools/validate_data.gd"
	) % GameData.load_error
	layer.add_child(label)
	add_child(layer)
	push_error(GameData.load_error)

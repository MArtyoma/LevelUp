class_name NpcRoutine
extends Node

## Чем сотрудник за столом занят между разговорами с игроком: печатает (это
## делает сам Npc), изредка говорит по телефону или отходит к шкафу и возвращается.
##
## Владелец кода: лид. Куда ходить — **level designer**: дочерние Marker2D у NPC на карте,
## имя начинается с `Errand`. Там сотрудник постоит лицом вверх — к шкафу,
## стеллажу, серверу. Нет маркеров — никуда не ходит, только звонит.
##
## Правила, ради которых всё так, а не иначе (на замере игрок не должен
## гоняться за сотрудником):
##
##   * из кабинета не выходит: маркеры стоят в его же кабинете, тест это проверяет;
##   * отлучка — секунды, почти всё время он за столом, где его и ищут;
##   * игрок ближе NOTICE_TILES — бросает дела и смотрит на него: E работает
##     сразу, никакой погони.
##
## Нужен лист на 6 рядов (tools/art/make_sheet.py, NPC_ROWS). У общего спрайта
## рядов четыре — такой сотрудник просто печатает, NpcRoutine ему не дают.

const ROW_IDLE := 0
const ROW_LEFT := 1
const ROW_RIGHT := 2
const ROW_UP := 3
const ROW_DOWN := 4
const ROW_PHONE := 5
const SHEET_ROWS := 6

## Сколько секунд между делами — случайно в этих пределах.
const PAUSE_SECONDS := Vector2(15.0, 35.0)
const PHONE_SECONDS := Vector2(5.0, 9.0)
## Сколько стоит у шкафа.
const ERRAND_SECONDS := Vector2(2.5, 4.5)
const PHONE_CHANCE := 0.5
## Скорость — доля скорости игрока: сотрудник не бегает по кабинету.
const SPEED_SHARE := 0.5
const WALK_FPS := 7.0
const PHONE_NOD_SECONDS := 0.4
## Игрок ближе — сотрудник бросает дела и смотрит на него.
const NOTICE_TILES := 2.5

enum State { DESK, PHONE, GOING, THERE, RETURNING }

var state: State = State.DESK

var _npc: Npc
var _sprite: Sprite2D
var _home: Vector2
var _spots: Array[Vector2] = []
var _path: PackedVector2Array = PackedVector2Array()
var _timer: Timer
var _anim: float = 0.0
var _player: Node2D


## `npc` — хозяин; вызывается до добавления в дерево, пока NPC стоит на месте.
func setup(npc: Npc, sprite: Sprite2D) -> void:
	name = "Routine"
	_npc = npc
	_sprite = sprite
	_home = npc.position
	for child in npc.get_children():
		if child is Marker2D and String(child.name).begins_with("Errand"):
			_spots.append(npc.position + (child as Marker2D).position)


func _ready() -> void:
	set_process(false)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_timer)
	add_child(_timer)
	_wait(PAUSE_SECONDS)


func _wait(range_seconds: Vector2) -> void:
	_timer.start(randf_range(range_seconds.x, range_seconds.y))


func _on_timer() -> void:
	match state:
		State.DESK:
			_start_something()
		State.PHONE:
			_back_to_work()
		State.THERE:
			_walk_to(_home, State.RETURNING)


# --- Решения ------------------------------------------------------------------

func _start_something() -> void:
	# Не при игроке и не посреди чьего-то разговора: отвлекать на замере нельзя.
	if DialogueRunner.is_running or _player_distance() < NOTICE_TILES * 2.0 * _tile():
		_wait(Vector2(4.0, 8.0))
		return
	if _spots.is_empty() or randf() < PHONE_CHANCE:
		_start_phone()
	else:
		_walk_to(_spots.pick_random(), State.GOING)


func _start_phone() -> void:
	state = State.PHONE
	_npc.busy = true
	_show(ROW_PHONE, 0)
	_anim = 0.0
	_wait(PHONE_SECONDS)
	set_process(true)


func _walk_to(target: Vector2, next_state: State) -> void:
	var level := _npc.get_parent()
	_path = find_path(level, _npc.position, target, _npc)
	if _path.is_empty():
		# Не дойти (level designer поставил шкаф на маркер) — значит, сидим. Тест это ловит.
		_back_to_work()
		return
	_path.remove_at(0)
	state = next_state
	_npc.busy = true
	_npc.set_seated(false)
	_anim = 0.0
	set_process(true)


func _back_to_work() -> void:
	state = State.DESK
	_npc.busy = false
	_npc.set_seated(true)
	_show(ROW_IDLE, 0)
	set_process(false)
	_wait(PAUSE_SECONDS)


# --- Каждый кадр, только пока занят делом ---------------------------------------

func _process(delta: float) -> void:
	var near := _player_distance() < NOTICE_TILES * _tile()
	if state == State.PHONE:
		if near:
			# Кладёт трубку: к нему пришли.
			_back_to_work()
			return
		_anim += delta
		_show(ROW_PHONE, int(_anim / PHONE_NOD_SECONDS) % 2)
		return
	if near:
		_face_player()
		return
	if state == State.THERE:
		_show(ROW_UP, 0)
		return
	_step(delta)


func _step(delta: float) -> void:
	if _path.is_empty():
		_arrive()
		return
	var target := _path[0]
	var move := target - _npc.position
	_npc.position = _npc.position.move_toward(target, Grid.player_speed() * SPEED_SHARE * delta)
	if _npc.position.is_equal_approx(target):
		_path.remove_at(0)
	_anim += delta * WALK_FPS
	_show(_row_for(move), int(_anim) % _sprite.hframes)


func _arrive() -> void:
	if state == State.GOING:
		state = State.THERE
		_show(ROW_UP, 0)
		_wait(ERRAND_SECONDS)
	else:
		_npc.position = _home
		_back_to_work()


func _face_player() -> void:
	if _player == null:
		return
	var direction := _player.global_position - _npc.global_position
	var row := _row_for(direction)
	_show(ROW_IDLE if row == ROW_DOWN else row, 0)


# --- Мелочи --------------------------------------------------------------------

func _show(row: int, column: int) -> void:
	_sprite.frame_coords = Vector2i(column, row)


func _row_for(direction: Vector2) -> int:
	if absf(direction.x) >= absf(direction.y):
		return ROW_RIGHT if direction.x > 0.0 else ROW_LEFT
	return ROW_DOWN if direction.y > 0.0 else ROW_UP


func _tile() -> float:
	return float(Grid.tile_size())


func _player_distance() -> float:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	if _player == null:
		return INF
	return _player.global_position.distance_to(_npc.global_position)


## Путь по клеткам от `from` до `to` (координаты уровня), обходя твёрдые тайлы
## и других сотрудников. Пустой — не дойти. Статическая: ею же пользуется тест
## «до каждого маркера можно дойти».
static func find_path(level: Node, from: Vector2, to: Vector2, walker: Node = null) -> PackedVector2Array:
	var layers: Array[TileMapLayer] = []
	for node in level.find_children("*", "TileMapLayer", true, false):
		layers.append(node as TileMapLayer)
	if layers.is_empty():
		return PackedVector2Array()
	var base := layers[0]
	var region := Rect2i()
	for layer in layers:
		region = region.merge(layer.get_used_rect()) if region.has_area() else layer.get_used_rect()

	var grid := AStarGrid2D.new()
	grid.region = region
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			grid.set_point_solid(Vector2i(x, y), not _walkable(layers, Vector2i(x, y)))
	for npc in level.find_children("*", "Area2D", true, false):
		if npc is Npc and npc != walker:
			grid.set_point_solid(base.local_to_map((npc as Node2D).position))

	var start := base.local_to_map(from)
	var goal := base.local_to_map(to)
	if not region.has_point(start) or not region.has_point(goal):
		return PackedVector2Array()
	# Свою клетку считаем свободной: сидящий стоит «в» ней.
	grid.set_point_solid(start, false)
	var path := PackedVector2Array()
	for cell in grid.get_id_path(start, goal):
		path.append(base.map_to_local(cell))
	return path


## Клетка проходима, если на ней есть пол и ни на одном слое нет твёрдого тайла.
static func _walkable(layers: Array[TileMapLayer], cell: Vector2i) -> bool:
	var has_floor := false
	for layer in layers:
		var data := layer.get_cell_tile_data(cell)
		if data == null:
			continue
		has_floor = true
		if data.get_collision_polygons_count(0) > 0:
			return false
	return has_floor

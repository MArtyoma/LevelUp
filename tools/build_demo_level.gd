extends SceneTree

## Собирает демонстрационный этаж `src/levels/office_demo.tscn`.
##
##     godot --headless --script tools/build_demo_level.gd
##
## Запускается **один раз**. Дальше карту правит level designer прямо в редакторе Godot,
## и перезапуск скрипта затрёт его работу — поэтому скрипт и не висит в сборке.
## Он существует ради одного: чтобы вертикальный срез можно было пройти уже
## сегодня, не дожидаясь, пока кто-то освоит редактор тайлов.
##
## Планировка нарочно примитивная: коридор посередине, четыре кабинета сверху,
## один снизу. Настоящая планировка — зона level designer, и она должна сойтись
## с легендой writer (в каком кабинете какой отдел).

const TILE := 16
const MAP_WIDTH := 40
const MAP_HEIGHT := 17

# Координаты тайлов в атласе assets/tiles/office_placeholder.png
const T_CARPET := Vector2i(0, 0)
const T_FLOOR := Vector2i(1, 0)
const T_WALL := Vector2i(2, 0)
const T_DESK := Vector2i(4, 0)
const T_PLANT := Vector2i(6, 0)
const T_CABINET := Vector2i(0, 1)
const T_COOLER := Vector2i(1, 1)

## Коридор: через него соединяются все кабинеты.
const CORRIDOR := Rect2i(1, 7, 38, 3)

## Кабинеты. `door` — клетка в стене, которую нужно открыть.
const ROOMS := [
	{ "id": "room_hr",      "rect": Rect2i(1, 1, 9, 5),   "door": Vector2i(5, 6) },
	{ "id": "room_sales",   "rect": Rect2i(11, 1, 9, 5),  "door": Vector2i(15, 6) },
	{ "id": "room_it",      "rect": Rect2i(21, 1, 8, 5),  "door": Vector2i(24, 6) },
	{ "id": "room_admin",   "rect": Rect2i(30, 1, 9, 5),  "door": Vector2i(34, 6), "access": 2 },
	{ "id": "room_finance", "rect": Rect2i(11, 11, 9, 5), "door": Vector2i(15, 10) },
]

## Кто где сидит. id сотрудника — из data/company.json.
const NPCS := [
	{ "employee": "emp_mironova", "cell": Vector2i(5, 3) },
	{ "employee": "emp_pavlov",   "cell": Vector2i(15, 3) },
	{ "employee": "emp_kim",      "cell": Vector2i(23, 3) },
	{ "employee": "emp_sokolov",  "cell": Vector2i(26, 3) },
	{ "employee": "emp_koroleva", "cell": Vector2i(34, 3) },
	{ "employee": "emp_zaytseva", "cell": Vector2i(15, 13) },
]

const PLAYER_SPAWN := Vector2i(5, 8)

var _root: Node2D
var _ground: TileMapLayer
var _walls: TileMapLayer


func _initialize() -> void:
	var tile_set: TileSet = load("res://assets/tiles/office_placeholder.tres")

	_root = Node2D.new()
	_root.name = "OfficeDemo"
	_root.y_sort_enabled = true

	_ground = _make_layer("Ground", tile_set, 0)
	_walls = _make_layer("Walls", tile_set, 1)

	_fill_with_walls()
	_carve(CORRIDOR, T_FLOOR)
	for room: Dictionary in ROOMS:
		_carve(room["rect"], T_CARPET)
		_open_door(room["door"])
		_furnish(room["rect"])

	_add_access_doors()
	_add_room_triggers()
	_add_npcs()
	_add_quest_object(Vector2i(7, 4))
	_add_player_spawn()

	_save()
	quit(0)


func _make_layer(layer_name: String, tile_set: TileSet, z: int) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = tile_set
	layer.z_index = z
	_root.add_child(layer)
	layer.owner = _root
	return layer


## Сначала всё — стена, потом вырезаем помещения. Так снаружи карты не остаётся
## дыр, через которые игрок уходит в пустоту.
func _fill_with_walls() -> void:
	for y in MAP_HEIGHT:
		for x in MAP_WIDTH:
			_walls.set_cell(Vector2i(x, y), 0, T_WALL)


func _carve(rect: Rect2i, floor_tile: Vector2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_walls.erase_cell(Vector2i(x, y))
			_ground.set_cell(Vector2i(x, y), 0, floor_tile)


func _open_door(cell: Vector2i) -> void:
	_walls.erase_cell(cell)
	_ground.set_cell(cell, 0, T_FLOOR)


## Немного мебели, чтобы кабинет не выглядел пустым прямоугольником.
## Стоит по углам — так она не перегораживает проход к NPC.
func _furnish(rect: Rect2i) -> void:
	var corner := Vector2i(rect.end.x - 2, rect.position.y)
	_walls.set_cell(corner, 0, T_PLANT)
	_walls.set_cell(Vector2i(rect.position.x, rect.position.y), 0, T_CABINET)
	_walls.set_cell(Vector2i(rect.position.x + 1, rect.end.y - 1), 0, T_DESK)
	_ground.set_cell(Vector2i(rect.end.x - 1, rect.end.y - 1), 0, T_CARPET)
	_walls.set_cell(Vector2i(rect.end.x - 1, rect.end.y - 1), 0, T_COOLER)


func _add_access_doors() -> void:
	var scene: PackedScene = load("res://src/actors/props/access_door.tscn")
	for room: Dictionary in ROOMS:
		if not room.has("access"):
			continue
		var door: Node2D = scene.instantiate()
		door.name = "Door_" + String(room["id"])
		door.position = _center_of(room["door"])
		door.set("required_access", int(room["access"]))
		door.set("denied_text", "Дверь дирекции. Нужен пропуск второго уровня.")
		_root.add_child(door)
		door.owner = _root


func _add_room_triggers() -> void:
	var scene: PackedScene = load("res://src/actors/props/room_trigger.tscn")
	for room: Dictionary in ROOMS:
		var rect: Rect2i = room["rect"]
		var trigger: Node2D = scene.instantiate()
		trigger.name = "Trigger_" + String(room["id"])
		trigger.position = Vector2(
			(float(rect.position.x) + float(rect.size.x) * 0.5) * TILE,
			(float(rect.position.y) + float(rect.size.y) * 0.5) * TILE)
		trigger.set("room_id", String(room["id"]))
		var shape: CollisionShape2D = trigger.get_node("CollisionShape2D")
		var box := RectangleShape2D.new()
		box.size = Vector2(rect.size) * TILE
		shape.shape = box
		_root.add_child(trigger)
		trigger.owner = _root


func _add_npcs() -> void:
	var scene: PackedScene = load("res://src/actors/npc/npc.tscn")
	for entry: Dictionary in NPCS:
		var npc: Node2D = scene.instantiate()
		npc.name = "Npc_" + String(entry["employee"])
		npc.position = _center_of(entry["cell"])
		npc.set("employee_id", String(entry["employee"]))
		_root.add_child(npc)
		npc.owner = _root


func _add_quest_object(cell: Vector2i) -> void:
	var scene: PackedScene = load("res://src/actors/props/quest_object.tscn")
	var object: Node2D = scene.instantiate()
	object.name = "Documents"
	object.position = _center_of(cell)
	object.set("quest_id", "q_onboarding")
	object.set("objective_id", "obj_docs")
	object.set("prompt", "E — забрать папку с документами")
	_root.add_child(object)
	object.owner = _root


func _add_player_spawn() -> void:
	var marker := Marker2D.new()
	marker.name = "PlayerSpawn"
	marker.position = _center_of(PLAYER_SPAWN)
	_root.add_child(marker)
	marker.owner = _root


func _center_of(cell: Vector2i) -> Vector2:
	return Vector2(cell) * TILE + Vector2(TILE, TILE) * 0.5


func _save() -> void:
	var packed := PackedScene.new()
	if packed.pack(_root) != OK:
		push_error("Не удалось упаковать сцену")
		quit(1)
		return
	var path := "res://src/levels/office_demo.tscn"
	if ResourceSaver.save(packed, path) != OK:
		push_error("Не удалось сохранить %s" % path)
		quit(1)
		return
	print("Уровень собран: %s (%dx%d тайлов)" % [path, MAP_WIDTH, MAP_HEIGHT])

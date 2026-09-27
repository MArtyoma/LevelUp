class_name RoomTrigger
extends Area2D

## Невидимая зона: игрок вошёл в помещение.
##
## Владелец кода: lead. Расстановка: **level designer**.
##
## Нужна не игре, а замеру гипотезы: по записи прохождения видно, в каком порядке
## человек обходил офис и где застрял. Без этого на защите нечем объяснить, почему
## участник не нашёл половину контента (см. `src/autoload/telemetry.gd`).

## Совпадает с id помещения в легенде компании: "room_sales", "room_hr".
@export var room_id: String = ""

## Размер зоны **в тайлах**, а не в пикселях. Так комната остаётся той же
## комнатой при любом размере тайла.
@export var size_in_tiles: Vector2i = Vector2i(9, 5)

@onready var _shape: CollisionShape2D = $CollisionShape2D

var _already_entered: bool = false


func _ready() -> void:
	_apply_grid()
	set_process(false)
	set_physics_process(false)
	body_entered.connect(_on_body_entered)


func _apply_grid() -> void:
	var box := RectangleShape2D.new()
	box.size = Vector2(size_in_tiles) * float(Grid.tile_size())
	_shape.shape = box


func _on_body_entered(body: Node2D) -> void:
	if _already_entered or not body is Player:
		return
	# Только первый вход: интересен маршрут, а не то, сколько раз человек
	# прошёл туда-обратно через дверной проём.
	_already_entered = true
	EventBus.room_entered.emit(room_id)

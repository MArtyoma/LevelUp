class_name RoomTrigger
extends Area2D

## Невидимая зона: игрок вошёл в помещение.
##
## Владелец кода: лид. Расстановка: **level designer**.
##
## Нужна не игре, а замеру гипотезы: по записи прохождения видно, в каком порядке
## человек обходил офис и где застрял. Без этого на защите нечем объяснить, почему
## участник не нашёл половину контента (см. `src/autoload/telemetry.gd`).

## Совпадает с id помещения в легенде компании: "room_sales", "room_hr".
@export var room_id: String = ""

var _already_entered: bool = false


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _already_entered or not body is Player:
		return
	# Только первый вход: интересен маршрут, а не то, сколько раз человек
	# прошёл туда-обратно через дверной проём.
	_already_entered = true
	EventBus.room_entered.emit(room_id)

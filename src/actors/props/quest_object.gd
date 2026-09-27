class_name QuestObject
extends Area2D

## Предмет, который закрывает шаг квеста: документ на столе, папка, принтер.
##
## Владелец кода: lead. Расстановка: **level designer**.
##
## Даёт квестам шаги, не требующие разговора («взять документ»), и не требует
## ни строчки кода на каждый новый предмет: id квеста и шага ставятся в инспекторе.

@export var quest_id: String = ""
@export var objective_id: String = ""

## Что написано в подсказке: «E — взять документ».
@export var prompt: String = "E — взять"

## Убрать предмет с карты после использования.
@export var disappear_after_use: bool = true

## Какая клетка атласа тайлов рисуется как этот предмет.
@export var atlas_cell: Vector2i = Vector2i(4, 0)

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _shape: CollisionShape2D = $CollisionShape2D

var _marker: QuestMarker


func _ready() -> void:
	_apply_grid()
	add_to_group("interactable")
	set_process(false)
	set_physics_process(false)
	_add_marker()


func _apply_grid() -> void:
	var reach := CircleShape2D.new()
	reach.radius = Grid.interactable_radius()
	_shape.shape = reach

	var atlas := _sprite.texture as AtlasTexture
	if atlas != null:
		atlas = atlas.duplicate() as AtlasTexture
		atlas.region = Grid.atlas_region(atlas_cell)
		_sprite.texture = atlas


func interact(_player: Node2D) -> void:
	if not QuestLog.complete_objective(quest_id, objective_id):
		# Шаг не тот или квест ещё не взят — подсказываем, а не молчим.
		EventBus.hint_shown.emit("Сейчас это не нужно.")
		return
	if disappear_after_use:
		queue_free()


## «?» над предметом, пока он — текущий шаг квеста. Документы на столе среди
## мебели иначе не заметить: игрок обходит кабинет по кругу и не видит папку.
func _add_marker() -> void:
	_marker = QuestMarker.new()
	add_child(_marker)
	_marker.position.y = -float(Grid.tile_size()) * 0.5 - _marker.height() * 0.5
	EventBus.quest_started.connect(_refresh_marker.unbind(1))
	EventBus.quest_objective_completed.connect(_refresh_marker.unbind(2))
	_refresh_marker()


func _refresh_marker() -> void:
	_marker.show_kind(QuestLog.MARK_STEP
		if QuestLog.is_current_step("%s/%s" % [quest_id, objective_id]) else "")


func interaction_prompt() -> String:
	return prompt

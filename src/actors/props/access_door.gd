class_name AccessDoor
extends Area2D

## Дверь, которую открывает пропуск нужного уровня.
##
## Владелец кода: лид. Расстановка: **level designer**.
##
## Это вся прогрессия игры (устав: «прогрессия завязана на пропуск»). Дверь ничего
## не знает про квесты: она смотрит только на уровень доступа в QuestLog. Квест
## выдаёт пропуск, дверь его проверяет — связи между ними в коде нет, и добавить
## новый способ повысить доступ можно, не трогая двери.

## Какой уровень пропуска нужен, чтобы пройти.
@export var required_access: int = 2

## Что игрок видит, когда пропуска не хватает. Пустая строка — текст по умолчанию.
@export var denied_text: String = ""

## Какая клетка атласа тайлов рисуется как дверь. Меняется в инспекторе,
## если artist переложит картинки в тайлсете.
@export var atlas_cell: Vector2i = Vector2i(7, 0)

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _blocker_shape: CollisionShape2D = $Blocker/CollisionShape2D

var _is_open: bool = false


func _ready() -> void:
	_apply_grid()
	add_to_group("interactable")
	set_process(false)
	set_physics_process(false)
	EventBus.access_level_changed.connect(_on_access_level_changed)
	_on_access_level_changed(QuestLog.access_level)


## Дверь занимает ровно один тайл, какого бы размера он ни был.
func _apply_grid() -> void:
	var tile := float(Grid.tile_size())

	var box := RectangleShape2D.new()
	box.size = Vector2(tile, tile)
	_shape.shape = box
	_blocker_shape.shape = box

	# Картинка берётся из того же атласа, что и карта. Копия нужна, чтобы
	# у каждой двери был свой регион: сам подресурс из сцены — общий.
	var atlas := _sprite.texture as AtlasTexture
	if atlas != null:
		atlas = atlas.duplicate() as AtlasTexture
		atlas.region = Grid.atlas_region(atlas_cell)
		_sprite.texture = atlas


func interact(_player: Node2D) -> void:
	if _is_open:
		return
	EventBus.access_denied.emit(required_access, QuestLog.access_level)
	EventBus.hint_shown.emit(_denied_message())


func interaction_prompt() -> String:
	if _is_open:
		return ""
	return _denied_message()


func _denied_message() -> String:
	if not denied_text.is_empty():
		return denied_text
	return "Пропуск не подходит. Нужен уровень %d, у тебя %d." % [
		required_access, QuestLog.access_level]


func _on_access_level_changed(level: int) -> void:
	_is_open = level >= required_access
	# Открытая дверь перестаёт быть препятствием и перестаёт перехватывать
	# взаимодействие — иначе игрок не сможет поговорить с тем, кто стоит за ней.
	# set_deferred, потому что менять формы столкновений посреди кадра физики
	# нельзя: Godot про это честно ругается.
	_shape.set_deferred("disabled", _is_open)
	_blocker_shape.set_deferred("disabled", _is_open)
	visible = not _is_open

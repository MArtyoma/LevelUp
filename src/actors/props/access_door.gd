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

@onready var _blocker: StaticBody2D = $Blocker

var _is_open: bool = false


func _ready() -> void:
	add_to_group("interactable")
	set_process(false)
	set_physics_process(false)
	EventBus.access_level_changed.connect(_on_access_level_changed)
	_on_access_level_changed(QuestLog.access_level)


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
	_blocker.set_deferred("process_mode",
		Node.PROCESS_MODE_DISABLED if _is_open else Node.PROCESS_MODE_INHERIT)
	$CollisionShape2D.set_deferred("disabled", _is_open)
	$Blocker/CollisionShape2D.set_deferred("disabled", _is_open)
	visible = not _is_open

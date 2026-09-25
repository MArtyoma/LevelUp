class_name QuestObject
extends Area2D

## Предмет, который закрывает шаг квеста: документ на столе, папка, принтер.
##
## Владелец кода: лид. Расстановка: **level designer**.
##
## Даёт квестам шаги, не требующие разговора («взять документ»), и не требует
## ни строчки кода на каждый новый предмет: id квеста и шага ставятся в инспекторе.

@export var quest_id: String = ""
@export var objective_id: String = ""

## Что написано в подсказке: «E — взять документ».
@export var prompt: String = "E — взять"

## Убрать предмет с карты после использования.
@export var disappear_after_use: bool = true


func _ready() -> void:
	add_to_group("interactable")
	set_process(false)
	set_physics_process(false)


func interact(_player: Node2D) -> void:
	if not QuestLog.complete_objective(quest_id, objective_id):
		# Шаг не тот или квест ещё не взят — подсказываем, а не молчим.
		EventBus.hint_shown.emit("Сейчас это не нужно.")
		return
	if disappear_after_use:
		queue_free()


func interaction_prompt() -> String:
	return prompt

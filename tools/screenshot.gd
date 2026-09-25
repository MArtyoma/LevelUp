extends Node

## Снимок экрана из запущенной игры, без рук.
##
##     godot --screenshot=shot.png --screenshot-frame=120 res://tools/screenshot.tscn
##
## Нужен для двух вещей из плана: письма заказчику со скриншотами (неделя 5)
## и отчёта на защите (неделя 10). Плюс им же удобно проверять, что билд вообще
## показывает картинку, на машине без монитора: `xvfb-run godot --screenshot=...`.
## С `--headless` снимок не получится — там нет видеокарты, и кадр пустой.

const MAIN_SCENE := preload("res://src/main.tscn")

var _output := "screenshot.png"
var _target_frame := 120
var _frame := 0
var _dialogue := ""


func _ready() -> void:
	for argument in OS.get_cmdline_args():
		if argument.begins_with("--screenshot="):
			_output = argument.trim_prefix("--screenshot=")
		elif argument.begins_with("--screenshot-frame="):
			_target_frame = int(argument.trim_prefix("--screenshot-frame="))
		elif argument.begins_with("--screenshot-dialogue="):
			_dialogue = argument.trim_prefix("--screenshot-dialogue=")
	add_child(MAIN_SCENE.instantiate())
	if not _dialogue.is_empty():
		DialogueRunner.start(_dialogue)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame < _target_frame:
		return
	# Ждём конца кадра: до этого момента в буфере может лежать ещё не дорисованный кадр.
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(_output)
	print("Снимок сохранён: %s" % ProjectSettings.globalize_path(_output))
	get_tree().quit(0)

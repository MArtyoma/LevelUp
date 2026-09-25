extends SceneTree

## Записывает раскладку управления в project.godot.
##
##     godot --headless --script tools/setup_input_map.gd
##
## Зачем скриптом, а не руками в редакторе: секция [input] в project.godot —
## это сериализованные объекты, руками их писать нельзя, а «настроил у себя
## в редакторе» кончается конфликтом в файле, который правят все. Раскладка
## задаётся здесь, в читаемом виде, и одинакова у всех после одного запуска.

func _initialize() -> void:
	var actions := {
		"move_up":       [KEY_W, KEY_UP],
		"move_down":     [KEY_S, KEY_DOWN],
		"move_left":     [KEY_A, KEY_LEFT],
		"move_right":    [KEY_D, KEY_RIGHT],
		"interact":      [KEY_E, KEY_SPACE, KEY_ENTER],
		"toggle_quests": [KEY_J, KEY_TAB],
	}

	for action_name: String in actions:
		var events: Array = []
		for keycode: int in actions[action_name]:
			var event := InputEventKey.new()
			# physical_keycode — клавиша по месту на клавиатуре. Иначе WASD
			# перестаёт работать при русской раскладке, и это ловят на демо.
			event.physical_keycode = keycode
			events.append(event)
		ProjectSettings.set_setting("input/" + action_name, {
			"deadzone": 0.2,
			"events": events,
		})

	var error := ProjectSettings.save()
	if error != OK:
		push_error("Не удалось сохранить project.godot: %d" % error)
		quit(1)
		return
	print("Управление записано: %s" % ", ".join(actions.keys()))
	quit(0)

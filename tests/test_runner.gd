extends Node

## Запуск всех тестов без редактора.
##
##     godot --headless res://tests/test_runner.tscn
##
## Код возврата 0 — всё зелёное, 1 — что-то сломано. По нему GitHub Actions
## ставит крестик в pull request (`.github/workflows/ci.yml`).
##
## Почему сцена, а не `--script`: тестам нужны автозагрузки (GameData, QuestLog,
## DialogueRunner), а они появляются только когда игра действительно запущена.

const SUITES := [
	preload("res://tests/test_data_validator.gd"),
	preload("res://tests/test_quest_log.gd"),
	preload("res://tests/test_dialogue_runner.gd"),
	preload("res://tests/test_dialogue_box.gd"),
	preload("res://tests/test_game_ui.gd"),
	preload("res://tests/test_sound.gd"),
	preload("res://tests/test_save_game.gd"),
	preload("res://tests/test_grid.gd"),
	preload("res://tests/test_level_scene.gd"),
]


func _ready() -> void:
	var passed := 0
	var failed := 0
	var started := Time.get_ticks_msec()

	print("\n=== Тесты LevelUp ===\n")
	for suite_script: GDScript in SUITES:
		var suite_name: String = suite_script.resource_path.get_file()
		print("— %s" % suite_name)

		for method: Dictionary in suite_script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue

			# Свежий экземпляр на каждый тест: общее состояние между тестами —
			# самый частый источник «у меня проходит, в CI падает».
			var suite: TestCase = suite_script.new()
			suite.before_each()
			suite.call(method_name)
			suite.after_each()

			if suite.failures.is_empty():
				passed += 1
				print("   ✓ %s" % method_name)
			else:
				failed += 1
				print("   ✗ %s" % method_name)
				for failure in suite.failures:
					print("       %s" % failure)

	var elapsed := Time.get_ticks_msec() - started
	print("\nПройдено: %d, провалено: %d, за %d мс\n" % [passed, failed, elapsed])
	get_tree().quit(0 if failed == 0 else 1)

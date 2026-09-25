extends TestCase

## Тесты сохранения.
##
## Сохранение — то место, которое ломается тихо и обнаруживается на защите.
## Поэтому проверяем не словари в памяти, а настоящий файл на диске: именно
## его будет открывать билд на чужом компьютере.

func before_each() -> void:
	QuestLog.reset()
	SaveGame.clear()


func after_each() -> void:
	SaveGame.clear()
	QuestLog.reset()


func test_save_and_load_through_a_real_file() -> void:
	QuestLog.start_quest("q_onboarding")
	QuestLog.complete_objective("q_onboarding", "obj_docs")
	QuestLog.set_flag("onboarding_taken")
	QuestLog.grant_access(3)

	check(SaveGame.save(Vector2(120.5, -40.0), "res://src/levels/office_demo.tscn"),
		"файл сохранения не записался")
	check(SaveGame.has_save(), "файл сохранения не появился на диске")

	QuestLog.reset()
	var payload := SaveGame.load_save()
	check(not payload.is_empty(), "сохранение не прочиталось")
	equals(SaveGame.player_position_from(payload), Vector2(120.5, -40.0), "позиция игрока")
	equals(payload.get("level", ""), "res://src/levels/office_demo.tscn", "имя уровня")
	check(QuestLog.is_active("q_onboarding"), "квест не восстановился")
	equals(QuestLog.next_objective_id("q_onboarding"), "obj_laptop", "шаг не восстановился")
	check(QuestLog.has_flag("onboarding_taken"), "отметка не восстановилась")
	equals(QuestLog.access_level, 3, "пропуск не восстановился")


func test_missing_save_is_not_an_error() -> void:
	equals(SaveGame.load_save(), {}, "отсутствие сохранения должно давать пустой словарь")


func test_broken_file_does_not_crash() -> void:
	# Файл поправили блокнотом и сломали. Игра обязана начаться сначала,
	# а не упасть: билд на защите запускают один раз.
	var file := FileAccess.open(SaveGame.SAVE_PATH, FileAccess.WRITE)
	file.store_string("{ это не json ")
	file.close()
	equals(SaveGame.load_save(), {}, "повреждённое сохранение должно игнорироваться")


func test_save_from_another_version_is_ignored() -> void:
	var file := FileAccess.open(SaveGame.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 999, "quests": {}}))
	file.close()
	equals(SaveGame.load_save(), {}, "сохранение чужой версии должно игнорироваться")


func test_garbage_inside_save_is_survived() -> void:
	# Версия верная, но внутри мусор вместо словарей.
	var file := FileAccess.open(SaveGame.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"version": SaveGame.SAVE_VERSION,
		"quests": {"access_level": "две штуки", "state": 17, "flags": [1, 2, 3]},
	}))
	file.close()

	SaveGame.load_save()
	equals(QuestLog.access_level, QuestLog.STARTING_ACCESS_LEVEL,
		"мусор в поле пропуска должен откатываться к начальному уровню")
	equals(QuestLog.active_quests().size(), 0, "мусор не должен превращаться в квесты")

extends Node

## Сохранение и загрузка прохождения.
##
## Владелец: лид. Это тонкая обёртка над QuestLog, и держать её надо рядом с ним:
## поменялось состояние прохождения — поменялся формат файла.
##
## **Игра не загружает сохранение сама, и это сознательно.** На замере гипотезы
## (неделя 9) каждый участник обязан начать с нуля: если второй участник за тем же
## ноутбуком продолжит прохождение первого, его результат в таблице будет ни о чём.
## Поэтому загрузка — только явным действием из меню, которого в v1 пока нет.
##
## Формат — обычный JSON в `user://save.json`. Никаких бинарных ресурсов Godot:
## бинарное сохранение ломается при смене версии движка, а игру на защите запускают
## один раз и без права на «странно, у меня работало». Текстовый файл к тому же
## можно открыть блокнотом и посмотреть, что не так.
##
## Состояние собирается из одного места (QuestLog) плюс позиция игрока. Если появится
## что-то ещё — добавляйте сюда, а не заводите второй файл сохранения.

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save(player_position: Vector2, level_path: String) -> bool:
	var payload := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"level": level_path,
		"player": {"x": player_position.x, "y": player_position.y},
		"quests": QuestLog.to_dict(),
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Не удалось открыть %s на запись" % SAVE_PATH)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


## Читает сохранение. Возвращает пустой словарь, если файла нет или он от другой
## версии формата — тогда игра просто начинается сначала. Ломаться на этом нельзя.
func load_save() -> Dictionary:
	if not has_save():
		return {}

	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(SAVE_PATH)) != OK:
		push_warning("Сохранение повреждено, начинаем заново")
		return {}

	var payload = parser.data
	if typeof(payload) != TYPE_DICTIONARY or int(payload.get("version", 0)) != SAVE_VERSION:
		push_warning("Сохранение от другой версии игры, начинаем заново")
		return {}

	var quests = payload.get("quests", {})
	QuestLog.from_dict(quests if typeof(quests) == TYPE_DICTIONARY else {})
	return payload


func player_position_from(payload: Dictionary) -> Vector2:
	# Без типа нарочно: типизированная переменная упала бы на чужом файле
	# раньше проверки (docs/conventions.md, «Грабли»).
	var player = payload.get("player", {})
	if typeof(player) != TYPE_DICTIONARY:
		return Vector2.ZERO
	return Vector2(float(player.get("x", 0.0)), float(player.get("y", 0.0)))


func clear() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	QuestLog.reset()

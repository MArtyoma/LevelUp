extends Node

## Запись прохождения: что игрок делал и сколько это заняло.
##
## Владелец: lead. Читает данные — researcher (замер гипотезы, неделя 9).
##
## **Зачем это в игре, если гипотезу проверяет тест на бумаге.** Тест показывает
## результат, но не показывает *почему*. Если группа B проиграла, объяснение
## «игра не работает» и объяснение «половина участников не нашла третий отдел
## и до половины контента не дошла» — это разные выводы и разные оценки за работу.
## Второе видно только из записи прохождения. Стоит это один файл и один час;
## не сделать это — значит на защите отвечать «мы не знаем» на первый же вопрос.
##
## **Про персональные данные.** Пишем код участника («B07»), а не имя, и ничего
## больше. Соответствие «код — человек» живёт на бумаге у researcher и в репозиторий
## не попадает — та же логика, что в D-003. Файлы пишутся в папку пользователя
## (`user://sessions`, путь печатается при сохранении), то есть вне репозитория.
##
## Запуск на замере (у собранной игры — так же, ключом к её exe):
##     godot --participant=B07
## Без ключа запись всё равно ведётся (под кодом "dev") — так мы замечаем, что
## телеметрия сломалась, на своих прогонах, а не на эксперименте.

const SESSIONS_DIR := "user://sessions"

var participant: String = "dev"
var session_id: String = ""

var _events: Array = []
var _started_at_ms: int = 0
var _is_recording: bool = false


func _ready() -> void:
	participant = _participant_from_cmdline()
	_connect_to_bus()
	if _should_record():
		start_session()


## Запись ведём, когда игру действительно играют: есть окно, либо код участника
## задан явно. Иначе каждый прогон `--script` и каждая сборка в CI оставляли бы
## файл «прохождения», и к неделе 9 в папке замера лежал бы мусор вперемешку
## с данными эксперимента.
func _should_record() -> bool:
	if participant != "dev":
		return true
	return DisplayServer.get_name() != "headless"


## Начать запись. Вызывается на старте и заново — при перезапуске прохождения.
func start_session() -> void:
	_events.clear()
	_started_at_ms = Time.get_ticks_msec()
	session_id = "%s_%s" % [participant, Time.get_datetime_string_from_system(false, false)
		.replace(":", "-").replace("T", "_")]
	_is_recording = true
	record("session_start", {"data_dir": GameData.data_dir})


## Записать событие. `payload` — любые подробности, которые пригодятся при разборе.
func record(event: String, payload: Dictionary = {}) -> void:
	if not _is_recording:
		return
	_events.append({
		"t_ms": Time.get_ticks_msec() - _started_at_ms,
		"event": event,
		"data": payload,
	})


## Закрыть запись и сохранить файл. Возвращает путь или пустую строку.
func finish_session(reason: String = "quit") -> String:
	if not _is_recording:
		return ""
	record("session_end", {"reason": reason})
	_is_recording = false

	DirAccess.make_dir_recursive_absolute(SESSIONS_DIR)
	var path := SESSIONS_DIR.path_join(session_id + ".json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Не удалось записать телеметрию в %s" % path)
		return ""

	file.store_string(JSON.stringify(_session_as_dict(), "\t"))
	file.close()
	print("Запись прохождения сохранена: %s" % ProjectSettings.globalize_path(path))
	return path


## Сводка одной строкой — то, что попадёт в таблицу researcher.
## Считается здесь, а не в Excel, чтобы у всех участников она считалась одинаково.
func summary() -> Dictionary:
	var quests_started := 0
	var quests_completed := 0
	var dialogues := 0
	var denied := 0
	var rooms: Dictionary = {}
	for event: Dictionary in _events:
		match String(event["event"]):
			"quest_started": quests_started += 1
			"quest_completed": quests_completed += 1
			"dialogue_finished": dialogues += 1
			"access_denied": denied += 1
			"room_entered": rooms[event["data"].get("room_id", "")] = true

	return {
		"participant": participant,
		"session_id": session_id,
		"duration_sec": float(_duration_ms()) / 1000.0,
		"quests_started": quests_started,
		"quests_completed": quests_completed,
		"dialogues_finished": dialogues,
		"rooms_visited": rooms.size(),
		"access_denied_times": denied,
		"events_total": _events.size(),
	}


func _duration_ms() -> int:
	if _events.is_empty():
		return 0
	return int(_events[-1]["t_ms"])


func _session_as_dict() -> Dictionary:
	return {
		"version": 1,
		"participant": participant,
		"session_id": session_id,
		"summary": summary(),
		"events": _events,
	}


## Подписка на шину — единственная связь телеметрии с остальной игрой.
## Ни квесты, ни диалоги не знают, что их пишут, и не должны знать: иначе
## «добавить запись нового события» означало бы править чужой код.
func _connect_to_bus() -> void:
	EventBus.quest_started.connect(func(quest_id: String):
		record("quest_started", {"quest_id": quest_id}))
	EventBus.quest_objective_completed.connect(func(quest_id: String, objective_id: String):
		record("objective_completed", {"quest_id": quest_id, "objective_id": objective_id}))
	EventBus.quest_completed.connect(func(quest_id: String):
		record("quest_completed", {"quest_id": quest_id}))
	EventBus.dialogue_started.connect(func(dialogue_id: String, speaker: Dictionary):
		record("dialogue_started", {"dialogue_id": dialogue_id, "speaker": speaker.get("id", "")}))
	EventBus.dialogue_finished.connect(func(dialogue_id: String, outcome: String):
		record("dialogue_finished", {"dialogue_id": dialogue_id, "outcome": outcome}))
	EventBus.access_denied.connect(func(required: int, current: int):
		record("access_denied", {"required": required, "current": current}))
	EventBus.access_level_changed.connect(func(level: int):
		record("access_granted", {"level": level}))
	EventBus.room_entered.connect(func(room_id: String):
		record("room_entered", {"room_id": room_id}))
	EventBus.game_finished.connect(func(reason: String):
		finish_session(reason))


func _participant_from_cmdline() -> String:
	for argument in OS.get_cmdline_args():
		if argument.begins_with("--participant="):
			return argument.trim_prefix("--participant=")
	return "dev"


func _notification(what: int) -> void:
	# Игрока закрыли крестиком — запись всё равно должна лечь на диск.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		finish_session("quit")

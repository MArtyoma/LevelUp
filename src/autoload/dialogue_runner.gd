extends Node

## Проигрывание разговоров: обычных и «дуэлей согласования» (D-002).
##
## Владелец: lead.
##
## Разговор — это граф реплик из `data/dialogues.json`. Код умеет ходить по графу,
## показывать варианты, считать время и применять последствия; *что именно говорят* —
## код не знает вообще. Поэтому writer добавляет новый диалог, не трогая ни строки
## кода, а новая механика внутри разговора добавляется как новый тип «действия»
## в `_apply_effect` — в одном месте.
##
## Интерфейс (зона artist) не вызывает ничего, кроме `advance()` и `choose()`,
## и рисует только то, что пришло сигналами EventBus. Значит, панель диалога можно
## переделать целиком, не открывая этот файл.
##
## Про производительность: `_process` включён **только** пока идёт дуэль с таймером.
## В остальное время узел ничего не делает каждый кадр. Это мелочь на одном диалоге
## и не мелочь, когда таких «мелочей» в проекте тридцать.

## Что сейчас происходит. Игрок не должен ходить во время разговора — движение
## смотрит на `is_running`.
var is_running: bool = false

var _dialogue: Dictionary = {}
var _node_id: String = ""
var _available_choices: Array = []      # варианты, прошедшие проверку условий
var _time_left: float = 0.0
var _patience_left: int = 0
var _is_duel: bool = false


func _ready() -> void:
	set_process(false)


## Запустить разговор. Возвращает false, если такого диалога нет —
## NPC в этом случае просто промолчит, а не уронит игру.
func start(dialogue_id: String) -> bool:
	if is_running:
		return false
	var dialogue := GameData.get_dialogue(dialogue_id)
	if dialogue.is_empty():
		push_warning("Диалога '%s' нет в data/dialogues.json" % dialogue_id)
		return false

	_dialogue = dialogue
	_is_duel = dialogue.get("kind", "") == "duel"
	_patience_left = int(dialogue.get("patience", 0))
	is_running = true

	var speaker := GameData.get_employee(dialogue.get("speaker", ""))
	EventBus.dialogue_started.emit(dialogue_id, speaker)
	if _is_duel:
		EventBus.duel_patience_changed.emit(_patience_left, _patience_left)

	_goto(dialogue.get("start", ""))
	return true


## Игрок нажал «дальше» на реплике без вариантов ответа.
func advance() -> void:
	if not is_running or not _available_choices.is_empty():
		return
	_goto(_current_node().get("next", "end"))


## Игрок выбрал вариант ответа. `index` — тот, что пришёл в `dialogue_choices_offered`.
func choose(index: int) -> void:
	if not is_running:
		return
	var choice := _find_choice(index)
	if choice.is_empty():
		return

	_stop_timer()

	if _is_duel and not bool(choice.get("correct", false)):
		_on_duel_miss(choice)
		return

	for effect: Dictionary in choice.get("effects", []):
		_apply_effect(effect)
	_goto(choice.get("next", "end"))


## Прервать разговор снаружи — например, при выходе в меню.
func stop(outcome: String = "aborted") -> void:
	if not is_running:
		return
	_finish(outcome)


# --- Ход по графу -------------------------------------------------------------

func _goto(node_id: String) -> void:
	if node_id == "end" or node_id.is_empty():
		_finish("duel_won" if _is_duel else "ok")
		return

	var nodes: Dictionary = _dialogue.get("nodes", {})
	if not nodes.has(node_id):
		# Валидатор такое ловит до запуска; сюда попадаем только если данные
		# подменили на ходу. Молча закрываем разговор, а не роняем игру на демо.
		push_error("В диалоге '%s' нет реплики '%s'" % [_dialogue.get("id", "?"), node_id])
		_finish("ok")
		return

	var is_repeat := node_id == _node_id
	_node_id = node_id
	var node: Dictionary = nodes[node_id]

	# Последствия реплики применяются один раз. Дуэль после промаха возвращается
	# на ту же реплику (`on_wrong`), и без этой проверки квест выдавался бы
	# заново на каждом круге. Сейчас действия идемпотентны и вреда бы не было,
	# но первое же действие вида «минус единица репутации» сломало бы дуэль.
	if not is_repeat:
		for effect: Dictionary in node.get("effects", []):
			_apply_effect(effect)

	var speaker_name: String = GameData.get_employee(_dialogue.get("speaker", "")).get("name", "")
	EventBus.dialogue_line_shown.emit(String(node.get("text", "")), speaker_name)

	_available_choices = _visible_choices(node)
	if _available_choices.is_empty():
		return

	var limit := float(_dialogue.get("time_limit", 0.0)) if _is_duel else 0.0
	EventBus.dialogue_choices_offered.emit(_available_choices, limit)
	if limit > 0.0:
		_time_left = limit
		set_process(true)


## Варианты, которые игрок вправе увидеть сейчас. Скрытые условием варианты
## не показываются вовсе — не «серым», а отсутствуют: иначе игрок видит подсказку
## о том, чего ещё не знает, и это портит замер.
func _visible_choices(node: Dictionary) -> Array:
	var visible: Array = []
	var choices: Array = node.get("choices", [])
	for index in choices.size():
		var choice: Dictionary = choices[index]
		if QuestLog.check_requirement(choice.get("requires", {})):
			visible.append({"text": String(choice.get("text", "")), "index": index})
	return visible


func _find_choice(index: int) -> Dictionary:
	for available: Dictionary in _available_choices:
		if int(available["index"]) == index:
			return _current_node().get("choices", [])[index]
	return {}


func _current_node() -> Dictionary:
	return _dialogue.get("nodes", {}).get(_node_id, {})


# --- Дуэль --------------------------------------------------------------------

func _process(delta: float) -> void:
	_time_left -= delta
	if _time_left <= 0.0:
		_stop_timer()
		# Промолчал — то же самое, что ответил неверно. Так решено сознательно:
		# «защита задачи» проверяет в том числе готовность ответить сразу.
		_on_duel_miss({})


func _on_duel_miss(choice: Dictionary) -> void:
	_patience_left -= 1
	EventBus.duel_patience_changed.emit(_patience_left, int(_dialogue.get("patience", 0)))

	if _patience_left <= 0:
		_finish("duel_lost")
		return

	# Куда уводит промах: либо явный `next` у варианта, либо повтор того же вопроса.
	var next_node: String = String(choice.get("next", ""))
	if next_node.is_empty():
		next_node = String(_dialogue.get("on_wrong", _node_id))
	_goto(next_node)


func _stop_timer() -> void:
	_time_left = 0.0
	set_process(false)


# --- Последствия --------------------------------------------------------------

## Единственное место, где разговор влияет на мир. Новая механика в диалогах —
## это новая ветка здесь плюс строчка в `docs/data-format.md` плюс проверка
## в `DataValidator._check_effect`. Три файла, и ни одного нового «если» в игре.
func _apply_effect(effect: Dictionary) -> void:
	match String(effect.get("type", "")):
		"start_quest":
			QuestLog.start_quest(String(effect.get("quest", "")))
		"complete_objective":
			QuestLog.complete_objective(
				String(effect.get("quest", "")), String(effect.get("objective", "")))
		"grant_access":
			QuestLog.grant_access(int(effect.get("level", 0)))
		"set_flag":
			QuestLog.set_flag(String(effect.get("flag", "")), bool(effect.get("value", true)))
		"finish_game":
			EventBus.game_finished.emit("completed")
		_:
			push_error("Неизвестное действие в диалоге: %s" % effect)


func _finish(outcome: String) -> void:
	_stop_timer()
	var dialogue_id: String = String(_dialogue.get("id", ""))
	is_running = false
	_dialogue = {}
	_node_id = ""
	_available_choices.clear()
	EventBus.dialogue_finished.emit(dialogue_id, outcome)

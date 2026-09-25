extends Node

## Состояние прохождения: какие квесты взяты, какие шаги закрыты, какой пропуск у игрока.
##
## Владелец: лид.
##
## Здесь и только здесь живёт ответ на вопрос «где сейчас игрок по сюжету». Ни NPC,
## ни двери, ни интерфейс своего кусочка состояния не держат: они спрашивают QuestLog
## или слушают EventBus. Одно место состояния — это и сохранение в один словарь,
## и отсутствие расхождений вида «журнал говорит одно, дверь думает другое».
##
## Соглашение о порядке шагов: шаги квеста закрываются **в том порядке, в котором
## записаны в данных**. Попытка закрыть шаг раньше времени игнорируется. Это
## осознанное упрощение: графы зависимостей между шагами нам на v1 не нужны,
## а последовательность делает квест предсказуемым для того, кто пишет тексты.

enum State { NOT_STARTED, ACTIVE, COMPLETED }

## Стартовый уровень пропуска. Двери с `required_access` выше — закрыты.
const STARTING_ACCESS_LEVEL := 1

var access_level: int = STARTING_ACCESS_LEVEL

# quest_id -> State
var _state: Dictionary = {}
# quest_id -> { objective_id: true }
var _done_objectives: Dictionary = {}
# Произвольные отметки из диалогов: «представился охраннику», «взял пропуск».
var _flags: Dictionary = {}


func reset() -> void:
	_state.clear()
	_done_objectives.clear()
	_flags.clear()
	access_level = STARTING_ACCESS_LEVEL


# --- Квесты ------------------------------------------------------------------

func state_of(quest_id: String) -> State:
	return _state.get(quest_id, State.NOT_STARTED)

func is_active(quest_id: String) -> bool:
	return state_of(quest_id) == State.ACTIVE

func is_completed(quest_id: String) -> bool:
	return state_of(quest_id) == State.COMPLETED


func active_quests() -> Array[String]:
	var result: Array[String] = []
	for quest_id: String in _state:
		if _state[quest_id] == State.ACTIVE:
			result.append(quest_id)
	return result


## Выдать квест. Повторная выдача молча игнорируется — так NPC может предлагать
## квест сколько угодно раз, и его не надо учить помнить, давал он его уже или нет.
func start_quest(quest_id: String) -> bool:
	if GameData.get_quest(quest_id).is_empty():
		push_error("Нет квеста с id '%s' — проверьте data/quests.json" % quest_id)
		return false
	if state_of(quest_id) != State.NOT_STARTED:
		return false

	_state[quest_id] = State.ACTIVE
	_done_objectives[quest_id] = {}
	EventBus.quest_started.emit(quest_id)
	return true


## Закрыть шаг квеста. Возвращает true, если шаг действительно закрылся сейчас.
func complete_objective(quest_id: String, objective_id: String) -> bool:
	if not is_active(quest_id):
		return false
	var expected := next_objective_id(quest_id)
	if expected != objective_id:
		# Не ошибка: так бывает, когда игрок говорит с NPC второй раз.
		return false

	_done_objectives[quest_id][objective_id] = true
	EventBus.quest_objective_completed.emit(quest_id, objective_id)

	if next_objective_id(quest_id).is_empty():
		_finish_quest(quest_id)
	return true


## Какой шаг игрок должен сделать сейчас. Пустая строка — все шаги закрыты.
func next_objective_id(quest_id: String) -> String:
	var done: Dictionary = _done_objectives.get(quest_id, {})
	for objective: Dictionary in GameData.get_quest(quest_id).get("objectives", []):
		var oid: String = objective.get("id", "")
		if not done.has(oid):
			return oid
	return ""


## Стоит ли игрок сейчас на этом шаге: квест взят, и шаг — следующий по порядку.
## В данных записывается как "q_onboarding/obj_laptop" (условие `step`).
##
## Нужно вариантам ответа, которые закрывают шаг. Без такого условия NPC «выдаёт
## ноутбук» игроку, который ещё не забрал документы: реплика прозвучала, а шаг
## не засчитался, потому что до него по порядку не дошли, — и игрок не понимает,
## почему журнал стоит на месте.
func is_current_step(step: String) -> bool:
	var parts := step.split("/")
	if parts.size() != 2:
		return false
	return is_active(parts[0]) and next_objective_id(parts[0]) == parts[1]


## Текст текущего шага — для журнала квестов и подсказки на экране.
func next_objective_text(quest_id: String) -> String:
	var oid := next_objective_id(quest_id)
	for objective: Dictionary in GameData.get_quest(quest_id).get("objectives", []):
		if objective.get("id", "") == oid:
			return objective.get("text", "")
	return ""


func _finish_quest(quest_id: String) -> void:
	_state[quest_id] = State.COMPLETED
	var reward: Dictionary = GameData.get_quest(quest_id).get("reward", {})
	if reward.has("access_level"):
		grant_access(int(reward["access_level"]))
	EventBus.quest_completed.emit(quest_id)


# --- Пропуск -----------------------------------------------------------------

## Уровень пропуска только растёт: отобрать доступ обратно v1 не умеет и не должна.
func grant_access(level: int) -> void:
	if level <= access_level:
		return
	access_level = level
	EventBus.access_level_changed.emit(access_level)


func has_access(required_level: int) -> bool:
	return access_level >= required_level


# --- Отметки -----------------------------------------------------------------

func set_flag(flag: String, value: bool = true) -> void:
	_flags[flag] = value

func has_flag(flag: String) -> bool:
	return bool(_flags.get(flag, false))


## Проверка условия из данных: показывать ли вариант ответа, открыта ли ветка диалога.
## Условие — словарь, все указанные ключи должны выполняться одновременно.
## Поддерживается: `flag`, `not_flag`, `quest_active`, `quest_done`, `step`, `access`.
## Новое условие добавляется сюда, в `DataValidator.KNOWN_REQUIREMENTS`
## и в `docs/data-format.md` — все три места сразу.
func check_requirement(requirement: Dictionary) -> bool:
	if requirement.is_empty():
		return true
	if requirement.has("flag") and not has_flag(requirement["flag"]):
		return false
	if requirement.has("not_flag") and has_flag(requirement["not_flag"]):
		return false
	if requirement.has("quest_active") and not is_active(requirement["quest_active"]):
		return false
	if requirement.has("quest_done") and not is_completed(requirement["quest_done"]):
		return false
	if requirement.has("step") and not is_current_step(String(requirement["step"])):
		return false
	if requirement.has("access") and not has_access(int(requirement["access"])):
		return false
	return true


# --- Сохранение --------------------------------------------------------------
# Состояние целиком — обычный словарь. SaveGame просто пишет его в файл и читает
# обратно; ничего «умного» с ним делать не надо, и это тоже решение: чем проще
# формат сохранения, тем меньше шансов, что билд на защите не откроет свой же файл.

func to_dict() -> Dictionary:
	return {
		"access_level": access_level,
		"state": _state.duplicate(true),
		"done_objectives": _done_objectives.duplicate(true),
		"flags": _flags.duplicate(true),
	}


## Восстановление из словаря. Ко всему относимся как к чужому файлу: его могли
## поправить руками, он мог остаться от прошлой версии игры. Испорченное поле
## пропускаем, а не роняем игру — билд на защите запускают один раз.
func from_dict(data: Dictionary) -> void:
	reset()
	var saved_access = data.get("access_level", STARTING_ACCESS_LEVEL)
	if typeof(saved_access) in [TYPE_INT, TYPE_FLOAT]:
		access_level = maxi(STARTING_ACCESS_LEVEL, int(saved_access))

	# Переменные нарочно без типа. `var state: Dictionary = <число>` падает
	# на самом присваивании, то есть раньше любой нашей проверки, — а смысл
	# всей функции в том, чтобы пережить чужой испорченный файл.
	var state = data.get("state", {})
	if typeof(state) == TYPE_DICTIONARY:
		for quest_id in state:
			# Квест, которого больше нет в данных (файл от прошлой версии), пропускаем:
			# иначе журнал покажет пустую строку, а закрыть такой квест нечем.
			if typeof(state[quest_id]) not in [TYPE_INT, TYPE_FLOAT] \
					or GameData.get_quest(String(quest_id)).is_empty():
				continue
			_state[String(quest_id)] = clampi(
				int(state[quest_id]), State.NOT_STARTED, State.COMPLETED)

	var done = data.get("done_objectives", {})
	if typeof(done) == TYPE_DICTIONARY:
		for quest_id: String in done:
			if typeof(done[quest_id]) == TYPE_DICTIONARY:
				_done_objectives[quest_id] = (done[quest_id] as Dictionary).duplicate()

	var flags = data.get("flags", {})
	if typeof(flags) == TYPE_DICTIONARY:
		_flags = flags.duplicate()

	# У взятого квеста обязана быть запись о шагах, даже если в файле её нет:
	# `complete_objective` пишет прямо в неё.
	for quest_id: String in _state:
		if not _done_objectives.has(quest_id):
			_done_objectives[quest_id] = {}

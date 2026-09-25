extends Node

## Загрузка и раздача всего игрового контента: компания, сотрудники, диалоги, квесты.
##
## Владелец: **artist**. Лид сделал каркас и контракт (список методов ниже);
## расширять — по этому контракту, чтобы не менять код, который уже им пользуется.
##
## Главное архитектурное решение проекта (D-003 в `docs/decisions.md`):
## **в коде нет ни одного имени, ни одной должности, ни одной реплики.** Всё
## лежит в `data/*.json`. Из этого следует то, ради чего это делалось:
##
##   * подменили папку данных — получили другую компанию, не тронув ни строки кода;
##   * реальные ФИО заказчика никогда не попадают в репозиторий
##     (`godot --data-dir=/путь/к/приватным/данным`);
##   * writer пишет легенду и тексты, не открывая редактор кода;
##   * данные проверяются скриптом в CI до того, как ломают игру.
##
## Скорость. Файлы читаются один раз при старте, дальше всё лежит в словарях,
## и любой поиск по id — это одно обращение, а не перебор массива. При 12 NPC
## разница неощутима; она важна потому, что диалог дёргает `get_employee()`
## на каждой реплике, и перебор массива в такой точке — классический способ
## получить просадку на ровном месте позже, когда сотрудников станет больше.

## Где лежат данные по умолчанию. Переопределяется ключом --data-dir.
const DEFAULT_DATA_DIR := "res://data"

## Файлы, которые обязаны быть в папке данных.
const REQUIRED_FILES := ["company.json", "dialogues.json", "quests.json"]

## Сработал ли запуск. Если false — играть нельзя, `load_error` объясняет почему.
var is_loaded: bool = false
var load_error: String = ""

## Откуда фактически загрузились. Показываем в углу экрана при запуске с чужими данными,
## чтобы на демо не спутать вымышленную компанию с реальной.
var data_dir: String = DEFAULT_DATA_DIR

var company_info: Dictionary = {}

# Индексы: id -> словарь. Строятся один раз в `_build_indices`.
var _departments: Dictionary = {}
var _employees: Dictionary = {}
var _topics: Dictionary = {}
var _dialogues: Dictionary = {}
var _quests: Dictionary = {}

# Производные списки, чтобы не пересобирать их на каждый запрос.
var _employees_by_department: Dictionary = {}
var _dialogue_by_speaker: Dictionary = {}


func _ready() -> void:
	data_dir = _data_dir_from_cmdline()
	var report := load_from(data_dir)
	if not report.is_ok():
		push_error("Данные не загружены:\n" + report.to_text())


## Загружает и проверяет данные из папки. Возвращает отчёт валидатора —
## тот же, что печатает CI. Публичный метод: им пользуются тесты и инструменты.
func load_from(dir_path: String) -> DataValidator.Report:
	var report := DataValidator.Report.new()
	is_loaded = false
	load_error = ""

	var company := _read_json(dir_path.path_join("company.json"), report)
	var dialogues := _read_json(dir_path.path_join("dialogues.json"), report)
	var quests := _read_json(dir_path.path_join("quests.json"), report)
	if not report.is_ok():
		load_error = report.to_text()
		return report

	var check := DataValidator.validate_all(company, dialogues, quests)
	report.errors.append_array(check.errors)
	report.warnings.append_array(check.warnings)
	if not report.is_ok():
		load_error = report.to_text()
		return report

	_build_indices(company, dialogues, quests)
	data_dir = dir_path
	is_loaded = true
	return report


# --- Чтение ------------------------------------------------------------------
# Всё ниже — только чтение. Данные во время игры не меняются: состояние прохождения
# живёт в QuestLog и SaveGame. Так один и тот же набор данных даёт одинаковый
# старт всем участникам эксперимента на неделе 9 — иначе замер нечем объяснять.

func get_employee(employee_id: String) -> Dictionary:
	return _employees.get(employee_id, {})

func get_department(department_id: String) -> Dictionary:
	return _departments.get(department_id, {})

func get_topic(topic_id: String) -> Dictionary:
	return _topics.get(topic_id, {})

func get_dialogue(dialogue_id: String) -> Dictionary:
	return _dialogues.get(dialogue_id, {})

func get_quest(quest_id: String) -> Dictionary:
	return _quests.get(quest_id, {})

func all_quests() -> Array:
	return _quests.values()

func all_topics() -> Array:
	return _topics.values()

func all_departments() -> Array:
	return _departments.values()


## Сотрудники отдела — готовый список, собранный при загрузке.
func employees_in_department(department_id: String) -> Array:
	return _employees_by_department.get(department_id, [])


## Имя и должность одной строкой: «Ирина Иванова, руководитель отдела продаж».
## Нужно подписи над NPC и шапке диалога — пусть формат живёт в одном месте.
func employee_caption(employee_id: String) -> String:
	var emp := get_employee(employee_id)
	if emp.is_empty():
		return "?"
	return "%s, %s" % [emp.get("name", "?"), emp.get("role", "?")]


## Диалог этого сотрудника. NPC на карте знает только свой `employee_id`
## (его ставит level designer в инспекторе) — какой именно диалог запустится, решается здесь.
func dialogue_for_speaker(employee_id: String) -> String:
	return _dialogue_by_speaker.get(employee_id, "")


# --- Внутреннее ---------------------------------------------------------------

func _read_json(path: String, report: DataValidator.Report) -> Dictionary:
	if not FileAccess.file_exists(path):
		report.add_error("файл %s не найден" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		report.add_error("файл %s пустой" % path)
		return {}

	var parser := JSON.new()
	if parser.parse(text) != OK:
		# Строка и текст ошибки — самое полезное, что можно дать человеку,
		# который правит JSON руками. Чаще всего это забытая запятая.
		report.add_error("%s, строка %d: %s (обычно это лишняя или забытая запятая)"
			% [path, parser.get_error_line(), parser.get_error_message()])
		return {}
	if typeof(parser.data) != TYPE_DICTIONARY:
		report.add_error("%s: на верхнем уровне должен быть объект { ... }" % path)
		return {}
	return parser.data


func _build_indices(company: Dictionary, dialogues: Dictionary, quests: Dictionary) -> void:
	company_info = company.get("company", {})
	_departments = _index(company.get("departments", []))
	_employees = _index(company.get("employees", []))
	_topics = _index(company.get("topics", []))
	_dialogues = _index(dialogues.get("dialogues", []))
	_quests = _index(quests.get("quests", []))

	_employees_by_department.clear()
	for employee: Dictionary in _employees.values():
		var dept: String = employee.get("department", "")
		if not _employees_by_department.has(dept):
			_employees_by_department[dept] = []
		_employees_by_department[dept].append(employee)

	_dialogue_by_speaker.clear()
	for dialogue: Dictionary in _dialogues.values():
		var speaker: String = dialogue.get("speaker", "")
		# Первый диалог сотрудника — основной. Ветвление «что он скажет сейчас»
		# делается внутри диалога условиями, а не десятком диалогов на человека.
		if speaker and not _dialogue_by_speaker.has(speaker):
			_dialogue_by_speaker[speaker] = dialogue.get("id", "")


func _index(list: Array) -> Dictionary:
	var result: Dictionary = {}
	for item in list:
		if typeof(item) == TYPE_DICTIONARY and item.get("id", ""):
			result[item["id"]] = item
	return result


## Поддержка `godot --data-dir=/path` — так игра запускается на реальных данных
## заказчика, которых нет и не будет в репозитории (D-003).
func _data_dir_from_cmdline() -> String:
	for argument in OS.get_cmdline_args():
		if argument.begins_with("--data-dir="):
			return argument.trim_prefix("--data-dir=")
	return DEFAULT_DATA_DIR

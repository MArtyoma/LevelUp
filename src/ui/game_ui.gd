extends CanvasLayer

## Постоянный интерфейс: подсказка у нижнего края, текущий шаг в углу, журнал квестов.
##
## На экране постоянно — только строка-другая текущего шага в левом верхнем углу,
## без подложки: игра про то, чтобы разглядывать офис и людей, и панель в углу
## закрывала бы как раз их. Полный журнал (задания, выполненное, пропуск) —
## по J или Tab, по центру.
##
## Владелец: **artist**.
##
## Как и окно диалога, знает про игру только через EventBus. Исключение одно:
## журнал спрашивает у QuestLog текст текущего шага — читать состояние можно,
## менять его из интерфейса нельзя.

@onready var _hint: Label = $Hint
@onready var _quest_panel: PanelContainer = $QuestPanel
@onready var _quest_list: VBoxContainer = $QuestPanel/Layout/List
@onready var _access_label: Label = $QuestPanel/Layout/Access
@onready var _footer: Label = $QuestPanel/Layout/Footer
@onready var _tracker: VBoxContainer = $Tracker
@onready var _room_banner: VBoxContainer = $RoomBanner
@onready var _room_title: Label = $RoomBanner/Title
@onready var _room_purpose: Label = $RoomBanner/Purpose

## Сколько секунд висит название отдела при первом входе в кабинет.
const ROOM_BANNER_SECONDS := 2.5

var _room_tween: Tween
var _tracker_tween: Tween


func _ready() -> void:
	_hint.text = ""
	_apply_ui_scale()
	EventBus.hint_shown.connect(_on_hint_shown)
	EventBus.hint_hidden.connect(_on_hint_hidden)
	EventBus.access_level_changed.connect(_on_access_changed)
	EventBus.access_denied.connect(_on_access_denied)
	EventBus.room_entered.connect(_on_room_entered)

	EventBus.quest_started.connect(_on_quest_changed.unbind(1))
	EventBus.quest_completed.connect(_on_quest_changed.unbind(1))
	EventBus.quest_objective_completed.connect(_on_quest_changed.unbind(2))

	_on_access_changed(QuestLog.access_level, false)
	_refresh_quests()


## Размеры в сценах интерфейса подобраны под окно высотой 272 пикселя (17 тайлов по 16).
## При другом размере тайла окно другое — и всё пересчитывается, иначе
## на тайле 32 подписи превращаются в муравьёв в углу экрана.
func _apply_ui_scale() -> void:
	var scale := Grid.ui_scale()
	if is_equal_approx(scale, 1.0):
		return

	var settings := _hint.label_settings
	if settings != null:
		settings = settings.duplicate() as LabelSettings
		settings.font_size = Grid.ui_font_size(8)
		settings.outline_size = Grid.ui_font_size(3)
		_hint.label_settings = settings
	_hint.offset_top = Grid.ui_length(-22.0)
	_hint.offset_bottom = Grid.ui_length(-8.0)

	_access_label.add_theme_font_size_override("font_size", Grid.ui_font_size(8))
	_footer.add_theme_font_size_override("font_size", Grid.ui_font_size(7))
	_quest_panel.offset_left = Grid.ui_length(-120.0)
	_quest_panel.offset_top = Grid.ui_length(-70.0)
	_quest_panel.offset_right = Grid.ui_length(120.0)
	_quest_panel.offset_bottom = Grid.ui_length(70.0)
	_tracker.offset_left = Grid.ui_length(6.0)
	_tracker.offset_top = Grid.ui_length(6.0)
	_tracker.offset_right = Grid.ui_length(186.0)
	_tracker.offset_bottom = Grid.ui_length(60.0)

	for label: Label in [_room_title, _room_purpose]:
		var room_settings := label.label_settings.duplicate() as LabelSettings
		room_settings.font_size = Grid.ui_font_size(room_settings.font_size)
		room_settings.outline_size = Grid.ui_font_size(room_settings.outline_size)
		label.label_settings = room_settings
	_room_banner.offset_left = Grid.ui_length(-110.0)
	_room_banner.offset_top = Grid.ui_length(10.0)
	_room_banner.offset_right = Grid.ui_length(110.0)
	_room_banner.offset_bottom = Grid.ui_length(44.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_quests"):
		_quest_panel.visible = not _quest_panel.visible
		# Открытый журнал и так показывает текущий шаг — строка в углу лишняя.
		_tracker.visible = not _quest_panel.visible
		Sound.play("journal")
		get_viewport().set_input_as_handled()


func _on_hint_shown(text: String) -> void:
	_hint.text = text


func _on_hint_hidden() -> void:
	_hint.text = ""


func _on_access_changed(level: int, announce: bool = true) -> void:
	_access_label.text = "Пропуск: уровень %d" % level
	# Уровень пропуска больше не висит на экране постоянно — о новом говорим вслух.
	if announce:
		_hint.text = "Новый пропуск: уровень %d" % level


func _on_access_denied(required: int, current: int) -> void:
	_hint.text = "Нужен пропуск %d, у тебя %d" % [required, current]


## Первый вход в кабинет: сверху на пару секунд — чей он и чем там занимаются.
## Это не украшение, а часть обучения: «где сидит бухгалтерия и за что она
## отвечает» — ровно то, что потом спросят в тесте на замере.
func _on_room_entered(room_id: String) -> void:
	var department := _department_in(room_id)
	if department.is_empty():
		return
	_room_title.text = String(department.get("name", ""))
	_room_purpose.text = String(department.get("purpose", ""))
	if _room_tween != null:
		_room_tween.kill()
	_room_banner.modulate.a = 0.0
	_room_banner.visible = true
	_room_tween = create_tween()
	_room_tween.tween_property(_room_banner, "modulate:a", 1.0, 0.3)
	_room_tween.tween_interval(ROOM_BANNER_SECONDS)
	_room_tween.tween_property(_room_banner, "modulate:a", 0.0, 0.6)
	_room_tween.tween_callback(_room_banner.hide)


func _department_in(room_id: String) -> Dictionary:
	for department: Dictionary in GameData.all_departments():
		if department.get("room", "") == room_id:
			return department
	return {}


func _on_quest_changed() -> void:
	_refresh_quests()
	# Строка в углу мигает жёлтым: шаг сменился — это видно краем глаза,
	# даже если игрок смотрит на собеседника.
	if _tracker_tween != null:
		_tracker_tween.kill()
	_tracker.modulate = Color(1.0, 0.8, 0.46)
	_tracker_tween = create_tween()
	_tracker_tween.tween_property(_tracker, "modulate", Color.WHITE, 1.2)


## Журнал и строка в углу перерисовываются целиком на каждое событие квеста. Это
## осознанно: квестов у нас 4-5, событий за прохождение — десятки, а не тысячи.
## Точечное обновление списка стоило бы вдвое больше кода и ловило бы рассинхрон.
func _refresh_quests() -> void:
	_refresh_tracker()
	_clear(_quest_list)

	var active := QuestLog.active_quests()
	if active.is_empty():
		_add_row(_quest_list, "Заданий пока нет — ищи «!» над головой", true)

	for quest_id in active:
		var quest := GameData.get_quest(quest_id)
		_add_row(_quest_list, String(quest.get("title", quest_id)), false)
		var step := QuestLog.next_objective_text(quest_id)
		if not step.is_empty():
			_add_row(_quest_list, "   • " + step, true)

	# Выполненное — тоже часть журнала: к концу дня это список того, что игрок
	# узнал, и по нему удобно освежить память.
	for quest: Dictionary in GameData.all_quests():
		if QuestLog.is_completed(String(quest.get("id", ""))):
			_add_row(_quest_list, "✓ " + String(quest.get("title", "")), true)


## Строка в углу: только текущие шаги, без названий заданий и без подложки.
func _refresh_tracker() -> void:
	_clear(_tracker)
	var steps: Array[String] = []
	for quest_id in QuestLog.active_quests():
		var step := QuestLog.next_objective_text(quest_id)
		if not step.is_empty():
			steps.append(step)
	if steps.is_empty():
		steps.append("Ищи «!» над головой")
	# Одна строка на шаг, длинное — с многоточием: целиком текст в журнале,
	# а здесь достаточно понять, куда идти (над целью и так висит «?»).
	for step in steps:
		var label := Label.new()
		label.text = "▸ " + step
		label.tooltip_text = step
		label.label_settings = _hint.label_settings
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_tracker.add_child(label)


func _add_row(list: VBoxContainer, text: String, is_secondary: bool) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", Grid.ui_font_size(8))
	if is_secondary:
		label.modulate = Color(0.75, 0.8, 0.86)
	list.add_child(label)


# Сначала вынуть, потом удалить: queue_free удаляет только в конце кадра, и до
# того старые строки стояли бы в списке рядом с новыми.
func _clear(list: Container) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()

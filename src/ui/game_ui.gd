extends CanvasLayer

## Постоянный интерфейс: подсказка у нижнего края, журнал квестов, уровень пропуска.
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
@onready var _room_banner: VBoxContainer = $RoomBanner
@onready var _room_title: Label = $RoomBanner/Title
@onready var _room_purpose: Label = $RoomBanner/Purpose

## Сколько секунд висит название отдела при первом входе в кабинет.
const ROOM_BANNER_SECONDS := 2.5

var _room_tween: Tween


func _ready() -> void:
	_hint.text = ""
	_apply_ui_scale()
	EventBus.hint_shown.connect(_on_hint_shown)
	EventBus.hint_hidden.connect(_on_hint_hidden)
	EventBus.access_level_changed.connect(_on_access_changed)
	EventBus.access_denied.connect(_on_access_denied)
	EventBus.room_entered.connect(_on_room_entered)

	for signal_name in ["quest_started", "quest_completed"]:
		EventBus.connect(signal_name, func(_quest_id: String): _refresh_quests())
	EventBus.quest_objective_completed.connect(
		func(_quest_id: String, _objective_id: String): _refresh_quests())

	_on_access_changed(QuestLog.access_level)
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
	_quest_panel.offset_left = Grid.ui_length(-132.0)
	_quest_panel.offset_top = Grid.ui_length(6.0)
	_quest_panel.offset_right = Grid.ui_length(-6.0)
	_quest_panel.offset_bottom = Grid.ui_length(70.0)

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
		Sound.play("journal")
		get_viewport().set_input_as_handled()


func _on_hint_shown(text: String) -> void:
	_hint.text = text


func _on_hint_hidden() -> void:
	_hint.text = ""


func _on_access_changed(level: int) -> void:
	_access_label.text = "Пропуск: уровень %d" % level


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


## Журнал перерисовывается целиком на каждое событие квеста. Это осознанно:
## квестов у нас 4-5, событий за прохождение — десятки, а не тысячи. Точечное
## обновление списка стоило бы вдвое больше кода и ловило бы рассинхрон.
func _refresh_quests() -> void:
	for child in _quest_list.get_children():
		child.queue_free()

	var active := QuestLog.active_quests()
	if active.is_empty():
		_add_row("Заданий пока нет", true)
		# Первое, что видит новичок, — пустой журнал. Пусть он хотя бы
		# говорит, куда смотреть.
		_add_row("   • ищи «!» над головой", true)
		return

	for quest_id in active:
		_add_row(String(GameData.get_quest(quest_id).get("title", quest_id)), false)
		var step := QuestLog.next_objective_text(quest_id)
		if not step.is_empty():
			_add_row("   • " + step, true)


func _add_row(text: String, is_secondary: bool) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", Grid.ui_font_size(8))
	if is_secondary:
		label.modulate = Color(0.75, 0.8, 0.86)
	_quest_list.add_child(label)

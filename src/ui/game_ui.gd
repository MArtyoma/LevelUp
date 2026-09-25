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


func _ready() -> void:
	_hint.text = ""
	_apply_ui_scale()
	EventBus.hint_shown.connect(_on_hint_shown)
	EventBus.hint_hidden.connect(_on_hint_hidden)
	EventBus.access_level_changed.connect(_on_access_changed)
	EventBus.access_denied.connect(_on_access_denied)

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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_quests"):
		_quest_panel.visible = not _quest_panel.visible
		get_viewport().set_input_as_handled()


func _on_hint_shown(text: String) -> void:
	_hint.text = text


func _on_hint_hidden() -> void:
	_hint.text = ""


func _on_access_changed(level: int) -> void:
	_access_label.text = "Пропуск: уровень %d" % level


func _on_access_denied(required: int, current: int) -> void:
	_hint.text = "Нужен пропуск %d, у тебя %d" % [required, current]


## Журнал перерисовывается целиком на каждое событие квеста. Это осознанно:
## квестов у нас 4-5, событий за прохождение — десятки, а не тысячи. Точечное
## обновление списка стоило бы вдвое больше кода и ловило бы рассинхрон.
func _refresh_quests() -> void:
	for child in _quest_list.get_children():
		child.queue_free()

	var active := QuestLog.active_quests()
	if active.is_empty():
		_add_row("Заданий пока нет", true)
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

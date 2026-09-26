extends CanvasLayer

## Окно разговора.
##
## Владелец: **artist**. Переделывать внешний вид можно целиком — контракт ниже
## менять нельзя без разговора с лидом.
##
## Контракт короткий и в этом весь смысл:
##   слушаем   EventBus.dialogue_started / dialogue_line_shown /
##             dialogue_choices_offered / duel_patience_changed / dialogue_finished
##   вызываем  DialogueRunner.advance() и DialogueRunner.choose(index)
##
## Ничего другого окно про игру не знает: ни про квесты, ни про сотрудников, ни про
## то, дуэль это или обычный разговор — про дуэль оно узнаёт по тому, что пришёл
## `time_limit` больше нуля. Поэтому окно можно переписать с нуля, не открывая
## ни одного файла лида.

@onready var _root: Control = $Root
@onready var _speaker_label: Label = $Root/Panel/Body/Layout/Header/Speaker
@onready var _patience_label: Label = $Root/Panel/Body/Layout/Header/Patience
@onready var _text_label: Label = $Root/Panel/Body/Layout/Text
@onready var _choices: VBoxContainer = $Root/Panel/Body/Layout/Choices
@onready var _timer_bar: ProgressBar = $Root/Panel/Body/Layout/TimerBar
@onready var _continue_hint: Label = $Root/Panel/Body/Layout/ContinueHint
@onready var _panel: PanelContainer = $Root/Panel
@onready var _portrait_frame: PanelContainer = $Root/Panel/Body/PortraitFrame
@onready var _portrait: TextureRect = $Root/Panel/Body/PortraitFrame/Portrait

## Скорость печати реплики, букв в секунду. 0 — реплика появляется сразу целиком.
## E во время печати дописывает реплику сразу: кто читает быстро, не ждёт.
@export var letters_per_second: float = 50.0

## Щелчок голоса собеседника — на каждой такой по счёту букве.
const LETTERS_PER_BLIP := 4

var _time_left: float = 0.0
var _time_total: float = 0.0
var _typing: bool = false
var _typed: float = 0.0
# Дуэль узнаём по первому сообщению о терпении — оно приходит до первой реплики.
var _in_duel: bool = false


func _ready() -> void:
	_root.visible = false
	set_process(false)
	_apply_ui_scale()

	EventBus.dialogue_started.connect(_on_started)
	EventBus.dialogue_line_shown.connect(_on_line)
	EventBus.dialogue_choices_offered.connect(_on_choices)
	EventBus.duel_patience_changed.connect(_on_patience)
	EventBus.dialogue_finished.connect(_on_finished)


## Сцена нарисована под окно высотой 272 пикселя; при другом размере тайла
## окно другое. Пересчитываем, чтобы окно диалога занимало ту же долю экрана.
func _apply_ui_scale() -> void:
	var scale := Grid.ui_scale()
	if is_equal_approx(scale, 1.0):
		return

	_panel.offset_left = Grid.ui_length(8.0)
	_panel.offset_top = Grid.ui_length(-74.0)
	_panel.offset_right = Grid.ui_length(-8.0)
	_panel.offset_bottom = Grid.ui_length(-8.0)

	var settings := _speaker_label.label_settings
	if settings != null:
		settings = settings.duplicate() as LabelSettings
		settings.font_size = Grid.ui_font_size(9)
		_speaker_label.label_settings = settings

	_patience_label.add_theme_font_size_override("font_size", Grid.ui_font_size(9))
	_text_label.add_theme_font_size_override("font_size", Grid.ui_font_size(8))
	_continue_hint.add_theme_font_size_override("font_size", Grid.ui_font_size(7))
	_timer_bar.custom_minimum_size = Vector2(0.0, Grid.ui_length(4.0))
	_portrait.custom_minimum_size = Vector2.ONE * Grid.ui_length(48.0)


func _on_started(_dialogue_id: String, speaker: Dictionary) -> void:
	_root.visible = true
	_in_duel = false
	_patience_label.text = ""
	_speaker_label.text = "%s — %s" % [
		speaker.get("name", "?"), speaker.get("role", "")]
	_show_portrait(speaker)


## Портрет собеседника (src/core/own_art.gd) на подложке его цвета из данных.
## Портрета нет — рамка прячется, и текст занимает всю ширину, как раньше.
func _show_portrait(speaker: Dictionary) -> void:
	var texture := OwnArt.portrait(String(speaker.get("id", "")))
	_portrait_frame.visible = texture != null
	if texture == null:
		return
	_portrait.texture = texture
	var style := _portrait_frame.get_theme_stylebox("panel") as StyleBoxFlat
	if style != null and speaker.has("palette"):
		style = style.duplicate() as StyleBoxFlat
		style.bg_color = Color(String(speaker["palette"]))
		_portrait_frame.add_theme_stylebox_override("panel", style)


func _on_line(text: String, _speaker_name: String) -> void:
	_text_label.text = text
	_clear_choices()
	_hide_timer()
	# В дуэли реплика появляется сразу: время на ответ уже идёт, и тратить его
	# на ожидание печати нечестно.
	_typing = letters_per_second > 0.0 and not _in_duel
	_typed = 0.0
	_text_label.visible_characters = 0 if _typing else -1
	_continue_hint.visible = not _typing
	_update_processing()


## Дописать реплику сразу и показать то, что ждало конца печати.
func _finish_typing() -> void:
	_typing = false
	_text_label.visible_characters = -1
	_choices.visible = true
	_continue_hint.visible = _choices.get_child_count() == 0
	_focus_first_choice()
	_update_processing()


func _on_choices(choices: Array, time_limit: float) -> void:
	_clear_choices()
	_continue_hint.visible = false

	for choice: Dictionary in choices:
		var button := Button.new()
		button.text = String(choice["text"])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# Размер шрифта задаётся в пикселях низкого разрешения: окно игры — 480×272,
		# и всё, что больше 8-9, занимает пол-экрана. Когда artist поставит
		# пиксельный шрифт темой, эту строку можно убрать.
		button.add_theme_font_size_override("font_size", Grid.ui_font_size(8))
		var index := int(choice["index"])
		button.pressed.connect(func():
			Sound.play("ui_confirm")
			DialogueRunner.choose(index))
		_choices.add_child(button)

	# Пока реплика печатается, вариантов не видно: иначе их читают вместо реплики.
	_choices.visible = not _typing
	if not _typing:
		_focus_first_choice()

	if time_limit > 0.0:
		_start_timer(time_limit)
	else:
		_hide_timer()


func _focus_first_choice() -> void:
	if _choices.get_child_count() == 0:
		return
	_choices.get_child(0).grab_focus()
	# Щелчок при переходе между вариантами — только после первого фокуса:
	# сам факт появления вариантов не должен щёлкать поверх голоса собеседника.
	for button in _choices.get_children():
		var click := Sound.play.bind("ui_select")
		if not (button as Button).focus_entered.is_connected(click):
			(button as Button).focus_entered.connect(click)


## E на вариантах ответа выбирает выделенный. Enter и пробел кнопка ловит сама
## (они же ui_accept), а E — нет: без этого игрок, которому сказано «E — говорить»,
## жмёт E на вариантах, и ничего не происходит. Сюда нажатие приходит раньше,
## чем к игроку: окно ниже в дереве main.tscn.
func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if _typing and (event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")):
		get_viewport().set_input_as_handled()
		_finish_typing()
		return
	if _choices.get_child_count() == 0 or not event.is_action_pressed("interact"):
		return
	get_viewport().set_input_as_handled()
	var focused := get_viewport().gui_get_focus_owner() as Button
	if focused != null and focused.get_parent() == _choices:
		focused.pressed.emit()
	else:
		(_choices.get_child(0) as Button).grab_focus()


func _on_patience(left: int, total: int) -> void:
	_in_duel = true
	# Терпение руководителя — кружки, а не число: читается мгновенно (D-002).
	_patience_label.text = "  " + "●".repeat(maxi(left, 0)) + "○".repeat(maxi(total - left, 0))


func _on_finished(_dialogue_id: String, outcome: String) -> void:
	_root.visible = false
	_typing = false
	_clear_choices()
	_hide_timer()
	if outcome == "duel_lost":
		EventBus.hint_shown.emit("Разговор не сложился. Попробуй зайти ещё раз.")


# --- Полоска времени в дуэли --------------------------------------------------
# Отсчёт здесь только рисуется. Решение «не успел» принимает DialogueRunner:
# два независимых таймера рано или поздно разойдутся, и виноват будет тот,
# который видно.

func _start_timer(limit: float) -> void:
	_time_total = limit
	_time_left = limit
	_timer_bar.max_value = limit
	_timer_bar.value = limit
	_timer_bar.visible = true
	_update_processing()


func _hide_timer() -> void:
	_timer_bar.visible = false
	_update_processing()


# Каждый кадр окно работает только пока печатает реплику или идёт время дуэли.
func _update_processing() -> void:
	set_process(_typing or (_timer_bar.visible and _time_left > 0.0))


func _process(delta: float) -> void:
	if _typing:
		_type(delta)
	if _timer_bar.visible:
		_time_left = maxf(_time_left - delta, 0.0)
		_timer_bar.value = _time_left
	_update_processing()


func _type(delta: float) -> void:
	var before := int(_typed)
	_typed += delta * letters_per_second
	var shown := int(_typed)
	_text_label.visible_characters = shown
	if shown / LETTERS_PER_BLIP > before / LETTERS_PER_BLIP:
		Sound.talk()
	if shown >= _text_label.get_total_character_count():
		_finish_typing()


func _clear_choices() -> void:
	# Сначала вынуть из контейнера, потом удалить. queue_free удаляет только в конце
	# кадра, и до того старая кнопка оставалась первой в списке: новые варианты
	# отдавали фокус ей, она исчезала, и выбрать ответ с клавиатуры было нечем.
	for child in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()

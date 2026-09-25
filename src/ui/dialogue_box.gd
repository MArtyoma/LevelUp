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
@onready var _speaker_label: Label = $Root/Panel/Layout/Header/Speaker
@onready var _patience_label: Label = $Root/Panel/Layout/Header/Patience
@onready var _text_label: Label = $Root/Panel/Layout/Text
@onready var _choices: VBoxContainer = $Root/Panel/Layout/Choices
@onready var _timer_bar: ProgressBar = $Root/Panel/Layout/TimerBar
@onready var _continue_hint: Label = $Root/Panel/Layout/ContinueHint

var _time_left: float = 0.0
var _time_total: float = 0.0


func _ready() -> void:
	_root.visible = false
	set_process(false)

	EventBus.dialogue_started.connect(_on_started)
	EventBus.dialogue_line_shown.connect(_on_line)
	EventBus.dialogue_choices_offered.connect(_on_choices)
	EventBus.duel_patience_changed.connect(_on_patience)
	EventBus.dialogue_finished.connect(_on_finished)


func _on_started(_dialogue_id: String, speaker: Dictionary) -> void:
	_root.visible = true
	_patience_label.text = ""
	_speaker_label.text = "%s — %s" % [
		speaker.get("name", "?"), speaker.get("role", "")]


func _on_line(text: String, _speaker_name: String) -> void:
	_text_label.text = text
	_clear_choices()
	_continue_hint.visible = true
	_hide_timer()


func _on_choices(choices: Array, time_limit: float) -> void:
	_clear_choices()
	_continue_hint.visible = false

	for choice: Dictionary in choices:
		var button := Button.new()
		button.text = String(choice["text"])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# Размер шрифта задаётся в пикселях низкого разрешения: окно игры — 480x270,
		# и всё, что больше 8-9, занимает пол-экрана. Когда artist поставит
		# пиксельный шрифт темой, эту строку можно убрать.
		button.add_theme_font_size_override("font_size", 8)
		var index := int(choice["index"])
		button.pressed.connect(func(): DialogueRunner.choose(index))
		_choices.add_child(button)

	if _choices.get_child_count() > 0:
		_choices.get_child(0).grab_focus()

	if time_limit > 0.0:
		_start_timer(time_limit)
	else:
		_hide_timer()


func _on_patience(left: int, total: int) -> void:
	# Терпение руководителя — кружки, а не число: читается мгновенно (D-002).
	_patience_label.text = "  " + "●".repeat(maxi(left, 0)) + "○".repeat(maxi(total - left, 0))


func _on_finished(_dialogue_id: String, outcome: String) -> void:
	_root.visible = false
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
	set_process(true)


func _hide_timer() -> void:
	_timer_bar.visible = false
	set_process(false)


func _process(delta: float) -> void:
	_time_left = maxf(_time_left - delta, 0.0)
	_timer_bar.value = _time_left
	if _time_left <= 0.0:
		set_process(false)


func _clear_choices() -> void:
	for child in _choices.get_children():
		child.queue_free()

@tool
class_name Npc
extends Area2D

## Сотрудник компании на карте.
##
## Владелец кода: лид. Владелец расстановки на карте: **level designer**.
##
## Скрипт не знает ни одного имени. В инспекторе у сцены одно поле — `employee_id`;
## имя, должность, отдел, цвет и диалог подтягиваются из `data/company.json`
## (D-003). Поэтому:
##
##   * level designer ставит NPC на карту и вписывает id — кода ноль;
##   * writer переименовывает сотрудника в JSON — на карте меняется само;
##   * подмена папки данных превращает вымышленную компанию в компанию заказчика.
##
## Скрипт помечен `@tool` ради одной вещи: если id написан с опечаткой, Godot
## покажет жёлтый треугольник прямо в дереве сцены, с текстом по-русски. Поймать
## опечатку в редакторе стоит секунду, а на плейтесте — вечер.

## id сотрудника из data/company.json, например "emp_ivanova".
@export var employee_id: String = "":
	set(value):
		employee_id = value
		update_configuration_warnings()
		# Значения из сцены присваиваются ДО _ready, когда дочерних узлов ещё нет.
		# Поэтому здесь перерисовываем, только если узел уже готов; при загрузке
		# сцены это делает сам _ready.
		if is_node_ready() and not Engine.is_editor_hint():
			_refresh()

## Разрешить подпись с именем над головой. Сама подпись появляется, только когда
## игрок подошёл: имена над всеми двенадцатью сотрудниками сразу превращают экран
## в кашу, а разобрать, кто есть кто, игра должна помогать, а не мешать.
@export var show_caption: bool = true

## Сидит за рабочим местом — оно в клетке прямо под ним (тайлы (1..3, 3) атласа).
## Спрайт опускается, стол закрывает ноги; заговорить можно через стол; вместо
## «дыхания» — печатает. Ставит галочку тот, кто сажает сотрудника за стол, — level designer.
@export var at_desk: bool = false

@onready var _sprite: Sprite2D = $Sprite2D
# У подписи z_index = 1 (в сцене): NPC сортируется по Y, и подпись над головой
# сортировалась бы по своей Y — как предмет на 2 тайла выше. Её закрывали бы
# стены, мебель и подошедший снизу игрок.
@onready var _caption: Label = $Caption
@onready var _reach_shape: CollisionShape2D = $CollisionShape2D
@onready var _blocker_shape: CollisionShape2D = $Blocker/CollisionShape2D

var _employee: Dictionary = {}
var _marker: QuestMarker
var _attentive: bool = false
var _typing_left: int = 0
var _seated: bool = false
var _shadow: GroundShadow

## Занят делом (телефон, отошёл к шкафу — src/actors/npc/npc_routine.gd): не печатает.
var busy: bool = false

## «Дыхание»: раз в столько секунд — следующий кадр первого ряда листа
## (tools/art/make_sheet.py --idle: вдох — один кадр из четырёх).
const IDLE_STEP_SECONDS := 0.45

## Печать за столом: кадры 0 и 1 первого ряда (плечи на пиксель ниже) через
## столько секунд, очередями по TYPING_BURST ударов с паузами — иначе это
## не печать, а дрожь.
const TYPING_STEP_SECONDS := 0.12
const TYPING_BURST := Vector2i(6, 18)
const TYPING_PAUSE := Vector2i(8, 25)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_seated = at_desk
	_apply_grid()
	_shadow = GroundShadow.attach(self)
	add_to_group("interactable")
	# NPC ничего не делает каждый кадр: он реагирует только на то, что к нему подошли.
	# Двенадцать спящих узлов вместо двенадцати работающих — мелочь, которая
	# на слабом ноутбуке в аудитории складывается с двумя десятками таких же мелочей.
	set_process(false)
	set_physics_process(false)
	_refresh()
	_add_marker()
	_apply_seat()
	_add_routine()


## Подгоняет размеры под текущий размер тайла (см. `src/core/grid.gd`).
##
## Формы создаются новыми для каждого NPC. Если бы мы правили подресурс из сцены,
## все шесть сотрудников делили бы одну коробку столкновений — и изменение
## у одного меняло бы её у всех.
func _apply_grid() -> void:
	var blocker := RectangleShape2D.new()
	blocker.size = Grid.body_collision_size()
	_blocker_shape.shape = blocker
	_blocker_shape.position = Grid.body_collision_offset()

	_sprite.hframes = Grid.walk_frames()
	_sprite.vframes = Grid.SHEET_ROWS
	_caption.add_theme_font_size_override("font_size", Grid.caption_font_size())


## Сесть за стол или встать. Сидящий ниже на Grid.seated_drop() (ноги за столом),
## без тени (её закрывает стол), и заговорить с ним можно через стол.
func set_seated(value: bool) -> void:
	if value == _seated:
		return
	_seated = value
	_apply_seat()


func _apply_seat() -> void:
	if _seated:
		var desk_reach := RectangleShape2D.new()
		var area := Grid.desk_reach_rect()
		desk_reach.size = area.size
		_reach_shape.shape = desk_reach
		_reach_shape.position = area.get_center()
	else:
		var reach := CircleShape2D.new()
		reach.radius = Grid.interactable_radius()
		_reach_shape.shape = reach
		_reach_shape.position = Vector2.ZERO

	_sprite.offset = Grid.character_sprite_offset() + Vector2(0.0, _seat())
	var caption := Grid.caption_rect()
	caption.position.y += _seat()
	_caption.offset_left = caption.position.x
	_caption.offset_top = caption.position.y
	_caption.offset_right = caption.end.x
	_caption.offset_bottom = caption.end.y
	if _shadow != null:
		_shadow.visible = not _seated
	_place_marker()


## Вызывается игроком. Единственная точка входа снаружи.
func interact(_player: Node2D) -> void:
	var dialogue_id := GameData.dialogue_for_speaker(employee_id)
	if dialogue_id.is_empty():
		push_warning("У сотрудника '%s' нет диалога в data/dialogues.json" % employee_id)
		return
	DialogueRunner.start(dialogue_id)


## Подсказка, которую показывает игрок, когда подошёл близко.
func interaction_prompt() -> String:
	var name_text: String = _employee.get("name", "")
	if name_text.is_empty():
		return "E — поговорить"
	return "E — поговорить: %s" % name_text


func _refresh() -> void:
	_employee = GameData.get_employee(employee_id)
	if _employee.is_empty():
		push_warning("NPC на карте ссылается на несуществующего сотрудника '%s'" % employee_id)
		_caption.text = "?"
		return

	# Свой рисунок сотрудника, если он есть (см. src/core/own_art.gd).
	# Нет — общий спрайт с цветом из данных. Это и есть
	# «смена палитры», о которой договорилась команда: пятнадцать разных
	# сотрудников без пятнадцати рисунков.
	var own := OwnArt.sprite(employee_id)
	if own != null:
		_sprite.texture = own
		_sprite.modulate = Color.WHITE
		# Лист сотрудника бывает выше общего: у того, кто ходит, рядов шесть.
		_sprite.vframes = maxi(1, own.get_height() / Grid.character_frame().y)
	elif _employee.has("palette"):
		_sprite.modulate = Color(String(_employee["palette"]))
	# За столом — печатает, с любым рисунком: в кадре 1 и «вдоха», и шага общего
	# листа корпус на пиксель ниже, а ноги за столом не видны. Стоя — дышит,
	# и только со своим рисунком: общий лист — это шаг, NPC шагал бы на месте.
	if at_desk:
		_start_typing()
	elif own != null:
		_start_idle()

	_caption.text = String(_employee.get("name", ""))
	_caption.visible = false


## Вызывается игроком, когда этот NPC стал ближайшим — или перестал им быть.
func set_caption_visible(value: bool) -> void:
	_caption.visible = value and show_caption
	_place_marker()
	# Игрок подошёл — отрывается от клавиатуры и смотрит на него.
	_attentive = value
	if value and _seated and not busy:
		_sprite.frame_coords = Vector2i(0, 0)


# --- Значок «!» / «?» над головой ------------------------------------------------

## Значок пересчитывается по событиям квестов, а не каждый кадр. Конец разговора —
## тоже событие: диалог мог поставить отметку (`set_flag`), от которой зависит,
## какой вариант ответа виден, а значит, и значок.
func _add_marker() -> void:
	_marker = QuestMarker.new()
	add_child(_marker)
	_place_marker()
	EventBus.quest_started.connect(_refresh_marker.unbind(1))
	EventBus.quest_objective_completed.connect(_refresh_marker.unbind(2))
	EventBus.quest_completed.connect(_refresh_marker.unbind(1))
	EventBus.access_level_changed.connect(_refresh_marker.unbind(1))
	EventBus.dialogue_finished.connect(_refresh_marker.unbind(2))
	_refresh_marker()


func _refresh_marker() -> void:
	_marker.show_kind(QuestLog.marker_for(employee_id))


## Над головой, а когда игрок подошёл и появилась подпись — над подписью.
func _place_marker() -> void:
	if _marker == null:
		return
	var bottom := Grid.caption_rect().position.y if _caption.visible \
		else float(Grid.tile_size()) * 0.5 - float(Grid.character_frame().y)
	_marker.position = Vector2(0.0, bottom + _seat() - _marker.height() * 0.5)


func _seat() -> float:
	return Grid.seated_drop() if _seated else 0.0


## Распорядок (телефон, шкаф) — только у сидящего за столом и только если в листе
## есть кадры ходьбы и телефона: у общего спрайта их нет.
func _add_routine() -> void:
	if not at_desk or _sprite.vframes < NpcRoutine.SHEET_ROWS:
		return
	var routine := NpcRoutine.new()
	routine.setup(self, _sprite)
	add_child(routine)


## Проверка в редакторе: существует ли такой сотрудник в данных.
## Читаем файл напрямую, а не через GameData — автозагрузки в редакторе не живут.
func _get_configuration_warnings() -> PackedStringArray:
	if employee_id.is_empty():
		return PackedStringArray(["Не заполнен employee_id — NPC будет безымянным."])

	var path := "res://data/company.json"
	if not FileAccess.file_exists(path):
		return PackedStringArray()

	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return PackedStringArray(["data/company.json не читается — проверьте запятые."])

	for employee in parser.data.get("employees", []):
		if employee.get("id", "") == employee_id:
			return PackedStringArray()
	return PackedStringArray([
		"В data/company.json нет сотрудника '%s'. Опечатка в id?" % employee_id])


## Кадры листает таймер, а не _process: NPC по-прежнему ничего не делает каждый
## кадр. Темп у каждого чуть свой (из id), иначе шесть человек дышат хором.
## Только у своего рисунка: общий спрайт — лист ходьбы, и в нём NPC шагал бы на месте.
func _start_idle() -> void:
	if get_node_or_null("IdleTimer") != null:
		return
	var timer := Timer.new()
	timer.name = "IdleTimer"
	var spread := float(absi(employee_id.hash()) % 100) / 100.0
	timer.wait_time = IDLE_STEP_SECONDS * lerpf(0.85, 1.2, spread)
	timer.timeout.connect(func():
		_sprite.frame_coords.x = (_sprite.frame_coords.x + 1) % _sprite.hframes)
	add_child(timer)
	timer.start()


## Печать очередями: несколько ударов, пауза, снова. Длины очереди и паузы —
## случайные в пределах TYPING_BURST и TYPING_PAUSE, чтобы соседи по кабинету
## не печатали в такт. Таймер, а не _process: как и дыхание.
func _start_typing() -> void:
	if get_node_or_null("TypingTimer") != null:
		return
	var timer := Timer.new()
	timer.name = "TypingTimer"
	timer.wait_time = TYPING_STEP_SECONDS
	timer.timeout.connect(_type_step)
	add_child(timer)
	# Первая очередь — не сразу и не у всех одновременно.
	_typing_left = -randi_range(0, TYPING_PAUSE.y)
	timer.start()


func _type_step() -> void:
	if _attentive or busy or not _seated:
		return
	if _typing_left > 0:
		_typing_left -= 1
		_sprite.frame_coords.x = 1 - _sprite.frame_coords.x
		if _typing_left == 0:
			_typing_left = -randi_range(TYPING_PAUSE.x, TYPING_PAUSE.y)
	else:
		_sprite.frame_coords.x = 0
		_typing_left += 1
		if _typing_left == 0:
			_typing_left = randi_range(TYPING_BURST.x, TYPING_BURST.y)

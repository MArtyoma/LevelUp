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

@onready var _sprite: Sprite2D = $Sprite2D
# У подписи z_index = 1 (в сцене): NPC сортируется по Y, и подпись над головой
# сортировалась бы по своей Y — как предмет на 2 тайла выше. Её закрывали бы
# стены, мебель и подошедший снизу игрок.
@onready var _caption: Label = $Caption
@onready var _reach_shape: CollisionShape2D = $CollisionShape2D
@onready var _blocker_shape: CollisionShape2D = $Blocker/CollisionShape2D

var _employee: Dictionary = {}

## «Дыхание»: раз в столько секунд — следующий кадр первого ряда листа
## (tools/art/make_sheet.py --idle: вдох — один кадр из четырёх).
const IDLE_STEP_SECONDS := 0.45


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_apply_grid()
	add_to_group("interactable")
	# NPC ничего не делает каждый кадр: он реагирует только на то, что к нему подошли.
	# Двенадцать спящих узлов вместо двенадцати работающих — мелочь, которая
	# на слабом ноутбуке в аудитории складывается с двумя десятками таких же мелочей.
	set_process(false)
	set_physics_process(false)
	_refresh()


## Подгоняет размеры под текущий размер тайла (см. `src/core/grid.gd`).
##
## Формы создаются новыми для каждого NPC. Если бы мы правили подресурс из сцены,
## все шесть сотрудников делили бы одну коробку столкновений — и изменение
## у одного меняло бы её у всех.
func _apply_grid() -> void:
	var reach := CircleShape2D.new()
	reach.radius = Grid.interactable_radius()
	_reach_shape.shape = reach

	var blocker := RectangleShape2D.new()
	blocker.size = Grid.body_collision_size()
	_blocker_shape.shape = blocker
	_blocker_shape.position = Grid.body_collision_offset()

	_sprite.hframes = Grid.walk_frames()
	_sprite.vframes = Grid.SHEET_ROWS
	_sprite.offset = Grid.character_sprite_offset()

	var caption := Grid.caption_rect()
	_caption.offset_left = caption.position.x
	_caption.offset_top = caption.position.y
	_caption.offset_right = caption.end.x
	_caption.offset_bottom = caption.end.y
	_caption.add_theme_font_size_override("font_size", Grid.caption_font_size())


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
		_start_idle()
	elif _employee.has("palette"):
		_sprite.modulate = Color(String(_employee["palette"]))

	_caption.text = String(_employee.get("name", ""))
	_caption.visible = false


## Вызывается игроком, когда этот NPC стал ближайшим — или перестал им быть.
func set_caption_visible(value: bool) -> void:
	_caption.visible = value and show_caption


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

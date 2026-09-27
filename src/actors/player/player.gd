class_name Player
extends CharacterBody2D

## Игрок — новый сотрудник. Движение, столкновения, взаимодействие.
##
## Владелец: lead.
##
## Почему именно так, а не иначе:
##
## * **Ни одного размера в пикселях.** Скорость, коробка столкновений, радиус,
##   с которого игрок дотягивается до NPC, смещение спрайта — всё берётся из
##   `Grid` и выражено через размер тайла. Поменяли 16 на 32 в настройках
##   проекта — персонаж проходит комнату за то же время и застревает там же,
##   где застревал, то есть нигде.
## * **Спрайт — обычный Sprite2D с кадрами, а не AnimatedSprite2D.** Кадры листает
##   этот скрипт. Так анимация не требует ресурса `.tres`, который пришлось бы
##   пересобирать при каждой замене картинки: artist кладёт новый PNG с той же
##   сеткой 4x4 — и всё работает. Один файл вместо двух и ноль конфликтов в Git.
## * **Во время разговора игрок не ходит.** Проверяется одним флагом
##   `DialogueRunner.is_running`, а не отключением ввода в пяти местах.

## Кадров анимации ходьбы в секунду. Подобрано под скорость (Grid.player_speed):
## медленнее — ноги не успевают за телом, и персонаж едет по полу, как на коньках.
const ANIMATION_FPS := 10.0

## Быстрее этого (в долях обычной скорости) — идём; медленнее — стоим. Упёрся
## в стену и жмёт кнопку — стоит, а не шагает на месте.
const WALKING_THRESHOLD := 0.2

## Ряды в спрайт-листе: порядок обязан совпадать с tools/make_placeholder_art.py.
const ROW_DOWN := 0
const ROW_LEFT := 1
const ROW_RIGHT := 2
const ROW_UP := 3

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _interaction_area: Area2D = $InteractionArea
@onready var _body_shape: CollisionShape2D = $CollisionShape2D
@onready var _reach_shape: CollisionShape2D = $InteractionArea/CollisionShape2D

# Скорость берётся из Grid один раз: в _physics_process ей делать нечего.
var _speed: float = 0.0

## Куда смотрит игрок. Пригодится, когда появится взаимодействие «перед собой».
var facing: Vector2 = Vector2.DOWN

# Всё, до чего сейчас можно дотянуться. Список почти всегда пуст или из одного
# элемента: его наполняет физика сигналами, а не перебор всех NPC каждый кадр.
var _reachable: Array[Node2D] = []
var _current_target: Node2D = null
var _animation_time: float = 0.0

# Слои тайлов уровня, верхний первым: по ним узнаём, по чему идём (звук шага).
var _floor_layers: Array[TileMapLayer] = []


func _ready() -> void:
	# По группе игрока находят те, кому важно, где он: сотрудник бросает дела,
	# когда игрок подошёл (src/actors/npc/npc_routine.gd).
	add_to_group("player")
	_apply_grid()
	GroundShadow.attach(self)
	_interaction_area.area_entered.connect(_on_reachable_entered)
	_interaction_area.area_exited.connect(_on_reachable_exited)
	_find_floor_layers()


## Подгоняет всё под текущий размер тайла (см. `src/core/grid.gd`).
##
## Формы столкновений создаются заново, а не правятся по месту: в сцене они
## лежат как подресурсы, и один и тот же объект достался бы всем копиям сразу.
## Для игрока это неважно — он один, — но привычка менять общий ресурс однажды
## аукнется на NPC, которых шесть.
func _apply_grid() -> void:
	_speed = Grid.player_speed()

	var body := RectangleShape2D.new()
	body.size = Grid.body_collision_size()
	_body_shape.shape = body
	_body_shape.position = Grid.body_collision_offset()

	var reach := CircleShape2D.new()
	reach.radius = Grid.reach_radius()
	_reach_shape.shape = reach

	_sprite.hframes = Grid.walk_frames()
	_sprite.vframes = Grid.SHEET_ROWS
	_sprite.offset = Grid.character_sprite_offset()


func _physics_process(delta: float) -> void:
	if DialogueRunner.is_running:
		velocity = Vector2.ZERO
		_set_frame(0)
		return

	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * _speed
	move_and_slide()

	_update_facing(direction)
	var moving := get_real_velocity().length() > _speed * WALKING_THRESHOLD
	_animate(direction if moving else Vector2.ZERO, delta)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if DialogueRunner.is_running:
		DialogueRunner.advance()
	elif is_instance_valid(_current_target):
		_current_target.interact(self)
	get_viewport().set_input_as_handled()


# --- Взаимодействие -----------------------------------------------------------

func _on_reachable_entered(area: Area2D) -> void:
	if not area.is_in_group("interactable"):
		return
	_reachable.append(area)
	_refresh_target()


func _on_reachable_exited(area: Area2D) -> void:
	_reachable.erase(area)
	_refresh_target()


## Цель могла исчезнуть с карты: предмет квеста после использования удаляется.
## Обращение к удалённому узлу роняет игру, поэтому цель всегда проверяется.
func _forget_invalid_target() -> void:
	if _current_target != null and not is_instance_valid(_current_target):
		_current_target = null


## Цель — ближайший объект из тех, до кого дотянулись. Если их несколько
## (NPC вплотную к двери), выбирать «какой-нибудь» нельзя: игрок ткнёт не туда
## и решит, что игра сломана.
func _refresh_target() -> void:
	_forget_invalid_target()
	# В списке тоже могли остаться удалённые узлы: сигнал area_exited от узла,
	# который освободили в этом же кадре, приходит не всегда.
	for index in range(_reachable.size() - 1, -1, -1):
		if not is_instance_valid(_reachable[index]):
			_reachable.remove_at(index)

	var nearest: Node2D = null
	var nearest_distance := INF
	for candidate in _reachable:
		if not is_instance_valid(candidate) or not candidate.has_method("interact"):
			continue
		var distance := global_position.distance_squared_to(candidate.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = candidate

	if nearest == _current_target:
		return

	# Подпись над головой зажигается только у того, к кому игрок реально подошёл.
	if is_instance_valid(_current_target) and _current_target.has_method("set_caption_visible"):
		_current_target.set_caption_visible(false)
	_current_target = nearest

	if _current_target == null:
		EventBus.hint_hidden.emit()
		return
	if _current_target.has_method("set_caption_visible"):
		_current_target.set_caption_visible(true)
	EventBus.hint_shown.emit(_prompt_for(_current_target))


func _prompt_for(target: Node2D) -> String:
	if target.has_method("interaction_prompt"):
		return target.interaction_prompt()
	return "Нажми E"


# --- Отображение --------------------------------------------------------------

func _update_facing(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return
	# По горизонтали приоритет: при диагонали персонаж смотрит вбок — так читается
	# лучше, чем «спиной к камере под углом».
	if absf(direction.x) >= absf(direction.y):
		facing = Vector2.RIGHT if direction.x > 0.0 else Vector2.LEFT
	else:
		facing = Vector2.DOWN if direction.y > 0.0 else Vector2.UP
	_sprite.frame_coords.y = _row_for(facing)


func _row_for(direction: Vector2) -> int:
	if direction == Vector2.UP:
		return ROW_UP
	if direction == Vector2.LEFT:
		return ROW_LEFT
	if direction == Vector2.RIGHT:
		return ROW_RIGHT
	return ROW_DOWN


func _animate(direction: Vector2, delta: float) -> void:
	if direction == Vector2.ZERO:
		_animation_time = 0.0
		_set_frame(0)
		return
	# С места — сразу шаг, а не ещё одна десятая секунды стойки: так кнопка
	# отзывается мгновенно.
	if _animation_time == 0.0:
		_animation_time = 1.0
	_animation_time += delta * ANIMATION_FPS
	var column := int(_animation_time) % _sprite.hframes
	# В листе нога поднята в нечётных кадрах; шаг слышен, когда она опускается.
	if column != _sprite.frame_coords.x and column % 2 == 0:
		Sound.footstep(surface_under_feet())
	_set_frame(column)


func _set_frame(column: int) -> void:
	_sprite.frame_coords.x = column


# --- Звук шагов ---------------------------------------------------------------

## Уровень добавлен в мир раньше игрока (src/main.gd), так что слои уже на месте.
## Нужны только те, у тайлсета которых есть слой данных `surface`
## (tools/build_tileset.gd): level designer для новой карты ничего настраивать не надо.
func _find_floor_layers() -> void:
	var world := get_parent()
	if world == null:
		return
	for node in world.find_children("*", "TileMapLayer", true, false):
		var layer := node as TileMapLayer
		if layer.tile_set != null and layer.tile_set.has_custom_data_layer_by_name("surface"):
			_floor_layers.push_front(layer)


## По чему стоит игрок: "carpet", "tile" или "" (не знаем — звучит ковролин).
func surface_under_feet() -> String:
	for layer in _floor_layers:
		var data := layer.get_cell_tile_data(layer.local_to_map(layer.to_local(global_position)))
		if data == null:
			continue
		var surface := String(data.get_custom_data("surface"))
		if not surface.is_empty():
			return surface
	return ""

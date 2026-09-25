class_name Player
extends CharacterBody2D

## Игрок — новый сотрудник. Движение, столкновения, взаимодействие.
##
## Владелец: лид.
##
## Почему именно так, а не иначе:
##
## * **Скорость в пикселях, кратная тайлу.** 60 px/с при тайле 16 — это ровно
##   3.75 тайла в секунду. Ровные числа здесь не эстетика: при виде сверху игрок
##   должен успевать читать подписи над NPC, и подобранная один раз скорость
##   больше не трогается «на глаз».
## * **Спрайт — обычный Sprite2D с кадрами, а не AnimatedSprite2D.** Кадры листает
##   этот скрипт. Так анимация не требует ресурса `.tres`, который пришлось бы
##   пересобирать при каждой замене картинки: artist кладёт новый PNG с той же
##   сеткой 4x4 — и всё работает. Один файл вместо двух и ноль конфликтов в Git.
## * **Во время разговора игрок не ходит.** Проверяется одним флагом
##   `DialogueRunner.is_running`, а не отключением ввода в пяти местах.

## Пикселей в секунду.
const SPEED := 60.0

## Кадров анимации ходьбы в секунду.
const ANIMATION_FPS := 8.0

## Ряды в спрайт-листе: порядок обязан совпадать с tools/make_placeholder_art.py.
const ROW_DOWN := 0
const ROW_LEFT := 1
const ROW_RIGHT := 2
const ROW_UP := 3

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _interaction_area: Area2D = $InteractionArea

## Куда смотрит игрок. Пригодится, когда появится взаимодействие «перед собой».
var facing: Vector2 = Vector2.DOWN

# Всё, до чего сейчас можно дотянуться. Список почти всегда пуст или из одного
# элемента: его наполняет физика сигналами, а не перебор всех NPC каждый кадр.
var _reachable: Array[Node2D] = []
var _current_target: Node2D = null
var _animation_time: float = 0.0


func _ready() -> void:
	_interaction_area.area_entered.connect(_on_reachable_entered)
	_interaction_area.area_exited.connect(_on_reachable_exited)


func _physics_process(delta: float) -> void:
	if DialogueRunner.is_running:
		velocity = Vector2.ZERO
		_set_frame(0)
		return

	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * SPEED
	move_and_slide()

	_update_facing(direction)
	_animate(direction, delta)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if DialogueRunner.is_running:
		DialogueRunner.advance()
	elif _current_target != null:
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


## Цель — ближайший объект из тех, до кого дотянулись. Если их несколько
## (NPC вплотную к двери), выбирать «какой-нибудь» нельзя: игрок ткнёт не туда
## и решит, что игра сломана.
func _refresh_target() -> void:
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
	if _current_target != null and _current_target.has_method("set_caption_visible"):
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
	_animation_time += delta * ANIMATION_FPS
	_set_frame(int(_animation_time) % _sprite.hframes)


func _set_frame(column: int) -> void:
	_sprite.frame_coords.x = column

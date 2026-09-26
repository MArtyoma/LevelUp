class_name QuestMarker
extends Sprite2D

## Значок над головой, как в WoW: «!» — здесь дают задание, «?» — сюда идти
## за текущим шагом задания.
##
## Владелец кода: лид. Рисунок: **artist** (`assets/ui/quest_markers.png`,
## пока черновик `tools/art/draw_markers.py`).
##
## Зачем игре про онбординг: на замере игрок не должен тратить время на поиски
## «а к кому теперь». Если половина группы заблудится, мы измерим навигацию,
## а не то, запомнил ли человек, кто за что отвечает.
##
## Сам значок ничего не решает: какой показать, говорит тот, над кем он висит
## (NPC спрашивает `QuestLog.marker_for`, предмет — `QuestLog.is_current_step`).

## Файл художника важнее черновика — как у спрайтов в OwnArt.
const TEXTURES := [
	"res://assets/ui/quest_markers.png",
	"res://assets/ui/quest_markers_placeholder.png",
]

## Кадр в листе для каждого значка.
const FRAMES := {
	"new": 0,
	"step": 1,
}

## Значок покачивается вверх-вниз: неподвижный теряется среди мебели.
const BOB_SECONDS := 0.5

## Что показано сейчас: "new", "step" или "" (ничего).
var kind: String = ""

var _tween: Tween


func _init() -> void:
	name = "QuestMarker"
	# Как подпись с именем: над всем, что сортируется по Y, иначе значок
	# человека в верхнем ряду прячется за стеной над ним.
	z_index = 1
	visible = false
	for path: String in TEXTURES:
		if ResourceLoader.exists(path):
			texture = load(path)
			break
	hframes = FRAMES.size()


## Показать значок ("new" / "step") или спрятать ("").
func show_kind(value: String) -> void:
	if value == kind:
		return
	kind = value
	visible = texture != null and FRAMES.has(value)
	if visible:
		frame = FRAMES[value]
	_bob()


func _ready() -> void:
	_bob()


## Покачивание — только у видимого значка и только в дереве сцены
## (твину нужен SceneTree). Спрятанный значок ничего не делает.
func _bob() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	offset.y = 0.0
	if not visible or not is_inside_tree():
		return
	var lift := ceilf(float(Grid.tile_size()) / 16.0)
	_tween = create_tween().set_loops()
	_tween.tween_property(self, "offset:y", -lift, BOB_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "offset:y", 0.0, BOB_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Высота значка в пикселях — чтобы поставить его нижним краем над головой.
func height() -> float:
	return float(texture.get_height()) if texture != null else 0.0

extends TileMapLayer

## Слой стен и мебели. Одна задача: показать стены «в три четверти».
##
## На карте стена — один и тот же тайл (2,0), вид сверху. Но стена, к которой
## обращён пол, в игре сверху видна лицом: светлая поверхность с плинтусом.
## Расставлять такие тайлы руками — лишняя работа и лишний шанс ошибиться
## при каждой правке карты. Поэтому при запуске уровня этот скрипт сам меняет
## на «лицо» (6,1) каждую стену, под которой пол. Столкновения у лица те же,
## что у стены, так что ходить игрок будет ровно как раньше.
##
## Владелец: lead. Level designer рисует карту как обычно — только тайлом (2,0).

const WALL := Vector2i(2, 0)
const WALL_FACE := Vector2i(6, 1)

## Слой пола: «под стеной пол» — это клетка ниже, где на полу что-то лежит,
## а на этом слое стены нет.
@export var ground: TileMapLayer


func _ready() -> void:
	if ground == null:
		push_warning("WallFaces: не указан слой пола (поле ground) — стены останутся плоскими")
		return
	for cell in get_used_cells_by_id(0, WALL):
		var below := cell + Vector2i.DOWN
		if ground.get_cell_source_id(below) != -1 and not _is_wall(below):
			set_cell(cell, 0, WALL_FACE)


func _is_wall(cell: Vector2i) -> bool:
	var atlas := get_cell_atlas_coords(cell)
	return atlas == WALL or atlas == WALL_FACE

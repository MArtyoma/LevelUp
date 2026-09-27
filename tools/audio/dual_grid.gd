@tool
class_name DualGrid extends TileMapLayer

const ATLAS_COORDS: Array[Vector2i] = [
	Vector2i(0,3), Vector2i(1,3),
	Vector2i(0,0), Vector2i(3,0),
	Vector2i(0,2), Vector2i(1,0),
	Vector2i(2,3), Vector2i(1,1),
	
	Vector2i(3,3), Vector2i(0,1),
	Vector2i(3,2), Vector2i(2,0),
	Vector2i(1,2), Vector2i(2,2),
	Vector2i(3,1), Vector2i(2,1),
	]
const ATLAS_SIZE: Vector2i = Vector2i(4,4)

@export var display_layer: TileMapLayer
@export_tool_button("Recalculate", "Reload") var recalc_func: Callable = recalc_grid
@export var auto_update: bool = true

@export_group("Randomization")
@export var randomize_tiles: bool = false
@export var rng_seed: int:
	set(value):
		rng_seed = value
		if randomize_tiles:
			recalc_grid()
@export var rng_weights: Dictionary[Vector2i,float]

var recalculating: bool = false
var prev_data: PackedByteArray


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint() or not auto_update:
		return
	if prev_data != tile_map_data and not recalculating:
		recalc_grid()
	prev_data = tile_map_data


func recalc_grid() -> void:
	recalculating = true
	seed(rng_seed)
	display_layer.clear()
	var sizedata = get_used_rect()
	for i in sizedata.size.x+1:
		for j in sizedata.size.y+1:
			calc_tile(Vector2i(i,j) + sizedata.position - Vector2i.ONE)
	randomize()
	recalculating = false


func calc_tile(coords: Vector2i) -> void:
	var atlas_offset: Vector2i = Vector2i.ZERO
	if randomize_tiles:
		var total_weight: float = 0
		for i: float in rng_weights.values():
			total_weight += i
		var weight_pick: float = randf_range(0,total_weight)
		for i: Vector2i in rng_weights.keys():
			weight_pick -= rng_weights[i]
			if weight_pick < 0:
				atlas_offset = ATLAS_SIZE * i
				break
	
	var state_idx: int = 0b0000
	if get_cell_tile_data(coords+Vector2i.ONE): 
		state_idx+=0b0001
	if get_cell_tile_data(coords+Vector2i.DOWN): 
		state_idx+=0b0010
	if get_cell_tile_data(coords+Vector2i.RIGHT): 
		state_idx+=0b0100
	if get_cell_tile_data(coords): 
		state_idx+=0b1000
	if state_idx == 0b0000:
		display_layer.erase_cell(coords)
		return
	display_layer.set_cell(coords, 0, ATLAS_COORDS[state_idx] + atlas_offset)

extends SceneTree

## Пересчитывает позиции на карте под новый размер тайла.
##
##     godot --headless --script tools/rescale_level.gd -- --from=16 --to=32
##     godot --headless --script tools/rescale_level.gd -- --from=16 --to=32 \
##           --scene=res://src/levels/office_demo.tscn
##
## Зачем. Сами тайлы на карте хранятся клетками, а не пикселями: при смене
## размера тайла карта перерисуется сама. А вот NPC, двери и предметы стоят
## по пикселям — их надо умножить на отношение размеров, иначе после смены
## 16 на 32 все сотрудники окажутся в левом верхнем углу, в стенах.
##
## Скрипт правит сцену на месте. **Сделайте коммит до запуска** — откатиться
## иначе будет нечем.

func _initialize() -> void:
	var from_size := 0
	var to_size := 0
	var scene_path := "res://src/levels/office_demo.tscn"

	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--from="):
			from_size = int(argument.trim_prefix("--from="))
		elif argument.begins_with("--to="):
			to_size = int(argument.trim_prefix("--to="))
		elif argument.begins_with("--scene="):
			scene_path = argument.trim_prefix("--scene=")

	if from_size <= 0 or to_size <= 0:
		print("Укажите оба размера: --from=16 --to=32")
		quit(1)
		return
	if from_size == to_size:
		print("Размеры совпадают, делать нечего")
		quit(0)
		return

	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Не открывается сцена %s" % scene_path)
		quit(1)
		return

	var root := packed.instantiate()
	var factor := float(to_size) / float(from_size)
	var moved := _rescale(root, root, factor)

	var repacked := PackedScene.new()
	if repacked.pack(root) != OK or ResourceSaver.save(repacked, scene_path) != OK:
		push_error("Не удалось сохранить %s" % scene_path)
		quit(1)
		return

	print("Пересчитано %d узлов в %s: %d -> %d пикселей на тайл (x%.2f)"
		% [moved, scene_path, from_size, to_size, factor])
	print("Проверьте карту глазами: godot --screenshot=after.png res://tools/screenshot.tscn")
	quit(0)


## Обходит дерево и двигает всё, что стоит по пикселям.
## Слои тайлов не трогаем: они считают в клетках и перерисуются сами.
func _rescale(node: Node, root: Node, factor: float) -> int:
	var moved := 0
	if node is TileMapLayer:
		return 0
	if node is Node2D and node != root:
		(node as Node2D).position *= factor
		moved += 1
	for child in node.get_children():
		moved += _rescale(child, root, factor)
	return moved

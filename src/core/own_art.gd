class_name OwnArt
extends RefCounted

## Личные картинки сотрудников: спрайт на карте и портрет в окне диалога.
##
## Имя файла — id сотрудника из data/company.json:
##
##   assets/sprites/npc/<id>.png            рисунок художника
##   assets/sprites/npc/<id>_placeholder.png черновик нейросети (tools/art/)
##
## и так же в assets/portraits/. Рисунок художника важнее черновика: положил
## `emp_kim.png` рядом с `emp_kim_placeholder.png` — в игре сразу новый.
## Файла нет — вызывающий показывает общее (спрайт с цветом из данных).

const SPRITES := "res://assets/sprites/npc/"
const PORTRAITS := "res://assets/portraits/"


static func sprite(employee_id: String) -> Texture2D:
	return _find(SPRITES, employee_id)


static func portrait(employee_id: String) -> Texture2D:
	return _find(PORTRAITS, employee_id)


static func _find(folder: String, employee_id: String) -> Texture2D:
	if employee_id.is_empty():
		return null
	for suffix: String in ["", "_placeholder"]:
		var path := folder + employee_id + suffix + ".png"
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null

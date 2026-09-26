class_name GroundShadow
extends Node2D

## Мягкая тень под ногами человека.
##
## Владелец: лид.
##
## Без неё персонаж 16x32 висит над полом, как наклейка: не видно, где он стоит,
## и шаги не «попадают» в пол. Тень — полупрозрачный овал, нарисованный кодом:
## ни картинки, ни настройки, размер — от размера тайла.

const COLOR := Color(0.1, 0.11, 0.17, 0.28)

## Ширина и высота овала в долях тайла.
const SIZE := Vector2(0.75, 0.3)


## Подложить тень под `body`. Тень рисуется раньше спрайта: у людей включена
## сортировка по Y, и при равной Y первым рисуется тот, кто раньше в дереве.
static func attach(body: Node2D) -> GroundShadow:
	var shadow := GroundShadow.new()
	shadow.name = "GroundShadow"
	body.add_child(shadow)
	body.move_child(shadow, 0)
	return shadow


func _draw() -> void:
	var tile := float(Grid.tile_size())
	var radius := SIZE * tile * 0.5
	# Центр — ровно на нижнем краю клетки, где стоят ноги (см. Grid.character_sprite_offset):
	# стопы приходятся на середину овала, и половина тени выглядывает из-под них.
	var center := Vector2(0.0, tile * 0.5)
	draw_set_transform(center, 0.0, Vector2(1.0, radius.y / radius.x))
	draw_circle(Vector2.ZERO, radius.x, COLOR)

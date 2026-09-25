extends TestCase

## Тесты звука. Услышать звук тест не может — проверяет, что звучать есть чему
## и что звучит то, что нужно.

const LEVEL_PATH := "res://src/levels/office_demo.tscn"
const PLAYER_PATH := "res://src/actors/player/player.tscn"

var _world: Node2D = null


func after_each() -> void:
	Sound.play_music("")
	if is_instance_valid(_world):
		_world.free()


func test_every_sound_has_a_file() -> void:
	# Имя в VOLUME_DB есть, файла нет — событие молчит, и никто этого не заметит.
	for sound_name: String in Sound.VOLUME_DB:
		check(not Sound._variants(Sound.SFX_DIR, sound_name, "wav").is_empty(),
			"нет файла assets/sfx/%s[_N][_placeholder].wav" % sound_name)
	for track: String in ["office", "duel"]:
		check(not Sound._variants(Sound.MUSIC_DIR, track, "ogg").is_empty(),
			"нет музыки assets/music/%s[_placeholder].ogg" % track)


func test_voice_is_the_same_every_time() -> void:
	var kim := Sound.voice_pitch("emp_kim")
	equals(Sound.voice_pitch("emp_kim"), kim, "голос Кима должен быть всегда один")
	check(kim >= Sound.VOICE_PITCH_MIN and kim <= Sound.VOICE_PITCH_MAX,
		"высота голоса %.2f вне диапазона" % kim)
	check(not is_equal_approx(kim, Sound.voice_pitch("emp_mironova")),
		"у Кима и Мироновой одинаковые голоса")


func test_many_events_at_once_play_one_sound() -> void:
	# Последняя цель квеста: цель выполнена, квест закрыт, выдан пропуск — три
	# события за кадр. Звучать должно одно, самое важное.
	Sound.recent.clear()
	EventBus.quest_objective_completed.emit("q", "o")
	EventBus.access_level_changed.emit(2)
	EventBus.quest_completed.emit("q")
	Sound._flush_pending()
	equals(Sound.recent.size(), 1, "за кадр должен прозвучать один звук")
	equals(Sound.recent.back(), "quest_done", "из трёх событий главное — квест выполнен")


func test_duel_music_starts_and_ends() -> void:
	Sound.play_music("office")
	EventBus.duel_patience_changed.emit(3, 3)
	equals(Sound.music_name, "duel", "в начале дуэли должна включиться её музыка")
	EventBus.duel_patience_changed.emit(2, 3)
	equals(Sound.music_name, "duel", "промах не должен сбрасывать музыку дуэли")
	EventBus.dialogue_finished.emit("duel", "duel_won")
	equals(Sound.music_name, "office", "после дуэли должна вернуться музыка офиса")


func test_footsteps_know_carpet_from_tiles() -> void:
	_world = Node2D.new()
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(_world)
	var level: Node = (load(LEVEL_PATH) as PackedScene).instantiate()
	_world.add_child(level)
	var ground := level.get_node("Ground") as TileMapLayer
	var player: Player = (load(PLAYER_PATH) as PackedScene).instantiate()
	_world.add_child(player)

	var expected := { Vector2i(0, 0): "carpet", Vector2i(1, 0): "tile" }
	for atlas: Vector2i in expected:
		var cells := ground.get_used_cells_by_id(0, atlas)
		check(not cells.is_empty(), "на карте нет тайла %s" % atlas)
		if cells.is_empty():
			continue
		player.global_position = ground.to_global(ground.map_to_local(cells[0]))
		equals(player.surface_under_feet(), expected[atlas],
			"на тайле %s шаги звучат не так" % atlas)

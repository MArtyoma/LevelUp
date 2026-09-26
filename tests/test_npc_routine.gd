extends TestCase

## Тесты распорядка сотрудника: отходит от стола и возвращается, при игроке
## замирает. Кадры в тестах не идут — шаги делаем руками через _process.

const LEVEL_PATH := "res://src/levels/office_demo.tscn"

var _level: Node2D
var _player: Node2D


func before_each() -> void:
	_level = (load(LEVEL_PATH) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(_level)


func after_each() -> void:
	if is_instance_valid(_player):
		_player.free()
	_level.free()


func _npc(employee_id: String) -> Npc:
	for node in _level.find_children("*", "Area2D", true, false):
		if node is Npc and (node as Npc).employee_id == employee_id:
			return node
	return null


func _run(routine: NpcRoutine, seconds: float) -> void:
	var step := 1.0 / 30.0
	var t := 0.0
	while t < seconds:
		routine._process(step)
		t += step


func test_errand_goes_and_comes_back_to_the_desk() -> void:
	var npc := _npc("emp_mironova")
	var routine := npc.get_node_or_null("Routine") as NpcRoutine
	check(routine != null, "у Мироновой нет распорядка: лист без кадров ходьбы?")
	if routine == null:
		return
	var home := npc.position
	var spot: Vector2 = routine._spots[0]
	routine._walk_to(spot, NpcRoutine.State.GOING)
	check(npc.busy, "ушла от стола, а считается свободной — будет печатать на ходу")
	_run(routine, 20.0)
	equals(routine.state, NpcRoutine.State.THERE, "не дошла до шкафа за 20 секунд")
	check(npc.position.is_equal_approx(spot), "стоит не у шкафа, а в %s" % npc.position)

	routine._walk_to(home, NpcRoutine.State.RETURNING)
	_run(routine, 20.0)
	equals(routine.state, NpcRoutine.State.DESK, "не вернулась за стол")
	check(npc.position.is_equal_approx(home), "вернулась не на своё место")
	check(not npc.busy, "вернулась за стол, но не печатает")


func test_stops_when_player_comes_close() -> void:
	# Главное правило: никакой погони. Игрок рядом — сотрудник стоит.
	var npc := _npc("emp_mironova")
	var routine := npc.get_node_or_null("Routine") as NpcRoutine
	if routine == null:
		return
	routine._walk_to(routine._spots[0], NpcRoutine.State.GOING)
	_run(routine, 0.3)
	_player = Node2D.new()
	_player.add_to_group("player")
	_level.add_child(_player)
	_player.position = npc.position + Vector2(float(Grid.tile_size()), 0.0)
	var before := npc.position
	_run(routine, 3.0)
	check(npc.position.is_equal_approx(before), "игрок рядом, а сотрудник продолжает идти")


func test_phone_call_ends_when_player_comes() -> void:
	var npc := _npc("emp_pavlov")
	var routine := npc.get_node_or_null("Routine") as NpcRoutine
	if routine == null:
		return
	routine._start_phone()
	equals(routine.state, NpcRoutine.State.PHONE, "звонок не начался")
	_player = Node2D.new()
	_player.add_to_group("player")
	_level.add_child(_player)
	_player.position = npc.position + Vector2(0.0, float(Grid.tile_size()) * 2.0)
	_run(routine, 0.1)
	equals(routine.state, NpcRoutine.State.DESK, "игрок подошёл, а сотрудник не положил трубку")

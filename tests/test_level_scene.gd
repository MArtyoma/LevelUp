extends TestCase

## Тесты карты — единственные, которые проверяют игру целиком.
##
## Всё остальное проверяет код и данные по отдельности. Но игра ломается
## на стыке: writer переименовал сотрудника, level designer этого не знал, и NPC на карте
## ссылается в пустоту. Или квест есть, диалог есть, а предмет, который
## закрывает его первый шаг, на карту поставить забыли — и игра непроходима.
## Такое ловится либо здесь за две секунды, либо на плейтесте за две недели
## до защиты.
##
## Тест читает сцену как данные и ничего не запускает: узлы не попадают
## в дерево, поэтому `_ready` у них не срабатывает и игра не стартует.

const LEVEL_PATH := "res://src/levels/office_demo.tscn"

var _root: Node = null


func before_each() -> void:
	var packed: PackedScene = load(LEVEL_PATH)
	if packed != null:
		_root = packed.instantiate()


func after_each() -> void:
	if is_instance_valid(_root):
		_root.free()
	_root = null


func test_level_opens() -> void:
	check(_root != null, "сцена %s не открывается" % LEVEL_PATH)


func test_player_has_a_place_to_start() -> void:
	if _root == null:
		return
	var marker := _root.get_node_or_null("PlayerSpawn")
	check(marker is Node2D,
		"в уровне нет узла PlayerSpawn — игрок появится в левом верхнем углу, в стене")


func test_every_npc_exists_in_the_company() -> void:
	if _root == null:
		return
	for npc: Npc in _find(_root, "Npc"):
		var employee := GameData.get_employee(npc.employee_id)
		check(not employee.is_empty(),
			"на карте стоит NPC '%s', а такого сотрудника нет в data/company.json"
				% npc.employee_id)


func test_every_npc_can_talk() -> void:
	if _root == null:
		return
	for npc: Npc in _find(_root, "Npc"):
		var dialogue := GameData.dialogue_for_speaker(npc.employee_id)
		check(not dialogue.is_empty(),
			"у сотрудника '%s' нет диалога: на карте он есть, а сказать ему нечего"
				% npc.employee_id)


func test_two_npcs_do_not_stand_in_one_place() -> void:
	if _root == null:
		return
	var seen: Dictionary = {}
	for npc: Npc in _find(_root, "Npc"):
		var key := str(npc.position)
		check(not seen.has(key),
			"сотрудники '%s' и '%s' стоят в одной точке — поговорить можно будет только с одним"
				% [seen.get(key, ""), npc.employee_id])
		seen[key] = npc.employee_id


func test_quest_objects_point_to_real_steps() -> void:
	if _root == null:
		return
	for object: QuestObject in _find(_root, "QuestObject"):
		var quest := GameData.get_quest(object.quest_id)
		if quest.is_empty():
			failures.append("предмет на карте выдаёт шаг квеста '%s', которого нет"
				% object.quest_id)
			continue
		var found := false
		for objective: Dictionary in quest.get("objectives", []):
			if objective.get("id", "") == object.objective_id:
				found = true
		check(found, "предмет на карте закрывает шаг '%s', которого нет в квесте '%s'"
			% [object.objective_id, object.quest_id])


func test_room_triggers_match_the_legend() -> void:
	if _root == null:
		return
	var rooms: Dictionary = {}
	for department: Dictionary in GameData.all_departments():
		if department.get("room", ""):
			rooms[department["room"]] = true

	for trigger: RoomTrigger in _find(_root, "RoomTrigger"):
		check(not trigger.room_id.is_empty(), "зона помещения без room_id — в записи прохождения "
			+ "она будет безымянной")
		check(rooms.has(trigger.room_id),
			"зона '%s' не сходится с легендой: такого помещения нет ни у одного отдела"
				% trigger.room_id)


func test_closed_doors_can_be_opened() -> void:
	if _root == null:
		return
	var highest := QuestLog.STARTING_ACCESS_LEVEL
	for quest: Dictionary in GameData.all_quests():
		highest = maxi(highest, int(quest.get("reward", {}).get("access_level", 0)))
	for level: int in _levels_granted_by_dialogues():
		highest = maxi(highest, level)

	for door: AccessDoor in _find(_root, "AccessDoor"):
		check(door.required_access <= highest,
			"дверь требует пропуск %d, а максимум, который игрок может получить, — %d. "
				% [door.required_access, highest] + "Она не откроется никогда")


func test_every_quest_can_be_finished() -> void:
	# Самая ценная проверка файла: игра вообще проходима до конца?
	# Шаг закрывается либо репликой в диалоге, либо предметом на карте.
	# Если ни там, ни там — квест повиснет навсегда, и это не заметно,
	# пока кто-нибудь не пройдёт игру целиком.
	if _root == null:
		return

	var closed: Dictionary = {}
	for dialogue: Dictionary in _all_dialogues():
		for node_id: String in dialogue.get("nodes", {}):
			for effect: Dictionary in _effects_of(dialogue["nodes"][node_id]):
				if String(effect.get("type", "")) == "complete_objective":
					var step := "%s/%s" % [effect.get("quest", ""), effect.get("objective", "")]
					closed[step] = "диалог"
	for object: QuestObject in _find(_root, "QuestObject"):
		closed["%s/%s" % [object.quest_id, object.objective_id]] = "предмет на карте"

	for quest: Dictionary in GameData.all_quests():
		for objective: Dictionary in quest.get("objectives", []):
			var key := "%s/%s" % [quest.get("id", ""), objective.get("id", "")]
			check(closed.has(key),
				"шаг «%s» квеста «%s» не закрывается ничем: ни репликой, ни предметом на карте"
					% [objective.get("text", objective.get("id", "?")), quest.get("title", "?")])


func test_every_step_shows_where_to_go() -> void:
	# Строже, чем «квест проходим»: в момент, когда шаг текущий, над кем-то на карте
	# висит «?». Ловит вариант ответа, закрывающий шаг, но спрятанный условием,
	# которое к этому моменту не выполняется: по данным квест проходим, а игрок
	# ходит по офису и не знает, куда.
	if _root == null:
		return
	var employees: Array[String] = []
	for npc: Npc in _find(_root, "Npc"):
		employees.append(npc.employee_id)
	var objects: Array[String] = []
	for object: QuestObject in _find(_root, "QuestObject"):
		objects.append("%s/%s" % [object.quest_id, object.objective_id])

	for quest: Dictionary in GameData.all_quests():
		var quest_id := String(quest.get("id", ""))
		QuestLog.reset()
		QuestLog.start_quest(quest_id)
		for objective: Dictionary in quest.get("objectives", []):
			var step := "%s/%s" % [quest_id, objective.get("id", "")]
			var marked := objects.has(step)
			for employee_id in employees:
				marked = marked or QuestLog.marker_for(employee_id) == QuestLog.MARK_STEP
			check(marked, "на шаге «%s» квеста «%s» ни над кем на карте нет «?»"
				% [objective.get("text", "?"), quest.get("title", "?")])
			QuestLog.complete_objective(quest_id, String(objective.get("id", "")))
	QuestLog.reset()


func test_everyone_can_be_reached_on_foot() -> void:
	# Мебель твёрдая. Поставили диван поперёк прохода — к сотруднику не подойти,
	# и игра непроходима, хотя все данные в порядке. Идём от старта по клеткам,
	# где есть пол и нет твёрдого тайла; дверь по пропуску считаем открытой —
	# открывается ли она, проверяет test_closed_doors_can_be_opened.
	if _root == null:
		return
	var ground := _root.get_node_or_null("Ground") as TileMapLayer
	var walls := _root.get_node_or_null("Walls") as TileMapLayer
	var spawn := _root.get_node_or_null("PlayerSpawn") as Node2D
	if ground == null or walls == null or spawn == null:
		failures.append("в уровне нет Ground, Walls или PlayerSpawn — проверить проходимость нельзя")
		return

	var reached := { ground.local_to_map(spawn.position): true }
	var queue: Array[Vector2i] = [ground.local_to_map(spawn.position)]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next := cell + step
			if reached.has(next) or ground.get_cell_source_id(next) == -1 or _is_solid(walls, next):
				continue
			reached[next] = true
			queue.append(next)

	var targets: Array = []
	for npc: Npc in _find(_root, "Npc"):
		# К сидящему подходят спереди, через стол: клетка перед столом — на две ниже.
		var front := Vector2(0.0, float(Grid.tile_size()) * 2.0) if npc.at_desk else Vector2.ZERO
		targets.append(["сотруднику '%s'" % npc.employee_id, npc.position + front])
	for object: QuestObject in _find(_root, "QuestObject"):
		targets.append(["предмету '%s'" % object.name, object.position])
	for target: Array in targets:
		var cell := ground.local_to_map(target[1])
		var near := false
		for step: Vector2i in [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			near = near or reached.has(cell + step)
		check(near, "к %s не подойти от точки старта: проход перегорожен мебелью или стеной"
			% target[0])


func test_seated_npc_has_a_desk_and_can_be_talked_to_across_it() -> void:
	# Сотрудника с галочкой «за столом» пересадили, а стол остался на месте —
	# он сидит «в воздухе», и ноги у него закрывает пол. И наоборот: поговорить
	# через стол можно, только если зона разговора дотягивается до переднего края.
	if _root == null:
		return
	var walls := _root.get_node_or_null("Walls") as TileMapLayer
	var tile := float(Grid.tile_size())
	for npc: Npc in _find(_root, "Npc"):
		if not npc.at_desk:
			continue
		var cell := walls.local_to_map(npc.position)
		for dx in [-1, 0, 1]:
			var atlas := walls.get_cell_atlas_coords(cell + Vector2i(dx, 1))
			check(atlas.y == 3 and atlas.x in [1, 2, 3],
				"'%s' сидит за столом, а под ним в клетке %s не рабочее место"
					% [npc.employee_id, cell + Vector2i(dx, 1)])
		# Игрок стоит перед столом, через клетку от сотрудника.
		var player_center := Vector2(0.0, tile * 2.0)
		var area := Grid.desk_reach_rect()
		var nearest := Vector2(clampf(player_center.x, area.position.x, area.end.x),
			clampf(player_center.y, area.position.y, area.end.y))
		check(nearest.distance_to(player_center) < Grid.reach_radius(),
			"с '%s' не заговорить через стол: зона разговора не дотягивается" % npc.employee_id)


# --- Помощники ----------------------------------------------------------------

func _is_solid(walls: TileMapLayer, cell: Vector2i) -> bool:
	var data := walls.get_cell_tile_data(cell)
	return data != null and data.get_collision_polygons_count(0) > 0


## Обход дерева сцены. Сравниваем по имени класса, а не через `is`: так тест
## не зависит от того, в каком файле лежит скрипт.
func _find(node: Node, class_name_wanted: String) -> Array:
	var found: Array = []
	var script: Script = node.get_script()
	if script != null and script.get_global_name() == class_name_wanted:
		found.append(node)
	for child in node.get_children():
		found.append_array(_find(child, class_name_wanted))
	return found


func _all_dialogues() -> Array:
	var parser := JSON.new()
	parser.parse(FileAccess.get_file_as_string("res://data/dialogues.json"))
	if typeof(parser.data) != TYPE_DICTIONARY:
		return []
	return parser.data.get("dialogues", [])


func _levels_granted_by_dialogues() -> Array:
	var levels: Array = []
	for dialogue: Dictionary in _all_dialogues():
		for node_id: String in dialogue.get("nodes", {}):
			for effect: Dictionary in _effects_of(dialogue["nodes"][node_id]):
				if String(effect.get("type", "")) == "grant_access":
					levels.append(int(effect.get("level", 0)))
	return levels


func _effects_of(node: Dictionary) -> Array:
	var effects: Array = []
	effects.append_array(node.get("effects", []))
	for choice: Dictionary in node.get("choices", []):
		effects.append_array(choice.get("effects", []))
	return effects

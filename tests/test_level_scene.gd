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


# --- Помощники ----------------------------------------------------------------

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

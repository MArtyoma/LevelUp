class_name DataValidator
extends RefCounted

## Проверка файлов из `data/` до того, как игра их покажет.
##
## Владелец: лид. Менять — только вместе с `docs/data-format.md`.
##
## Зачем это вообще есть. Контент в LevelUp пишет не программист (writer — легенда
## и тексты, level designer — расстановка на карте), а ломается он молча: опечатка в `"dept_sels"`
## не падает с ошибкой, она просто даёт NPC без отдела, и заметят это через две недели
## на плейтесте. Валидатор превращает «молча сломалось» в понятную строку по-русски
## с указанием файла и id.
##
## Три уровня проверок:
##   1. Структура   — поля на месте, типы верные.
##   2. Ссылки      — каждый id, на который ссылаются, существует.
##   3. Методика    — данные пригодны для замера гипотезы (см. `check_testability`).
##      Третий уровень — не педантизм: тест из 10 вопросов для недели 9 собирается
##      ровно из этих данных, и если на вопрос есть два правильных ответа, замер
##      измеряет шум. Дешевле поймать это скриптом, чем на эксперименте.
##
## Валидатор не знает ни про Godot-сцены, ни про UI — только словари. Поэтому он
## одинаково запускается из игры, из тестов и из CI (`tools/validate_data.gd`).


## Результат проверки. `errors` — игру запускать нельзя, `warnings` — можно, но стоит посмотреть.
class Report extends RefCounted:
	var errors: PackedStringArray = PackedStringArray()
	var warnings: PackedStringArray = PackedStringArray()

	func add_error(text: String) -> void:
		errors.append(text)

	func add_warning(text: String) -> void:
		warnings.append(text)

	func is_ok() -> bool:
		return errors.is_empty()

	## Человекочитаемый вывод — то, что видит участник команды в консоли или в CI.
	func to_text() -> String:
		var lines: PackedStringArray = PackedStringArray()
		for e in errors:
			lines.append("  ОШИБКА:      " + e)
		for w in warnings:
			lines.append("  предупрежд.: " + w)
		if lines.is_empty():
			return "  данные в порядке"
		return "\n".join(lines)


## Полная проверка трёх файлов сразу. Принимает уже разобранный JSON.
static func validate_all(company: Dictionary, dialogues: Dictionary, quests: Dictionary) -> Report:
	var report := Report.new()
	_check_company(company, report)
	_check_dialogues(dialogues, company, quests, report)
	_check_quests(quests, company, report)
	_check_quests_are_obtainable(quests, dialogues, report)
	_check_testability(company, quests, dialogues, report)
	return report


# --- Уровень 1-2: структура и ссылки -----------------------------------------

static func _check_company(company: Dictionary, report: Report) -> void:
	var where := "data/company.json"

	if not company.has("company") or typeof(company["company"]) != TYPE_DICTIONARY:
		report.add_error("%s: нет блока \"company\" с названием и сферой компании" % where)
	elif not company["company"].get("name", ""):
		report.add_error("%s: у компании не заполнено поле \"name\"" % where)

	var departments: Array = company.get("departments", [])
	var employees: Array = company.get("employees", [])
	var topics: Array = company.get("topics", [])

	if departments.is_empty():
		report.add_error("%s: список \"departments\" пуст — играть не во что" % where)
	if employees.is_empty():
		report.add_error("%s: список \"employees\" пуст" % where)

	var dept_ids := _collect_ids(departments, where, "departments", report)
	var emp_ids := _collect_ids(employees, where, "employees", report)
	_collect_ids(topics, where, "topics", report)

	# Отделы: обязательные поля и руководитель, который действительно работает в отделе.
	for dept: Dictionary in departments:
		var did: String = dept.get("id", "?")
		for field in ["name", "head"]:
			if not dept.get(field, ""):
				report.add_error("%s: у отдела %s не заполнено поле \"%s\"" % [where, did, field])
		var head: String = dept.get("head", "")
		if head and not emp_ids.has(head):
			report.add_error("%s: отдел %s назначил руководителем %s, а такого сотрудника нет"
				% [where, did, head])

	# Сотрудники: обязательные поля и существующий отдел.
	for emp: Dictionary in employees:
		var eid: String = emp.get("id", "?")
		for field in ["name", "role", "department"]:
			if not emp.get(field, ""):
				report.add_error("%s: у сотрудника %s не заполнено поле \"%s\"" % [where, eid, field])
		var dept_id: String = emp.get("department", "")
		if dept_id and not dept_ids.has(dept_id):
			report.add_error("%s: сотрудник %s числится в отделе %s, которого нет в списке отделов"
				% [where, eid, dept_id])
		var boss: String = emp.get("reports_to", "")
		if boss:
			if not emp_ids.has(boss):
				report.add_error("%s: сотрудник %s подчиняется %s, а такого сотрудника нет"
					% [where, eid, boss])
			elif boss == eid:
				report.add_error("%s: сотрудник %s подчиняется сам себе" % [where, eid])

	# Руководитель отдела должен в этом отделе и работать, иначе структура нечитаема.
	for dept: Dictionary in departments:
		var head: String = dept.get("head", "")
		if not head or not emp_ids.has(head):
			continue
		for emp: Dictionary in employees:
			if emp.get("id", "") == head and emp.get("department", "") != dept.get("id", ""):
				report.add_error("%s: %s руководит отделом %s, но сам числится в %s"
					% [where, head, dept.get("id", "?"), emp.get("department", "?")])

	_check_hierarchy_has_no_cycles(employees, where, report)


## Цепочка «кто кому подчиняется» должна быть деревом: ровно один человек наверху
## и никаких колец. Кольцо повесит любой обход структуры, а два директора делают
## вопрос теста «кто главный в компании» неоднозначным.
static func _check_hierarchy_has_no_cycles(employees: Array, where: String, report: Report) -> void:
	var boss_of: Dictionary = {}
	for emp: Dictionary in employees:
		boss_of[emp.get("id", "")] = emp.get("reports_to", "")

	var tops: PackedStringArray = PackedStringArray()
	for eid: String in boss_of:
		if boss_of[eid] == "":
			tops.append(eid)

	if tops.is_empty() and not employees.is_empty():
		report.add_error("%s: ни у кого не пустое \"reports_to\" — значит, в иерархии кольцо" % where)
	elif tops.size() > 1:
		report.add_warning("%s: сотрудников без начальника несколько (%s). Для теста лучше, "
			% [where, ", ".join(tops)] + "когда главный в компании ровно один")

	# Обычный обход вверх с ограничением глубины: команда маленькая, хватает с запасом.
	for eid: String in boss_of:
		var seen: Dictionary = {eid: true}
		var current: String = boss_of[eid]
		var depth := 0
		while current != "" and depth < 64:
			if seen.has(current):
				report.add_error("%s: кольцо в подчинении — %s в итоге подчиняется сам себе"
					% [where, eid])
				break
			seen[current] = true
			current = boss_of.get(current, "")
			depth += 1


static func _check_dialogues(dialogues: Dictionary, company: Dictionary,
		quests: Dictionary, report: Report) -> void:
	var where := "data/dialogues.json"
	var list: Array = dialogues.get("dialogues", [])
	if list.is_empty():
		report.add_warning("%s: ни одного диалога — NPC будут молчать" % where)

	var emp_ids := _ids_of(company.get("employees", []))
	var quest_ids := _ids_of(quests.get("quests", []))
	_collect_ids(list, where, "dialogues", report)

	for dlg: Dictionary in list:
		var did: String = dlg.get("id", "?")
		var speaker: String = dlg.get("speaker", "")
		if speaker and not emp_ids.has(speaker):
			report.add_error("%s: диалог %s ведёт %s, а такого сотрудника нет" % [where, did, speaker])
		elif speaker.is_empty():
			# Диалог запускается только через NPC, а NPC находит его по speaker.
			# Без speaker до этого разговора невозможно дойти в игре.
			report.add_warning("%s: у диалога %s не указан \"speaker\" — запустить его в игре нечем"
				% [where, did])

		var nodes: Dictionary = dlg.get("nodes", {})
		if nodes.is_empty():
			report.add_error("%s: у диалога %s нет ни одной реплики" % [where, did])
			continue

		var start: String = dlg.get("start", "")
		if not nodes.has(start):
			report.add_error("%s: диалог %s начинается с реплики \"%s\", которой нет" % [where, did, start])

		# Точек входа в граф может быть две: обычный старт и `on_wrong` у дуэли,
		# куда разговор уводит при неверном ответе.
		var entry_points: PackedStringArray = PackedStringArray([start])
		if dlg.get("on_wrong", ""):
			entry_points.append(String(dlg["on_wrong"]))
		var reachable := _reachable_nodes(nodes, entry_points)
		for node_id: String in nodes:
			if not reachable.has(node_id):
				report.add_warning("%s: в диалоге %s до реплики \"%s\" невозможно дойти"
					% [where, did, node_id])

		for node_id: String in nodes:
			var node: Dictionary = nodes[node_id]
			if not node.get("text", ""):
				report.add_error("%s: реплика %s/%s пустая" % [where, did, node_id])
			for target in _targets_of(node):
				if target != "end" and not nodes.has(target):
					report.add_error("%s: реплика %s/%s ведёт на \"%s\", которой нет"
						% [where, did, node_id, target])
			for effect: Dictionary in _effects_of(node):
				_check_effect(effect, quest_ids, "%s: диалог %s/%s" % [where, did, node_id], report)

		if dlg.get("kind", "") == "duel":
			if int(dlg.get("patience", 0)) <= 0:
				report.add_error("%s: у дуэли %s не задано терпение (\"patience\")" % [where, did])
			var has_correct := false
			for node_id: String in nodes:
				for choice: Dictionary in nodes[node_id].get("choices", []):
					if bool(choice.get("correct", false)):
						has_correct = true
			if not has_correct:
				report.add_error("%s: в дуэли %s ни один ответ не помечен \"correct\": true"
					% [where, did])


## Каждый квест должен кто-то выдавать. Квест, на который не ссылается ни один
## диалог, игрок получить не сможет — он просто лежит в файле.
static func _check_quests_are_obtainable(quests: Dictionary, dialogues: Dictionary,
		report: Report) -> void:
	var offered: Dictionary = {}
	for dlg: Dictionary in dialogues.get("dialogues", []):
		for node_id: String in dlg.get("nodes", {}):
			for effect: Dictionary in _effects_of(dlg["nodes"][node_id]):
				if String(effect.get("type", "")) == "start_quest":
					offered[String(effect.get("quest", ""))] = true

	for quest: Dictionary in quests.get("quests", []):
		var qid: String = quest.get("id", "?")
		if not offered.has(qid):
			report.add_warning("data/quests.json: квест %s не выдаётся ни одним диалогом — "
				% qid + "игрок не сможет его получить")


static func _check_quests(quests: Dictionary, company: Dictionary, report: Report) -> void:
	var where := "data/quests.json"
	var list: Array = quests.get("quests", [])
	if list.is_empty():
		report.add_warning("%s: ни одного квеста" % where)

	var emp_ids := _ids_of(company.get("employees", []))
	var topic_ids := _ids_of(company.get("topics", []))
	_collect_ids(list, where, "quests", report)

	for quest: Dictionary in list:
		var qid: String = quest.get("id", "?")
		if not quest.get("title", ""):
			report.add_error("%s: у квеста %s нет названия" % [where, qid])

		var giver: String = quest.get("giver", "")
		if not giver:
			report.add_error("%s: у квеста %s не указан \"giver\" — некому его выдать" % [where, qid])
		elif not emp_ids.has(giver):
			report.add_error("%s: квест %s выдаёт %s, а такого сотрудника нет" % [where, qid, giver])

		var objectives: Array = quest.get("objectives", [])
		if objectives.is_empty():
			report.add_error("%s: у квеста %s нет ни одного шага (\"objectives\")" % [where, qid])
		var seen: Dictionary = {}
		for obj: Dictionary in objectives:
			var oid: String = obj.get("id", "")
			if not oid:
				report.add_error("%s: в квесте %s у шага нет \"id\"" % [where, qid])
			elif seen.has(oid):
				report.add_error("%s: в квесте %s два шага с id \"%s\"" % [where, qid, oid])
			seen[oid] = true
			if not obj.get("text", ""):
				report.add_error("%s: шаг %s/%s без текста — игрок не поймёт, что делать"
					% [where, qid, oid])

		for topic: String in quest.get("teaches", []):
			if not topic_ids.has(topic):
				report.add_error("%s: квест %s учит теме %s, которой нет в company.json"
					% [where, qid, topic])


# --- Уровень 3: пригодность данных для замера гипотезы ------------------------

## Проверки, которых нет в обычной игре, но без которых у нас нет курсовой работы.
##
## Гипотеза проверяется тестом из 10 вопросов «кто за что отвечает» (устав, метрика 1).
## Вопросы берутся из `topics`. Значит, данные обязаны удовлетворять трём условиям:
## у каждого вопроса ровно один верный ответ, каждый отдел хоть чем-то представлен
## в тесте, и всё, что спрашивается, игра действительно показывает.
static func _check_testability(company: Dictionary, quests: Dictionary,
		dialogues: Dictionary, report: Report) -> void:
	var where := "data/company.json"
	var topics: Array = company.get("topics", [])
	var employees: Array = company.get("employees", [])
	var emp_ids := _ids_of(employees)

	if topics.size() < 10:
		report.add_warning("%s: тем всего %d. Тест для замера — 10 вопросов, тем нужно не меньше"
			% [where, topics.size()])

	var by_question: Dictionary = {}
	var by_title: Dictionary = {}
	for topic: Dictionary in topics:
		var tid: String = topic.get("id", "?")
		var owner: String = topic.get("owner", "")
		if not owner:
			report.add_error("%s: у темы %s не указан \"owner\" — не с чем сверять ответ в тесте"
				% [where, tid])
		elif not emp_ids.has(owner):
			report.add_error("%s: тема %s закреплена за %s, а такого сотрудника нет" % [where, tid, owner])

		var question: String = topic.get("question", "")
		if not question:
			report.add_error("%s: у темы %s нет формулировки вопроса для теста" % [where, tid])
		elif by_question.has(question):
			report.add_error("%s: темы %s и %s задают один и тот же вопрос — в тесте у него "
				% [where, by_question[question], tid] + "окажется два разных правильных ответа")
		else:
			by_question[question] = tid

		var title: String = topic.get("title", "")
		if title:
			if by_title.has(title):
				report.add_error("%s: темы %s и %s называются одинаково (\"%s\") — игрок не различит"
					% [where, by_title[title], tid, title])
			by_title[title] = tid

	# Каждый отдел должен отвечать хотя бы за одну тему, иначе он декорация:
	# в тесте его не спросят, и на гипотезу он не работает.
	var dept_of: Dictionary = {}
	for emp: Dictionary in employees:
		dept_of[emp.get("id", "")] = emp.get("department", "")
	var covered: Dictionary = {}
	for topic: Dictionary in topics:
		covered[dept_of.get(topic.get("owner", ""), "")] = true
	for dept: Dictionary in company.get("departments", []):
		if not covered.has(dept.get("id", "")):
			report.add_warning("%s: отдел %s не отвечает ни за одну тему — в тест он не попадёт"
				% [where, dept.get("id", "?")])

	# И обратная сторона: всё, что спрашивается в тесте, игра должна где-то показать.
	var taught: Dictionary = {}
	for quest: Dictionary in quests.get("quests", []):
		for topic_id: String in quest.get("teaches", []):
			taught[topic_id] = true
	for dlg: Dictionary in dialogues.get("dialogues", []):
		for topic_id: String in dlg.get("teaches", []):
			taught[topic_id] = true
	for topic: Dictionary in topics:
		if not taught.has(topic.get("id", "")):
			report.add_warning("data/quests.json: тему %s не преподаёт ни один квест и ни один "
				% topic.get("id", "?") + "диалог, а в тесте она будет — спросим то, чего не показали")


# --- Мелкие помощники ---------------------------------------------------------

## Действия, которые понимает DialogueRunner._apply_effect. Списки обязаны
## совпадать: новое действие добавляется в оба места сразу.
const KNOWN_EFFECTS := ["start_quest", "complete_objective", "grant_access",
	"set_flag", "finish_game"]


static func _check_effect(effect: Dictionary, quest_ids: Dictionary, where: String,
		report: Report) -> void:
	var type: String = effect.get("type", "")
	if not KNOWN_EFFECTS.has(type):
		report.add_error("%s: неизвестное действие \"%s\". Доступны: %s"
			% [where, type, ", ".join(KNOWN_EFFECTS)])
		return
	if type in ["start_quest", "complete_objective"]:
		var qid: String = effect.get("quest", "")
		if not quest_ids.has(qid):
			report.add_error("%s: действие \"%s\" ссылается на квест %s, которого нет"
				% [where, type, qid])


## Собирает id из списка, попутно ругаясь на пустые и повторяющиеся.
static func _collect_ids(list: Array, where: String, section: String, report: Report) -> Dictionary:
	var ids: Dictionary = {}
	for index in list.size():
		var item = list[index]
		if typeof(item) != TYPE_DICTIONARY:
			report.add_error("%s: в \"%s\" элемент №%d — не объект" % [where, section, index + 1])
			continue
		var id: String = item.get("id", "")
		if not id:
			report.add_error("%s: в \"%s\" у элемента №%d нет \"id\"" % [where, section, index + 1])
		elif ids.has(id):
			report.add_error("%s: в \"%s\" два элемента с id \"%s\"" % [where, section, id])
		else:
			ids[id] = true
	return ids


static func _ids_of(list: Array) -> Dictionary:
	var ids: Dictionary = {}
	for item in list:
		if typeof(item) == TYPE_DICTIONARY and item.get("id", ""):
			ids[item["id"]] = true
	return ids


## Куда может увести реплика: `next` и все `next` из вариантов ответа.
static func _targets_of(node: Dictionary) -> PackedStringArray:
	var targets: PackedStringArray = PackedStringArray()
	if node.get("next", ""):
		targets.append(node["next"])
	for choice: Dictionary in node.get("choices", []):
		if choice.get("next", ""):
			targets.append(choice["next"])
	return targets


static func _effects_of(node: Dictionary) -> Array:
	var effects: Array = []
	effects.append_array(node.get("effects", []))
	for choice: Dictionary in node.get("choices", []):
		effects.append_array(choice.get("effects", []))
	return effects


## Обход диалога от точек входа — ищем ветки, до которых нельзя дойти.
static func _reachable_nodes(nodes: Dictionary, entry_points: PackedStringArray) -> Dictionary:
	var reached: Dictionary = {}
	var queue: Array[String] = []
	for entry in entry_points:
		if nodes.has(entry):
			queue.append(entry)
	while not queue.is_empty():
		var current: String = queue.pop_back()
		if reached.has(current):
			continue
		reached[current] = true
		for target in _targets_of(nodes[current]):
			if nodes.has(target) and not reached.has(target):
				queue.append(target)
	return reached

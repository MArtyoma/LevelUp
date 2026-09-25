extends TestCase

## Тесты проверки данных.
##
## Именно эти тесты защищают самое уязвимое место проекта: контент пишут люди,
## которые не пишут код, и ошибка в данных должна ловиться скриптом, а не глазами
## на плейтесте за неделю до защиты.


func _company(employees: Array, departments: Array = [], topics: Array = []) -> Dictionary:
	return {
		"company": {"id": "test", "name": "Тест"},
		"departments": departments,
		"employees": employees,
		"topics": topics,
	}


func test_real_data_is_valid() -> void:
	# Главный тест файла: то, что лежит в data/, обязано проходить проверку.
	# Если он красный — в master попали сломанные данные.
	var company := _load("res://data/company.json")
	var dialogues := _load("res://data/dialogues.json")
	var quests := _load("res://data/quests.json")
	var report := DataValidator.validate_all(company, dialogues, quests)
	equals(report.errors.size(), 0, "данные в data/ содержат ошибки:\n" + report.to_text())


func test_employee_in_missing_department() -> void:
	var company := _company(
		[{"id": "emp_a", "name": "А", "role": "роль", "department": "dept_none"}],
		[{"id": "dept_real", "name": "Отдел", "head": "emp_a"}])
	var report := DataValidator.validate_all(company, {}, {})
	contains_error(report, "dept_none", "отдел-призрак не пойман")


func test_head_from_another_department() -> void:
	var company := _company(
		[
			{"id": "emp_a", "name": "А", "role": "роль", "department": "dept_one"},
			{"id": "emp_b", "name": "Б", "role": "роль", "department": "dept_two",
				"reports_to": "emp_a"},
		],
		[
			{"id": "dept_one", "name": "Раз", "head": "emp_a"},
			{"id": "dept_two", "name": "Два", "head": "emp_a"},
		])
	var report := DataValidator.validate_all(company, {}, {})
	contains_error(report, "руководит отделом", "руководитель чужого отдела не пойман")


func test_cycle_in_hierarchy() -> void:
	var company := _company([
		{"id": "emp_a", "name": "А", "role": "роль", "department": "d", "reports_to": "emp_b"},
		{"id": "emp_b", "name": "Б", "role": "роль", "department": "d", "reports_to": "emp_a"},
	], [{"id": "d", "name": "Отдел", "head": "emp_a"}])
	var report := DataValidator.validate_all(company, {}, {})
	contains_error(report, "кольц", "кольцо в подчинении не поймано")


func test_two_topics_with_same_question() -> void:
	# Самая опасная ошибка для курсовой: у вопроса теста два правильных ответа.
	var company := _company(
		[
			{"id": "emp_a", "name": "А", "role": "роль", "department": "d"},
			{"id": "emp_b", "name": "Б", "role": "роль", "department": "d", "reports_to": "emp_a"},
		],
		[{"id": "d", "name": "Отдел", "head": "emp_a"}],
		[
			{"id": "t1", "title": "отпуск", "question": "К кому идти за отпуском?",
				"owner": "emp_a"},
			{"id": "t2", "title": "отпуск-2", "question": "К кому идти за отпуском?",
				"owner": "emp_b"},
		])
	var report := DataValidator.validate_all(company, {}, {})
	contains_error(report, "один и тот же вопрос", "дубль вопроса теста не пойман")


func test_dialogue_points_to_missing_node() -> void:
	var dialogues := {"dialogues": [{
		"id": "dlg", "speaker": "", "start": "a",
		"nodes": {"a": {"text": "раз", "next": "b_которого_нет"}},
	}]}
	var report := DataValidator.validate_all(_company([]), dialogues, {})
	contains_error(report, "b_которого_нет", "ссылка на несуществующую реплику не поймана")


func test_effect_points_to_missing_quest() -> void:
	var dialogues := {"dialogues": [{
		"id": "dlg", "speaker": "", "start": "a",
		"nodes": {"a": {"text": "раз", "next": "end",
			"effects": [{"type": "start_quest", "quest": "q_нет"}]}},
	}]}
	var report := DataValidator.validate_all(_company([]), dialogues, {})
	contains_error(report, "q_нет", "выдача несуществующего квеста не поймана")


func test_quest_without_giver() -> void:
	var quests := {"quests": [{
		"id": "q", "title": "Квест", "objectives": [{"id": "o", "text": "шаг"}],
	}]}
	var report := DataValidator.validate_all(_company([]), {}, quests)
	contains_error(report, "giver", "квест без выдающего не пойман")


func test_duel_without_correct_answer() -> void:
	var dialogues := {"dialogues": [{
		"id": "duel", "kind": "duel", "patience": 2, "speaker": "", "start": "a",
		"nodes": {"a": {"text": "вопрос", "choices": [{"text": "ответ", "next": "end"}]}},
	}]}
	var report := DataValidator.validate_all(_company([]), dialogues, {})
	contains_error(report, "correct", "дуэль без верного ответа не поймана")


func test_effect_closes_missing_step() -> void:
	# Реплика звучит, шаг не закрывается никогда — и никто не видит почему.
	var quests := {"quests": [{"id": "q", "title": "Квест", "giver": "",
		"objectives": [{"id": "obj_real", "text": "шаг"}]}]}
	var dialogues := {"dialogues": [{
		"id": "dlg", "speaker": "", "start": "a",
		"nodes": {"a": {"text": "раз", "next": "end", "effects": [
			{"type": "complete_objective", "quest": "q", "objective": "obj_опечатка"}]}},
	}]}
	var report := DataValidator.validate_all(_company([]), dialogues, quests)
	contains_error(report, "obj_опечатка", "опечатка в id шага не поймана")


func test_requirement_typo_is_caught() -> void:
	# `quest_activ` вместо `quest_active` иначе значит «условия нет»:
	# вариант виден всегда, и игрок видит подсказку раньше времени.
	var dialogues := {"dialogues": [{
		"id": "dlg", "speaker": "", "start": "a",
		"nodes": {"a": {"text": "раз", "choices": [
			{"text": "вариант", "next": "end", "requires": {"quest_activ": "q"}},
			{"text": "другой", "next": "end", "requires": {"quest_done": "q_нет"}},
		]}},
	}]}
	var report := DataValidator.validate_all(_company([]), dialogues, {})
	contains_error(report, "quest_activ", "опечатка в названии условия не поймана")
	contains_error(report, "q_нет", "условие на несуществующий квест не поймано")


func test_duel_on_wrong_points_to_missing_node() -> void:
	var dialogues := {"dialogues": [{
		"id": "duel", "kind": "duel", "patience": 2, "on_wrong": "agian", "speaker": "",
		"start": "a", "nodes": {"a": {"text": "вопрос",
			"choices": [{"text": "ответ", "next": "end", "correct": true}]}},
	}]}
	var report := DataValidator.validate_all(_company([]), dialogues, {})
	contains_error(report, "agian", "опечатка в on_wrong не поймана")


func test_bad_palette_is_caught() -> void:
	var company := _company(
		[{"id": "emp_a", "name": "А", "role": "роль", "department": "d", "palette": "зелёный"}],
		[{"id": "d", "name": "Отдел", "head": "emp_a"}])
	var report := DataValidator.validate_all(company, {}, {})
	contains_error(report, "зелёный", "цвет не в формате #rrggbb не пойман")


func _load(path: String) -> Dictionary:
	var parser := JSON.new()
	parser.parse(FileAccess.get_file_as_string(path))
	return parser.data if typeof(parser.data) == TYPE_DICTIONARY else {}

extends TestCase

## Тесты журнала квестов — единственного места, где живёт состояние прохождения.

func before_each() -> void:
	QuestLog.reset()


func test_quest_starts_once() -> void:
	check(QuestLog.start_quest("q_onboarding"), "квест не выдался")
	check(not QuestLog.start_quest("q_onboarding"), "квест выдался второй раз")
	check(QuestLog.is_active("q_onboarding"), "квест не стал активным")


func test_unknown_quest_is_ignored() -> void:
	check(not QuestLog.start_quest("q_такого_нет"), "выдался квест, которого нет в данных")


func test_objectives_close_in_order() -> void:
	QuestLog.start_quest("q_onboarding")
	# Второй шаг раньше первого закрыться не должен: игрок не может получить
	# ноутбук до того, как забрал документы.
	check(not QuestLog.complete_objective("q_onboarding", "obj_laptop"),
		"второй шаг закрылся раньше первого")
	check(QuestLog.complete_objective("q_onboarding", "obj_docs"), "первый шаг не закрылся")
	equals(QuestLog.next_objective_id("q_onboarding"), "obj_laptop", "не тот следующий шаг")


func test_quest_completes_and_gives_access() -> void:
	QuestLog.start_quest("q_onboarding")
	QuestLog.complete_objective("q_onboarding", "obj_docs")
	QuestLog.complete_objective("q_onboarding", "obj_laptop")
	check(not QuestLog.is_completed("q_onboarding"), "квест закрылся раньше последнего шага")
	equals(QuestLog.access_level, 1, "пропуск выдан до возвращения в отдел кадров")
	QuestLog.complete_objective("q_onboarding", "obj_pass")
	check(QuestLog.is_completed("q_onboarding"), "квест не закрылся после последнего шага")
	equals(QuestLog.access_level, 2, "награда-пропуск не выдалась")


func test_access_level_never_drops() -> void:
	QuestLog.grant_access(3)
	QuestLog.grant_access(1)
	equals(QuestLog.access_level, 3, "уровень пропуска понизился")


func test_requirements() -> void:
	QuestLog.set_flag("знаком_с_охраной")
	QuestLog.start_quest("q_onboarding")

	check(QuestLog.check_requirement({}), "пустое условие должно проходить")
	check(QuestLog.check_requirement({"flag": "знаком_с_охраной"}), "отметка не сработала")
	check(not QuestLog.check_requirement({"flag": "нет_такой"}), "прошла несуществующая отметка")
	check(not QuestLog.check_requirement({"not_flag": "знаком_с_охраной"}), "not_flag наоборот")
	check(QuestLog.check_requirement({"quest_active": "q_onboarding"}), "активный квест не виден")
	check(not QuestLog.check_requirement({"quest_done": "q_onboarding"}),
		"квест считается сделанным")
	check(not QuestLog.check_requirement({"access": 5}), "прошёл недостаточный пропуск")
	# Несколько условий сразу — должны выполняться все.
	check(not QuestLog.check_requirement({"flag": "знаком_с_охраной", "access": 5}),
		"условия проверяются не все сразу")


func test_step_requirement_follows_the_order() -> void:
	# Условие `step` — «игрок сейчас на этом шаге». Им закрыт вариант «Меня прислала
	# Елена за ноутбуком»: до того как забрана папка, Ким ноутбук не выдаёт.
	check(not QuestLog.check_requirement({"step": "q_onboarding/obj_docs"}),
		"шаг невзятого квеста считается текущим")
	QuestLog.start_quest("q_onboarding")
	check(QuestLog.check_requirement({"step": "q_onboarding/obj_docs"}), "первый шаг не текущий")
	check(not QuestLog.check_requirement({"step": "q_onboarding/obj_laptop"}),
		"второй шаг стал текущим раньше первого")
	QuestLog.complete_objective("q_onboarding", "obj_docs")
	check(QuestLog.check_requirement({"step": "q_onboarding/obj_laptop"}),
		"второй шаг не стал текущим")
	check(not QuestLog.check_requirement({"step": "мусор"}), "кривая запись шага прошла проверку")


func test_state_survives_save_and_load() -> void:
	QuestLog.start_quest("q_onboarding")
	QuestLog.complete_objective("q_onboarding", "obj_docs")
	QuestLog.set_flag("onboarding_taken")
	var snapshot := QuestLog.to_dict()

	QuestLog.reset()
	equals(QuestLog.access_level, 1, "reset не сбросил пропуск")

	QuestLog.from_dict(snapshot)
	check(QuestLog.is_active("q_onboarding"), "квест не восстановился")
	equals(QuestLog.next_objective_id("q_onboarding"), "obj_laptop", "шаг не восстановился")
	check(QuestLog.has_flag("onboarding_taken"), "отметка не восстановилась")

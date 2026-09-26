extends TestCase

## Тесты постоянного интерфейса: что игрок видит, не открывая журнал.

var _ui: CanvasLayer


func before_each() -> void:
	QuestLog.reset()
	_ui = (load("res://src/ui/game_ui.tscn") as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(_ui)


func after_each() -> void:
	_ui.free()
	QuestLog.reset()


func _tracker_text() -> String:
	var lines: PackedStringArray = []
	for label: Label in _ui.get_node("Tracker").get_children():
		lines.append(label.text)
	return "\n".join(lines)


func _toggle_journal() -> void:
	var event := InputEventAction.new()
	event.action = "toggle_quests"
	event.pressed = true
	_ui._unhandled_input(event)


func test_journal_does_not_cover_the_office() -> void:
	# Раньше журнал висел в углу постоянно и закрывал людей в соседнем кабинете.
	check(not (_ui.get_node("QuestPanel") as Control).visible,
		"журнал должен быть закрыт, пока его не открыли")
	check(_tracker_text().contains("«!»"), "без заданий строка в углу должна подсказывать про «!»")


func test_tracker_follows_the_current_step() -> void:
	QuestLog.start_quest("q_onboarding")
	check(_tracker_text().contains(QuestLog.next_objective_text("q_onboarding")),
		"в углу нет текущего шага, а есть «%s»" % _tracker_text())
	QuestLog.complete_objective("q_onboarding", "obj_docs")
	check(_tracker_text().contains("ноутбук"), "строка в углу не сменилась на следующий шаг")


func test_journal_opens_and_hides_the_tracker() -> void:
	_toggle_journal()
	check((_ui.get_node("QuestPanel") as Control).visible, "J не открыл журнал")
	check(not (_ui.get_node("Tracker") as Control).visible,
		"при открытом журнале строка в углу дублирует его")
	_toggle_journal()
	check(not (_ui.get_node("QuestPanel") as Control).visible, "J не закрыл журнал")
	check((_ui.get_node("Tracker") as Control).visible, "строка в углу не вернулась")

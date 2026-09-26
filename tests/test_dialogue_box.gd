extends TestCase

## Тесты окна разговора: то, что игрок делает клавиатурой.
##
## Окно добавляется в сцену раннера: фокус у кнопок бывает только в дереве.
## Кадры здесь не идут, поэтому кнопки, удалённые через queue_free, остаются
## в дереве до конца теста — ровно как в игре до конца кадра. На этом и был баг.

var _box: CanvasLayer


func before_each() -> void:
	DialogueRunner.stop()
	QuestLog.reset()
	_box = (load("res://src/ui/dialogue_box.tscn") as PackedScene).instantiate()
	# Печать по буквам выключена: кадры в тестах не идут, реплика не допечаталась бы.
	# Сама печать — в test_typing_*.
	_box.letters_per_second = 0.0
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(_box)


func after_each() -> void:
	DialogueRunner.stop()
	_box.free()


func _focused_choice() -> Button:
	var owner := _box.get_viewport().gui_get_focus_owner() as Button
	if owner == null or owner.is_queued_for_deletion():
		return null
	return owner


func _interact() -> void:
	var event := InputEventAction.new()
	event.action = "interact"
	event.pressed = true
	_box._unhandled_input(event)


func test_second_set_of_choices_gets_focus() -> void:
	# «А где ИТ-отдел?» возвращает к тем же вариантам. Раньше фокус уходил
	# на старую, уже удаляемую кнопку, и выбрать ответ с клавиатуры было нельзя.
	DialogueRunner.start("dlg_mironova")
	DialogueRunner.advance()
	check(_focused_choice() != null, "на первых вариантах нет выделенного")
	DialogueRunner.choose(2)          # «А где ИТ-отдел?»
	DialogueRunner.advance()          # обратно к вариантам
	var focused := _focused_choice()
	check(focused != null, "на повторных вариантах выделение пропало — выбрать нечем")
	if focused != null:
		equals(focused.text, "Понял, иду.", "выделен не первый вариант")


func test_interact_key_picks_the_highlighted_choice() -> void:
	# В README: «E — говорить». Игрок жмёт E и на вариантах ответа.
	DialogueRunner.start("dlg_mironova")
	DialogueRunner.advance()
	_interact()
	check(QuestLog.is_active("q_onboarding"), "E на варианте «Понял, иду» не выбрал его")


func test_typing_hides_choices_until_the_line_is_read() -> void:
	# Варианты под недопечатанной репликой читают вместо реплики — а реплика
	# и есть то, чему игра учит.
	_box.letters_per_second = 50.0
	DialogueRunner.start("dlg_mironova")
	DialogueRunner.advance()                      # реплика с вариантами
	var choices: Control = _box.get_node("Root/Panel/Body/Layout/Choices")
	check(not choices.visible, "варианты видны, пока реплика ещё печатается")

	_box._process(0.2)
	var text: Label = _box.get_node("Root/Panel/Body/Layout/Text")
	check(text.visible_characters > 0 and text.visible_characters < text.text.length(),
		"за 0.2 с должна напечататься часть реплики, а видно %d букв" % text.visible_characters)

	_interact()                                   # первое E — дописать
	check(choices.visible, "E не дописал реплику: вариантов не видно")
	check(not QuestLog.is_active("q_onboarding"), "E во время печати сразу выбрал ответ")
	check(_focused_choice() != null, "после печати на вариантах нет выделенного")
	_interact()                                   # второе E — выбрать
	check(QuestLog.is_active("q_onboarding"), "второе E не выбрало вариант")


func test_duel_line_is_shown_at_once() -> void:
	# В дуэли идёт время на ответ: ждать печать нечестно.
	_box.letters_per_second = 50.0
	DialogueRunner.start("dlg_pavlov")
	var text: Label = _box.get_node("Root/Panel/Body/Layout/Text")
	equals(text.visible_characters, -1, "в дуэли реплика должна появиться сразу целиком")
	check((_box.get_node("Root/Panel/Body/Layout/Choices") as Control).visible,
		"в дуэли варианты должны быть видны сразу")

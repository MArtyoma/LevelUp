extends TestCase

## Тесты разговоров: обычного прохода по графу и дуэли согласования (D-002).
##
## Грабли, на которые здесь легко наступить: **лямбда в GDScript захватывает
## локальные переменные по значению.** `var outcome := ""` плюс `outcome = x`
## внутри лямбды меняет копию, а снаружи остаётся пустая строка, и тест врёт.
## Поэтому результат сигналов собираем в массив: массивы передаются по ссылке.

func before_each() -> void:
	DialogueRunner.stop()
	QuestLog.reset()


func test_dialogue_gives_quest() -> void:
	check(DialogueRunner.start("dlg_mironova"), "диалог не запустился")
	DialogueRunner.advance()          # приветствие -> предложение
	DialogueRunner.choose(0)          # «Понял, иду»
	check(QuestLog.is_active("q_onboarding"), "квест не выдался из диалога")
	check(QuestLog.has_flag("onboarding_taken"), "отметка из диалога не поставилась")


func test_unknown_dialogue_does_not_crash() -> void:
	check(not DialogueRunner.start("dlg_которого_нет"), "запустился несуществующий диалог")
	check(not DialogueRunner.is_running, "движок диалогов остался в работе")


func test_choice_hidden_by_requirement() -> void:
	# Вариант «Уже занимаюсь» показывается только тем, кто уже взял квест.
	var sizes: Array = []
	var handler := func(choices: Array, _limit: float): sizes.append(choices.size())
	EventBus.dialogue_choices_offered.connect(handler)

	DialogueRunner.start("dlg_mironova")
	DialogueRunner.advance()

	DialogueRunner.stop()
	QuestLog.set_flag("onboarding_taken")
	DialogueRunner.start("dlg_mironova")
	DialogueRunner.advance()

	EventBus.dialogue_choices_offered.disconnect(handler)
	equals(sizes.size(), 2, "варианты предлагались не дважды")
	# До отметки: «Понял, иду» и «А где ИТ-отдел?». После: «А где...» и «Уже занимаюсь».
	equals(sizes[0], 2, "не то число доступных вариантов до отметки")
	equals(sizes[1], 2, "не то число доступных вариантов после отметки")


func test_duel_lost_after_patience_runs_out() -> void:
	var outcome: Array = []
	var handler := func(_id: String, result: String): outcome.append(result)
	EventBus.dialogue_finished.connect(handler)

	DialogueRunner.start("dlg_pavlov")
	DialogueRunner.choose(1)   # неверно, терпение 3 -> 2
	DialogueRunner.choose(1)   # неверно, 2 -> 1
	DialogueRunner.choose(1)   # неверно, 1 -> 0, разговор проигран

	EventBus.dialogue_finished.disconnect(handler)
	equals(outcome.back(), "duel_lost", "дуэль не закончилась проигрышем")
	check(not QuestLog.is_active("q_first_task"), "проигранная дуэль всё равно выдала квест")


func test_duel_won_gives_quest() -> void:
	var outcome: Array = []
	var handler := func(_id: String, result: String): outcome.append(result)
	EventBus.dialogue_finished.connect(handler)

	DialogueRunner.start("dlg_pavlov")
	DialogueRunner.choose(0)   # верный ответ
	DialogueRunner.advance()   # реплика «Годится» -> конец

	EventBus.dialogue_finished.disconnect(handler)
	equals(outcome.back(), "duel_won", "дуэль не засчиталась выигранной")
	check(QuestLog.is_active("q_first_task"), "квест за выигранную дуэль не выдался")


func test_full_chain_finishes_game() -> void:
	# Сквозной проход: то же, что сделает живой игрок, только без ходьбы.
	# Этот тест — страховка вертикального среза: если он красный, цепочка
	# «поговорил -> взял квест -> закрыл -> получил пропуск» где-то порвалась.
	var finished: Array = []
	var handler := func(reason: String): finished.append(reason)
	EventBus.game_finished.connect(handler)

	DialogueRunner.start("dlg_mironova")
	DialogueRunner.advance()
	DialogueRunner.choose(0)
	DialogueRunner.stop()

	QuestLog.complete_objective("q_onboarding", "obj_docs")   # папка на столе

	DialogueRunner.start("dlg_kim")
	DialogueRunner.choose(0)
	DialogueRunner.advance()
	DialogueRunner.stop()

	check(QuestLog.is_completed("q_onboarding"), "первый квест не закрылся")
	equals(QuestLog.access_level, 2, "пропуск второго уровня не выдан — дверь дирекции закрыта")

	DialogueRunner.start("dlg_koroleva")
	DialogueRunner.choose(0)
	DialogueRunner.stop()

	EventBus.game_finished.disconnect(handler)
	equals(finished.back(), "completed", "прохождение не засчиталось законченным")

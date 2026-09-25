class_name TestCase
extends RefCounted

## Основа для тестов. Своя, на тридцать строк, вместо внешней библиотеки.
##
## Причина простая: любая зависимость — это то, что каждый в команде должен
## поставить себе руками, и то, что однажды не поставится в CI. Нам нужен
## запуск тестов, а не фреймворк; когда понадобится больше — возьмём GUT.
##
## Как писать тест: наследуйтесь от TestCase, назовите метод с `test_`, внутри
## вызывайте `check` и `equals`. Всё, что начинается с `test_`, запустится само.

var failures: PackedStringArray = PackedStringArray()

## Вызывается перед каждым тестом. Здесь сбрасывают общее состояние.
func before_each() -> void:
	pass


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func equals(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: ожидалось %s, получено %s" % [message, expected, actual])


## Проверка, что в списке ошибок валидатора есть сообщение с таким куском текста.
## Сравниваем по фрагменту, а не целиком: формулировки ошибок мы ещё будем править,
## и тест не должен падать от запятой в тексте.
func contains_error(report: DataValidator.Report, fragment: String, message: String) -> void:
	for error in report.errors:
		if error.contains(fragment):
			return
	failures.append("%s: среди ошибок нет ни одной со словами «%s». Есть: %s"
		% [message, fragment, ", ".join(report.errors)])

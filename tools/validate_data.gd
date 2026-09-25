extends SceneTree

## Проверка файлов data/ без запуска игры.
##
##     godot --headless --script tools/validate_data.gd
##     godot --headless --script tools/validate_data.gd --data-dir=../private-data
##
## Возвращает код 0, если ошибок нет, и 1, если есть — по этому коду CI на GitHub
## не пускает в master сломанные данные. Запускать полезно и руками: writer правит
## JSON и за пять секунд узнаёт, что забыл запятую, — вместо того чтобы узнать это
## от лида через два дня.
##
## Намеренно не использует GameData: валидатору не нужен ни один узел игры,
## поэтому он работает даже если игра не запускается вовсе.

func _initialize() -> void:
	var dir := "res://data"
	for argument in OS.get_cmdline_args():
		if argument.begins_with("--data-dir="):
			dir = argument.trim_prefix("--data-dir=")

	print("Проверяю данные в %s" % dir)

	var report := DataValidator.Report.new()
	var company := _read(dir.path_join("company.json"), report)
	var dialogues := _read(dir.path_join("dialogues.json"), report)
	var quests := _read(dir.path_join("quests.json"), report)

	if report.is_ok():
		var check := DataValidator.validate_all(company, dialogues, quests)
		report.errors.append_array(check.errors)
		report.warnings.append_array(check.warnings)

	print(report.to_text())
	if report.is_ok():
		print("\nОшибок нет%s." % ("" if report.warnings.is_empty()
			else ", но есть %d предупреждени(я/й)" % report.warnings.size()))
		quit(0)
	else:
		print("\nОшибок: %d. Игра с такими данными не запустится." % report.errors.size())
		quit(1)


func _read(path: String, report: DataValidator.Report) -> Dictionary:
	if not FileAccess.file_exists(path):
		report.add_error("файл %s не найден" % path)
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		report.add_error("%s, строка %d: %s (чаще всего это лишняя или забытая запятая)"
			% [path, parser.get_error_line(), parser.get_error_message()])
		return {}
	if typeof(parser.data) != TYPE_DICTIONARY:
		report.add_error("%s: на верхнем уровне должен быть объект { ... }" % path)
		return {}
	return parser.data

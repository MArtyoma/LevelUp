extends Node

## Звуки и музыка.
##
## Владелец: лид. Сами звуки — artist (`assets/sfx/`, `assets/music/`).
##
## Как интерфейс, про игру знает только через EventBus: квесты не знают, что у них
## есть звук, а звук не лезет в квесты. Прямо сюда обращаются двое — окно разговора
## (щелчки по вариантам ответа) и игрок (шаги): у этих событий нет сигнала в шине,
## и заводить сигнал на каждый шаг шина запрещает.
##
## **Файлы ищутся по имени, как картинки в `OwnArt`:**
##
##   assets/sfx/<имя>.wav                звук, который выбрал человек
##   assets/sfx/<имя>_placeholder.wav    черновик нейросети или sfxr (tools/audio/)
##   assets/sfx/<имя>_0.wav, <имя>_1 ... варианты — играется случайный (шаги)
##
## Файл человека важнее черновика: положил `quest_done.wav` рядом с
## `quest_done_placeholder.wav` — в игре сразу он. Музыка — `assets/music/<имя>.ogg`
## по тем же правилам. **Файла нет — тишина, а не ошибка:** игра обязана работать
## и без звука, на замере он может быть выключен.

const SFX_DIR := "res://assets/sfx/"
const MUSIC_DIR := "res://assets/music/"
const MAX_VARIANTS := 8

## Сколько звуков может звучать одновременно. Больше — самый старый обрывается.
const VOICES := 6

## Громкость звуков относительно друг друга, dB. Писки sfxr громкие по природе
## (квадратная волна на полной громкости), поэтому они тише нуля; шаги — фон.
## Общая громкость — шины Music и SFX в default_bus_layout.tres.
const VOLUME_DB := {
	"talk": -14.0,
	"ui_select": -18.0,
	"ui_confirm": -14.0,
	"ui_cancel": -14.0,
	"journal": -18.0,
	"door_denied": -12.0,
	"objective": -12.0,
	"quest_new": -10.0,
	"quest_done": -8.0,
	"access_up": -10.0,
	"duel_miss": -10.0,
	"duel_lost": -10.0,
	"step_carpet": -12.0,
	"step_tile": -14.0,
}

## Если несколько событий пришли разом (выполнил цель — закрылся квест — выдали
## пропуск), играет одно, самое важное. Три звука подряд за один кадр — каша.
const PRIORITY := {
	"objective": 1,
	"quest_new": 2,
	"access_up": 2,
	"quest_done": 3,
}

## Высота «голоса» NPC в разговоре. Берётся из id, а не случайно: у Кима всегда
## один и тот же голос, и его узнаёшь, не глядя на портрет.
const VOICE_PITCH_MIN := 0.8
const VOICE_PITCH_MAX := 1.3

const MUSIC_FADE_SECONDS := 0.8
const SILENT_DB := -40.0

## Что играет сейчас: имя музыки ("" — тишина) и последние звуки. Нужно тестам
## и для отладки: звук в headless не услышишь.
var music_name: String = ""
var recent: Array[String] = []

var _cache: Dictionary = {}
var _last_variant: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _music_tween: Tween
var _music_before_duel: String = ""
var _voice_pitch: float = 1.0
var _pending: String = ""

# Без экрана (тесты, проверка данных) звук никто не услышит, а играющий в момент
# выхода звук Godot записывает в утечки — лог тестов в CI краснеет на пустом месте.
# Поэтому в headless звуки только запоминаются в `recent`, но не играют.
var _silent: bool = DisplayServer.get_name() == "headless"


func _ready() -> void:
	# Звук паузы не боится: меню паузы тоже щёлкает.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = _bus("SFX")
		add_child(player)
		_pool.append(player)
	_music = AudioStreamPlayer.new()
	_music.bus = _bus("Music")
	add_child(_music)
	_connect_to_bus()


func _connect_to_bus() -> void:
	EventBus.dialogue_started.connect(_on_dialogue_started)
	EventBus.dialogue_line_shown.connect(func(_text: String, _speaker: String):
		play("talk", _voice_pitch))
	EventBus.duel_patience_changed.connect(_on_patience)
	EventBus.dialogue_finished.connect(_on_dialogue_finished)
	EventBus.quest_started.connect(func(_id: String): _queue("quest_new"))
	EventBus.quest_objective_completed.connect(func(_quest: String, _objective: String):
		_queue("objective"))
	EventBus.quest_completed.connect(func(_id: String): _queue("quest_done"))
	EventBus.access_level_changed.connect(func(_level: int): _queue("access_up"))
	EventBus.access_denied.connect(func(_required: int, _current: int):
		play("door_denied"))


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("toggle_mute"):
		return
	var master := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(master, not AudioServer.is_bus_mute(master))
	EventBus.hint_shown.emit("Звук выключен (M)" if AudioServer.is_bus_mute(master)
		else "Звук включён (M)")
	get_viewport().set_input_as_handled()


# --- Звуки --------------------------------------------------------------------

## Сыграть звук по имени. `pitch` — высота: 1.0 как в файле.
func play(sound_name: String, pitch: float = 1.0) -> void:
	var stream := _pick(sound_name)
	_remember(sound_name)
	if stream == null or _silent:
		return
	var player := _free_player()
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = float(VOLUME_DB.get(sound_name, -10.0))
	player.play()


## Шаг игрока. `surface` — из тайлсета (слой данных `surface`): "carpet", "tile".
## Высота чуть гуляет: одинаковые шаги подряд звучат как метроном.
func footstep(surface: String) -> void:
	play("step_" + (surface if not surface.is_empty() else "carpet"),
		randf_range(0.92, 1.08))


## Голос сотрудника: высота из его id, всегда одна и та же.
static func voice_pitch(employee_id: String) -> float:
	if employee_id.is_empty():
		return 1.0
	var t := float(absi(employee_id.hash()) % 1000) / 999.0
	return lerpf(VOICE_PITCH_MIN, VOICE_PITCH_MAX, t)


func _queue(sound_name: String) -> void:
	if _pending.is_empty():
		_flush_pending.call_deferred()
	if int(PRIORITY.get(sound_name, 0)) >= int(PRIORITY.get(_pending, 0)):
		_pending = sound_name


func _flush_pending() -> void:
	var sound_name := _pending
	_pending = ""
	if not sound_name.is_empty():
		play(sound_name)


func _remember(sound_name: String) -> void:
	recent.append(sound_name)
	if recent.size() > 16:
		recent.pop_front()


## Свободный проигрыватель, а если все заняты — тот, что играет дольше всех.
func _free_player() -> AudioStreamPlayer:
	var oldest := _pool[0]
	for player in _pool:
		if not player.playing:
			return player
		if player.get_playback_position() > oldest.get_playback_position():
			oldest = player
	return oldest


## Случайный вариант, но не тот же, что в прошлый раз.
func _pick(sound_name: String) -> AudioStream:
	var variants := _variants(SFX_DIR, sound_name, "wav")
	if variants.is_empty():
		return null
	var index := randi() % variants.size()
	if variants.size() > 1 and index == int(_last_variant.get(sound_name, -1)):
		index = (index + 1) % variants.size()
	_last_variant[sound_name] = index
	return variants[index]


## Все файлы звука. Если человек положил хоть один свой вариант — черновики
## этого звука больше не играют, даже если своих вариантов меньше.
func _variants(folder: String, sound_name: String, extension: String) -> Array:
	var key := folder + sound_name
	if _cache.has(key):
		return _cache[key]
	var result: Array = []
	for suffix: String in ["", "_placeholder"]:
		var names: Array[String] = [sound_name]
		for i in MAX_VARIANTS:
			names.append("%s_%d" % [sound_name, i])
		for base in names:
			var path := "%s%s%s.%s" % [folder, base, suffix, extension]
			if ResourceLoader.exists(path):
				result.append(load(path))
		if not result.is_empty():
			break
	_cache[key] = result
	return result


func _bus(bus_name: String) -> StringName:
	return StringName(bus_name) if AudioServer.get_bus_index(bus_name) >= 0 else &"Master"


# --- Музыка -------------------------------------------------------------------

## Включить музыку по имени ("" — выключить). Смена — через затухание.
func play_music(track: String) -> void:
	if track == music_name:
		return
	music_name = track
	var stream: AudioStream = null
	var found := _variants(MUSIC_DIR, track, "ogg") if not track.is_empty() else []
	if not found.is_empty():
		stream = found[0]
		# Петля включается здесь, а не галочкой в импорте: новый файл artist
		# зациклится сам, настраивать ничего не надо.
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true

	if _music_tween != null:
		_music_tween.kill()
	_music_tween = create_tween()
	if _music.playing:
		_music_tween.tween_property(_music, "volume_db", SILENT_DB, MUSIC_FADE_SECONDS * 0.5)
	_music_tween.tween_callback(_switch_music.bind(stream))
	if stream != null:
		_music_tween.tween_property(_music, "volume_db", 0.0, MUSIC_FADE_SECONDS)


func _switch_music(stream: AudioStream) -> void:
	_music.stop()
	_music.stream = null
	_music.stream = stream
	if stream != null:
		_music.volume_db = SILENT_DB
		_music.play()


# --- События разговора ----------------------------------------------------------

func _on_dialogue_started(_dialogue_id: String, speaker: Dictionary) -> void:
	_voice_pitch = voice_pitch(String(speaker.get("id", "")))


## Первое сообщение о терпении приходит в начале дуэли (терпение полное) —
## по нему включается музыка дуэли. Остальные — промахи игрока.
func _on_patience(left: int, total: int) -> void:
	if left == total:
		if music_name != "duel":
			_music_before_duel = music_name
		play_music("duel")
	else:
		play("duel_miss")


func _on_dialogue_finished(_dialogue_id: String, outcome: String) -> void:
	match outcome:
		"aborted":
			play("ui_cancel")
		"duel_lost":
			play("duel_lost")
	if music_name == "duel":
		play_music(_music_before_duel)

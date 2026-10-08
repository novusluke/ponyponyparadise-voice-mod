extends Node
## Synthesis runs in a separate process. Optional text gating awaits readiness,
## never playback, and releases on failure, OFF, cancellation or cleanup.

const NODE_NAME := "PonyVoiceMod"
const MAX_PENDING := 32
const ALIASES := {"narrator": "narrator", "narration": "narrator", "princesscelestia": "celestia", "cel": "celestia", "princessluna": "luna", "twilightsparkle": "twilight", "twi": "twilight", "sweetiebelle": "sweetiebelle", "buttonmash": "buttonmash", "aj": "applejack", "chrys": "chrysalis", "queenchrysalis": "chrysalis", "shy": "fluttershy", "pinkie": "pinkiepie", "dash": "rainbowdash", "rainbow": "rainbowdash", "trixielulamoon": "trixie", "berry": "berrypunch", "bigmac": "bigmcintosh", "bigmacintosh": "bigmcintosh", "princeblueblood": "blueblood", "derpy": "derpyhooves", "diamond": "diamondtiara", "fleet": "fleetfoot", "fleur": "fleurdelys", "granny": "grannysmith", "lightning": "lightningdust", "lyra": "lyraheartstrings", "mayor": "mayormare", "redheart": "nurseredheart", "nursehedheart": "nurseredheart", "octavia": "octaviamelody", "spitf": "spitfire"}

const SYSTEM_LINES := ["You can now ask questions or continue the conversation.", "The library is warm and welcoming, a stark contrast to the dark forest.", "As the conversation winds down, you all drift off to sleep, feeling comfortable and safe..."]
var settings: Dictionary = {"enabled": true, "execution_mode": "local", "language": "en", "volume_db": 0.0, "request_timeout_seconds": 120, "text_display_mode": "wait"}
var status := "Local OmniVoice ready."
var player: AudioStreamPlayer
var _folder := ""
var _session := ""
var _worker_pid := -1
var _current_key := ""
var _pending: Dictionary = {}
var _failed: Dictionary = {}
var _captured: Dictionary = {}
var _capture_dirty := false
var _poll_time := 0.0
var _heartbeat_time := 0.0
var _capture_time := 0.0
var _is_test_voice := false
var _timeline_voice := false
var _waiting_key := ""
var _wait_epoch := 0
var _protected: Dictionary = {}
var _suppress_once := ""
var _batch_preparing := false
var _release_wait_epoch := -1
var _watched_scene: Node
var _tree_was_paused := false
var _preparation_rows: Array[Dictionary] = []
var preparation: CanvasLayer

static func ensure(tree: SceneTree) -> Node:
	# Dialogic serializes its children as subsystems. Keep the voice player outside
	# that collection so a save can never abort on a non-subsystem node.
	var parent: Node = tree.root
	var existing := parent.get_node_or_null(NODE_NAME)
	if existing != null:
		return existing
	var controller: Node = load("res://scripts/voice_mod/voice_controller.gd").new()
	controller.name = NODE_NAME
	parent.add_child(controller)
	return controller

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var game_folder := OS.get_executable_path().get_base_dir()
	if OS.has_feature("editor"):
		game_folder = ProjectSettings.globalize_path("res://").trim_suffix("/")
	_folder = game_folder.path_join("data/voice_mod")
	_session = _folder.path_join("runtime/session_%s_%s" % [OS.get_process_id(), Time.get_ticks_msec()])
	DirAccess.make_dir_recursive_absolute(_session)
	load_settings()
	_load_protected()
	player = AudioStreamPlayer.new()
	player.name = "VoiceAudio"
	# A dedicated player on Master avoids an independently muted SFX channel.
	player.bus = "Master"
	add_child(player)
	preparation = preload("res://scripts/voice_mod/voice_preparation.gd").new()
	preparation.controller = self
	add_child(preparation)
	# Load after Dialogic's autoload finishes to avoid a circular script dependency.
	add_child(load("res://scripts/voice_mod/dialogue_input.gd").new())
	player.finished.connect(func(): status = "Ready.")
	get_tree().scene_changed.connect(_watch_scene)
	_watch_scene()
	var dialogic: Node = get_tree().root.get_node_or_null("Dialogic")
	if dialogic != null:
		dialogic.Text.text_started.connect(_on_text_started)
		dialogic.Text.about_to_show_text.connect(func(_info: Dictionary): stop())
		dialogic.timeline_ended.connect(func():
			if _timeline_voice:
				stop()
		)
		# Opening any dialogue menu discards playback, including late completions.
		# Test Voice and deliberate history previews can start afterwards.
		dialogic.dialogic_paused.connect(func(): stop(false))
	var capture_path := _folder.path_join("dialogue_manifest.json")
	if FileAccess.file_exists(capture_path):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(capture_path))
		if saved is Dictionary:
			for row in saved.get("lines", []):
				if row is Dictionary and row.has("id"):
					_captured[row.id] = row

func _watch_scene() -> void:
	if is_instance_valid(_watched_scene) and _watched_scene.tree_exiting.is_connected(_on_scene_leaving):
		_watched_scene.tree_exiting.disconnect(_on_scene_leaving)
	_watched_scene = get_tree().current_scene
	if is_instance_valid(_watched_scene):
		_watched_scene.tree_exiting.connect(_on_scene_leaving, CONNECT_ONE_SHOT)

func _on_scene_leaving() -> void:
	cancel_preparation()

func cancel_preparation() -> void:
	stop()
	_cancel_jobs()
	_finish_preparation()

func load_settings() -> void:
	var path := _folder.path_join("config.json")
	if FileAccess.file_exists(path):
		var value = JSON.parse_string(FileAccess.get_file_as_string(path))
		if value is Dictionary:
			settings.merge(value, true)
	if not settings.has("omnivoice"):
		settings.omnivoice = {}
	settings.execution_mode = "local"
	settings.language = "en"
	settings.erase("cache_cleanup_days") # Retire previous automatic-cleanup preferences.
	settings.omnivoice.num_step = clampi(int(settings.omnivoice.get("num_step", 64)), 8, 64)
	settings.omnivoice.speed = clampf(float(settings.omnivoice.get("speed", 1.0)), 0.5, 2.0)
	status = "Ready." if bool(settings.enabled) else "Voice system OFF."

func apply_settings(value: Dictionary) -> void:
	var engine_changed: bool = str(value.get("python_path", "")) != str(settings.get("python_path", "")) or str(value.get("omnivoice", {}).get("model", "")) != str(settings.omnivoice.get("model", "")) or value.get("omnivoice", {}).get("character_voices", {}) != settings.omnivoice.get("character_voices", {}) or str(value.get("references_path", "reference_audios")) != str(settings.get("references_path", "reference_audios"))
	settings = value.duplicate(true)
	settings.execution_mode = "local"
	settings.language = "en"
	settings.erase("cache_cleanup_days")
	if not settings.has("omnivoice"):
		settings.omnivoice = {}
	settings.omnivoice.num_step = clampi(int(settings.omnivoice.get("num_step", 64)), 8, 64)
	settings.omnivoice.speed = clampf(float(settings.omnivoice.get("speed", 1.0)), 0.5, 2.0)
	_write_json(_folder.path_join("config.json"), settings)
	if engine_changed or not bool(settings.enabled):
		_release_wait_epoch = _wait_epoch
		_suppress_once = _waiting_key
		stop(false)
		_cancel_jobs()
		_finish_preparation()
	else:
		_update_queued_steps()
		if is_instance_valid(player):
			player.volume_db = float(settings.volume_db)
			player.pitch_scale = float(settings.omnivoice.speed)
	status = "Ready." if bool(settings.enabled) else "Voice system OFF."

func reference_path(language: String, speaker: String) -> String:
	speaker = speaker_id(speaker)
	var overrides: Dictionary = settings.omnivoice.get("character_voices", {})
	var selected := str(overrides.get(speaker, ""))
	if not selected.is_empty() and FileAccess.file_exists(_resolve(selected)):
		return _resolve(selected)
	for extension in ["mp3", "wav", "ogg", "flac"]:
		var path := _resolve(str(settings.get("references_path", "reference_audios"))).path_join(language).path_join(speaker + "." + extension)
		if FileAccess.file_exists(path):
			return path
	selected = str(settings.omnivoice.get("default_voice", ""))
	if selected.is_empty():
		selected = str(settings.get("references_path", "reference_audios")).path_join(language).path_join("twilight.mp3")
	if speaker not in ["narrator", "celestia"] and not selected.is_empty() and FileAccess.file_exists(_resolve(selected)):
		return _resolve(selected)
	return ""

func test_voice() -> void:
	if not bool(settings.enabled):
		status = "Enable voices to hear the test."
		return
	var sample := "Hello! My name is Twilight Sparkle, and I'm so happy to meet you!"
	speak("twilight", sample, true)

func set_option(key: String, value: Variant) -> void:
	if key == "num_steps":
		settings.omnivoice.num_step = clampi(int(value), 8, 64)
		_update_queued_steps()
	else:
		if key == "language":
			value = "en"
		settings[key] = value
	if not bool(settings.enabled):
		_release_wait_epoch = _wait_epoch
		_suppress_once = _waiting_key
		stop(false)
		_cancel_jobs()
		_finish_preparation()
	if not _write_json(_folder.path_join("config.json"), settings):
		status = "Could not save Voice Options."
	elif not bool(settings.enabled):
		status = "Voice system OFF."

static func speaker_id(value: String) -> String:
	var re := RegEx.create_from_string("[^a-z0-9]")
	var normalized := re.sub(value.to_lower(), "", true)
	if normalized.is_empty() or normalized == "player":
		normalized = "narrator"
	return str(ALIASES.get(normalized, normalized))

static func speech_text(value: String) -> String:
	var tags := RegEx.create_from_string("\\[[^\\]]*\\]")
	var whitespace := RegEx.create_from_string("\\s+")
	return whitespace.sub(tags.sub(value, "", true).replace("\\:", ":").replace("�", "..."), " ", true).strip_edges()

static func line_id(language: String, speaker: String, text: String) -> String:
	return (language.to_lower() + "\n" + speaker_id(speaker) + "\n" + speech_text(text)).sha256_text()

func _on_text_started(info: Dictionary) -> void:
	var character = info.get("character")
	var speaker := "narrator"
	if character != null:
		speaker = str(character.get_identifier())
	speak(speaker, str(info.get("text", "")), false, true)

func speak(speaker: String, text: String, is_test: bool = false, from_timeline: bool = false) -> void:
	stop(not is_test)
	_is_test_voice = is_test
	_timeline_voice = from_timeline
	var row := _row(speaker, text)
	if str(row.text).is_empty():
		return
	_capture(row)
	if not bool(settings.enabled):
		return
	var dialogic: Node = get_tree().root.get_node_or_null("Dialogic")
	if not is_test and (get_tree().paused or (dialogic != null and dialogic.paused)):
		return
	if not is_test and dialogic != null and dialogic.Inputs.auto_skip.enabled:
		return
	_current_key = str(row.id)
	if _suppress_once == _current_key:
		_suppress_once = ""
		_current_key = ""
		return
	var audio_path := _audio_path(row)
	if FileAccess.file_exists(audio_path):
		_play(audio_path)
	elif str(settings.execution_mode) == "local":
		_enqueue(row, true)

func prefetch(speaker: String, text: String) -> void:
	var row := _row(speaker, text)
	_capture(row)
	if bool(settings.enabled) and str(settings.execution_mode) == "local" and not FileAccess.file_exists(_audio_path(row)):
		_enqueue(row)

func _row(speaker: String, text: String) -> Dictionary:
	var language := str(settings.language).to_lower()
	# Fixed English system narration is an asset, never a runtime synthesis job.
	if language == "en":
		for fixed in SYSTEM_LINES:
			if speech_text(text).trim_suffix(".") == str(fixed).trim_suffix("."):
				speaker = "narrator"
				text = str(fixed)
				break
	return {"id": line_id(language, speaker, text), "language": language, "speaker": speaker_id(speaker), "text": speech_text(text)}

func history_metadata(speaker: String, text: String) -> Dictionary:
	var row := _row(speaker, text)
	return {"voice_audio_path": str(row.language) + "/" + str(row.id) + ".mp3", "voice_id": row.id, "voice_language": row.language, "voice_speaker": row.speaker, "voice_text": row.text}

func replay_history(entry: Dictionary, speaker: String = "narrator", text: String = "", in_history_panel: bool = false) -> void:
	stop(not in_history_panel)
	if not bool(settings.enabled):
		return
	var metadata := entry.duplicate(true) if entry.has("voice_audio_path") else history_metadata(speaker, text)
	# Old fixed narration used Celestia's identity. Replay its new Narrator asset
	# without changing the saved history or synthesizing a replacement.
	var old_id := str(metadata.get("voice_id", ""))
	var character = entry.get("character")
	var narrator_entry := bool(entry.get("is_narrator", false)) or (not entry.has("is_narrator") and (character == null or str(character).is_empty()))
	var migration: Dictionary = preload("res://scripts/voice_mod/voice_base_index.gd").LEGACY_NARRATOR_IDS
	var player_migration: Dictionary = preload("res://scripts/voice_mod/voice_base_index.gd").LEGACY_PLAYER_IDS
	if (narrator_entry and migration.has(old_id)) or player_migration.has(old_id):
		metadata.voice_id = player_migration[old_id] if player_migration.has(old_id) else migration[old_id]
		metadata.voice_speaker = "narrator"
		metadata.voice_audio_path = str(metadata.get("voice_language", "en")) + "/" + str(metadata.voice_id) + ".mp3"
	var relative := str(metadata.get("voice_audio_path", ""))
	var stored_text := str(entry.get("text", entry.get("display_text", text)))
	if not stored_text.is_empty() and metadata.has("voice_text"):
		var normalized := speech_text(stored_text)
		if str(metadata.get("voice_language", "en")) == "en":
			for fixed in SYSTEM_LINES:
				if normalized.trim_suffix(".") == str(fixed).trim_suffix("."):
					normalized = str(fixed)
					break
		if normalized != str(metadata.voice_text):
			# Editing an old history entry must never replay its previous wording.
			relative = str(metadata.voice_language) + "/" + line_id(str(metadata.voice_language), str(metadata.voice_speaker), normalized) + ".mp3"
	if RegEx.create_from_string("^[a-z]{2,3}(-[a-z0-9]{2,8})*/[a-f0-9]{64}\\.mp3$").search(relative) == null:
		return
	var path := _resolve(str(settings.get("voices_path", "../voices"))).path_join(relative)
	_is_test_voice = in_history_panel # History previews are audible while the log pauses dialogue.
	if FileAccess.file_exists(path):
		_play(path)
	else:
		status = "This history clip is no longer cached."
	# History never calls _enqueue, including after cache cleanup.

func response_rows(entries: Array) -> Array[Dictionary]:
	# A separate synthesis order leaves the caller's dialogue/history untouched.
	var groups := {}
	var speakers: Array[String] = []
	var seen := {}
	for entry in entries:
		if not entry is Dictionary or str(entry.get("type", "")) != "dialogue":
			continue
		var text := str(entry.get("text", ""))
		var dialogic: Node = get_tree().root.get_node_or_null("Dialogic")
		if dialogic != null:
			text = dialogic.Text.parse_text(text, 0)
		var row := _row("narrator" if bool(entry.get("is_narrator", false)) else str(entry.get("speaker", "narrator")), text)
		_capture(row)
		if str(row.text).is_empty() or seen.has(row.id):
			continue
		var group := str(row.language) + "/" + str(row.speaker)
		if not groups.has(group):
			groups[group] = []
			speakers.append(group)
		groups[group].append(row)
		seen[row.id] = true
	var rows: Array[Dictionary] = []
	for group in speakers:
		rows.append_array(groups[group])
	return rows

func prefetch_response(entries: Array) -> void:
	if not bool(settings.enabled) or str(settings.text_display_mode) != "instant":
		return
	_begin_preparation(response_rows(entries))
	_pump_preparation()

func prepare_response(entries: Array, is_current: Callable = Callable()) -> bool:
	# Prepare all speech before the caller pops a line, changes history or reveals
	# text. Submit one missing clip at a time: inference is serial, and long
	# responses must not overflow MAX_PENDING or expire while waiting in a queue.
	if not bool(settings.enabled) or str(settings.text_display_mode) != "wait" or str(settings.execution_mode) != "local":
		return not is_current.is_valid() or bool(is_current.call())
	stop()
	var epoch := _wait_epoch
	var rows := response_rows(entries)
	_batch_preparing = true
	_begin_preparation(rows)
	var completed := 0
	for row in rows:
		if epoch != _wait_epoch or (is_current.is_valid() and not bool(is_current.call())):
			if epoch == _wait_epoch:
				_waiting_key = ""
				_batch_preparing = false
				_finish_preparation()
			return false
		if _release_wait_epoch == epoch or not bool(settings.enabled) or str(settings.text_display_mode) != "wait" or str(settings.execution_mode) != "local":
			# Stop, cleanup and settings changes release this response completely.
			# Do not resume line-by-line generation after revealing its first line.
			if _release_wait_epoch == epoch and str(settings.text_display_mode) == "wait":
				for unfinished in rows:
					if not FileAccess.file_exists(_audio_path(unfinished)):
						_failed[unfinished.id] = true
			break
		if not FileAccess.file_exists(_audio_path(row)) and not _failed.has(row.id):
			_waiting_key = str(row.id)
			while _pending.size() >= MAX_PENDING and not _pending.has(row.id):
				if epoch != _wait_epoch or _release_wait_epoch == epoch or not bool(settings.enabled) or str(settings.execution_mode) != "local" or str(settings.text_display_mode) != "wait" or (is_current.is_valid() and not bool(is_current.call())):
					break
				await get_tree().process_frame
			if epoch == _wait_epoch and _release_wait_epoch != epoch and bool(settings.enabled) and str(settings.execution_mode) == "local" and str(settings.text_display_mode) == "wait" and (not is_current.is_valid() or bool(is_current.call())):
				_enqueue(row, true)
			while _pending.has(row.id) and epoch == _wait_epoch and _release_wait_epoch != epoch and bool(settings.enabled) and str(settings.execution_mode) == "local" and str(settings.text_display_mode) == "wait":
				if is_current.is_valid() and not bool(is_current.call()):
					break
				status = "Preparing response audio (%d/%d)..." % [completed, rows.size()]
				await get_tree().process_frame
			if not FileAccess.file_exists(_audio_path(row)) and not _pending.has(row.id):
				_failed[row.id] = true
		completed += 1
	if epoch == _wait_epoch:
		_waiting_key = ""
		_batch_preparing = false
		var all_ready := true
		for row in rows:
			all_ready = all_ready and FileAccess.file_exists(_audio_path(row))
		status = "Response audio ready." if all_ready else "Audio preparation unavailable; dialogue continues."
		_finish_preparation()
	return epoch == _wait_epoch and (not is_current.is_valid() or bool(is_current.call()))

func prepare_line(speaker: String, text: String, is_current: Callable = Callable()) -> bool:
	stop()
	var epoch := _wait_epoch
	var row := _row(speaker, text)
	_capture(row)
	if not bool(settings.enabled) or str(row.text).is_empty():
		return true
	var dialogic: Node = get_tree().root.get_node_or_null("Dialogic")
	if dialogic != null and dialogic.Inputs.auto_skip.enabled:
		return true
	_waiting_key = str(row.id)
	if str(settings.text_display_mode) == "wait" and not FileAccess.file_exists(_audio_path(row)) and str(settings.execution_mode) == "local":
		_enqueue(row, true)
	while _pending.has(row.id) and bool(settings.enabled) and str(settings.execution_mode) == "local" and str(settings.get("text_display_mode", "wait")) == "wait":
		if dialogic != null and dialogic.Inputs.auto_skip.enabled:
			_suppress_once = str(row.id)
			break
		if epoch != _wait_epoch or (is_current.is_valid() and not bool(is_current.call())):
			if _waiting_key == str(row.id):
				_waiting_key = ""
			return false
		await get_tree().process_frame
	# A settings/history overlay pauses the story. Ready audio must not reveal
	# the underlying line while a test or history preview is playing there.
	while dialogic != null and dialogic.paused and bool(settings.enabled):
		if epoch != _wait_epoch or (is_current.is_valid() and not bool(is_current.call())):
			if _waiting_key == str(row.id):
				_waiting_key = ""
			return false
		await get_tree().process_frame
	if _waiting_key == str(row.id):
		_waiting_key = ""
	return epoch == _wait_epoch and (not is_current.is_valid() or bool(is_current.call()))

func _audio_path(row: Dictionary) -> String:
	return _resolve(str(settings.get("voices_path", "../voices"))).path_join(str(row.language)).path_join(str(row.id) + ".mp3")

func _reference_exists(row: Dictionary) -> bool:
	return not reference_path(str(row.language), str(row.speaker)).is_empty()

func _enqueue(row: Dictionary, current: bool = false) -> void:
	var key := str(row.id)
	if _protected.has(str(row.language) + "/" + key + ".mp3") or (str(row.language) == "en" and str(row.text) in SYSTEM_LINES):
		status = "Base voice clip missing. Apply voices again to restore it."
		return
	if _pending.has(key):
		if current and FileAccess.file_exists(_session.path_join("job_" + key + ".json")):
			_pending[key].priority = 1
			_pending[key].deadline = Time.get_unix_time_from_system() + clampf(float(settings.request_timeout_seconds), 1.0, 600.0)
			_write_json(_session.path_join("job_" + key + ".json"), _pending[key])
		return
	if _failed.has(key) or _pending.size() >= MAX_PENDING:
		return
	if not _reference_exists(row):
		status = "No reference audio for %s; dialogue continues." % str(row.speaker)
		return
	if not _start_worker():
		return
	row = row.duplicate()
	row.steps = clampi(int(settings.omnivoice.get("num_step", 64)), 8, 64)
	row.priority = 1 if current else 0
	row.deadline = Time.get_unix_time_from_system() + clampf(float(settings.request_timeout_seconds), 1.0, 600.0)
	if _write_json(_session.path_join("job_" + key + ".json"), row):
		_pending[key] = row
		status = "Generating speech in the background."
		if _preparation_rows.is_empty():
			_begin_preparation([row])
	else:
		status = "Voice job could not be written; dialogue continues."

func _start_worker() -> bool:
	if _worker_pid > 0 and OS.is_process_running(_worker_pid):
		return true
	var python := str(settings.get("python_path", ""))
	if python.is_empty() or not FileAccess.file_exists(_resolve(python)):
		status = "Select OmniVoice in Voice Setup or browse to its folder here."
		return false
	_write_heartbeat()
	_worker_pid = OS.create_process(_resolve(python), PackedStringArray(["-B", "-u", _folder.path_join("worker_bootstrap.py"), "--config", _folder.path_join("config.json"), "--session", _session]), false)
	if _worker_pid <= 0:
		status = "Voice worker failed to start; dialogue continues."
		return false
	return true

func _process(delta: float) -> void:
	_update_preparation()
	_pump_preparation()
	if get_tree().paused and not _tree_was_paused:
		stop(false)
	_tree_was_paused = get_tree().paused
	_poll_time += delta
	_heartbeat_time += delta
	_capture_time += delta
	if _capture_dirty and _capture_time >= 5.0:
		flush_capture()
	if _worker_pid > 0 and _heartbeat_time >= 3.0:
		_write_heartbeat()
	if _poll_time < 0.1:
		return
	_poll_time = 0.0
	var worker_state = JSON.parse_string(FileAccess.get_file_as_string(_session.path_join("worker_state.json"))) if FileAccess.file_exists(_session.path_join("worker_state.json")) else {}
	var loading: bool = worker_state is Dictionary and str(worker_state.get("phase", "")) == "loading" and Time.get_unix_time_from_system() - float(worker_state.get("started", 0)) < 600
	if _worker_pid > 0 and not OS.is_process_running(_worker_pid):
		_worker_pid = -1
		for key in _pending:
			_failed[key] = true
		_pending.clear()
		status = "OmniVoice Python stopped. Check the selected environment in Voice Setup."
	for key in _pending.keys():
		var row: Dictionary = _pending[key]
		if loading and float(row.deadline) - Time.get_unix_time_from_system() < float(settings.request_timeout_seconds) * 0.5:
			row.deadline = Time.get_unix_time_from_system() + float(settings.request_timeout_seconds)
			if FileAccess.file_exists(_session.path_join("job_" + str(key) + ".json")):
				_write_json(_session.path_join("job_" + str(key) + ".json"), row)
			status = "Starting OmniVoice / downloading models in the backgroundâ€¦"
		var done := _session.path_join("done_" + str(key) + ".json")
		if FileAccess.file_exists(done):
			var result = JSON.parse_string(FileAccess.get_file_as_string(done))
			if OS.get_environment("PONY_VOICE_TRACE") == "1":
				print("VOICE_DONE ", key, " current=", _current_key, " enabled=", settings.enabled, " mode=", settings.execution_mode, " result=", result)
			DirAccess.remove_absolute(done)
			_pending.erase(key)
			if result is Dictionary and bool(result.get("ok", false)):
				if key == _current_key and key != _waiting_key and not _batch_preparing and bool(settings.enabled) and str(settings.execution_mode) == "local":
					_play(_audio_path(row))
			else:
				_failed[key] = true
				status = "Voice unavailable: " + str(result.get("error", "See worker.log.")) if result is Dictionary else "Voice unavailable. See worker.log."
		elif Time.get_unix_time_from_system() > float(row.deadline):
			_pending.erase(key)
			_failed[key] = true
			DirAccess.remove_absolute(_session.path_join("job_" + str(key) + ".json"))
			if key == _current_key:
				_current_key = ""
				status = "Voice timed out; dialogue continues."

func _play(path: String) -> void:
	var dialogic: Node = get_tree().root.get_node_or_null("Dialogic")
	if not _is_test_voice and (get_tree().paused or (dialogic != null and dialogic.paused)):
		return
	if not FileAccess.file_exists(path):
		return
	var data := FileAccess.get_file_as_bytes(path)
	if data.is_empty():
		status = "Empty voice clip; dialogue continues."
		return
	var stream := AudioStreamMP3.new()
	stream.data = data
	if stream.get_length() <= 0.0:
		status = "Invalid voice clip; dialogue continues."
		return
	player.volume_db = float(settings.volume_db)
	player.pitch_scale = clampf(float(settings.omnivoice.get("speed", 1.0)), 0.5, 2.0)
	player.stream = stream
	player.play()
	player.stream_paused = false
	status = "Playing voice."

func stop(cancel_wait: bool = true) -> void:
	if cancel_wait:
		_wait_epoch += 1
		_waiting_key = ""
		_batch_preparing = false
	if OS.get_environment("PONY_VOICE_TRACE") == "1" and not _current_key.is_empty():
		print("VOICE_STOP ", _current_key, " ", get_stack())
	_current_key = ""
	_is_test_voice = false
	_timeline_voice = false
	if is_instance_valid(player):
		player.stop()
		player.stream = null
	# Prefetch jobs may finish into the cache; they can never play a stale line.

func stop_voice() -> void:
	# Menu Stop releases an audio gate, but does not cancel the story coroutine.
	_release_wait_epoch = _wait_epoch
	_suppress_once = _waiting_key
	if not _waiting_key.is_empty():
		_pending.erase(_waiting_key)
		DirAccess.remove_absolute(_session.path_join("job_" + _waiting_key + ".json"))
	stop(false)
	status = "Voice playback stopped."

func _load_protected() -> void:
	_protected.clear()
	for file in preload("res://scripts/voice_mod/voice_base_index.gd").FILES:
		_protected[file] = true
	var path := _resolve("../voices/opening_manifest.json")
	var index = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	if index is Dictionary:
		for row in index.get("lines", []):
			if row is Dictionary:
				_protected[str(row.get("file", ""))] = true

func clean_cache() -> Dictionary:
	# Stop the writer before deletion; pending text can reveal without audio.
	stop(false)
	_release_wait_epoch = _wait_epoch
	_suppress_once = _waiting_key
	_cancel_jobs()
	_finish_preparation()
	var result: Dictionary = preload("res://scripts/voice_mod/voice_cache.gd").clean(_folder.path_join("../voices").simplify_path(), _folder.path_join("runtime"))
	DirAccess.make_dir_recursive_absolute(_session)
	if str(result.error).is_empty():
		_write_json(_folder.path_join("cache_state.json"), {"last_cleanup": Time.get_unix_time_from_system()})
		status = "Cache cleaned: %d generated voices, %d temporary files. Base voices kept." % [result.audio, result.temporary]
	else:
		status = str(result.error)
	return result

func _capture(row: Dictionary) -> void:
	if str(row.text).is_empty() or _captured.has(row.id):
		return
	_captured[row.id] = row.duplicate()
	_capture_dirty = true

func flush_capture() -> void:
	_capture_time = 0.0
	if _write_json(_folder.path_join("dialogue_manifest.json"), {"schema_version": 1, "lines": _captured.values()}):
		_capture_dirty = false

func _write_heartbeat() -> void:
	_heartbeat_time = 0.0
	var file := FileAccess.open(_session.path_join("heartbeat"), FileAccess.WRITE)
	if file != null:
		file.store_string(str(Time.get_unix_time_from_system()))

func _resolve(path: String) -> String:
	return path if path.is_absolute_path() else _folder.path_join(path).simplify_path()

func _write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
	return DirAccess.rename_absolute(path + ".tmp", path) == OK

func _exit_tree() -> void:
	stop()
	flush_capture()
	DirAccess.remove_absolute(_session.path_join("heartbeat"))
	if _worker_pid > 0 and OS.is_process_running(_worker_pid):
		OS.kill(_worker_pid)

func _begin_preparation(rows: Array[Dictionary]) -> void:
	_preparation_rows = rows.duplicate(true)
	preparation.begin()
	_update_preparation()

func _finish_preparation() -> void:
	_preparation_rows.clear()
	if is_instance_valid(preparation):
		preparation.update_progress(0, 0)

func _update_preparation() -> void:
	if _preparation_rows.is_empty():
		return
	var ready := 0
	var unresolved := false
	for row in _preparation_rows:
		if FileAccess.file_exists(_audio_path(row)):
			ready += 1
		elif not _failed.has(row.id):
			unresolved = true
	preparation.update_progress(ready, _preparation_rows.size())
	if ready == _preparation_rows.size() or (not unresolved and not _batch_preparing):
		_finish_preparation()

func _pump_preparation() -> void:
	if _batch_preparing or not _pending.is_empty() or not bool(settings.enabled):
		return
	for row in _preparation_rows:
		if not FileAccess.file_exists(_audio_path(row)) and not _failed.has(row.id):
			_enqueue(row)
			if not _pending.has(row.id):
				_failed[row.id] = true
			return

func _update_queued_steps() -> void:
	for key in _pending:
		var path := _session.path_join("job_" + str(key) + ".json")
		if FileAccess.file_exists(path):
			_pending[key].steps = int(settings.omnivoice.num_step)
			_write_json(path, _pending[key])

func _cancel_jobs() -> void:
	DirAccess.remove_absolute(_session.path_join("heartbeat"))
	if _worker_pid > 0 and OS.is_process_running(_worker_pid):
		OS.kill(_worker_pid)
	_worker_pid = -1
	_pending.clear()
	_failed.clear()
	_session = _folder.path_join("runtime/session_%s_%s" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(_session)

func apply_preparation_steps(value: int) -> void:
	# Keep the response epoch and completed clips. Restart only unfinished jobs.
	set_option("num_steps", value)
	var remaining: Array = _pending.values().duplicate(true)
	_cancel_jobs()
	for row in remaining:
		if not FileAccess.file_exists(_audio_path(row)):
			_enqueue(row, int(row.get("priority", 0)) > 0)
	status = "Preparing remaining voices at %d steps…" % int(settings.omnivoice.num_step)

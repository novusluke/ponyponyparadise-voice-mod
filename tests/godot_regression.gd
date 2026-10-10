extends Node

var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame

func _run() -> void:
	assert(OS.get_user_data_dir().contains("VoiceModQA"))
	for path in ["res://scripts/voice_mod/voice_controller.gd", "res://scripts/voice_mod/voice_options.gd", "res://addons/dialogic/Modules/Text/event_text.gd", "res://scenes/ui_settings_menu.gd", "res://scripts/ai/dialogic_ai_conversation.gd", "res://scripts/ai/ai_scene_generator.gd", "res://scripts/voice_mod/voice_cache.gd", "res://autoloads/map_manager.gd", "res://autoloads/rollback_manager.gd", "res://scripts/ai/ai_dialogue_shared.gd", "res://addons/dialogic/Modules/History/subsystem_history.gd", "res://addons/dialogic/Modules/DefaultLayoutParts/Layer_History/history_layer.gd"]:
		var script = load(path)
		check(script != null and script.can_instantiate(), "Cannot compile " + path)
	if not failures.is_empty():
		get_tree().quit(1)
		return
	var controller: Node = load("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree())
	var original: Dictionary = controller.settings.duplicate(true)
	var original_capture: Dictionary = controller._captured.duplicate(true)
	check(controller.line_id("en", "cel", "[i]Hello[/i]   world!") == "804dfb0ffeeb6dcca883b26f792076440bfea1ea753563154382eb9dd7fe9fe1", "Python/Godot identity mismatch")
	check(controller.line_id("en", "narrator", "Darkness.") != controller.line_id("en", "celestia", "Darkness."), "Narrator still shares Celestia's identity")
	var roster: Dictionary = {}
	# The roster is supplied by the runner without adding it to game content.
	var roster_path := OS.get_environment("PONY_VOICE_ROSTER")
	if not roster_path.is_empty():
		roster = JSON.parse_string(FileAccess.get_file_as_string(roster_path))
		for row in roster.characters:
			check(controller.speaker_id(str(row.tag)) == str(row.voice), "Wrong voice for character tag " + str(row.tag))
			check(controller.reference_path("en", str(row.tag)).get_file() == str(row.voice) + ".mp3", "Reference missing for " + str(row.name))
	check(controller.reference_path("en", "narrator").get_file() == "narrator.mp3" and controller.reference_path("en", "cel").get_file() == "celestia.mp3", "Narrator/Celestia references are not separate")
	CharacterSpriteLoader.load_all_characters()
	check(CharacterSpriteLoader.get_emotions("buttonmash").size() == 12, "Bundled Button Mash sprites were not loaded")
	var settings_menu: Node = load("res://scenes/ui_settings_menu.gd").new()
	get_tree().root.add_child(settings_menu)
	check(settings_menu != null, "Settings menu could not be created")
	var options: Node = settings_menu._voice_options
	check(options.steps.max_value == 64, "Quality slider exceeds 64 steps")
	check(options.steps.min_value == 8 and options.steps.editable, "Quality slider cannot select faster generation")
	controller.settings.omnivoice.num_step = 4
	controller.apply_settings(controller.settings)
	check(controller.settings.omnivoice.num_step == 8, "Quality minimum was not clamped")
	options.reset()
	check(options.steps.value == 64, "Quality does not default to 64 steps")
	check(options.speed.min_value == 0.5 and options.speed.max_value == 2.0, "Speed range differs from original")
	check(options.text_mode.item_count == 2, "Text mode options missing")
	check(options.text_mode.selected == 0 and options.text_mode.get_item_text(0) == "Wait for Audio (Recommended)", "Wait mode is not the recommended default")
	var option_count := 0
	for option_row in options.get_children():
		for child in option_row.get_children():
			if child is OptionButton:
				option_count += 1
	check(option_count == 2, "Unexpected execution/automatic-cleanup selector in local-only options")
	check(options.enabled is Button and options.enabled.toggle_mode, "Green voice toggle missing")
	check(options.folder_dialog.use_native_dialog, "Browse dialogs are not native")
	controller.settings.enabled = true
	controller.settings.execution_mode = "local"
	controller.test_voice()
	check(controller.player.playing, "Bundled Twilight test voice failed")
	Dialogic.paused = true
	check(not controller.player.playing, "Menu entry did not stop the previous voice")
	controller.test_voice()
	check(controller.player.playing and not controller.player.stream_paused, "Voice test was muted by settings-menu pause")
	Dialogic.paused = false
	controller.speak("twilight", "Hello! My name is Twilight Sparkle, and I'm so happy to meet you!")
	check(controller.player.playing, "Normal voice fixture did not play")
	get_tree().paused = true
	await frames(2)
	check(not controller.player.playing, "Game pause/menu did not stop speech")
	get_tree().paused = false
	await frames(2)
	check(not controller.player.playing, "Speech resumed after closing the pause/menu")
	controller.set_option("enabled", false)
	check(not controller.player.playing, "OFF did not immediately stop test voice")
	controller.test_voice()
	check(not controller.player.playing, "Test voice bypassed disabled voices")
	controller.settings.enabled = true
	var opening = JSON.parse_string(FileAccess.get_file_as_string(controller._resolve("../voices/opening_manifest.json")))
	check(opening is Dictionary and opening.lines.size() >= 151, "Opening pack is incomplete")
	if opening is Dictionary:
		for clip in opening.lines:
			var path: String = controller._resolve("../voices/" + str(clip.file))
			var audio := AudioStreamMP3.new()
			audio.data = FileAccess.get_file_as_bytes(path)
			check(audio.get_length() > 0.2, "Opening MP3 is not decodable: " + str(clip.id))
	# Play through real Dialogic signals, not just the controller's direct method.
	for entry in [{"speaker": "narrator", "text": "Darkness."}, {"speaker": "twilight", "text": "\"Hello? Is somepony there?\""}]:
		var event := DialogicTextEvent.new()
		event.text = entry.text
		if entry.speaker == "twilight":
			event.get_or_create_character("twilight")
		var spoken_timeline := DialogicTimeline.new()
		spoken_timeline.events = [event]
		spoken_timeline.events_processed = true
		Dialogic.start(spoken_timeline)
		for _attempt in range(100):
			if controller.player.playing:
				break
			await get_tree().create_timer(0.01).timeout
		check(controller.player.playing, "Dialogic did not play " + str(entry.speaker))
		Dialogic.Text.skip_text_reveal()
		for _attempt in range(100):
			if event.state == event.States.DONE:
				break
			await get_tree().create_timer(0.01).timeout
		await Dialogic.end_timeline()
		await frames(2)
	controller.settings.text_display_mode = "wait"
	for mode in ["off", "local_missing_audio", "local_missing_reference", "local_missing_python"]:
		controller.settings.enabled = mode != "off"
		controller.settings.execution_mode = "local"
		controller.settings.python_path = ""
		var speaker := "spike" if mode == "local_missing_python" else "no_reference"
		controller.speak(speaker, "A silent line must not block input.")
		check(not controller.player.playing, "Unexpected audio in " + mode)
		var first := DialogicTextEvent.new()
		first.text = "First line."
		var second := DialogicTextEvent.new()
		second.text = "Second line."
		var timeline := DialogicTimeline.new()
		timeline.events = [first, second]
		timeline.events_processed = true
		Dialogic.start(timeline)
		for _attempt in range(150):
			if first.state == first.States.REVEALING or first.state == first.States.DONE:
				break
			await get_tree().create_timer(0.02).timeout
		await get_tree().create_timer(0.15).timeout
		Dialogic.Text.skip_text_reveal()
		await get_tree().create_timer(0.15).timeout
		Dialogic.Inputs.manual_advance.system_enabled = true
		Dialogic.Inputs.manual_advance.disabled_until_next_event = false
		Dialogic.Inputs.dialogic_action.emit()
		await frames(5)
		print("ADVANCE ", mode, " index=", Dialogic.current_event_idx, " state=", Dialogic.current_state)
		check(Dialogic.current_event_idx >= 1, "Dialogue did not advance in " + mode)
		await Dialogic.end_timeline()
		await frames(2)
		print("PASS checked voice mode: ", mode)
	# A late completion from a skipped line must never start playback.
	controller.settings.enabled = true
	controller.settings.execution_mode = "local"
	var row: Dictionary = controller._row("spike", "Skipped line.")
	row.deadline = Time.get_unix_time_from_system() + 30
	controller._pending[row.id] = row
	controller._current_key = str(row.id)
	controller.stop()
	controller._write_json(controller._session.path_join("done_" + str(row.id) + ".json"), {"ok": true})
	controller._process(0.2)
	check(not controller.player.playing, "Stale synthesis played after advance")
	# Timeout is a background bookkeeping event, never a dialogue lock.
	row.deadline = 0
	controller._pending[row.id] = row
	controller._current_key = str(row.id)
	controller._process(0.2)
	check(controller._pending.is_empty() and controller._current_key.is_empty(), "Timeout did not clear pending playback")
	# Decode and play a real MP3, then confirm that cancellation stops it immediately.
	var fixture: String = controller._resolve("reference_audios/en/celestia.mp3")
	check(FileAccess.file_exists(fixture), "Reference fixture not found")
	if FileAccess.file_exists(fixture):
		controller._play(fixture)
		check(controller.player.playing, "MP3 playback did not start")
		controller.stop()
		check(not controller.player.playing, "Stopping dialogue did not stop MP3 playback")
		var cached: Dictionary = controller._row("spike", "Cached playback regression fixture.")
		var cached_path: String = controller._audio_path(cached)
		DirAccess.make_dir_recursive_absolute(cached_path.get_base_dir())
		var cached_file := FileAccess.open(cached_path, FileAccess.WRITE)
		cached_file.store_buffer(FileAccess.get_file_as_bytes(fixture))
		cached_file.close()
		controller.settings.execution_mode = "local"
		controller.speak("spike", "Cached playback regression fixture.")
		check(controller.player.playing, "Local cache lookup did not start MP3 playback")
		controller.stop()
		DirAccess.remove_absolute(cached_path)
	# Wait mode must keep both a real timeline and an Ask-response display unchanged.
	controller.apply_settings(original)
	controller.settings.enabled = true
	controller.settings.execution_mode = "local"
	controller.settings.text_display_mode = "wait"
	controller.settings.python_path = ""
	Dialogic.History.simple_history_enabled = true
	for source in ["timeline", "ask"]:
		var text: String = "Delayed audio regression " + source + "."
		var delayed: Dictionary = controller._row("twilight", text)
		delayed.deadline = Time.get_unix_time_from_system() + 30
		controller._pending[delayed.id] = delayed
		Dialogic.Text.update_dialog_text("Previous visible line.", true)
		var event: DialogicTextEvent
		var conversation: Node
		if source == "timeline":
			event = DialogicTextEvent.new()
			event.text = text
			event.get_or_create_character("twilight")
			var timeline := DialogicTimeline.new()
			timeline.events = [event]
			timeline.events_processed = true
			Dialogic.start(timeline)
		else:
			conversation = load("res://scripts/ai/dialogic_ai_conversation.gd").new()
			get_tree().root.add_child(conversation)
			conversation._is_active = true
			conversation._dialogue_queue = [{"type": "dialogue", "speaker": "twilight", "text": text, "is_narrator": false}]
			conversation._display_next_dialogue()
		for _attempt in range(100):
			if controller._waiting_key == str(delayed.id):
				break
			await get_tree().create_timer(0.01).timeout
		check(controller._waiting_key == str(delayed.id), "Wait mode did not gate " + source)
		var before := str(Dialogic.current_state_info.get("text", ""))
		await frames(5)
		check(str(Dialogic.current_state_info.get("text", "")) == before and not before.contains(text), "Text appeared before audio for " + source)
		check(not controller.player.playing, "Audio started before text commit")
		if event != null:
			event._on_dialogic_input_action()
			check(not controller._waiting_key.is_empty(), "Click cancelled a gated event and stranded dialogue")
		var path: String = controller._audio_path(delayed)
		var output := FileAccess.open(path, FileAccess.WRITE)
		output.store_buffer(FileAccess.get_file_as_bytes(fixture))
		output.close()
		controller._write_json(controller._session.path_join("done_" + str(delayed.id) + ".json"), {"ok": true})
		for _attempt in range(100):
			if controller.player.playing:
				break
			await get_tree().create_timer(0.01).timeout
		check(controller.player.playing and str(Dialogic.current_state_info.get("text", "")).contains(text), "Text/audio did not start together for " + source)
		var metadata: Dictionary = controller.history_metadata("twilight", text)
		check(str(metadata.voice_audio_path) == "en/" + str(delayed.id) + ".mp3", "History did not retain portable audio path")
		if conversation != null:
			check(conversation._displayed_lines.back().get("voice_audio_path", "") == metadata.voice_audio_path, "Ask node lost its audio path")
			conversation._is_active = false
			conversation._session_id += 1
			conversation.queue_free()
		Dialogic.Text.skip_text_reveal()
		await frames(5)
		if event != null:
			await Dialogic.end_timeline()
		var history_row := metadata.duplicate(true)
		history_row.character_name = "Twilight Sparkle"
		history_row.text = text
		var history: Node
		if ResourceLoader.exists("res://scenes/story_panel/story_panel.gd"):
			history = load(get_script().resource_path.get_base_dir().path_join("godot_story_panel_probe.gd")).new()
			get_tree().root.add_child(history)
			history.fixture = history_row
			history._select("ln_0")
		else:
			history = load("res://addons/dialogic/Modules/DefaultLayoutParts/Layer_History/history_layer.tscn").instantiate()
			get_tree().root.add_child(history)
			history._context_entries = [history_row]
			history._context_total_entries = 1
			history._on_entry_clicked(0)
		check(controller.player.playing and controller._pending.is_empty(), "History log click did not replay cached audio")
		history.queue_free()
		var snapshot: Dictionary = metadata.duplicate(true)
		snapshot.display_text = text
		snapshot.character_id = "twilight"
		check(await RollbackManager._restore_snapshot(snapshot, true), "Backtracking restore failed")
		check(controller.player.playing and controller._pending.is_empty(), "Backtracking did not replay the saved audio")
		controller.replay_history(metadata)
		check(controller.player.playing and controller._pending.is_empty(), "History replay generated instead of reusing cached audio")
		controller.stop()
		DirAccess.remove_absolute(path)
		controller.replay_history(metadata)
		check(not controller.player.playing and controller._pending.is_empty(), "Missing history audio attempted regeneration")
		await frames(3)
	# OFF and timeout must release an in-flight wait immediately.
	for release in ["off", "timeout", "stop", "settings_test"]:
		controller.settings.enabled = true
		controller.settings.text_display_mode = "wait"
		var waiting: Dictionary = controller._row("twilight", "Release pending " + str(release))
		waiting.deadline = Time.get_unix_time_from_system() + 30
		controller._pending[waiting.id] = waiting
		var result := {"finished": false, "allowed": false}
		_probe_prepare(controller, waiting, result)
		await frames(2)
		check(not bool(result.finished), "Wait returned before audio or failure")
		if release == "off":
			controller.set_option("enabled", false)
		elif release == "timeout":
			controller._pending[waiting.id].deadline = 0
			controller._process(0.2)
		elif release == "stop":
			controller.stop_voice()
		else:
			Dialogic.paused = true
			controller.apply_settings(controller.settings)
			controller.test_voice()
			await frames(3)
			check(controller.player.playing and not bool(result.finished), "Settings test cancelled or exposed a waiting story line")
			Dialogic.paused = false
			check(controller._pending.has(waiting.id), "Settings discarded the pending voice job")
			controller._pending[waiting.id].deadline = 0
			controller._process(0.2)
		await frames(3)
		check(bool(result.finished) and bool(result.allowed), "Pending wait not released by " + str(release))
		controller._pending.clear()
		controller.stop()
	controller.settings.enabled = true
	# Show Instantly does not await a pending job.
	controller.settings.text_display_mode = "instant"
	var instant: Dictionary = controller._row("twilight", "Instant mode pending fixture.")
	instant.deadline = Time.get_unix_time_from_system() + 30
	controller._pending[instant.id] = instant
	check(await controller.prepare_line("twilight", str(instant.text)), "Instant mode blocked")
	check(controller._pending.has(instant.id), "Instant mode waited for generation")
	controller._pending.clear()
	# A fixed system prompt always selects the shipped Narrator file, even when
	# the caller accidentally supplies Twilight and omits final punctuation.
	controller.speak("twilight", "You can now ask questions or continue the conversation")
	check(controller.player.playing and controller._pending.is_empty(), "Fixed narrator prompt was regenerated")
	check(controller._current_key == controller.line_id("en", "narrator", "You can now ask questions or continue the conversation."), "System prompt used the wrong voice")
	controller.stop()
	var old_narrator_id: String = controller.line_id("en", "celestia", "Darkness.")
	var old_history := {"voice_id": old_narrator_id, "voice_audio_path": "en/" + old_narrator_id + ".mp3", "voice_speaker": "celestia", "voice_language": "en", "voice_text": "Darkness.", "text": "Darkness.", "is_narrator": true}
	controller.replay_history(old_history, "narrator", "Darkness.")
	var new_narrator_path: String = controller._audio_path(controller._row("narrator", "Darkness."))
	check(controller.player.playing and controller.player.stream.data == FileAccess.get_file_as_bytes(new_narrator_path), "Old narrator history did not replay the new static Narrator clip")
	check(old_history.voice_id == old_narrator_id and controller._pending.is_empty(), "History migration modified the save or regenerated audio")
	controller.stop()
	var player_migrations: Dictionary = preload("res://scripts/voice_mod/voice_base_index.gd").LEGACY_PLAYER_IDS
	for old_id in player_migrations:
		var current_id: String = player_migrations[old_id]
		var fixed_text := ""
		for fixed_row in opening.lines:
			if str(fixed_row.id) == current_id:
				fixed_text = str(fixed_row.text)
		var player_history := {"voice_id": old_id, "voice_audio_path": "en/" + old_id + ".mp3", "voice_speaker": "player", "voice_language": "en", "voice_text": fixed_text, "text": fixed_text, "character": "???", "is_narrator": false}
		controller.replay_history(player_history)
		var path: String = controller._audio_path(controller._row("narrator", fixed_text))
		check(not fixed_text.is_empty() and controller.player.playing and controller.player.stream.data == FileAccess.get_file_as_bytes(path), "Old player history failed to replay Narrator: " + old_id)
		check(player_history.voice_id == old_id and controller._pending.is_empty(), "Player history migration modified save data or regenerated")
		controller.stop()
	await _test_keyboard_advance()
	await _test_cache_cleanup(controller, opening)
	controller.apply_settings(original)
	# Optional real CUDA synthesis: exercise Godot -> Python worker -> MP3 -> player.
	var gpu_python := OS.get_environment("PONY_TEST_GPU_PYTHON")
	if not gpu_python.is_empty():
		controller.settings.enabled = true
		controller.settings.execution_mode = "local"
		controller.settings.python_path = gpu_python
		var sample := "Welcome to Ponyville. This dialogue voice was generated in the background."
		var live_row: Dictionary = controller._row("twilight", sample)
		var narrator_sample := "Every voice is ready before this conversation begins."
		var narrator_row: Dictionary = controller._row("narrator", narrator_sample)
		controller.settings.text_display_mode = "wait"
		controller.settings.omnivoice.num_step = 64
		Dialogic.Text.update_dialog_text("Waiting for real GPU speech.", true)
		var conversation: Node = load("res://scripts/ai/dialogic_ai_conversation.gd").new()
		get_tree().root.add_child(conversation)
		conversation._is_active = true
		conversation._dialogue_queue = [{"type": "dialogue", "speaker": "narrator", "text": narrator_sample, "is_narrator": true}, {"type": "dialogue", "speaker": "twilight", "text": sample, "is_narrator": false}]
		conversation._display_next_dialogue()
		var observed_wait := false
		for _attempt in range(3000):
			if not controller._waiting_key.is_empty():
				observed_wait = true
				check(not str(Dialogic.current_state_info.get("text", "")).contains(narrator_sample), "Real GPU text was shown before audio")
			if controller.player.playing:
				break
			await get_tree().create_timer(0.05).timeout
		check(observed_wait, "Real Ask path did not wait for GPU synthesis")
		check(controller.player.playing and str(Dialogic.current_state_info.get("text", "")).contains(narrator_sample), "Real GPU first narration speech/text did not start together: " + str(controller.status))
		check(FileAccess.file_exists(controller._audio_path(live_row)), "GPU worker did not produce an MP3")
		check(FileAccess.file_exists(controller._audio_path(narrator_row)) and controller._pending.is_empty(), "First text appeared before the full GPU response was ready")
		conversation._is_active = false
		conversation._session_id += 1
		conversation.queue_free()
		Dialogic.Text.skip_text_reveal()
		await frames(5)
		controller.stop()
		DirAccess.remove_absolute(controller._audio_path(live_row))
		DirAccess.remove_absolute(controller._audio_path(narrator_row))
		controller.apply_settings(original)
		print("LIVE_GPU_WORKER_PLAYBACK_OK")
	# Launch the real worker with a Python lacking OmniVoice; failure must be reported.
	var test_python := OS.get_environment("PONY_TEST_PYTHON")
	if not test_python.is_empty():
		controller.settings.execution_mode = "local"
		controller.settings.python_path = test_python
		controller.settings.text_display_mode = "wait"
		check(await controller.prepare_line("spike", "Worker failure regression fixture."), "Failed worker did not release gated text")
		for _attempt in range(300):
			if controller._pending.is_empty():
				break
			await get_tree().create_timer(0.05).timeout
		check(controller._pending.is_empty(), "Failed worker left a pending synthesis job")
		check(not controller.player.playing, "Failed worker started playback")
		controller.stop()
	controller.settings = original
	controller._write_json(controller._folder.path_join("config.json"), original)
	controller._captured = original_capture
	controller.flush_capture()
	settings_menu.queue_free()
	if failures.is_empty():
		print("VOICE_MOD_REGRESSION_OK")
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_keyboard_advance() -> void:
	var conversation: Node = load(get_script().resource_path.get_base_dir().path_join("godot_conversation_probe.gd")).new()
	get_tree().root.add_child(conversation)
	conversation._is_active = true
	Dialogic.current_state = Dialogic.States.IDLE
	Dialogic.paused = false
	Dialogic.Inputs.input_block_timer.stop()
	var result := {"finished": false}
	_probe_advance(conversation, result)
	Dialogic.Inputs.input_was_mouse_input = false
	Dialogic.Inputs.dialogic_action.emit()
	await frames(2)
	await get_tree().create_timer(0.12).timeout
	check(bool(result.finished), "Hovering over controls blocked keyboard dialogue advance")
	conversation._is_active = false
	conversation.queue_free()
	await frames(2)

func _probe_advance(conversation: Node, result: Dictionary) -> void:
	await conversation._wait_for_advance()
	result.finished = true

func _test_cache_cleanup(controller: Node, opening: Dictionary) -> void:
	var base := OS.get_user_data_dir().path_join("voice_mod_regression_cache")
	var voices := base.path_join("data/voices")
	var runtime := base.path_join("data/voice_mod/runtime")
	DirAccess.make_dir_recursive_absolute(voices.path_join("en"))
	DirAccess.make_dir_recursive_absolute(runtime.path_join("session_%s_123" % OS.get_process_id()))
	DirAccess.make_dir_recursive_absolute(runtime.path_join("prompts"))
	var protected: Dictionary = opening.lines[0]
	controller._write_json(voices.path_join("opening_manifest.json"), {"lines": [protected]})
	var protected_path := voices.path_join(str(protected.file))
	var dynamic := voices.path_join("en/" + "a".repeat(64) + ".mp3")
	var important := voices.path_join("en/important.txt")
	var log := runtime.path_join("session_%s_123/worker.log" % OS.get_process_id())
	var unknown := runtime.path_join("session_%s_123/keep-save.json" % OS.get_process_id())
	var prompt := runtime.path_join("prompts/" + "b".repeat(64) + ".pt")
	for path in [protected_path, dynamic, important, log, unknown, prompt]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string("fixture")
		file.close()
	var result: Dictionary = load("res://scripts/voice_mod/voice_cache.gd").clean(voices, runtime)
	check(result.audio == 1 and result.temporary == 2, "Cache cleanup did not remove only owned cache files")
	check(FileAccess.file_exists(protected_path) and FileAccess.file_exists(important) and FileAccess.file_exists(unknown), "Cleanup deleted protected or unknown files")
	var old_folder: String = controller._folder
	var old_session: String = controller._session
	var old_settings: Dictionary = controller.settings.duplicate(true)
	controller._folder = base.path_join("data/voice_mod")
	controller._session = runtime.path_join("session_%s_123" % OS.get_process_id())
	controller.settings.cache_cleanup_days = 1
	controller._write_json(controller._folder.path_join("cache_state.json"), {"last_cleanup": Time.get_unix_time_from_system() - 172800})
	var file := FileAccess.open(dynamic, FileAccess.WRITE)
	file.store_string("fixture")
	file.close()
	controller._process(61.0)
	check(FileAccess.file_exists(dynamic), "Cache was deleted automatically despite removal of automatic cleanup")
	controller.clean_cache()
	check(not FileAccess.file_exists(dynamic) and FileAccess.file_exists(protected_path), "Manual cleanup did not preserve base pack")
	controller._folder = old_folder
	controller._session = old_session
	controller.settings = old_settings
	# Only remove fixtures explicitly created above; never recursively delete user data.
	for path in [protected_path, dynamic, important, log, unknown, prompt, voices.path_join("opening_manifest.json"), base.path_join("data/voice_mod/cache_state.json")]:
		DirAccess.remove_absolute(path)
	for path in [runtime.path_join("session_%s_123" % OS.get_process_id()), runtime.path_join("prompts"), runtime, voices.path_join("en"), voices, base.path_join("data/voice_mod"), base.path_join("data"), base]:
		DirAccess.remove_absolute(path)
	print("CACHE_PROTECTION_MANUAL_ONLY_OK")


func _probe_prepare(controller: Node, row: Dictionary, result: Dictionary) -> void:
	result.allowed = await controller.prepare_line(str(row.speaker), str(row.text))
	result.finished = true

extends Node
var failures: Array[String] = []
var clips: Array[String] = []
var voice: Node
var fixture: PackedByteArray
func _ready():
	_run.call_deferred()
func check(ok: bool, message: String):
	if not ok:
		failures.append(message)
		push_error(message)
func frames(count: int):
	for _i in range(count):
		await get_tree().process_frame
func finish_job(key: String):
	var row: Dictionary = voice._pending[key]
	var path: String = voice._audio_path(row)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(fixture)
	file.close()
	clips.append(path)
	DirAccess.remove_absolute(voice._session.path_join("job_" + key + ".json"))
	voice._write_json(voice._session.path_join("done_" + key + ".json"), {"ok": true})
	voice._process(0.2)
func _run():
	assert(OS.get_user_data_dir().contains("VoiceModQA"))
	voice = load(get_script().resource_path.get_base_dir().path_join("godot_worker_fixture.gd")).new()
	voice.name = "PonyVoiceMod"
	get_tree().root.add_child(voice)
	var original: Dictionary = voice.settings.duplicate(true)
	var base = JSON.parse_string(FileAccess.get_file_as_string(voice._resolve("../voices/opening_manifest.json")))
	fixture = FileAccess.get_file_as_bytes(voice._resolve("../voices/" + str(base.lines[0].file)))
	voice.settings.enabled = true
	voice.settings.execution_mode = "local"
	voice.settings.text_display_mode = "wait"
	Dialogic.paused = false
	Dialogic.Styles.load_style("Default")
	await frames(8)
	for source in ["ask", "custom"]:
		Dialogic.Text.update_dialog_text("Previous visible line.", true)
		var entries: Array = []
		# More than MAX_PENDING; repeated and narrator rows exercise dedup/aliases.
		for i in range(40):
			entries.append({"type": "dialogue", "speaker": "narrator" if i % 2 == 0 else "twi", "is_narrator": i % 2 == 0, "text": "Batch %s fixture %d." % [source, i]})
		entries.append(entries[0].duplicate())
		entries.insert(0, {"type": "command", "command": "noop"})
		var owner: Node
		if source == "ask":
			owner = load("res://scripts/ai/dialogic_ai_conversation.gd").new()
			get_tree().root.add_child(owner)
			owner._is_active = true
			owner._dialogue_queue = entries.duplicate(true)
			owner._display_next_dialogue()
		else:
			owner = load("res://scripts/ai/ai_scene_generator.gd").new()
			get_tree().root.add_child(owner)
			owner._is_playing = true
			owner._scene_queue = entries.duplicate(true)
			owner._play_next_line()
		var completed := 0
		var deadline := Time.get_ticks_msec() + 10000
		while completed < 40 and Time.get_ticks_msec() < deadline:
			await frames(2)
			check(str(Dialogic.current_state_info.get("text", "")) == "Previous visible line.", "First response text appeared before ALL clips completed: " + source)
			check(owner._displayed_lines.is_empty(), "History committed a response line during batch preparation: " + source)
			check(not voice.player.playing, "A batch clip played before the response was ready")
			check(voice._pending.size() <= 1, "Serial worker queue overflowed or accumulated expiring jobs")
			if not voice._pending.is_empty():
				var pending_row: Dictionary = voice._pending[voice._pending.keys()[0]]
				check(str(pending_row.speaker) == ("narrator" if completed < 20 else "twilight"), "Response synthesis switched speakers before completing their group: " + source)
				finish_job(str(voice._pending.keys()[0]))
				completed += 1
		check(completed == 40, "Long response dropped clips past the old queue limit: " + source)
		for _i in range(100):
			if voice.player.playing:
				break
			await get_tree().create_timer(0.01).timeout
		check(voice.player.playing and str(Dialogic.current_state_info.get("text", "")).contains("fixture 0"), "First text/playback did not start when entire response became ready: " + source)
		check(voice._pending.is_empty(), "Response revealed with unfinished synthesis")
		check(voice._current_key == voice.line_id("en", "narrator", "Batch %s fixture 0." % source), "First narrator slide did not play its own prepared audio")
		for _i in range(100):
			Dialogic.Text.skip_text_reveal()
			if owner._edit_enabled:
				break
			await get_tree().create_timer(0.01).timeout
		Dialogic.Inputs.input_block_timer.stop()
		Dialogic.Inputs.input_was_mouse_input = false
		Dialogic.Inputs.dialogic_action.emit()
		for _i in range(100):
			if str(Dialogic.current_state_info.get("text", "")).contains("fixture 1"):
				break
			await get_tree().create_timer(0.01).timeout
		check(str(Dialogic.current_state_info.get("text", "")).contains("fixture 1") and voice._pending.is_empty(), "Advancing a prepared response regenerated or froze: " + source)
		check(voice._current_key == voice.line_id("en", "twilight", "Batch %s fixture 1." % source), "Playback order no longer matches story order")
		if source == "ask":
			owner._is_active = false
		else:
			owner._is_playing = false
		owner._session_id += 1
		Dialogic.Text.skip_text_reveal()
		voice.stop()
		await frames(3)
		owner.queue_free()
		await frames(3)
	for source in ["ask", "custom"]:
		for mode in ["wait", "instant"]:
			await _cached_response(source, mode)
	# Cached narration must wait through a menu, then play when the line reveals.
	var cached_text := "Cached first narrator response fixture."
	var cached_row: Dictionary = voice._row("narrator", cached_text)
	var cached_path: String = voice._audio_path(cached_row)
	var cached_file := FileAccess.open(cached_path, FileAccess.WRITE)
	cached_file.store_buffer(fixture)
	cached_file.close()
	clips.append(cached_path)
	Dialogic.paused = true
	var cached_result := {"finished": false, "allowed": false, "current": true}
	_probe_line(cached_text, cached_result)
	await frames(3)
	check(not cached_result.finished, "Cached narrator line bypassed the overlay pause")
	Dialogic.paused = false
	await frames(3)
	check(cached_result.finished and cached_result.allowed, "Cached narrator did not release after closing the overlay")
	voice.speak("narrator", cached_text)
	check(voice.player.playing and voice._pending.is_empty(), "Cached first narration failed to play or regenerated")
	voice.stop()
	for action in ["off", "stop", "cleanup", "cancel", "failure", "instant"]:
		voice.settings.enabled = true
		voice.settings.text_display_mode = "wait"
		voice._failed.clear()
		var rows := [{"type": "dialogue", "speaker": "twi", "text": "Release fixture " + action}, {"type": "dialogue", "speaker": "twi", "text": "Release second fixture " + action}]
		var result := {"finished": false, "allowed": false, "current": true}
		_probe_batch(rows, result)
		await frames(2)
		check(not result.finished, "Batch did not wait for its first missing clip")
		match action:
			"off": voice.settings.enabled = false
			"stop": voice.stop_voice()
			"cleanup": voice.clean_cache()
			"cancel": result.current = false
			"failure":
				for key in voice._pending.keys():
					voice._write_json(voice._session.path_join("done_" + str(key) + ".json"), {"ok": false, "error": "QA failure"})
				voice._process(0.2)
				voice.settings.python_path = ""
			"instant": voice.settings.text_display_mode = "instant"
		# Failure can submit the second clip; fail every queued fixture deterministically.
		for _i in range(20):
			await frames(1)
			if result.finished:
				break
			if action == "failure":
				for key in voice._pending.keys():
					voice._write_json(voice._session.path_join("done_" + str(key) + ".json"), {"ok": false, "error": "QA failure"})
				voice._process(0.2)
		check(result.finished and result.allowed == (action != "cancel"), "Batch did not release safely after " + action)
		voice.stop()
		for key in voice._pending.keys():
			DirAccess.remove_absolute(voice._session.path_join("job_" + str(key) + ".json"))
		voice._pending.clear()
	for path in clips:
		DirAccess.remove_absolute(path)
	voice.settings = original
	voice._write_json(voice._folder.path_join("config.json"), original)
	await Dialogic.end_timeline()
	print("BATCH_AUDIO_REGRESSION_OK" if failures.is_empty() else "BATCH_AUDIO_REGRESSION_FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)
func _probe_batch(rows: Array, result: Dictionary):
	result.allowed = await voice.prepare_response(rows, func(): return bool(result.current))
	result.finished = true
func _probe_line(text: String, result: Dictionary):
	result.allowed = await voice.prepare_line("narrator", text, func(): return bool(result.current))
	result.finished = true
func _cached_response(source: String, mode: String):
	var text := "Cached first %s narration in %s mode." % [source, mode]
	var row: Dictionary = voice._row("narrator", text)
	var path: String = voice._audio_path(row)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(fixture)
	file.close()
	clips.append(path)
	voice.settings.text_display_mode = mode
	Dialogic.paused = true # A stale input/edit pause, with no visible overlay.
	var owner: Node
	var entries := [{"type": "dialogue", "speaker": "narrator", "is_narrator": true, "text": text}]
	if source == "ask":
		owner = load("res://scripts/ai/dialogic_ai_conversation.gd").new()
		get_tree().root.add_child(owner)
		owner._is_active = true
		owner._dialogue_queue = entries
		owner._display_next_dialogue()
	else:
		owner = load("res://scripts/ai/ai_scene_generator.gd").new()
		get_tree().root.add_child(owner)
		owner._is_playing = true
		owner._scene_queue = entries
		owner._play_next_line()
	for _i in range(100):
		if voice.player.playing:
			break
		await get_tree().create_timer(.01).timeout
	check(not Dialogic.paused and voice.player.playing and voice._current_key == str(row.id), "First cached narrator response remained silent after input pause: " + source + "/" + mode)
	check(str(Dialogic.current_state_info.get("text", "")) == text and voice._pending.is_empty(), "Cached narrator text/audio identity diverged or regenerated")
	check(owner._displayed_lines[0].voice_id == row.id, "First narrator history lost its prepared audio identity")
	if source == "ask":
		owner._is_active = false
	else:
		owner._is_playing = false
	owner._session_id += 1
	Dialogic.Text.skip_text_reveal()
	voice.stop()
	await frames(3)
	owner.queue_free()
	await frames(3)
	voice.settings.text_display_mode = "wait"

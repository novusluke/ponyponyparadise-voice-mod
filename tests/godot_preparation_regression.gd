extends Node
var failures: Array[String] = []
var voice: Node
var fixture: PackedByteArray
var clips: Array[String] = []

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func check(ok: bool, message: String):
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count: int):
	for _i in range(count):
		await get_tree().process_frame

func probe(rows: Array, result: Dictionary):
	result.allowed = await voice.prepare_response(rows, func(): return bool(result.current))
	result.finished = true

func finish_job():
	var key: String = str(voice._pending.keys()[0])
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
	var captured: Dictionary = voice._captured.duplicate(true)
	var base = JSON.parse_string(FileAccess.get_file_as_string(voice._resolve("../voices/opening_manifest.json")))
	fixture = FileAccess.get_file_as_bytes(voice._resolve("../voices/" + str(base.lines[0].file)))
	voice.settings.enabled = true
	voice.settings.text_display_mode = "wait"
	voice.settings.omnivoice.num_step = 64
	Dialogic.paused = false
	Dialogic.Styles.load_style("Default")
	await frames(8)
	# Every Quick Start branch is installed as a protected static clip.
	var quick = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("PONY_QUICK_LINES")))
	check(quick is Dictionary and quick.lines.size() == 101, "Quick Start manifest missing")
	for row in quick.lines:
		var path: String = voice._audio_path(voice._row(str(row.speaker), str(row.text)))
		check(FileAccess.file_exists(path) and voice._protected.has("en/" + str(row.id) + ".mp3"), "Quick Start clip not installed/protected")
		voice.speak(str(row.speaker), str(row.text))
		check(voice.player.playing and voice._pending.is_empty(), "Quick Start used runtime generation")
	voice.stop()
	var rows: Array = []
	for i in range(4):
		rows.append({"type": "dialogue", "speaker": "twilight", "text": "Preparation UI fixture %d." % i})
	var result := {"current": true, "finished": false, "allowed": false}
	probe(rows, result)
	await frames(3)
	check(not result.finished and voice.preparation.visible, "Preparation gate/progress missing")
	voice.preparation.started_msec = Time.get_ticks_msec() - 29900
	voice._update_preparation()
	check(not voice.preparation.prompt.visible, "Slow popup appeared before 30 seconds")
	voice.preparation.started_msec = Time.get_ticks_msec() - 30001
	voice._update_preparation()
	check(voice.preparation.prompt.visible and voice.preparation.steps.value == 64 and voice.preparation.step_label.text == "64 steps", "Slow popup timing/current steps wrong")
	await frames(3)
	check(voice.preparation.prompt.get_global_rect().end.y < voice.preparation.label.get_global_rect().position.y, "Slow popup overlaps progress")
	# Menus pause playback and text, while the worker queue stays alive.
	var session: String = voice._session
	var epoch: int = voice._wait_epoch
	Dialogic.paused = true
	voice.apply_settings(voice.settings)
	check(voice._session == session and voice._wait_epoch == epoch and voice._pending.size() == 1, "Saving unchanged settings restarted/cancelled generation")
	get_tree().paused = true
	finish_job()
	await frames(3)
	check(not result.finished and voice._pending.size() == 1, "Preparation stopped through burger/menu pause")
	finish_job()
	await frames(3)
	voice._update_preparation()
	check(voice.preparation.label.text.ends_with("50%") and voice.preparation.bar.value == 50, "Full-response percentage is not based on ready clips")
	# Apply restarts only unfinished work and preserves the response gate/cache.
	var live_menu: Node = load("res://scenes/ui_settings_menu.gd").new()
	get_tree().root.add_child(live_menu)
	voice.preparation.steps.value = 16
	check(voice.preparation.step_label.text == "16 steps", "Popup slider number is stale")
	voice.preparation.apply_button.pressed.emit()
	check(voice.settings.omnivoice.num_step == 16 and voice._session != session and voice._wait_epoch == epoch, "Steps Apply lost the gate or failed to restart unfinished work")
	check(voice._pending.size() == 1 and voice._pending.values()[0].steps == 16, "Worker did not receive selected steps")
	live_menu._voice_options._refresh_status()
	check(live_menu._voice_options.steps.value == 16 and live_menu._voice_options.snapshot.omnivoice.num_step == 16, "An open settings menu retained stale quality after popup Apply")
	live_menu.queue_free()
	check(FileAccess.file_exists(clips[0]) and FileAccess.file_exists(clips[1]), "Steps Apply discarded completed clips")
	finish_job()
	await frames(3)
	finish_job()
	await frames(3)
	check(result.finished and result.allowed and not voice.preparation.visible, "Ready response did not release/hide progress")
	get_tree().paused = false
	Dialogic.paused = false
	# The settings slider reflects the chosen value, and reset returns to 64.
	var menu: Node = load("res://scenes/ui_settings_menu.gd").new()
	get_tree().root.add_child(menu)
	check(menu._voice_options.steps.value == 16, "Settings slider does not reflect popup quality")
	menu._voice_options.reset()
	check(menu._voice_options.steps.value == 64 and menu._voice_options.text_mode.selected == 0, "Quality/wait defaults changed")
	menu.queue_free()
	await frames(2)
	# Main menu invalidates the owner, discards jobs, and cannot play late output.
	voice.settings.omnivoice.num_step = 64
	var cancelled := {"current": true, "finished": false, "allowed": false}
	probe([{"type": "dialogue", "speaker": "twilight", "text": "Cancel on main menu fixture."}], cancelled)
	await frames(2)
	voice._on_scene_leaving()
	await frames(3)
	check(cancelled.finished and not cancelled.allowed and voice._pending.is_empty() and not voice.preparation.visible, "Main menu did not cancel preparation")
	voice.settings = original
	voice._captured = captured
	voice._write_json(voice._folder.path_join("config.json"), original)
	for path in clips:
		DirAccess.remove_absolute(path)
	print("PREPARATION_UI_REGRESSION_OK" if failures.is_empty() else "PREPARATION_UI_REGRESSION_FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)

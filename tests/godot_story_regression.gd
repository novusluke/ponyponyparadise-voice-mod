extends Node
var failures: Array[String] = []
func _ready():
	_run.call_deferred()
func check(value: bool, message: String):
	if not value:
		failures.append(message)
		push_error(message)
func frames(count: int):
	for i in range(count):
		await get_tree().process_frame
func _run():
	assert(OS.get_user_data_dir().contains("VoiceModQA"))
	var voice: Node = load("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree())
	check(voice.get_parent() == get_tree().root, "Voice controller is inside Dialogic's save subsystem collection")
	var unrelated := Node.new()
	Dialogic.add_child(unrelated)
	var full: Dictionary = Dialogic.get_full_state()
	check(full.has("variables") and full.has("manual_advance"), "Saving with voice/non-subsystem children lost the dialogue state")
	unrelated.queue_free()
	await frames(2)
	Dialogic.load_full_state({})
	await frames(8)
	check(Dialogic.current_state_info.has("variables") and Dialogic.current_state_info.has("manual_advance"), "Empty legacy save lost subsystem defaults")
	Dialogic.Inputs.manual_advance.system_enabled = true
	Dialogic.Inputs.manual_advance.disabled_until_next_event = false
	check(Dialogic.Inputs.manual_advance.is_enabled(), "Legacy load disabled manual advancement")
	var original := {}
	var info := {"ai_state": {"rollback_state": {"snapshots": [
		{"background": {"scene": "", "path": "locations/core/Ponyville/golden_oak_library/background.png"}, "variables": {"is_human": true}, "portraits": {}, "timeline": "library_scene", "event_idx": 73},
		{"background": {"scene": "", "path": ""}, "variables": {}, "timeline": "", "event_idx": -1}
	]}}}
	var repaired: Dictionary = load("res://scripts/voice_mod/voice_save_repair.gd").recover(original, info)
	check(original.is_empty(), "Save repair mutated original data")
	check(str(repaired.get("background_argument", "")).ends_with("golden_oak_library/background.png"), "Save repair did not recover the library background")
	check(repaired.get("variables", {}).get("is_human", false), "Save repair lost player variables")
	check(repaired.get("current_event_idx") == 73, "Save repair lost the resume position")
	# A fade from an obsolete ending must not clear a newly loaded background.
	Dialogic.Text.update_dialog_text("Previous scene.", true)
	var ending := DialogicClearEvent.new()
	ending.time = 0.1
	var ending_timeline := DialogicTimeline.new()
	ending_timeline.events = [ending]
	ending_timeline.events_processed = true
	Dialogic.start(ending_timeline)
	await frames(2)
	var loaded := Dialogic.get_full_state()
	loaded.current_timeline = null
	loaded.background_argument = "locations/core/Ponyville/golden_oak_library/background.png"
	loaded.background_scene = ""
	Dialogic.load_full_state(loaded)
	await get_tree().create_timer(0.35).timeout
	check(str(Dialogic.current_state_info.get("background_argument", "")).contains("golden_oak_library"), "An old ending cleared the loaded background")
	# Traverse the real fixed scene into Q&A with an unconfigured AI and no Python.
	voice.settings.enabled = true
	voice.settings.execution_mode = "local"
	voice.settings.python_path = ""
	voice.settings.text_display_mode = "wait"
	Dialogic.paused = false
	Dialogic.VAR.set_variable("is_human", true)
	Dialogic.start("library_scene")
	var saw_question := false
	var reached_input := false
	var deadline := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < deadline:
		check(voice._pending.is_empty(), "Fixed library dialogue requested runtime synthesis")
		var text := str(Dialogic.current_state_info.get("text", ""))
		if text.contains("Is there anything you'd like to know?"):
			saw_question = true
		if AIConversation._ai_conversation != null and AIConversation._ai_conversation.is_active():
			var convo: Node = AIConversation._ai_conversation
			if convo._input_field != null and convo._input_container.visible:
				reached_input = true
				check(not voice.player.playing and voice._current_key.is_empty(), "Previous speech continued into the player question slide")
				check(not convo._is_request_in_flight, "Opening Q&A sent an automatic AI request")
				await test_question_input(convo, "story")
				convo.end_conversation()
				break
		if Dialogic.has_meta("previous_event"):
			var event: Variant = Dialogic.get_meta("previous_event")
			if event is DialogicTextEvent:
				if event.state == event.States.REVEALING:
					Dialogic.Text.skip_text_reveal()
				elif event.state == event.States.DONE:
					await send_key(KEY_ENTER)
		await get_tree().create_timer(0.03).timeout
	check(saw_question and reached_input, "Library froze at Twilight's question instead of opening input/Continue")
	await frames(6)
	check(not AIConversation.is_in_conversation(), "Continue did not exit the optional conversation")
	await Dialogic.end_timeline()
	# Reuse the same question UI in a custom/sandbox conversation.
	GameState.current_mode = GameState.Mode.SANDBOX
	AIConversation.start_conversation(["twi"], "", false, "", false)
	await frames(8)
	var custom: Node = AIConversation._ai_conversation
	check(custom != null and custom.is_active(), "Custom question mode did not start")
	if custom != null and custom.is_active():
		await test_question_input(custom, "custom")
		custom.end_conversation()
	await frames(6)
	voice.stop()
	print("STORY_SAVE_REGRESSION_OK" if failures.is_empty() else "STORY_SAVE_REGRESSION_FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)

func send_key(code: int, unicode: int = 0):
	var key := InputEventKey.new()
	key.keycode = code
	key.unicode = unicode
	key.pressed = true
	Input.parse_input_event(key)
	await frames(2)
	key.pressed = false
	Input.parse_input_event(key)
	await frames(2)

func click_control(control: Control):
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await frames(2)
	var click := InputEventMouseButton.new()
	click.position = point
	click.global_position = point
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await frames(2)
	click.pressed = false
	Input.parse_input_event(click)
	await frames(2)

func test_question_input(convo: Node, context: String):
	var voice: Node = preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree())
	# Replaying the previous line then returning to input models Back/Forward.
	voice.replay_history(voice.history_metadata("twilight", "Hello! My name is Twilight Sparkle, and I'm so happy to meet you!"))
	check(voice.player.playing, "Backtracking fixture did not start audio: " + context)
	convo._show_input_in_textbox()
	check(not voice.player.playing and voice._current_key.is_empty(), "Back/Forward carried speech into player input: " + context)
	var input_deadline := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < input_deadline and (convo._input_field == null or not convo._input_container.is_visible_in_tree() or Dialogic.Animations.is_animating()):
		await get_tree().create_timer(0.01).timeout
	# Exercise Save/close of the real settings overlay at the question boundary.
	var menu: Node = load("res://scenes/ui_settings_menu.gd").new()
	get_tree().root.add_child(menu)
	voice.test_voice()
	menu.open()
	check(not voice.player.playing, "Opening UI Settings did not discard previous audio: " + context)
	await frames(3)
	menu._on_save_pressed()
	await frames(8)
	check(not voice.player.playing, "Closing UI Settings resumed discarded audio: " + context)
	menu.queue_free()
	check(not Dialogic.paused, "Settings left question input paused: " + context)
	check(convo._input_field.is_visible_in_tree() and convo._input_field.size.y > 20 and convo._input_field.editable, "Question field cannot accept text: " + context)
	check(get_viewport().get_visible_rect().encloses(convo._send_button.get_global_rect()), "Ask is outside the viewport after the scene transition: " + context)
	convo._input_field.release_focus()
	await click_control(convo._input_field)
	check(get_viewport().gui_get_focus_owner() == convo._input_field, "Clicking the question field did not focus it: " + context)
	for letter in "hello":
		await send_key(KEY_A + letter.unicode_at(0) - 97, letter.unicode_at(0))
	check(convo._input_field.text == "hello", "Typing at the question prompt failed: " + context)
	# Replace the provider only; leave the real submission/queue/UI code in use.
	var previous: Node = convo._ai_client
	previous.response_received.disconnect(convo._on_ai_response_received)
	previous.request_failed.disconnect(convo._on_ai_request_failed)
	previous.request_started.disconnect(convo._on_ai_request_started)
	previous.queue_free()
	var client: Node = load(get_script().resource_path.get_base_dir().path_join("godot_ai_client_fixture.gd")).new()
	convo.add_child(client)
	convo._ai_client = client
	client.response_received.connect(convo._on_ai_response_received)
	client.request_failed.connect(convo._on_ai_request_failed)
	client.request_started.connect(convo._on_ai_request_started)
	await click_control(convo._send_button)
	check(client.asked == "hello", "Ask did not submit typed text: " + context)
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		if convo._input_container.visible:
			break
		Dialogic.Text.skip_text_reveal()
		await get_tree().create_timer(0.12).timeout
		await send_key(KEY_ENTER)
	check(convo._input_container.visible and not convo._is_request_in_flight, "Completed reply did not return to writable question input: " + context)
	await click_control(convo._input_field)
	await send_key(KEY_A, 97)
	check(convo._input_field.text == "a", "Question input stopped accepting text after a reply: " + context)

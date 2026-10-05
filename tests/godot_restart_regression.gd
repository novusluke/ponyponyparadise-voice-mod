extends Node

var failures: Array[String] = []

func _ready():
	_run.call_deferred()

func frames(count: int):
	for i in range(count):
		await get_tree().process_frame

func check(value: bool, message: String):
	if not value:
		failures.append(message)
		push_error(message)

func first_text() -> Control:
	var nodes := get_tree().get_nodes_in_group("dialogic_dialog_text")
	return nodes[0] if not nodes.is_empty() else null

func wait_for_opening():
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		if str(Dialogic.current_state_info.get("text", "")) == "Darkness.":
			Dialogic.Text.skip_text_reveal()
			await frames(5)
			return
		await frames(1)
	check(false, "New Game did not reach the first opening line; current text: " + str(Dialogic.current_state_info.get("text", "")))

func advance():
	Dialogic.Text.skip_text_reveal()
	await frames(2)
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	Input.parse_input_event(key)
	await frames(2)
	key.pressed = false
	Input.parse_input_event(key)
	await frames(2)

func _run():
	assert(OS.get_user_data_dir().contains("VoiceModQA"))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await frames(20)
	var voice: Node = preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree())
	voice.settings.enabled = false
	main._on_scenario_selected("base")
	await wait_for_opening()
	var baseline: Rect2 = first_text().get_global_rect()
	var slot := "VoiceModRestartTest_%s" % Time.get_ticks_usec()
	check(Dialogic.Save.save(slot, false, Dialogic.Save.ThumbnailMode.NONE, {"game_state": GameState.save_state()}) == OK, "Could not create isolated restart fixture")
	for pause in [0.0, 0.8]:
		main._return_to_main_menu_confirmed()
		await frames(5)
		await main._ensure_save_load_menu()._perform_load(slot)
		await frames(12)
		check(main.is_in_game, "Load did not enter the game")
		var old_layout: Node = Dialogic.Styles.get_layout_node()
		check(is_instance_valid(old_layout), "Load did not restore a dialogue layout")
		voice.test_voice()
		main._return_to_main_menu_confirmed()
		check(not voice.player.playing, "Returning to title kept speech playing")
		check(not Dialogic.Styles.has_active_layout_node(), "Title retained a loaded dialogue layout")
		if pause > 0:
			await get_tree().create_timer(pause).timeout
		main._on_scenario_selected("base")
		await wait_for_opening()
		var text := first_text()
		check(text != null and text.is_visible_in_tree(), "Opening text was hidden after Load/Title/New Game")
		if text != null:
			check(text.get_global_rect().is_equal_approx(baseline), "Loaded textbox geometry leaked into New Game")
			check(get_viewport().get_visible_rect().encloses(text.get_global_rect()), "New Game dialogue lies outside the viewport")
		check(not AIConversation.is_in_conversation(), "A loaded AI conversation survived New Game")
		await advance()
		check(str(Dialogic.current_state_info.get("text", "")) == "Weight.", "New Game cannot advance after loading")
	# A load waiting for the next frame must not restore its timeline after a reset.
	var stale := Dialogic.get_full_state()
	Dialogic.load_full_state(stale)
	main._return_to_main_menu_confirmed()
	main._on_scenario_selected("base")
	await wait_for_opening()
	check(str(Dialogic.current_state_info.get("text", "")) == "Darkness.", "An obsolete save load overwrote the fresh opening")
	main._return_to_main_menu_confirmed()
	Dialogic.Save.delete_slot(slot)
	await frames(3)
	print("LOAD_TITLE_NEW_GAME_OK" if failures.is_empty() else "LOAD_TITLE_NEW_GAME_FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)

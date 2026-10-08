extends Node
var failures: Array[String] = []
var last_mouse := Vector2.ZERO

func _ready():
	_run.call_deferred()

func check(ok: bool, message: String):
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count: int):
	for _i in range(count):
		await get_tree().process_frame

func mouse(point: Vector2, pressed: bool):
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(event)
	await frames(2)

func move_mouse(point: Vector2, dragging: bool = false):
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if dragging else 0
	event.relative = point - last_mouse
	last_mouse = point
	Input.parse_input_event(event)
	await frames(2)

func key(code: int):
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)
	event.pressed = false
	Input.parse_input_event(event)
	await frames(2)

func ready_line():
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		Dialogic.Text.skip_text_reveal()
		if Dialogic.current_state == Dialogic.States.IDLE and not str(Dialogic.current_state_info.get("text", "")).is_empty():
			break
		await get_tree().create_timer(0.01).timeout
	await frames(3)
	Dialogic.Inputs.input_block_timer.stop()
	Dialogic.Inputs.manual_advance.system_enabled = true
	Dialogic.Inputs.manual_advance.disabled_until_next_event = false

func _run():
	assert(OS.get_user_data_dir().contains("VoiceModQA"))
	var voice: Node = load("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree())
	var original: Dictionary = voice.settings.duplicate(true)
	voice.settings.enabled = false
	Dialogic.paused = false
	var timeline := DialogicTimeline.new()
	for i in range(5):
		var event := DialogicTextEvent.new()
		event.text = "Selection and navigation fixture %d. Drag these words to copy the dialogue." % i
		timeline.events.append(event)
	timeline.events_processed = true
	Dialogic.start(timeline)
	await ready_line()
	var text: RichTextLabel = get_tree().get_first_node_in_group("dialogic_dialog_text")
	check(text.selection_enabled and text.focus_mode == Control.FOCUS_ALL, "Dialogue does not support native selection/copy")
	var point := text.get_global_rect().position + Vector2(28, 10)
	await move_mouse(point)
	await mouse(point, true)
	check(Dialogic.current_event_idx == 0, "Mouse-down advanced before selection could start")
	await move_mouse(point + Vector2(110, 0), true)
	# Godot updates the native selection on its held-click timer.
	await get_tree().create_timer(0.15).timeout
	await mouse(point + Vector2(110, 0), false)
	check(Dialogic.current_event_idx == 0, "Dragging selected text advanced the slide")
	check(not text.get_selected_text().is_empty(), "Dragging did not select dialogue text")
	var selected := text.get_selected_text()
	var copy_key := InputEventKey.new()
	copy_key.keycode = KEY_C
	copy_key.ctrl_pressed = true
	copy_key.pressed = true
	Input.parse_input_event(copy_key)
	await frames(2)
	copy_key.pressed = false
	Input.parse_input_event(copy_key)
	check(Dialogic.current_event_idx == 0 and text.get_selected_text() == selected, "Copying changed the current slide or selection")
	await move_mouse(point)
	await mouse(point, true)
	await mouse(point, false)
	check(Dialogic.current_event_idx == 1, "A released click failed to advance exactly one slide")
	await ready_line()
	text.grab_focus()
	await key(KEY_SPACE)
	check(Dialogic.current_event_idx == 2, "Space did not advance exactly one slide with dialogue focus")
	await ready_line()
	text.release_focus()
	await key(KEY_ENTER)
	check(Dialogic.current_event_idx == 3, "Enter did not advance exactly one slide without dialogue focus")
	await ready_line()
	var input := LineEdit.new()
	input.position = Vector2(30, 30)
	input.size = Vector2(300, 40)
	get_tree().root.add_child(input)
	input.grab_focus()
	await key(KEY_SPACE)
	check(Dialogic.current_event_idx == 3, "Typing in a field advanced the story")
	input.queue_free()
	await Dialogic.end_timeline()
	voice.settings = original
	voice._write_json(voice._folder.path_join("config.json"), original)
	print("SELECTION_NAVIGATION_OK" if failures.is_empty() else "SELECTION_NAVIGATION_FAILED")
	get_tree().quit(0 if failures.is_empty() else 1)

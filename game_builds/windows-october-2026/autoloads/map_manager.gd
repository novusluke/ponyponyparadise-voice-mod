extends Node




signal visit_blocked(location_id: String, reason: String)
signal map_opened
signal map_closed
signal sandbox_end_day_sequence_finished(new_day: int)


var _map_instance: Control = null


var _scene_generator: AISceneGenerator = null


var _conversation_bridge: AIConversationBridge = null


var _current_location: LocationData = null
var _current_character_tags: Array[String] = []
var _pending_visit_character_tags: Array[String] = []
var _pending_visit_scene_brief: String = ""
var _pending_visit_conversation_prompt: String = ""
var _pending_visit_keep_scene_brief_in_qa: bool = false
var _current_visit_qa_guidance: String = ""
var _pending_visit_go_alone: bool = false
const MAX_SANDBOX_VISIT_CHARACTERS: = 6


const MAP_SCENE_PATH: = "res://scenes/ui/ponyville_map.tscn"
const PONYVILLE_MAP_MUSIC_PATH: = "regions/core/ponyville/map.mp3"
const CANTERLOT_MAP_MUSIC_PATH: = "regions/core/canterlot/map.mp3"
const DEFAULT_TRANSPORT_HUB_LOCATION_IDS: = ["train_station", "canterlot_train_station", "train", "hot_air_balloon_flying"]
const RUNTIME_RESTRICTED_LOCATION_IDS: = ["dream_realm"]
const DREAM_BACKGROUND_PATH: = "locations/core/standalone/dream/background.png"
const DREAM_MUSIC_PATH: = "locations/core/standalone/dream/bgm.mp3"
const ScenarioEventFlowScript: = preload("res://scripts/flows/scenario_event_flow.gd")
const DialogicForegroundControllerScript: = preload("res://scripts/services/dialogic_foreground_controller.gd")
const LocationDescriptionStorage: = preload("res://scripts/services/location_description_storage.gd")
const LocationSleepOverrides: = preload("res://scripts/services/location_sleep_overrides.gd")


var _map_music_player: AudioStreamPlayer = null
var _map_music_tween: Tween = null
var _suppress_conversation_completed_during_load: bool = false
var _transition_overlay: CanvasLayer = null
var _transition_rect: ColorRect = null
var _transition_tween: Tween = null
var _active_ai_error_canvas: CanvasLayer = null
var _foreground_controller: Node = null
var _bridge_managed_scene_flow_active: bool = false
var _timeline_restore_resume_path: String = ""
var _timeline_restore_resume_event_idx: int = -1
var _resume_sandbox_night_ai_after_load: bool = false


var _train_flow: TrainTravelFlow
var _chrysalis_flow: ChrysalisFlow
var _custom_start_flow: CustomStartFlow
var _load_generation: = 0
var _scenario_event_flow: ScenarioEventFlowScript = null
var _night_flow: SandboxNightFlow = null

const TRANSITION_FADE_IN_TIME: = 0.18
const TRANSITION_FADE_OUT_TIME: = 0.22
const TRANSITION_COLOR: = Color(0.02, 0.02, 0.03, 1.0)


func _ready() -> void :
	_setup_transition_overlay()

	_map_music_player = AudioStreamPlayer.new()
	UISettingsManager.ensure_audio_buses()
	_map_music_player.bus = UISettingsManager.AUDIO_MUSIC_BUS_NAME
	_map_music_player.finished.connect(_on_map_music_finished)
	add_child(_map_music_player)

	_scene_generator = AISceneGenerator.new()
	_scene_generator.set_rollback_owner_key("map_manager")
	add_child(_scene_generator)
	_scene_generator.scene_playback_completed.connect(_on_scene_playback_completed)
	_scene_generator.scene_generation_failed.connect(_on_scene_generation_failed)
	_scene_generator.scene_interrupted.connect(_on_scene_interrupted)


	_conversation_bridge = AIConversationBridge.new()
	_conversation_bridge.set_rollback_owner_key("map_manager")
	add_child(_conversation_bridge)
	_conversation_bridge.set_shared_scene_generator(_scene_generator)
	_conversation_bridge.conversation_completed.connect(_on_conversation_completed)

	_foreground_controller = DialogicForegroundControllerScript.new()
	add_child(_foreground_controller)

	_train_flow = TrainTravelFlow.new(self)
	_chrysalis_flow = ChrysalisFlow.new(self)
	_custom_start_flow = CustomStartFlow.new(self)
	_scenario_event_flow = ScenarioEventFlowScript.new(self)
	_night_flow = SandboxNightFlow.new(self)


func _setup_transition_overlay() -> void :
	_transition_overlay = CanvasLayer.new()
	_transition_overlay.layer = 90
	_transition_overlay.visible = false
	add_child(_transition_overlay)

	_transition_rect = ColorRect.new()
	_transition_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_transition_rect.color = Color(
		TRANSITION_COLOR.r, 
		TRANSITION_COLOR.g, 
		TRANSITION_COLOR.b, 
		0.0
	)
	_transition_overlay.add_child(_transition_rect)


func _fade_transition_in(duration: float = TRANSITION_FADE_IN_TIME) -> void :
	if _transition_overlay == null or _transition_rect == null:
		return

	if _transition_tween:




		var previous_tween: = _transition_tween
		_transition_tween = null
		previous_tween.custom_step(INF)
		previous_tween.kill()

	_transition_overlay.show()
	if duration <= 0.0:
		var opaque_color: = _transition_rect.color
		opaque_color.a = 1.0
		_transition_rect.color = opaque_color
		return

	var target_color: = _transition_rect.color
	target_color.a = 1.0
	_transition_tween = create_tween()
	_transition_tween.tween_property(_transition_rect, "color", target_color, duration)
	await _transition_tween.finished
	_transition_tween = null


func _fade_transition_out(duration: float = TRANSITION_FADE_OUT_TIME) -> void :
	if _transition_overlay == null or _transition_rect == null:
		return

	if _transition_tween:




		var previous_tween: = _transition_tween
		_transition_tween = null
		previous_tween.custom_step(INF)
		previous_tween.kill()

	if duration <= 0.0:
		var transparent_color: = _transition_rect.color
		transparent_color.a = 0.0
		_transition_rect.color = transparent_color
		_transition_overlay.hide()
		return

	var target_color: = _transition_rect.color
	target_color.a = 0.0
	_transition_tween = create_tween()
	_transition_tween.tween_property(_transition_rect, "color", target_color, duration)
	await _transition_tween.finished
	_transition_tween = null
	_transition_overlay.hide()



func open_map() -> void :
	if (
		_custom_start_flow.is_active
		and AIStateCoordinator.is_active()
		and AIStateCoordinator.get_phase() == AIStateCoordinator.Phase.SCENE_GENERATION
	):
		push_warning("[MapManager] Ignoring map open request during active custom start scene playback")
		return
	if _map_instance != null:
		push_warning("[MapManager] Map already open")
		return

	var map_scene: = load(MAP_SCENE_PATH)
	if map_scene == null:
		push_error("[MapManager] Cannot load map scene: %s" % MAP_SCENE_PATH)
		return

	_map_instance = map_scene.instantiate()


	if _map_instance.has_signal("location_clicked"):
		_map_instance.location_clicked.connect(_on_location_clicked)


	get_tree().current_scene.add_child(_map_instance)


	if _map_instance and _map_instance.has_method("set_region"):
		_map_instance.set_region(get_current_region())




	if Dialogic.has_subsystem("Styles") and Dialogic.Styles.has_active_layout_node():
		Dialogic.Styles.get_layout_node().hide()


	var rollback_histories = get_tree().get_nodes_in_group("rollback_history")
	for rh in rollback_histories:
		rh.cleanup_navigation_buttons()


	if Dialogic.has_subsystem("Audio"):
		Dialogic.Audio.stop_all_channels(0.0)


	_play_map_music()

	map_opened.emit()


	var house_offer_shown_now: = _maybe_show_house_offer_prompt()
	_maybe_show_scenario_offers(house_offer_shown_now)
	Log.info("MapManager", "Map opened")



func close_map() -> void :
	if _map_instance == null:
		return

	_map_instance.queue_free()
	_map_instance = null


	stop_map_music()




	if Dialogic.has_subsystem("Styles") and Dialogic.Styles.has_active_layout_node():
		Dialogic.Styles.get_layout_node().show()

	map_closed.emit()
	Log.info("MapManager", "Map closed")



func _play_map_music() -> void :
	if not _map_music_player:
		return

	if _map_music_tween:
		_map_music_tween.kill()
		_map_music_tween = null
	_map_music_player.stop()

	var music_path: = _get_map_music_path_for_region(get_current_region())
	var stream: = AssetLoader.load_audio(ContentPaths.resolve(music_path))
	if stream:
		_map_music_player.stream = stream
		_map_music_player.volume_db = -80
		_map_music_player.play()

		_map_music_tween = create_tween()
		_map_music_tween.tween_property(_map_music_player, "volume_db", 0.0, 0.5)
		_map_music_tween.finished.connect( func(): _map_music_tween = null, CONNECT_ONE_SHOT)



func stop_map_music() -> void :
	if not _map_music_player or not _map_music_player.playing:
		return

	if _map_music_tween:
		_map_music_tween.kill()
		_map_music_tween = null

	_map_music_tween = create_tween()
	_map_music_tween.tween_property(_map_music_player, "volume_db", -80.0, 0.3)
	_map_music_tween.tween_callback(_map_music_player.stop)
	_map_music_tween.finished.connect( func(): _map_music_tween = null, CONNECT_ONE_SHOT)



func _on_map_music_finished() -> void :
	if _map_instance == null or _map_music_player == null:
		return
	if _map_music_player.stream == null:
		return
	_map_music_player.play()



func is_map_open() -> bool:
	return _map_instance != null



func is_sandbox_end_day_sequence_active() -> bool:
	return _night_flow._sandbox_end_day_sequence_active


func get_sandbox_night_residence_intro_text_for_location(location_id: String) -> String:
	return _night_flow.get_sandbox_night_residence_intro_text_for_location(location_id)


func start_sandbox_end_day_sequence() -> bool:
	return _night_flow.start_sandbox_end_day_sequence()


func resume_sandbox_sleep_choice_checkpoint() -> bool:
	return _night_flow.resume_sandbox_sleep_choice_checkpoint()


func arm_sandbox_night_ai_restore() -> void :
	_resume_sandbox_night_ai_after_load = true


func clear_sandbox_night_ai_restore() -> void :
	_resume_sandbox_night_ai_after_load = false


func _ensure_dialogic_layout_visible() -> void :
	var load_generation: = _load_generation
	if not Dialogic.has_subsystem("Styles"):
		return
	if not Dialogic.Styles.has_active_layout_node():
		Dialogic.Styles.load_style()
		await get_tree().process_frame
		if load_generation != _load_generation:
			return
	if Dialogic.Styles.has_active_layout_node():
		Dialogic.Styles.get_layout_node().show()
	await get_tree().create_timer(0.1).timeout


func _show_narrator_line(text: String, is_current: Callable = Callable()) -> void :
	var load_generation: = _load_generation
	if not _is_narration_current(load_generation, is_current):
		return
	var line: = text.strip_edges()
	if line.is_empty():
		return
	if not Dialogic.has_subsystem("Text"):
		Log.d("MapManager", "Narration: %s" % line)
		await get_tree().create_timer(0.4).timeout
		return

	var narrator_char = DialogicResourceUtil.get_character_resource("narrator")
	if narrator_char != null:
		Dialogic.Text.update_name_label(narrator_char)
	CharacterSpriteLoader.call("apply_typing_sound_for_dialogic_character", narrator_char)
	var voice_controller: Node = preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree())
	var voice_valid := _is_narration_current.bind(load_generation, is_current)
	if not await voice_controller.prepare_line("narrator", Dialogic.Text.parse_text(line, 0), voice_valid):
		return
	await Dialogic.Text.update_textbox(line, false)
	if not _is_narration_current(load_generation, is_current):
		return
	var finished: = [false]
	var on_finished: = func(_info: Dictionary): finished[0] = true
	Dialogic.Text.text_finished.connect(on_finished, CONNECT_ONE_SHOT)
	var voice_text: String = Dialogic.Text.update_dialog_text(line)
	voice_controller.speak("narrator", voice_text)
	while not finished[0] and _is_narration_current(load_generation, is_current):
		await get_tree().process_frame
	if Dialogic.Text.text_finished.is_connected(on_finished):
		Dialogic.Text.text_finished.disconnect(on_finished)
	if not _is_narration_current(load_generation, is_current):
		return
	await _wait_for_dialogic_advance(is_current)
	voice_controller.stop()


func _is_narration_current(load_generation: int, is_current: Callable) -> bool:


	return not is_current.is_valid() or (load_generation == _load_generation and bool(is_current.call()))


func _store_narrator_history_entry(text: String) -> int:
	var line: = text.strip_edges()
	if line.is_empty() or not Dialogic.has_subsystem("History"):
		return -1
	Dialogic.History.store_simple_history_entry(line, "Text")
	return Dialogic.History.simple_history_content.size()


func _truncate_dialogic_history_to_size(target_size: int) -> void :
	if target_size < 0 or not Dialogic.has_subsystem("History"):
		return
	var current_size: = Dialogic.History.simple_history_content.size()
	if current_size > target_size:
		Dialogic.History.simple_history_content.resize(target_size)
	if RollbackManager != null:
		if RollbackManager.is_in_rollback_mode():
			RollbackManager.exit_rollback_mode()
		RollbackManager.clear_snapshots()


func _wait_for_dialogic_advance(is_current: Callable = Callable()) -> void :
	var load_generation: = _load_generation
	if not Dialogic.has_subsystem("Text"):
		return
	Dialogic.current_state = Dialogic.States.IDLE
	Dialogic.Text.show_next_indicators()
	while true:
		if not _is_narration_current(load_generation, is_current):
			return
		if Dialogic.paused:
			await get_tree().process_frame
			continue
		if Input.is_action_just_pressed("dialogic_default_action"):
			break
		if Input.is_action_just_pressed("ui_accept"):
			break
		await get_tree().process_frame
	Dialogic.Text.hide_next_indicators()
	await get_tree().create_timer(0.1).timeout


func _show_ai_error_dialog(
	title_text: String, 
	message_text: String, 
	retry_action: Callable = Callable(), 
	secondary_label: String = "", 
	secondary_action: Callable = Callable(), 
	cancel_label: String = "Return to Map", 
	cancel_action: Callable = Callable()
) -> void :
	_close_ai_error_dialog()

	var canvas: = CanvasLayer.new()
	canvas.layer = 95
	add_child(canvas)
	_active_ai_error_canvas = canvas

	var blocker: = Control.new()
	blocker.name = "AIErrorBlocker"
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.add_to_group("ui_blocking_overlay")
	canvas.add_child(blocker)

	var dimmer: = ColorRect.new()
	dimmer.name = "AIErrorDimmer"
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.01, 0.01, 0.03, 0.78)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.add_child(dimmer)

	var panel: = PanelContainer.new()
	panel.name = "AIErrorPanel"
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -360
	panel.offset_top = -150
	panel.offset_right = 360
	panel.offset_bottom = 150
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(panel)

	var panel_style: = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.09, 0.07, 0.14, 0.98)
	panel_style.set_border_width_all(2)
	panel_style.border_color = Color(0.85, 0.45, 0.56, 0.95)
	panel_style.set_corner_radius_all(14)
	panel_style.shadow_color = Color(0, 0, 0, 0.3)
	panel_style.shadow_size = 12
	panel_style.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", panel_style)

	var margin: = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var root: = VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var title: = Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.96))
	root.add_child(title)

	var message: = Label.new()
	message.text = message_text
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_font_size_override("font_size", 14)
	message.add_theme_color_override("font_color", Color(0.86, 0.83, 0.92))
	root.add_child(message)

	var button_row: = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 12)
	root.add_child(button_row)

	var retry_button: = Button.new()
	retry_button.text = "Retry"
	retry_button.custom_minimum_size = Vector2(120, 42)
	retry_button.disabled = not retry_action.is_valid()
	_style_ai_error_button(retry_button, Color(0.42, 0.72, 0.48), Color(0.22, 0.42, 0.24))
	retry_button.pressed.connect( func() -> void :
		_close_ai_error_dialog()
		retry_action.call_deferred()
	)
	button_row.add_child(retry_button)

	if secondary_action.is_valid():
		var secondary_button: = Button.new()
		secondary_button.text = secondary_label if not secondary_label.strip_edges().is_empty() else tr("Edit")
		secondary_button.custom_minimum_size = Vector2(140, 42)
		_style_ai_error_button(secondary_button, Color(0.72, 0.58, 0.36), Color(0.42, 0.3, 0.16))
		secondary_button.pressed.connect( func() -> void :
			_close_ai_error_dialog()
			secondary_action.call_deferred()
		)
		button_row.add_child(secondary_button)

	var settings_button: = Button.new()
	settings_button.text = "API Settings"
	settings_button.custom_minimum_size = Vector2(140, 42)
	_style_ai_error_button(settings_button, Color(0.48, 0.42, 0.78), Color(0.24, 0.22, 0.46))
	settings_button.pressed.connect(_open_api_settings_from_ai_error)
	button_row.add_child(settings_button)

	var cancel_button: = Button.new()
	cancel_button.text = cancel_label
	cancel_button.custom_minimum_size = Vector2(140, 42)
	_style_ai_error_button(cancel_button, Color(0.78, 0.44, 0.48), Color(0.44, 0.2, 0.24))
	cancel_button.pressed.connect( func() -> void :
		_close_ai_error_dialog()
		if cancel_action.is_valid():
			cancel_action.call_deferred()
		else:
			_recover_to_map_after_ai_failure.call_deferred()
	)
	button_row.add_child(cancel_button)


func _close_ai_error_dialog() -> void :
	if _active_ai_error_canvas and is_instance_valid(_active_ai_error_canvas):
		_active_ai_error_canvas.queue_free()
	_active_ai_error_canvas = null


func _style_ai_error_button(button: Button, fill_color: Color, border_color: Color) -> void :
	var normal_style: = StyleBoxFlat.new()
	normal_style.bg_color = fill_color
	normal_style.border_color = border_color
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(8)
	normal_style.content_margin_left = 14
	normal_style.content_margin_right = 14
	normal_style.content_margin_top = 8
	normal_style.content_margin_bottom = 8
	button.add_theme_stylebox_override("normal", normal_style)

	var hover_style: = normal_style.duplicate()
	hover_style.bg_color = fill_color.lerp(Color.WHITE, 0.08)
	button.add_theme_stylebox_override("hover", hover_style)

	var pressed_style: = normal_style.duplicate()
	pressed_style.bg_color = fill_color.darkened(0.08)
	button.add_theme_stylebox_override("pressed", pressed_style)

	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)


func _open_api_settings_from_ai_error() -> void :
	var current_scene: = get_tree().current_scene
	if current_scene and current_scene.has_method("open_api_settings_menu"):
		current_scene.call_deferred("open_api_settings_menu")


func _recover_to_map_after_ai_failure() -> void :
	await _fade_transition_in(0.12)
	if Dialogic.has_subsystem("Text"):
		Dialogic.Text.hide_textbox()
	if Dialogic.has_subsystem("Portraits"):
		await Dialogic.Portraits.leave_all_characters("", 0.0, false)
	CharacterPortraitService.clear_scene_layout_state()
	if Dialogic.has_subsystem("Backgrounds") and Dialogic.Backgrounds.has_background():
		Dialogic.Backgrounds.update_background("", "", 0.0)
	if Dialogic.has_subsystem("Audio"):
		Dialogic.Audio.stop_all_channels(0.0)
	if Dialogic.has_subsystem("Styles") and Dialogic.Styles.has_active_layout_node():
		Dialogic.Styles.get_layout_node().hide()
	AIStateCoordinator.end_session()
	open_map()
	await get_tree().process_frame
	await _fade_transition_out()


func _snapshot_pending_visit_options() -> Dictionary:
	return {
		"character_tags": _pending_visit_character_tags.duplicate(), 
		"scene_brief": _pending_visit_scene_brief, 
		"conversation_prompt": _pending_visit_conversation_prompt, 
		"keep_scene_brief_in_qa": _pending_visit_keep_scene_brief_in_qa, 
		"go_alone": _pending_visit_go_alone, 
	}


func _restore_pending_visit_options(options: Dictionary) -> void :
	_pending_visit_character_tags.clear()
	for raw_tag in options.get("character_tags", []):
		var tag: = str(raw_tag).strip_edges().to_lower()
		if tag.is_empty() or tag in _pending_visit_character_tags:
			continue
		_pending_visit_character_tags.append(tag)
	_pending_visit_scene_brief = str(options.get("scene_brief", "")).strip_edges()
	_pending_visit_conversation_prompt = str(options.get("conversation_prompt", "")).strip_edges()
	_pending_visit_keep_scene_brief_in_qa = bool(options.get("keep_scene_brief_in_qa", false))
	_pending_visit_go_alone = bool(options.get("go_alone", false))


func _retry_location_scene_start(location: LocationData, pending_options: Dictionary = {}) -> void :
	if not pending_options.is_empty():
		_restore_pending_visit_options(pending_options)
	_start_location_scene(location)


func _retry_location_conversation_start(location: LocationData, pending_options: Dictionary = {}) -> void :
	if not pending_options.is_empty():
		_restore_pending_visit_options(pending_options)
	_start_location_conversation(location)


func _retry_solo_location_conversation_start(location: LocationData, pending_options: Dictionary = {}) -> void :
	if not pending_options.is_empty():
		_restore_pending_visit_options(pending_options)
	_start_solo_location_conversation(location)


func _show_custom_start_failure_dialog(error: String) -> void :
	_show_ai_error_dialog(
		tr("Custom Start Failed"), 
		_build_ai_error_message(tr("I couldn't generate the custom opening scene."), error), 
		Callable(_scene_generator, "retry_scene"), 
		tr("Edit Opening"), 
		Callable(self, "_show_custom_start_prompt_edit_dialog").bind(error), 
		tr("Return to Map"), 
		Callable(self, "_return_to_map_after_custom_start_failure")
	)


func _show_custom_start_prompt_edit_dialog(error: String = "") -> void :
	_close_ai_error_dialog()
	var config: = _custom_start_flow.config.duplicate(true)
	var original_prompt: = str(config.get("prompt", ""))

	var canvas: = CanvasLayer.new()
	canvas.layer = 96
	add_child(canvas)
	_active_ai_error_canvas = canvas

	var blocker: = Control.new()
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.add_to_group("ui_blocking_overlay")
	canvas.add_child(blocker)

	var dimmer: = ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.01, 0.01, 0.03, 0.78)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.add_child(dimmer)

	var panel: = PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -380
	panel.offset_top = -245
	panel.offset_right = 380
	panel.offset_bottom = 245
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(panel)

	var panel_style: = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.13, 0.98)
	panel_style.set_border_width_all(2)
	panel_style.border_color = Color(0.68, 0.55, 0.32, 0.95)
	panel_style.set_corner_radius_all(14)
	panel_style.shadow_color = Color(0, 0, 0, 0.3)
	panel_style.shadow_size = 12
	panel_style.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", panel_style)

	var margin: = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var root: = VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title: = Label.new()
	title.text = "Edit Opening"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.94, 0.82))
	root.add_child(title)

	var prompt_edit: = TextEdit.new()
	prompt_edit.text = original_prompt
	prompt_edit.custom_minimum_size = Vector2(0, 260)
	prompt_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	root.add_child(prompt_edit)

	var status_label: = Label.new()
	status_label.text = ""
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color(1.0, 0.68, 0.68))
	root.add_child(status_label)

	var button_row: = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 12)
	root.add_child(button_row)

	var generate_button: = Button.new()
	generate_button.text = "Generate"
	generate_button.custom_minimum_size = Vector2(130, 42)
	_style_ai_error_button(generate_button, Color(0.42, 0.72, 0.48), Color(0.22, 0.42, 0.24))
	generate_button.pressed.connect( func() -> void :
		var updated_prompt: = prompt_edit.text.strip_edges()
		if updated_prompt.length() <= 10:
			status_label.text = "Describe the opening scene before retrying."
			return
		config["prompt"] = updated_prompt
		_close_ai_error_dialog()
		call_deferred("_restart_custom_start_with_config", config)
	)
	button_row.add_child(generate_button)

	var back_button: = Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(120, 42)
	_style_ai_error_button(back_button, Color(0.48, 0.42, 0.78), Color(0.24, 0.22, 0.46))
	back_button.pressed.connect( func() -> void :
		_close_ai_error_dialog()
		call_deferred("_show_custom_start_failure_dialog", error)
	)
	button_row.add_child(back_button)

	var map_button: = Button.new()
	map_button.text = "Return to Map"
	map_button.custom_minimum_size = Vector2(140, 42)
	_style_ai_error_button(map_button, Color(0.78, 0.44, 0.48), Color(0.44, 0.2, 0.24))
	map_button.pressed.connect( func() -> void :
		_close_ai_error_dialog()
		call_deferred("_return_to_map_after_custom_start_failure")
	)
	button_row.add_child(map_button)

	prompt_edit.call_deferred("grab_focus")


func _restart_custom_start_with_config(config: Dictionary) -> void :
	AIStateCoordinator.end_session()
	_custom_start_flow.is_active = false
	_custom_start_flow.scene_interrupted = false
	_custom_start_flow.start(config)


func _return_to_map_after_custom_start_failure() -> void :
	await _custom_start_flow.finish_transition(true, false)


func _recover_sleepover_after_ai_failure() -> void :
	if SleepoverSystem != null:
		SleepoverSystem.clear_all_state()
	await _recover_to_map_after_ai_failure()


func _build_ai_error_message(prefix: String, error: String) -> String:
	var trimmed_error: = error.strip_edges()
	if trimmed_error.is_empty():
		return prefix
	return "%s\n\n%s" % [prefix, trimmed_error]


func _fade_to_black_and_stop_music(fade_length: float = 1.0) -> void :
	var fade: = maxf(0.2, fade_length)
	if Dialogic.has_subsystem("Audio"):
		Dialogic.Audio.update_audio("music", "", {"fade_length": fade})
	if Dialogic.has_subsystem("Backgrounds"):
		Dialogic.Backgrounds.update_background("", CustomStartFlow.BLACK_BACKGROUND_PATH, fade)
	await get_tree().create_timer(fade + 0.2).timeout










func prepare_and_start_scene(
	location: LocationData, 
	character_tags: Array[String], 
	scene_brief: String, 
	keep_scene_brief_in_qa: bool = false, 
	conversation_prompt: String = ""
) -> void :
	_pending_visit_character_tags = character_tags.duplicate()
	_pending_visit_scene_brief = scene_brief
	_pending_visit_conversation_prompt = conversation_prompt
	_pending_visit_keep_scene_brief_in_qa = keep_scene_brief_in_qa
	_pending_visit_go_alone = false
	_start_location_scene(location)



func set_current_scene(location: LocationData, character_tags: Array[String]) -> void :
	_current_location = location
	_current_character_tags = character_tags.duplicate()



func clear_pending_visit() -> void :
	_pending_visit_character_tags.clear()
	_pending_visit_scene_brief = ""
	_pending_visit_conversation_prompt = ""
	_pending_visit_keep_scene_brief_in_qa = false
	_pending_visit_go_alone = false



func reset_chrysalis_state() -> void :
	_chrysalis_flow.pending_followup_check = false
	_chrysalis_flow.pending_custom_qa_prompt = false



func start_scene_generation(location: LocationData, character_tags: Array[String], story_context: String, scene_brief: String = "", system_prompt: String = "", user_prompt: String = "", overrides: Dictionary = {}, prefill_scope: String = "") -> void :
	AIStateCoordinator.begin_scene_generation(location, character_tags)
	AIStateCoordinator.register_scene_generator(_scene_generator)
	_scene_generator.generate_scene(location, character_tags, story_context, scene_brief, system_prompt, user_prompt, overrides, prefill_scope)


func get_conversation_bridge() -> AIConversationBridge:
	return _conversation_bridge



func get_current_location_id() -> String:
	if _current_location != null:
		return _current_location.id
	return ""


func start_custom_start(config: Dictionary) -> void :
	_custom_start_flow.start(config)


func _run_custom_start_deferred(config: Dictionary, sequence_token: int = -1) -> void :
	await _custom_start_flow.run(config, sequence_token)



func _on_location_clicked(location_id: String) -> void :
	var location: = LocationDatabase.get_location(location_id)
	var map_location: = _get_map_location_for_click(location_id)
	if GameState.current_mode == GameState.Mode.SANDBOX and map_location != null:
		location = map_location
	elif GameState.current_mode == GameState.Mode.STORY:
		var story_location: = _resolve_story_map_click_location(map_location, location)
		if story_location != null:
			location = story_location

	if location == null:
		push_error("[MapManager] Unknown location: %s" % location_id)
		return

	if GameState.current_mode == GameState.Mode.STORY:
		_handle_story_visit(location)
	else:
		_handle_sandbox_visit(location)


func _get_map_location_for_click(location_id: String) -> LocationData:
	if _map_instance == null or not _map_instance.has_method("get_map_location_for_id"):
		return null
	return _map_instance.get_map_location_for_id(location_id)


func _resolve_story_map_click_location(map_location: LocationData, fallback_location: LocationData) -> LocationData:
	var clicked_location: = map_location if map_location != null else fallback_location
	if clicked_location == null:
		return fallback_location

	var candidate_ids: = _get_story_hotspot_candidate_ids(clicked_location)
	if candidate_ids.is_empty():
		return fallback_location

	for loc_id in GameState.REQUIRED_STORY_LOCATIONS:
		if loc_id in candidate_ids and not GameState.has_visited(loc_id):
			var required_location: = LocationDatabase.get_location(loc_id)
			if required_location != null:
				return required_location

	for loc_id in GameState.OPTIONAL_STORY_LOCATIONS:
		if loc_id in candidate_ids and not GameState.has_visited(loc_id):
			var optional_location: = LocationDatabase.get_location(loc_id)
			if optional_location != null:
				return optional_location



	for loc_id in GameState.REQUIRED_STORY_LOCATIONS:
		if loc_id in candidate_ids:
			var visited_required: = LocationDatabase.get_location(loc_id)
			if visited_required != null:
				return visited_required
	for loc_id in GameState.OPTIONAL_STORY_LOCATIONS:
		if loc_id in candidate_ids:
			var visited_optional: = LocationDatabase.get_location(loc_id)
			if visited_optional != null:
				return visited_optional

	return fallback_location


func _get_story_hotspot_candidate_ids(location: LocationData) -> Array[String]:
	var result: Array[String] = []
	if location == null:
		return result

	_append_location_candidate_id(result, location.id)
	_append_location_candidate_id(result, location.map_hotspot_default_location_id)
	_append_location_candidate_id(result, location.map_hotspot_manifest_default_location_id)
	for raw_id in location.map_hotspot_location_ids:
		_append_location_candidate_id(result, str(raw_id))
	return result


func _append_location_candidate_id(target: Array[String], raw_id: String) -> void :
	var normalized: = LocationDatabase.resolve_location_id(raw_id).strip_edges()
	if normalized.is_empty() or normalized in target:
		return
	target.append(normalized)



func _handle_story_visit(location: LocationData) -> void :
	if location.id == "golden_oak_library":
		_handle_story_library_click(location)
		return


	if GameState.has_visited(location.id):
		_show_revisit_blocked(location)
		return


	if _map_instance and _map_instance.has_method("show_location_prompt"):
		_map_instance.show_location_prompt(location)
	else:

		_accept_story_visit(location)


func _handle_story_library_click(location: LocationData) -> void :
	if not GameState.is_story_complete():
		var required_remaining: = _get_unvisited_required_location_names()
		if _map_instance and _map_instance.has_method("show_story_library_blocked"):
			_map_instance.show_story_library_blocked(location, required_remaining)
		return

	request_story_completion()



func accept_visit(location_id: String) -> bool:
	var location: = LocationDatabase.get_location(location_id)
	if location == null:
		return false

	if GameState.current_mode == GameState.Mode.STORY:
		_accept_story_visit(location)
		return true
	else:
		clear_pending_visit()
		if not _can_accept_sandbox_visit(location):
			return false
		_accept_sandbox_visit(location)
		return true


func request_visit(location_id: String) -> bool:
	var location: = LocationDatabase.get_location(location_id)
	if location == null:
		push_warning("[MapManager] request_visit called with unknown location: %s" % location_id)
		return false

	if GameState.current_mode == GameState.Mode.STORY:
		_handle_story_visit(location)
		return true
	else:
		return _handle_sandbox_visit(location)


func accept_visit_with_options(
	location_id: String, 
	character_tags: Array[String], 
	custom_instructions: String = "", 
	keep_scene_prompt_in_qa: bool = false, 
	conversation_prompt: String = ""
) -> bool:
	var location: = LocationDatabase.get_location(location_id)
	if location == null or GameState.current_mode != GameState.Mode.SANDBOX:
		clear_pending_visit()
		return false
	if not _can_accept_sandbox_visit(location):
		return false
	var visible_tags: Array[String] = CharacterSpriteLoader.get_all_tags()
	var visible_lookup: Dictionary = {}
	for visible_tag in visible_tags:
		visible_lookup[str(visible_tag).strip_edges().to_lower()] = true
	var sanitized_tags: Array[String] = []
	for raw_tag in character_tags:
		var tag: = str(raw_tag).strip_edges().to_lower()
		if tag.is_empty() or tag in sanitized_tags or not visible_lookup.has(tag):
			continue
		sanitized_tags.append(tag)
		if sanitized_tags.size() >= MAX_SANDBOX_VISIT_CHARACTERS:
			break
	if sanitized_tags.is_empty():
		clear_pending_visit()
		visit_blocked.emit(location.id, "invalid_cast")
		return false
	_pending_visit_character_tags = sanitized_tags
	_pending_visit_scene_brief = custom_instructions.strip_edges()
	_pending_visit_conversation_prompt = conversation_prompt.strip_edges()
	_pending_visit_keep_scene_brief_in_qa = keep_scene_prompt_in_qa
	_pending_visit_go_alone = false
	_accept_sandbox_visit(location)
	return true


func accept_visit_alone(
	location_id: String, 
	custom_instructions: String = "", 
	keep_scene_prompt_in_qa: bool = false, 
	conversation_prompt: String = ""
) -> bool:
	var location: = LocationDatabase.get_location(location_id)
	if location == null or GameState.current_mode != GameState.Mode.SANDBOX:
		clear_pending_visit()
		return false
	if not _can_accept_sandbox_visit(location):
		return false
	_pending_visit_character_tags.clear()
	_pending_visit_scene_brief = custom_instructions.strip_edges()
	_pending_visit_conversation_prompt = conversation_prompt.strip_edges()
	_pending_visit_keep_scene_brief_in_qa = keep_scene_prompt_in_qa
	_pending_visit_go_alone = true
	_accept_sandbox_visit(location)
	return true


func _can_accept_sandbox_visit(location: LocationData) -> bool:
	if location == null or GameState.current_mode != GameState.Mode.SANDBOX:
		clear_pending_visit()
		return false
	if _is_runtime_location_restricted(location.id):
		clear_pending_visit()
		visit_blocked.emit(location.id, "restricted_location")
		return false
	if location.id == "user_house" and not GameState.owns_house:
		clear_pending_visit()
		visit_blocked.emit(location.id, "house_locked")
		if _map_instance and _map_instance.has_method("show_house_move_in_prompt"):
			_map_instance.show_house_move_in_prompt(location)
		return false
	if GameState.can_visit(location.id):
		return true
	clear_pending_visit()
	visit_blocked.emit(location.id, "daily_limit")
	_show_daily_limit_reached()
	return false


func bring_character_to_location(tag: String, location_id: String, refresh_ui: bool = true) -> bool:
	if GameState.current_mode != GameState.Mode.SANDBOX:
		return false
	var ok: = CharacterScheduleManager.move_character_for_current_timeslot(tag, location_id)
	if ok and refresh_ui and _map_instance and _map_instance.has_method("refresh"):
		_map_instance.refresh()
	return ok



func _accept_story_visit(location: LocationData) -> void :

	GameState.mark_visited(location.id)
	await _fade_transition_in()


	close_map()


	_start_location_scene(location)



func _show_revisit_blocked(location: LocationData) -> void :
	visit_blocked.emit(location.id, "already_visited")


	if _map_instance and _map_instance.has_method("show_revisit_message"):
		_map_instance.show_revisit_message(location)



func _start_location_scene(location: LocationData) -> void :
	Log.d("MapManager", "Starting AI scene for: %s" % location.id)
	_current_location = location
	_current_character_tags.clear()


	var character_tags: = _resolve_location_character_tags(location)

	_current_character_tags = character_tags.duplicate()
	var scene_brief: = _resolve_visit_scene_brief(location, _pending_visit_scene_brief)
	var retry_options: = _snapshot_pending_visit_options()
	_current_visit_qa_guidance = _build_session_qa_guidance(
		_pending_visit_conversation_prompt, 
		_pending_visit_scene_brief, 
		_pending_visit_keep_scene_brief_in_qa
	)
	_pending_visit_character_tags.clear()
	_pending_visit_scene_brief = ""
	_pending_visit_conversation_prompt = ""
	_pending_visit_keep_scene_brief_in_qa = false
	_pending_visit_go_alone = false

	if not APIConfigManager.is_configured():
		push_warning("[MapManager] API not configured, blocking AI visit")
		_show_ai_error_dialog(
			tr("AI Setup Required"), 
			tr("This visit needs a working AI configuration before it can generate a scene."), 
			Callable(self, "_retry_location_scene_start").bind(location, retry_options)
		)
		return


	AIStateCoordinator.begin_scene_generation(location, character_tags)
	AIStateCoordinator.register_scene_generator(_scene_generator)


	await _setup_scene_visuals(location)
	await get_tree().process_frame
	await _fade_transition_out()


	var story_context: = _get_story_context()


	_scene_generator.generate_scene(location, character_tags, story_context, scene_brief)


func _start_location_conversation(location: LocationData) -> void :
	Log.d("MapManager", "Starting direct Q&A for: %s" % location.id)
	_current_location = location
	_current_character_tags.clear()

	var character_tags: = _resolve_location_character_tags(location)
	_current_character_tags = character_tags.duplicate()
	var retry_options: = _snapshot_pending_visit_options()
	_current_visit_qa_guidance = _build_session_qa_guidance(
		_pending_visit_conversation_prompt, 
		_pending_visit_scene_brief, 
		_pending_visit_keep_scene_brief_in_qa
	)
	_pending_visit_character_tags.clear()
	_pending_visit_scene_brief = ""
	_pending_visit_conversation_prompt = ""
	_pending_visit_keep_scene_brief_in_qa = false
	_pending_visit_go_alone = false

	if not APIConfigManager.is_configured():
		push_warning("[MapManager] API not configured, blocking AI conversation")
		_show_ai_error_dialog(
			tr("AI Setup Required"), 
			tr("This visit needs a working AI configuration before it can start the conversation."), 
			Callable(self, "_retry_location_conversation_start").bind(location, retry_options)
		)
		return

	AIStateCoordinator.begin_qa_conversation(character_tags, location)

	await _setup_scene_visuals(location)
	show_ui_after_loading()
	await get_tree().process_frame
	await _fade_transition_out()
	var custom_prompt: = _resolve_visit_conversation_prompt(location, _chrysalis_flow.consume_pending_qa_prompt(character_tags), character_tags)
	_conversation_bridge.start_conversation(character_tags, "", true, custom_prompt)


func _start_solo_location_conversation(location: LocationData) -> void :
	Log.d("MapManager", "Starting solo exploration Q&A for: %s" % location.id)
	_current_location = location
	_current_character_tags.clear()

	var scene_brief: = _pending_visit_scene_brief
	var conversation_prompt: = _pending_visit_conversation_prompt
	var keep_scene_brief_in_qa: = _pending_visit_keep_scene_brief_in_qa
	var retry_options: = _snapshot_pending_visit_options()
	_pending_visit_character_tags.clear()
	_pending_visit_scene_brief = ""
	_pending_visit_conversation_prompt = ""
	_pending_visit_keep_scene_brief_in_qa = false
	_pending_visit_go_alone = false

	if not APIConfigManager.is_configured():
		push_warning("[MapManager] API not configured, blocking solo AI conversation")
		_show_ai_error_dialog(
			tr("AI Setup Required"), 
			tr("This solo exploration needs a working AI configuration before it can start."), 
			Callable(self, "_retry_solo_location_conversation_start").bind(location, retry_options)
		)
		return

	AIStateCoordinator.begin_qa_conversation([], location)

	await _setup_scene_visuals(location)
	show_ui_after_loading()
	await get_tree().process_frame
	await _fade_transition_out()
	await _show_narrator_line(_build_solo_visit_intro(location))

	var solo_prompt: = _build_solo_session_prompt(location, scene_brief, keep_scene_brief_in_qa, conversation_prompt)
	_conversation_bridge.start_conversation([], "", false, solo_prompt)


func _resolve_location_character_tags(location: LocationData) -> Array[String]:
	var character_tags: Array[String] = []
	if GameState.current_mode == GameState.Mode.SANDBOX and _pending_visit_go_alone:
		character_tags = []
	elif GameState.current_mode == GameState.Mode.SANDBOX and not _pending_visit_character_tags.is_empty():
		character_tags = _pending_visit_character_tags.duplicate()
	elif GameState.current_mode == GameState.Mode.SANDBOX:
		if _should_use_scenario_visit_scenes():
			character_tags = _get_scenario_visit_scene_characters(location.id)
		if character_tags.is_empty():
			character_tags = CharacterScheduleManager.get_characters_at_location(location.id)
	else:
		if _should_use_scenario_visit_scenes():
			character_tags = _get_scenario_visit_scene_characters(location.id)
		if character_tags.is_empty():
			for char_tag in location.characters:
				character_tags.append(char_tag)


	var has_twilight: = "twi" in character_tags or "twilight" in character_tags
	if not has_twilight and GameState.current_mode == GameState.Mode.STORY:

		character_tags.insert(0, "twi")


	if character_tags.is_empty() and not location.characters.is_empty():
		for char_tag in location.characters:
			character_tags.append(char_tag)

	if GameState.current_mode == GameState.Mode.SANDBOX and character_tags.size() > MAX_SANDBOX_VISIT_CHARACTERS:
		character_tags = character_tags.slice(0, MAX_SANDBOX_VISIT_CHARACTERS)

	return character_tags


func get_visit_scene_characters(location_id: String) -> Array[String]:
	return _get_scenario_visit_scene_characters(location_id)


func get_visit_scene_brief(location: LocationData, requested_brief: String = "") -> String:
	return _resolve_visit_scene_brief(location, requested_brief)


func _get_scenario_visit_scene_characters(location_id: String) -> Array[String]:
	var out: Array[String] = []
	if not _should_use_scenario_visit_scenes():
		return out
	if ScenarioVisitSceneManager == null:
		return out
	if not ScenarioVisitSceneManager.has_scene_for_location(location_id):
		return out
	for raw_tag in ScenarioVisitSceneManager.get_characters_for_location(location_id):
		var tag: = str(raw_tag).strip_edges().to_lower()
		if tag.is_empty() or tag in out:
			continue
		if CharacterSpriteLoader != null and CharacterSpriteLoader.get_dialogic_character(tag) == null:
			Log.warn("MapManager", "scenario visit scene for '%s' references unknown character '%s'" % [location_id, tag])
			continue
		out.append(tag)
	return out


func _resolve_visit_scene_brief(location: LocationData, requested_brief: String) -> String:
	var brief: = requested_brief.strip_edges()
	if not _should_use_scenario_visit_scenes():
		return brief
	if location == null or ScenarioVisitSceneManager == null:
		return brief
	var scenario_brief: = ScenarioVisitSceneManager.get_scene_prompt_for_location(location.id)
	if scenario_brief.is_empty():
		return brief
	if brief.is_empty():
		return scenario_brief
	return "%s\n\nPlayer visit instructions: %s" % [scenario_brief, brief]


func _resolve_visit_conversation_prompt(location: LocationData, fallback_prompt: String = "", character_tags: Array = []) -> String:
	var prompt: = fallback_prompt.strip_edges()
	var session_guidance: = _current_visit_qa_guidance.strip_edges()
	if not _should_use_scenario_visit_scenes():
		if prompt.is_empty() and not session_guidance.is_empty():
			return _build_visit_conversation_prompt(character_tags, "", session_guidance)
		return _append_prompt_section(prompt, session_guidance)
	if location == null or ScenarioVisitSceneManager == null:
		if prompt.is_empty() and not session_guidance.is_empty():
			return _build_visit_conversation_prompt(character_tags, "", session_guidance)
		return _append_prompt_section(prompt, session_guidance)
	var scenario_prompt: = ScenarioVisitSceneManager.get_conversation_prompt_for_location(location.id)
	if scenario_prompt.is_empty() and session_guidance.is_empty():
		return prompt
	if prompt.is_empty():
		return _build_visit_conversation_prompt(character_tags, scenario_prompt, session_guidance)
	if not scenario_prompt.is_empty():
		prompt = "%s\n\n## Scenario Visit Guidance\n%s" % [prompt, scenario_prompt]
	return _append_prompt_section(prompt, session_guidance)


func _build_visit_conversation_prompt(character_tags: Array, scenario_prompt: String = "", session_guidance: String = "") -> String:
	var guidance: = scenario_prompt.strip_edges()
	var session: = session_guidance.strip_edges()
	if guidance.is_empty() and session.is_empty():
		return ""

	var prompt_manager: = PromptManager.new()
	var characters: Array[CharacterData] = []
	for raw_tag in character_tags:
		var tag: = str(raw_tag).strip_edges().to_lower()
		if tag.is_empty():
			continue
		var char_data: = prompt_manager.load_character(tag)
		if char_data != null and char_data.is_valid():
			characters.append(char_data)

	var sections: Array[String] = []
	if not guidance.is_empty():
		sections.append("## Scenario Visit Guidance\n%s" % guidance)
	if not session.is_empty():
		sections.append(session)

	if characters.is_empty():
		return "\n\n".join(sections)

	var base_prompt: = prompt_manager.build_qa_prompt(characters, "")
	if base_prompt.strip_edges().is_empty():
		return "\n\n".join(sections)
	return preload("res://scripts/services/live_qa_prompt.gd").compose(base_prompt, "\n\n".join(sections))


func _build_session_qa_guidance(conversation_prompt: String, scene_prompt: String, keep_scene_prompt_in_qa: bool) -> String:
	var sections: Array[String] = []
	var conversation: = conversation_prompt.strip_edges()
	if not conversation.is_empty():
		sections.append("## Scenario Q&A Guidance\n%s" % conversation)
	var scene: = scene_prompt.strip_edges()
	if keep_scene_prompt_in_qa and not scene.is_empty():
		sections.append(preload("res://scripts/services/initial_setup_prompt.gd").section(preload("res://scripts/services/initial_setup_prompt.gd").TITLES[1], scene))
	return "\n\n".join(sections)


func _append_prompt_section(prompt: String, section: String) -> String:
	var base: = prompt.strip_edges()
	var extra: = section.strip_edges()
	if extra.is_empty():
		return base
	if base.is_empty():
		return extra
	return "%s\n\n%s" % [base, extra]


func _should_use_scenario_visit_scenes() -> bool:
	return GameState.current_mode == GameState.Mode.STORY



func _setup_scene_visuals(location: LocationData) -> void :
	var load_generation: = _load_generation

	if Dialogic.has_subsystem("Styles"):
		if not Dialogic.Styles.has_active_layout_node():
			Dialogic.Styles.load_style()
		else:
			Dialogic.Styles.get_layout_node().show()


	await get_tree().process_frame
	if load_generation != _load_generation:
		return



	_hide_ui_during_loading()



	await _setup_background_and_audio(location)




func _setup_background_and_audio(location: LocationData) -> void :
	if _foreground_controller != null:
		_foreground_controller.set_current_location(location)


	if not location.background.is_empty():
		Log.d("MapManager", "Setting background: %s" % location.background)
		Dialogic.Backgrounds.update_background("", location.background, 0.0)


	if not location.music.is_empty():
		var selected_music: = MusicMixManager.select_track(location)
		Log.d("MapManager", "Setting music: %s" % selected_music)
		Dialogic.Audio.update_audio("music", selected_music, {"fade_length": 1.0, "loop": true})

	await get_tree().process_frame





func _build_solo_visit_intro(location: LocationData) -> String:
	if location == null:
		return tr("You arrive alone.")
	return tr("You arrive alone at %s.") % location.display_name


func _build_solo_session_prompt(location: LocationData, scene_brief: String, retain: bool, guidance: String) -> String:
	var prompt: = _build_solo_exploration_prompt(location)
	if not retain and not scene_brief.strip_edges().is_empty():
		prompt += "\n\n" + preload("res://scripts/services/initial_setup_prompt.gd").section("## Player Intent", scene_brief, true)
	return _append_prompt_section(prompt, _build_session_qa_guidance(guidance, scene_brief, retain))


func _build_solo_exploration_prompt(location: LocationData, scene_brief: String = "") -> String:
	var location_name: = location.display_name if location != null else "this place"
	var location_id: = location.id if location != null else ""
	var location_desc: = LocationDescriptionStorage.get_effective_description(location)





	var lines: Array[String] = [
		"## Solo Exploration Mode", 
		"The player is exploring alone. Only the narrator is present at the start.", 
		"Respond as the narrator by default using lines like: narrator \"...\"", 
		"Describe the place, atmosphere, discoveries, and the immediate consequences of the player's actions.", 
		"Do not require any existing character to be present, introduced, or mentioned.", 
		"Whether characters can join the scene is governed by the runtime scene-command rules included with each turn; follow those rules exactly.", 
		"Write dialogue lines only for characters currently present in the scene or entering it under the current rules; while nopony is present, keep every line narrator-only.", 
		"If arrivals are currently allowed, keep them occasional and narratively justified; at the start of this conversation, keep the scene player + narrator only.", 
		"", 
		"## Starting Situation", 
		"Location id: %s" % (location_id if not location_id.is_empty() else "<unknown>"), 
		"Location name: %s" % location_name, 
		"The player has just arrived alone here and is free to explore.", 
	]
	if not location_desc.is_empty():
		lines.append("Location context: %s" % location_desc)
	var brief: = scene_brief.strip_edges()
	if not brief.is_empty():
		lines.append("")
		lines.append("## Player Intent")
		lines.append(brief)
	return "\n".join(lines)





func _get_story_context() -> String:
	if StorySummaryManager != null:
		return StorySummaryManager.build_active_context()


	var context_lines: Array[String] = []

	if not Dialogic.has_subsystem("History"):
		return ""

	var history: Array = Dialogic.History.get_simple_history()
	if history.is_empty():
		return ""

	for entry in history:
		var text: String = entry.get("text", "")
		var character: String = entry.get("character", "")

		if text.is_empty():
			continue

		if text.ends_with(" left") or text.ends_with(" joined"):
			continue

		if character.is_empty() or character == "null":
			context_lines.append("narrator \"%s\"" % text)
		else:
			var tag: = _get_character_tag(character)
			context_lines.append("%s \"%s\"" % [tag, text])

	return "\n".join(context_lines)



func _get_character_tag(display_name: String) -> String:
	return CharacterPortraitService.get_character_tag(display_name, "full")



func _on_scene_playback_completed() -> void :
	if _bridge_managed_scene_flow_active:
		Log.d("MapManager", "Ignoring shared scene playback completion for bridge-managed flow")
		return
	Log.d(
		"MapManager", 
		"Scene playback completed, starting Q&A (phase=%s, bridge_in_conv=%s, location=%s)" % [
			AIStateCoordinator.get_phase_string(), 
			str(_conversation_bridge != null and _conversation_bridge.is_in_conversation()), 
			_current_location.id if _current_location else "<none>", 
		]
	)

	if _current_location == null:


		Log.d("MapManager", "Ignoring scene playback completion — no current location (bridge handles)")
		return

	if _custom_start_flow.is_active:
		var custom_start_token: = _custom_start_flow._sequence_token
		AIStateCoordinator.unregister_scene_generator()
		AIStateCoordinator.transition_to_qa_conversation()
		if not _custom_start_flow.scene_interrupted:
			var character_tags: = _get_post_scene_active_character_tags(_custom_start_flow.character_tags)
			if character_tags.is_empty():
				character_tags = _filter_valid_character_tags(_custom_start_flow.character_tags, "custom start Q&A fallback tags")
			_custom_start_flow.character_tags = character_tags.duplicate()
			AIStateCoordinator.update_runtime_character_tags(character_tags)
			await _show_narrator_line(tr("You can now ask questions or continue the conversation."), _custom_start_flow.is_sequence_current.bind(custom_start_token))
			if not _custom_start_flow.is_sequence_current(custom_start_token):
				return
			var custom_start_qa_prompt: = _custom_start_flow.build_qa_prompt(character_tags)
			_conversation_bridge.start_conversation(character_tags, "", false, custom_start_qa_prompt)
		else:
			await _custom_start_flow.finish_transition()
		return


	AIStateCoordinator.unregister_scene_generator()
	if AIStateCoordinator.is_in_scene_generation():
		AIStateCoordinator.transition_to_qa_conversation()
	elif AIStateCoordinator.is_in_qa_conversation():
		Log.d("MapManager", "Scene playback completed while coordinator was already in Q&A; continuing with Q&A start")
	else:
		Log.d("MapManager", "Scene playback completed while coordinator was idle; bridge will register Q&A if needed")



	var character_tags: = _filter_valid_character_tags(_current_character_tags, "scene completion current tags")
	if character_tags.is_empty():
		character_tags = _filter_valid_character_tags(_current_location.characters, "scene completion location tags")
	if character_tags.is_empty():
		character_tags = _filter_valid_character_tags(AIStateCoordinator.get_character_tags(), "scene completion coordinator tags")
	var post_scene_tags: = _get_post_scene_active_character_tags(character_tags)
	if not post_scene_tags.is_empty():
		character_tags = post_scene_tags
		_current_character_tags = character_tags.duplicate()

	if SleepoverSystem != null and SleepoverSystem.flow_phase == SleepoverSystem.FLOW_NIGHT_SCENE:
		var active_tags: = _get_post_scene_active_character_tags(character_tags)
		if not active_tags.is_empty():
			character_tags = active_tags
			_current_character_tags = active_tags.duplicate()
			SleepoverSystem.set_flow_location_and_characters(_current_location.id, active_tags)




	var is_timeline_driven_scene: = _current_location != null and _current_location.id == "_timeline_driven"
	var has_twilight: = "twi" in character_tags or "twilight" in character_tags
	if not is_timeline_driven_scene and not has_twilight and GameState.current_mode == GameState.Mode.STORY:
		character_tags.insert(0, "twi")

	if SleepoverSystem != null and SleepoverSystem.flow_phase == SleepoverSystem.FLOW_NIGHT_SCENE:
		character_tags = _resolve_sleepover_conversation_tags(character_tags, "night Q&A")
		if character_tags.is_empty():
			_abort_sleepover_flow("night_qa_missing_valid_characters")
			return
		SleepoverSystem.set_flow_phase(SleepoverSystem.FLOW_NIGHT_QA)
		SleepoverSystem.nighttime_conversation_active = true
		var nighttime_prompt: = SleepoverSystem.get_nighttime_conversation_prompt(_current_location.id, character_tags)

		AIStateCoordinator.update_runtime_location(_current_location)
		AIStateCoordinator.update_runtime_character_tags(character_tags)
		_conversation_bridge.start_conversation(character_tags, "", false, nighttime_prompt)
		return

	if SleepoverSystem != null and SleepoverSystem.flow_phase == SleepoverSystem.FLOW_MORNING_SCENE:
		character_tags = _resolve_sleepover_conversation_tags(character_tags, "morning Q&A")
		if character_tags.is_empty():
			_abort_sleepover_flow("morning_qa_missing_valid_characters")
			return
		SleepoverSystem.set_flow_phase(SleepoverSystem.FLOW_MORNING_QA)
		SleepoverSystem.sleepover_morning = true

		AIStateCoordinator.update_runtime_location(_current_location)
		AIStateCoordinator.update_runtime_character_tags(character_tags)
		_conversation_bridge.start_conversation(character_tags)
		return

	character_tags = _filter_valid_character_tags(character_tags, "regular Q&A")
	if character_tags.is_empty():
		push_warning("[MapManager] Cannot start Q&A: no valid character tags after scene playback at %s" % _current_location.id)
		AIStateCoordinator.end_session()
		open_map()
		return
	AIStateCoordinator.update_runtime_character_tags(character_tags)


	if _current_location != null and _current_location.id == "_timeline_driven":

		Log.d("MapManager", "Starting timeline-driven Q&A via autoload bridge")
		AIConversation.start_conversation(character_tags)
	else:
		var custom_prompt: = _resolve_visit_conversation_prompt(_current_location, _chrysalis_flow.consume_pending_qa_prompt(character_tags), character_tags)
		_conversation_bridge.start_conversation(character_tags, "", false, custom_prompt)


func _get_post_scene_active_character_tags(fallback_tags: Array) -> Array[String]:
	var tags: Array[String] = []
	if _scene_generator != null and _scene_generator.has_method("get_active_character_tags"):
		var scene_tags = _scene_generator.get_active_character_tags()
		if scene_tags is Array:
			for raw_tag in scene_tags:
				var tag: = str(raw_tag).strip_edges().to_lower()
				if tag.is_empty():
					continue
				if not tag in tags:
					tags.append(tag)

		if tags.is_empty():
			for raw_tag in fallback_tags:
				var fallback: = str(raw_tag).strip_edges().to_lower()
				if fallback.is_empty():
					continue
				if not fallback in tags:
					tags.append(fallback)

	var valid_tags: = _filter_valid_character_tags(tags, "post-scene active tags")
	if not valid_tags.is_empty():
		return valid_tags
	return _filter_valid_character_tags(fallback_tags, "post-scene fallback tags")


func _resolve_sleepover_conversation_tags(candidate_tags: Array, context: String) -> Array[String]:
	var tags: = _filter_valid_character_tags(candidate_tags, context)
	if not tags.is_empty():
		return tags
	if SleepoverSystem != null:
		tags = _filter_valid_character_tags(SleepoverSystem.flow_character_tags, "%s sleepover flow tags" % context)
		if not tags.is_empty():
			return tags
	tags = _filter_valid_character_tags(_current_character_tags, "%s current map tags" % context)
	if not tags.is_empty():
		return tags
	if _current_location != null:
		tags = _filter_valid_character_tags(_current_location.characters, "%s location tags" % context)
	return tags


func _filter_valid_character_tags(raw_tags: Array, context: String = "") -> Array[String]:
	var valid_tags: Array[String] = []
	var prompt_manager: = PromptManager.new()
	for raw_tag in raw_tags:
		var tag: = str(raw_tag).strip_edges().to_lower()
		if tag.is_empty() or tag in valid_tags:
			continue
		var char_data: = prompt_manager.load_character(tag)
		if char_data == null or not char_data.is_valid():
			var suffix: = " (%s)" % context if not context.is_empty() else ""
			push_warning("[MapManager] Ignoring invalid Q&A character tag '%s'%s" % [tag, suffix])
			continue
		valid_tags.append(tag)
	return valid_tags



func _on_scene_generation_failed(error: String) -> void :
	if _bridge_managed_scene_flow_active:
		Log.d("MapManager", "Ignoring shared scene generation failure for bridge-managed flow")
		return
	if _is_scenario_event_flow_active():
		Log.d("MapManager", "Ignoring shared scene generation failure for scenario event flow")
		return
	push_error("[MapManager] AI scene generation failed: " + error)
	if _custom_start_flow.is_active:
		_show_custom_start_failure_dialog(error)
		return
	if SleepoverSystem != null and SleepoverSystem.is_sleepover_flow_active():
		_show_ai_error_dialog(
			tr("Sleepover Scene Failed"), 
			_build_ai_error_message(tr("I couldn't generate the sleepover scene."), error), 
			Callable(_scene_generator, "retry_scene"), 
			"", 
			Callable(), 
			tr("Return to Map"), 
			Callable(self, "_recover_sleepover_after_ai_failure")
		)
		return

	_show_ai_error_dialog(
		tr("AI Scene Failed"), 
		_build_ai_error_message(tr("I couldn't generate the scene for this visit."), error), 
		Callable(_scene_generator, "retry_scene")
	)



func _on_conversation_completed() -> void :
	if _suppress_conversation_completed_during_load:
		Log.d("MapManager", "Ignoring conversation completion during load/reset")
		return
	if _bridge_managed_scene_flow_active:
		Log.d("MapManager", "Ignoring conversation completion for bridge-managed flow")
		return
	if _is_scenario_event_flow_active():
		Log.d("MapManager", "Ignoring conversation completion for scenario event flow")
		return

	Log.d("MapManager", "Conversation completed")
	if _night_flow._night_residence_chat_active:
		return
	if _custom_start_flow.is_active:
		if _current_location != null:
			_maybe_unlock_night_residence(_current_location, _current_character_tags)
		await _custom_start_flow.finish_transition()
		return
	if SleepoverSystem != null and SleepoverSystem.consume_sleep_action_request():
		await _start_sleepover_night_scene()
		return

	if SleepoverSystem != null:
		if SleepoverSystem.flow_phase == SleepoverSystem.FLOW_NIGHT_QA:
			await _play_sleepover_night_transition()
			await _start_sleepover_morning_scene()
			return
		if SleepoverSystem.flow_phase == SleepoverSystem.FLOW_MORNING_QA:
			_finish_sleepover_flow()
			return

	if await _chrysalis_flow.maybe_trigger_followup():
		return

	if _scenario_event_flow.finish_restored_event():
		return

	if _current_location:
		_on_scene_completed(_current_location)
	else:
		open_map()


func _on_scene_interrupted() -> void :
	if not _custom_start_flow.is_active:
		return
	_custom_start_flow.scene_interrupted = true
	await _custom_start_flow.finish_transition(true)


func complete_quick_start() -> void :
	GameState.enter_sandbox_mode()
	GameState.custom_start_used = false
	GameState.quick_start_used = true
	GameState.daily_visits = 0
	GameState.current_time_slot = 0
	GameState.current_region = "Ponyville"
	GameState.owns_house = false
	var start: = CalendarManager.pending_start_date
	CalendarManager.pending_start_date = {}
	CalendarManager.set_date(
		int(start.get("year", CalendarManager.DEFAULT_START_YEAR)), 
		int(start.get("month", CalendarManager.DEFAULT_START_MONTH)), 
		int(start.get("day", CalendarManager.DEFAULT_START_DAY)), 
		true
	)
	open_map()





func complete_scenario_intro(start_region: String = "") -> void :
	var resolved_region: = start_region.strip_edges()
	if not resolved_region.is_empty() and RegionRegistry != null and RegionRegistry.has_method("resolve_region_name"):
		resolved_region = RegionRegistry.resolve_region_name(resolved_region)
	GameState.enter_sandbox_mode(resolved_region)
	GameState.custom_start_used = false
	GameState.quick_start_used = false
	GameState.daily_visits = 0
	GameState.current_time_slot = 0
	open_map()


func _play_sleepover_night_transition() -> void :
	var transition_line: = tr("As the conversation winds down, you all drift off to sleep, feeling comfortable and safe...")
	if Dialogic.has_subsystem("Text"):
		var narrator_char = DialogicResourceUtil.get_character_resource("narrator")
		if narrator_char != null:
			Dialogic.Text.update_name_label(narrator_char)
		CharacterSpriteLoader.call("apply_typing_sound_for_dialogic_character", narrator_char)
		var voice_controller: Node = preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree())
		if not await voice_controller.prepare_line("narrator", transition_line):
			return
		await Dialogic.Text.update_textbox(transition_line, false)
		var voice_text: String = Dialogic.Text.update_dialog_text(transition_line)
		voice_controller.speak("narrator", voice_text)
		await Dialogic.Text.text_finished
	if Dialogic.has_subsystem("Backgrounds"):
		Dialogic.Backgrounds.update_background("", "", 0.8)
	await get_tree().create_timer(1.4).timeout


func _start_sleepover_night_scene() -> void :
	if SleepoverSystem == null or _current_location == null:
		_abort_sleepover_flow("night_scene_missing_context")
		return

	var tags: Array[String] = SleepoverSystem.flow_character_tags.duplicate()
	if tags.is_empty():
		for raw_tag in _current_character_tags:
			tags.append(str(raw_tag))
	if tags.is_empty():
		for raw_tag in _current_location.characters:
			tags.append(str(raw_tag))
	if tags.is_empty():
		_abort_sleepover_flow("night_scene_missing_characters")
		return

	_current_character_tags = tags.duplicate()
	var flow_location_id: = SleepoverSystem.flow_location_id.strip_edges()
	if not flow_location_id.is_empty() and (_current_location == null or _current_location.id != flow_location_id):
		var flow_location: = LocationDatabase.get_location(flow_location_id)
		if flow_location != null:
			try_change_conversation_location(flow_location_id, 0.45, true, false)
			_current_location = flow_location

	SleepoverSystem.set_flow_phase(SleepoverSystem.FLOW_NIGHT_SCENE)
	SleepoverSystem.nighttime_conversation_active = false
	SleepoverSystem.sleepover_morning = false
	SleepoverSystem.sleepover_planned = true

	if not _is_dynamic_location_mode_enabled():
		var manual_target: = SleepoverSystem.choose_manual_sleep_location(_current_location.id, tags)
		if not manual_target.is_empty():
			try_change_conversation_location(manual_target, 0.45, true)
			var updated: = LocationDatabase.get_location(manual_target)
			if updated != null:
				_current_location = updated

	SleepoverSystem.set_flow_location_and_characters(_current_location.id, tags)
	var night_prompt: = SleepoverSystem.get_night_scene_prompt(_current_location.id, tags)
	if not _is_dynamic_location_mode_enabled():
		night_prompt = SleepoverSystem.strip_location_hints(night_prompt)
	await _start_sleepover_scene_generation(tags, night_prompt)


func _start_sleepover_morning_scene() -> void :
	if SleepoverSystem == null or _current_location == null:
		_abort_sleepover_flow("morning_scene_missing_context")
		return

	var tags: Array[String] = SleepoverSystem.flow_character_tags.duplicate()
	if tags.is_empty():
		for raw_tag in _current_character_tags:
			tags.append(str(raw_tag))
	if tags.is_empty():
		for raw_tag in _current_location.characters:
			tags.append(str(raw_tag))
	if tags.is_empty():
		_abort_sleepover_flow("morning_scene_missing_characters")
		return

	_current_character_tags = tags.duplicate()
	SleepoverSystem.set_flow_phase(SleepoverSystem.FLOW_MORNING_SCENE)
	SleepoverSystem.nighttime_conversation_active = false
	SleepoverSystem.sleepover_morning = true
	SleepoverSystem.sleepover_planned = true


	GameState.end_day()
	SleepoverSystem.set_flow_phase(SleepoverSystem.FLOW_MORNING_SCENE)
	SleepoverSystem.sleepover_morning = true
	SleepoverSystem.set_flow_location_and_characters(_current_location.id, tags)

	var morning_prompt: = SleepoverSystem.get_morning_scene_prompt(_current_location.id, tags)
	await _start_sleepover_scene_generation(tags, morning_prompt)


func _start_sleepover_scene_generation(character_tags: Array[String], scene_brief: String) -> void :
	if _current_location == null:
		_abort_sleepover_flow("sleepover_scene_missing_location")
		return
	if not APIConfigManager.is_configured():
		_abort_sleepover_flow("sleepover_scene_api_not_configured")
		return

	AIStateCoordinator.end_session()
	AIStateCoordinator.begin_scene_generation(_current_location, character_tags)
	AIStateCoordinator.register_scene_generator(_scene_generator)
	await _setup_scene_visuals(_current_location)
	var story_context: = _get_story_context()
	_scene_generator.generate_scene(_current_location, character_tags, story_context, scene_brief)


func _finish_sleepover_flow() -> void :
	if SleepoverSystem != null:
		SleepoverSystem.clear_all_state()
	if _current_location:
		_on_scene_completed(_current_location)
	else:
		AIStateCoordinator.end_session()
		open_map()


func _abort_sleepover_flow(reason: String) -> void :
	push_warning("[MapManager] Aborting sleepover flow: %s" % reason)
	if SleepoverSystem != null:
		SleepoverSystem.clear_all_state()
	AIStateCoordinator.end_session()
	open_map()



func _on_scene_completed(location: LocationData) -> void :
	Log.d("MapManager", "Scene completed: %s" % location.id)
	await _fade_transition_in()
	_chrysalis_flow.pending_followup_check = false
	_chrysalis_flow.pending_custom_qa_prompt = false
	var will_auto_end_day: = false
	if location.id == ChrysalisFlow.CHRYSALIS_RUNTIME_LOCATION_ID:
		_chrysalis_flow.is_encounter_active = false



	if GameState.current_mode == GameState.Mode.SANDBOX and not _is_transport_scene_location_id(location.id):

		var initial_loc: = SleepoverSystem.qa_session_start_location_id.strip_edges() if SleepoverSystem else ""
		var visit_origin: = initial_loc if not initial_loc.is_empty() else location.id
		if visit_origin == "canterlot_throne_room" and not GameState.canterlot_castle_access_granted:
			GameState.canterlot_castle_access_granted = true
			GameState.unlock_night_residence("castle_guest_room")
			Log.d("MapManager", "Canterlot castle access granted via throne room visit")
		_maybe_unlock_night_residence(location, _current_character_tags)
		GameState.finalize_sandbox_visit()
		will_auto_end_day = GameState.current_time_slot >= 2


	AIStateCoordinator.end_session()



	if Dialogic.has_subsystem("Text") and not will_auto_end_day:
		Dialogic.Text.hide_textbox()


	if Dialogic.has_subsystem("Portraits"):
		await Dialogic.Portraits.leave_all_characters("", 0.0, false)
	CharacterPortraitService.clear_scene_layout_state()
	if Dialogic.has_subsystem("Backgrounds") and Dialogic.Backgrounds.has_background():
		Dialogic.Backgrounds.update_background("", "", 0.0)
	if Dialogic.has_subsystem("Audio"):
		Dialogic.Audio.stop_all_channels(0.0)


	if Dialogic.has_subsystem("Styles") and Dialogic.Styles.has_active_layout_node():
		Dialogic.Styles.get_layout_node().hide()

	await get_tree().process_frame

	if SleepoverSystem != null:
		if SleepoverSystem.sleepover_planned and not SleepoverSystem.sleepover_morning:
			SleepoverSystem.clear_all_state()
		elif SleepoverSystem.sleepover_error_recovery:

			SleepoverSystem.clear_all_state()

	var completed_train_travel: = _train_flow.is_active or _is_transport_scene_location_id(location.id)
	if completed_train_travel:
		_train_flow.handle_scene_completed()
		open_map()
		await get_tree().process_frame
		await _fade_transition_out()
		return


	if GameState.current_mode == GameState.Mode.SANDBOX and GameState.current_time_slot >= 2:
		start_sandbox_end_day_sequence()
		return




	open_map()
	await get_tree().process_frame
	await _fade_transition_out()
	AutosaveManager.request_autosave("visit_complete")


func get_current_region() -> String:
	return GameState.current_region


func get_current_runtime_location_id() -> String:
	if AIStateCoordinator != null and AIStateCoordinator.has_method("get_location_id"):
		var ai_location_id: = str(AIStateCoordinator.get_location_id()).strip_edges()
		if not ai_location_id.is_empty():
			return ai_location_id
	if _current_location != null and not _current_location.id.is_empty():
		return _current_location.id
	return ""




func is_free_travel_enabled() -> bool:
	return (
		GameState.current_mode == GameState.Mode.SANDBOX
		and UISettingsManager != null
		and UISettingsManager.get_free_travel_enabled()
	)


func get_runtime_location_change_policy() -> Dictionary:
	var active_region: = _normalize_region_name(get_current_region())
	var current_location_id: = get_current_runtime_location_id()
	var bridge_location_ids: = _get_bridge_location_ids()
	var at_transport_hub: = is_free_travel_enabled() or _is_transport_hub_location_id(current_location_id)
	var transport_modes: = get_transport_modes_for_location(current_location_id)
	var reachable_regions: = _get_reachable_region_names_for_active_region(active_region, transport_modes)
	return {
		"active_region": active_region, 
		"current_location_id": current_location_id, 
		"bridge_location_ids": bridge_location_ids, 
		"at_transport_hub": at_transport_hub, 
		"transport_modes": transport_modes, 
		"reachable_regions": reachable_regions, 
	}


func get_dynamic_locations_for_current_context() -> Array[LocationData]:
	var result: Array[LocationData] = []
	var seen_ids: Dictionary = {}
	var policy: = get_runtime_location_change_policy()
	var active_region: = str(policy.get("active_region", _get_default_region_name()))
	var at_transport_hub: = bool(policy.get("at_transport_hub", false))
	var reachable_regions: Array = policy.get("reachable_regions", [])

	for location_id in LocationDatabase.get_all_ids():
		var location: = LocationDatabase.get_location(location_id)
		if location == null:
			continue
		var normalized_id: = location.id.strip_edges()
		if normalized_id.is_empty():
			continue
		if not _is_location_allowed_for_runtime_selection(location):
			continue
		if _is_runtime_location_restricted(normalized_id):
			continue
		var location_region: = _get_region_for_location(location)
		if not at_transport_hub and location_region != active_region:
			continue
		if at_transport_hub and location_region != active_region and not reachable_regions.has(location_region):
			continue
		if seen_ids.has(normalized_id):
			continue
		seen_ids[normalized_id] = true
		result.append(location)

	return result


func _is_location_allowed_for_runtime_selection(location: LocationData) -> bool:
	if location == null:
		return false
	if location.can_be_player_home:
		return GameState.is_selected_player_home_location(location.id)
	if location.id == "user_house" and GameState.owns_house and GameState.get_player_home_location_id() != "user_house":
		return false
	return true


func set_current_region(region: String) -> void :
	GameState.current_region = _normalize_region_name(region)
	if is_map_open() and _map_instance and _map_instance.has_method("set_region"):
		_map_instance.set_region(GameState.current_region)
		_play_map_music()


func get_current_location() -> LocationData:
	return _current_location


func _is_dynamic_location_mode_enabled() -> bool:
	return (
		GameState.current_mode == GameState.Mode.SANDBOX
		and APIConfigManager != null
		and APIConfigManager.is_dynamic_location_management_enabled()
	)




func try_change_conversation_location(
	location_id: String, 
	fade_length: float = 0.45, 
	update_music: bool = true, 
	enforce_policy: bool = true
) -> bool:
	var target_id: String = location_id.strip_edges()
	if target_id.is_empty():
		return false

	if _is_runtime_location_restricted(target_id):
		push_warning("[MapManager] Runtime location change blocked for restricted location: %s" % target_id)
		return false

	var location: LocationData = LocationDatabase.get_location(target_id)
	if location == null:
		push_warning("[MapManager] Runtime location change failed - unknown location: %s" % target_id)
		return false

	if GameState.current_mode != GameState.Mode.SANDBOX:
		push_warning("[MapManager] Runtime location change blocked outside sandbox: %s" % target_id)
		return false

	var policy: = get_runtime_location_change_policy()
	var active_region: = str(policy.get("active_region", _get_default_region_name()))
	var at_transport_hub: = bool(policy.get("at_transport_hub", false))
	var current_location_id: = str(policy.get("current_location_id", ""))
	var reachable_regions: Array = policy.get("reachable_regions", [])
	var target_region: = _get_region_for_location(location)
	if enforce_policy and target_region != active_region and not at_transport_hub:
		push_warning(
			"[MapManager] Runtime location change blocked - cross-region move requires a configured bridge location (from %s/%s to %s/%s)" %
			[active_region, current_location_id, target_region, target_id]
		)
		return false
	if enforce_policy and target_region != active_region and at_transport_hub and not reachable_regions.has(target_region):
		push_warning(
			"[MapManager] Runtime location change blocked - region %s is not reachable from %s via configured travel edges." %
			[target_region, active_region]
		)
		return false

	Log.d("MapManager", "Runtime location change requested: %s (%s)" % [location.display_name, target_id])
	_current_location = location
	if _foreground_controller != null:
		_foreground_controller.set_current_location(location)
	if target_region != active_region:
		set_current_region(target_region)
	if AIStateCoordinator:
		AIStateCoordinator.update_runtime_location(location)

	var background_path: String = location.background.strip_edges()
	if not background_path.is_empty():
		var background_exists: bool = AssetLoader.file_exists(ContentPaths.resolve(background_path))
		Log.d("MapManager", "Runtime background candidate: path=%s exists=%s" % [background_path, str(background_exists)])
		if background_exists:
			Dialogic.Backgrounds.update_background("", background_path, fade_length)
		else:
			push_warning("[MapManager] Runtime location background missing: %s" % background_path)
	else:
		Log.d("MapManager", "Runtime location has no background. Keeping current background.")

	if update_music:
		var music_path: String = location.music.strip_edges()
		var keep_previous_music: bool = not location.has_map_position
		if not music_path.is_empty():
			var selected_music: String = str(MusicMixManager.select_track(location))
			var music_exists: bool = AssetLoader.file_exists(ContentPaths.resolve(selected_music))
			Log.d("MapManager", "Runtime music candidate: path=%s exists=%s" % [selected_music, str(music_exists)])
			if music_exists:


				if _is_music_track_already_playing(selected_music):
					Log.d("MapManager", "Runtime music already playing, preserving position.")
				else:
					Dialogic.Audio.update_audio("music", selected_music, {
						"fade_length": maxf(0.2, fade_length), 
						"loop": true
					})
			else:
				push_warning("[MapManager] Runtime location music missing: %s" % selected_music)
				if keep_previous_music:
					Log.d("MapManager", "Hidden runtime location has invalid music. Keeping current music.")
				else:
					Dialogic.Audio.update_audio("music", "", {"fade_length": maxf(0.2, fade_length)})
		else:
			if keep_previous_music:
				Log.d("MapManager", "Hidden runtime location has no music. Keeping current music.")
			else:
				Log.d("MapManager", "Runtime location has no music. Stopping current music.")
				Dialogic.Audio.update_audio("music", "", {"fade_length": maxf(0.2, fade_length)})

	_refresh_music_switcher_after_restore()
	Log.d("MapManager", "Runtime location changed to: %s" % target_id)
	return true





func restore_conversation_location(location_id: String, fade_length: float = 0.35, update_music: bool = true) -> bool:
	return try_change_conversation_location(location_id, fade_length, update_music, false)


func _is_music_track_already_playing(track_path: String) -> bool:
	var target: = track_path.strip_edges()
	if target.is_empty():
		return false
	if not Dialogic.has_subsystem("Audio"):
		return false
	if Dialogic.Audio == null:
		return false

	var music_player: AudioStreamPlayer = null
	if Dialogic.Audio.current_audio_channels.has("music"):
		var channel = Dialogic.Audio.current_audio_channels["music"]
		if channel is AudioStreamPlayer:
			music_player = channel

	if music_player == null and Dialogic.Audio.audio_node:
		var fallback = Dialogic.Audio.audio_node.get_node_or_null("music")
		if fallback is AudioStreamPlayer:
			music_player = fallback

	if music_player == null or music_player.stream == null or not music_player.playing:
		return false


	var audio_state: Dictionary = Dialogic.current_state_info.get("audio", {})
	var music_state: Dictionary = audio_state.get("music", {})
	var state_path: = str(music_state.get("path", "")).strip_edges()
	if not state_path.is_empty():
		return state_path == target


	var current_path: = str(music_player.stream.resource_path).strip_edges()
	if current_path.is_empty():
		return false
	return current_path == target


func _normalize_region_name(region: String) -> String:
	var normalized: = region.strip_edges()
	if RegionRegistry != null and RegionRegistry.has_method("resolve_region_name"):
		return RegionRegistry.resolve_region_name(normalized)
	return normalized if not normalized.is_empty() else _get_default_region_name()


func _get_region_for_location(location: LocationData) -> String:
	if location == null:
		return _get_default_region_name()
	return _normalize_region_name(str(location.region))


func _get_default_region_name() -> String:
	return RegionRegistry.get_default_region_name() if RegionRegistry != null and RegionRegistry.has_method("get_default_region_name") else "Ponyville"


func _get_default_train_destination_region(from_region: String = "") -> String:
	var source_region: String = _normalize_region_name(from_region if not from_region.is_empty() else get_current_region())
	var reachable_regions: Array[String] = _get_reachable_region_names_for_active_region(source_region)
	if not reachable_regions.is_empty():
		return str(reachable_regions[0])
	if RegionRegistry != null and RegionRegistry.has_method("get_fallback_return_region_name"):
		var fallback_region: = str(RegionRegistry.get_fallback_return_region_name(source_region)).strip_edges()
		if not fallback_region.is_empty():
			return fallback_region
	return _get_default_region_name()


func _is_transport_hub_location_id(location_id: String) -> bool:
	var normalized_id: = location_id.strip_edges().to_lower()
	if not get_transport_modes_for_location(normalized_id).is_empty():
		return true
	return _get_bridge_location_ids().has(normalized_id) or _is_custom_start_bridge_location(normalized_id)


func _is_transport_scene_location_id(location_id: String) -> bool:
	return _train_flow != null and _train_flow.is_transport_scene_location_id(location_id)


func _get_transport_mode_for_scene_location_id(location_id: String) -> String:
	var normalized: = location_id.strip_edges().to_lower()
	var saved_mode: = RegionRegistry.normalize_transport_mode(GameState.travel_transport_mode) if RegionRegistry != null and RegionRegistry.has_method("normalize_transport_mode") else "train"
	if _train_flow != null and _train_flow.get_transport_location_id(saved_mode) == normalized:
		return saved_mode
	if _train_flow != null and _train_flow.has_method("get_transport_mode_for_scene_location_id"):
		return _train_flow.get_transport_mode_for_scene_location_id(normalized)
	return "train"


func _is_custom_start_bridge_location(location_id: String) -> bool:
	return (
		location_id == CustomStartFlow.CUSTOM_START_RUNTIME_LOCATION_ID
		and AIStateCoordinator != null
		and AIStateCoordinator.has_method("is_custom_start_active")
		and AIStateCoordinator.is_custom_start_active()
	)


func _get_bridge_location_ids() -> Array[String]:
	if PromptConfigManager != null and PromptConfigManager.has_method("has_custom_bridge_location_ids") and PromptConfigManager.has_custom_bridge_location_ids():
		if PromptConfigManager.has_method("get_bridge_location_ids"):
			var configured_ids: Array[String] = PromptConfigManager.get_bridge_location_ids()
			if not configured_ids.is_empty():
				return configured_ids
	if RegionRegistry != null and RegionRegistry.has_method("get_bridge_location_ids"):
		var manifest_ids: Array[String] = RegionRegistry.get_bridge_location_ids(get_current_region())
		if not manifest_ids.is_empty():
			var normalized_manifest_ids: Array[String] = []
			for raw_id in manifest_ids:
				var location_id: = str(raw_id).strip_edges().to_lower()
				if location_id.is_empty() or location_id in normalized_manifest_ids:
					continue
				normalized_manifest_ids.append(location_id)
			if not normalized_manifest_ids.is_empty():
				return normalized_manifest_ids
	var fallback_ids: Array[String] = []
	for raw_id in DEFAULT_TRANSPORT_HUB_LOCATION_IDS:
		var location_id: = str(raw_id).strip_edges().to_lower()
		if location_id.is_empty():
			continue
		if fallback_ids.has(location_id):
			continue
		fallback_ids.append(location_id)
	return fallback_ids


func _get_reachable_region_names_for_active_region(region: String = "", transport_modes: Array[String] = []) -> Array[String]:
	var active_region: = _normalize_region_name(region if not region.is_empty() else get_current_region())
	if is_free_travel_enabled() and RegionRegistry != null and RegionRegistry.has_method("get_region_folder_names"):
		var all_regions: Array[String] = []
		for region_name in RegionRegistry.get_region_folder_names():
			if region_name != active_region and region_name not in all_regions:
				all_regions.append(region_name)
		return all_regions
	if RegionRegistry != null and RegionRegistry.has_method("get_transport_destinations_from_region"):
		var result: Array[String] = []
		if transport_modes.is_empty():
			for destination in RegionRegistry.get_transport_destinations_from_region(active_region):
				var destination_name: = str(destination)
				if destination_name.is_empty() or destination_name in result:
					continue
				result.append(destination_name)
		else:
			for raw_mode in transport_modes:
				for destination in RegionRegistry.get_transport_destinations_from_region(active_region, str(raw_mode)):
					var destination_name: = str(destination)
					if destination_name.is_empty() or destination_name in result:
						continue
					result.append(destination_name)
		return result
	if RegionRegistry != null and RegionRegistry.has_method("get_train_destinations_from_region"):
		return RegionRegistry.get_train_destinations_from_region(active_region)
	if active_region == "Ponyville":
		return ["Canterlot"]
	if active_region == "Canterlot":
		return ["Ponyville"]
	return []


func _is_runtime_location_restricted(location_id: String) -> bool:
	return RUNTIME_RESTRICTED_LOCATION_IDS.has(location_id.strip_edges().to_lower())


func refresh_map_ui(check_house_offer: bool = true) -> void :
	if _map_instance and _map_instance.has_method("refresh"):
		_map_instance.refresh()
	if check_house_offer:
		_maybe_show_house_offer_prompt()


func get_night_residence_summary() -> String:
	var default_location_id: = _night_flow._get_night_residence_location_id_for_mode(GameState.NIGHT_RESIDENCE_MODE_DEFAULT)
	var library_location_id: = _night_flow._get_night_residence_location_id_for_mode(GameState.NIGHT_RESIDENCE_MODE_LIBRARY)
	match GameState.get_night_residence_mode():
		GameState.NIGHT_RESIDENCE_MODE_LIBRARY:
			return _night_flow._get_night_residence_label_for_location(library_location_id)
		GameState.NIGHT_RESIDENCE_MODE_OWN_HOUSE:
			return _night_flow._get_night_residence_label_for_location(GameState.get_player_home_location_id()) if GameState.owns_house else _night_flow._get_night_residence_label_for_location(default_location_id)
		GameState.NIGHT_RESIDENCE_MODE_HOSTED:
			var hosted_id: = GameState.night_residence_location_id.strip_edges()
			if not hosted_id.is_empty() and GameState.is_night_residence_unlocked(hosted_id):
				return _night_flow._get_night_residence_label_for_location(hosted_id)
			return _night_flow._get_night_residence_label_for_location(default_location_id)
		_:
			return _night_flow._get_night_residence_label_for_location(default_location_id)


func get_night_residence_summary_note() -> String:
	match GameState.get_night_residence_mode():
		GameState.NIGHT_RESIDENCE_MODE_DEFAULT:
			return tr("Using the normal sleeping rules for the current game state.")
		GameState.NIGHT_RESIDENCE_MODE_HOSTED:
			return tr("The player will automatically return here at the end of the day unless a special night scene overrides it.")
		_:
			return tr("This location will be used automatically at the end of the day unless a special night scene overrides it.")


func get_night_residence_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var current_mode: = GameState.get_night_residence_mode()
	var current_hosted_id: = GameState.night_residence_location_id.strip_edges()
	var default_location_id: = _night_flow._get_night_residence_location_id_for_mode(GameState.NIGHT_RESIDENCE_MODE_DEFAULT)
	var library_location_id: = _night_flow._get_night_residence_location_id_for_mode(GameState.NIGHT_RESIDENCE_MODE_LIBRARY)
	options.append({
		"mode": GameState.NIGHT_RESIDENCE_MODE_LIBRARY, 
		"location_id": library_location_id, 
		"label": _night_flow._get_night_residence_label_for_location(library_location_id), 
		"description": _night_flow._get_night_residence_description_for_location(library_location_id, true), 
		"current": current_mode == GameState.NIGHT_RESIDENCE_MODE_LIBRARY
			or (current_mode == GameState.NIGHT_RESIDENCE_MODE_DEFAULT and default_location_id == library_location_id), 
	})
	if GameState.owns_house:
		var player_home_id: = GameState.get_player_home_location_id()
		options.append({
			"mode": GameState.NIGHT_RESIDENCE_MODE_OWN_HOUSE, 
			"location_id": player_home_id, 
			"label": _night_flow._get_night_residence_label_for_location(player_home_id), 
			"description": _night_flow._get_night_residence_description_for_location(player_home_id), 
			"current": current_mode == GameState.NIGHT_RESIDENCE_MODE_OWN_HOUSE
				or (current_mode == GameState.NIGHT_RESIDENCE_MODE_DEFAULT and default_location_id == player_home_id), 
		})

	for location_id in GameState.get_unlocked_night_residences():
		options.append({
			"mode": GameState.NIGHT_RESIDENCE_MODE_HOSTED, 
			"location_id": location_id, 
			"label": _night_flow._get_night_residence_label_for_location(location_id), 
			"description": _night_flow._get_night_residence_description_for_location(location_id), 
			"current": current_mode == GameState.NIGHT_RESIDENCE_MODE_HOSTED and current_hosted_id == location_id, 
		})

	return options


func get_locked_night_residence_ids() -> Array[String]:
	var locked: Array[String] = []
	if GameState.current_mode != GameState.Mode.SANDBOX:
		return locked
	for location_id in SleepoverSystem.get_all_hosted_residence_candidate_ids():
		if LocationDatabase.has_location(location_id) and not GameState.is_night_residence_unlocked(location_id):
			locked.append(location_id)
	return locked


func unlock_all_night_residences() -> void :
	for location_id in get_locked_night_residence_ids():
		GameState.unlock_night_residence(location_id)


func set_night_residence_choice(mode: String, location_id: String = "") -> bool:
	var changed: = GameState.set_night_residence(mode, location_id)
	if changed:
		refresh_map_ui(false)
	return changed


func _maybe_unlock_night_residence(location: LocationData, character_tags: Array[String]) -> void :
	if location == null:
		return
	if GameState.current_mode != GameState.Mode.SANDBOX:
		return
	if SleepoverSystem == null:
		return
	var initial_location_id: = SleepoverSystem.qa_session_start_location_id.strip_edges()
	var unlock_location_id: = location.id.strip_edges()
	if not initial_location_id.is_empty():
		unlock_location_id = initial_location_id


	if unlock_location_id == "castle_guest_room" and GameState.canterlot_castle_access_granted:
		GameState.unlock_night_residence(unlock_location_id)
		return

	if not SleepoverSystem.can_set_hosted_night_residence(location.id, character_tags, initial_location_id):
		return
	GameState.unlock_night_residence(unlock_location_id)


func _get_location_display_name(location_id: String) -> String:
	var location: = LocationDatabase.get_location(location_id)
	if location == null:
		var fallback: = location_id.replace("_", " ").strip_edges()
		return fallback.capitalize() if not fallback.is_empty() else "Home"
	var location_name: = str(location.display_name).strip_edges()
	if not location_name.is_empty():
		return location_name
	var id_fallback: = location_id.replace("_", " ").strip_edges()
	return id_fallback.capitalize() if not id_fallback.is_empty() else "Home"


func reload_custom_content() -> Dictionary:
	if RegionRegistry != null and RegionRegistry.has_method("reload_regions"):
		RegionRegistry.reload_regions()
	CustomLocationLoader.reload_custom_locations()
	CharacterScheduleManager.reload_schedules()
	refresh_map_ui()
	return get_custom_content_report()


func get_custom_content_report() -> Dictionary:
	return {
		"regions": RegionRegistry.get_last_report() if RegionRegistry != null and RegionRegistry.has_method("get_last_report") else {}, 
		"locations": CustomLocationLoader.get_last_report(), 
		"schedules": CharacterScheduleManager.get_last_report(), 
	}


func _get_map_music_path_for_region(region: String) -> String:
	if RegionRegistry != null and RegionRegistry.has_method("get_map_music_path"):
		var manifest_music: = str(RegionRegistry.get_map_music_path(region)).strip_edges()
		if not manifest_music.is_empty():
			return manifest_music
	if region == "Canterlot" and AssetLoader.file_exists(ContentPaths.resolve(CANTERLOT_MAP_MUSIC_PATH)):
		return CANTERLOT_MAP_MUSIC_PATH
	return PONYVILLE_MAP_MUSIC_PATH





func _maybe_show_house_offer_prompt() -> bool:
	if _map_instance == null:
		return false
	if not _should_show_house_offer_now():
		return false

	GameState.house_offer_shown = true
	refresh_map_ui(false)
	if _map_instance.has_method("show_house_offer_prompt"):
		_map_instance.show_house_offer_prompt()
	return true











func _maybe_show_scenario_offers(house_offer_showing: bool = false) -> void :
	if _map_instance == null:
		return
	var event: = _select_scenario_offer_for_map_open(house_offer_showing)
	if event.is_empty():
		return
	Log.info("MapManager", "Scenario event offer: '%s'" % str(event.get("id", "?")))
	if _map_instance.has_method("show_scenario_offer_prompt"):
		_scenario_event_flow.apply_state_changes(event, "on_offer")
		_map_instance.show_scenario_offer_prompt(event)













func _select_scenario_offer_for_map_open(house_offer_showing: bool) -> Dictionary:
	if ScenarioEventManager == null:
		return {}
	if GameState.current_mode != GameState.Mode.SANDBOX:
		return {}
	if GameState.custom_start_used:
		return {}
	if house_offer_showing:
		return {}
	var offers: Array = ScenarioEventManager.get_offers("sandbox_setup_open", _build_scenario_offer_context())
	if offers.is_empty():
		return {}


	return offers[0]


func _build_scenario_offer_context() -> Dictionary:
	return {
		"current_day": GameState.current_day, 
		"current_time_slot": GameState.current_time_slot, 
		"current_region": get_current_region(), 
		"scenario_id": ScenarioManager.get_active_scenario_id() if ScenarioManager != null else "base", 
	}








func decline_scenario_event(event: Dictionary) -> void :
	_scenario_event_flow.decline(event)



func execute_scenario_event(event: Dictionary) -> void :
	_scenario_event_flow.execute(event)



func _build_scenario_event_timeline(
	location: LocationData, 
	characters: Array, 
	pre_scene: Array = []
) -> String:
	return _scenario_event_flow.build_timeline(location, characters, pre_scene)



func start_pending_scenario_event_scene() -> void :
	await _scenario_event_flow.start_pending_scene_from_timeline()


func _is_scenario_event_flow_active() -> bool:
	return _scenario_event_flow != null and _scenario_event_flow.is_active


func _should_show_house_offer_now() -> bool:
	if GameState.current_mode != GameState.Mode.SANDBOX:
		return false
	if get_current_region() != "Ponyville":
		return false
	if GameState.current_time_slot != 0:
		return false
	if GameState.owns_house or GameState.house_offer_shown:
		return false

	return GameState.house_offer_available




func request_story_completion() -> void :
	if GameState.current_mode != GameState.Mode.STORY:
		return
	if not GameState.is_story_complete():
		return
	if GameState.story_complete:
		return

	var optional_remaining: = _get_unvisited_optional_location_names()
	if not optional_remaining.is_empty():
		if _map_instance and _map_instance.has_method("show_story_complete_choice"):
			_map_instance.show_story_complete_choice(optional_remaining)
			return

	confirm_story_completion()



func confirm_story_completion() -> void :
	if GameState.current_mode != GameState.Mode.STORY:
		return
	if not GameState.is_story_complete():
		return
	if GameState.story_complete:
		return

	close_map()
	_show_story_complete_prompt()


func _get_unvisited_optional_location_names() -> Array[String]:
	var names: Array[String] = []
	for loc_id in GameState.OPTIONAL_STORY_LOCATIONS:
		if GameState.has_visited(loc_id):
			continue
		var loc: = LocationDatabase.get_location(loc_id)
		if loc and not loc.display_name.is_empty():
			names.append(loc.display_name)
		else:
			names.append(loc_id.replace("_", " ").capitalize())
	return names


func _get_unvisited_required_location_names() -> Array[String]:
	var names: Array[String] = []
	for loc_id in GameState.REQUIRED_STORY_LOCATIONS:
		if GameState.has_visited(loc_id):
			continue
		var loc: = LocationDatabase.get_location(loc_id)
		if loc and not loc.display_name.is_empty():
			names.append(loc.display_name)
		else:
			names.append(loc_id.replace("_", " ").capitalize())
	return names



func _show_story_complete_prompt() -> void :
	Log.info("MapManager", "All required locations visited! Showing story complete prompt")


	var completion_timeline: = "story_complete_return"
	if ResourceLoader.exists("res://dialogic/timelines/%s.dtl" % completion_timeline):
		_ensure_story_complete_timeline_end_hook()
		Dialogic.start(completion_timeline)
	else:

		_transition_to_sandbox()



func _on_story_complete_timeline_ended() -> void :
	_transition_to_sandbox()



func _transition_to_sandbox() -> void :
	GameState.enter_sandbox_mode()
	Log.info("MapManager", "Transitioned to sandbox mode")
	open_map()
	AutosaveManager.request_autosave("sandbox_unlocked")



func _handle_sandbox_visit(location: LocationData) -> bool:
	var transport_modes: = get_transport_modes_for_location(location.id)
	var has_transport_action: = not transport_modes.is_empty() and _has_transport_destinations_for_modes(transport_modes)



	if location.id == "user_house" and not GameState.owns_house:
		if _map_instance and _map_instance.has_method("show_house_move_in_prompt"):
			_map_instance.show_house_move_in_prompt(location)
			return true
		return false

	if not GameState.can_visit(location.id) and not has_transport_action:
		_can_accept_sandbox_visit(location)
		return false





	if _map_instance and _map_instance.has_method("show_location_prompt"):
		_map_instance.show_location_prompt(location)
		return true
	else:
		if not _can_accept_sandbox_visit(location):
			return false
		_accept_sandbox_visit(location)
		return true



func _accept_sandbox_visit(location: LocationData) -> void :


	if not _can_accept_sandbox_visit(location):
		return







	var raw_location_region: = str(location.region).strip_edges()
	if not raw_location_region.is_empty():
		var target_region: = _normalize_region_name(raw_location_region)
		if target_region != _normalize_region_name(get_current_region()):
			set_current_region(target_region)


	for tag in _pending_visit_character_tags:
		var current: = CharacterScheduleManager.get_character_current_location(tag)
		if str(current.get("location_id", "")) != location.id:
			CharacterScheduleManager.move_character_for_current_timeslot(tag, location.id)
	_chrysalis_flow.pending_followup_check = _should_arm_chrysalis_followup(location)
	GameState.record_sandbox_visit()
	await _fade_transition_in()
	close_map()

	var sandbox_intro_mode: = APIConfigData.SANDBOX_INTRO_MODE_INTRO_THEN_QA
	if APIConfigManager and APIConfigManager.has_method("get_sandbox_intro_mode"):
		sandbox_intro_mode = str(APIConfigManager.get_sandbox_intro_mode())
	Log.d("MapManager", "Sandbox intro mode: %s" % sandbox_intro_mode)

	if _pending_visit_go_alone:
		_start_solo_location_conversation(location)
	elif sandbox_intro_mode == APIConfigData.SANDBOX_INTRO_MODE_DIRECT_QA:
		_start_location_conversation(location)
	else:
		_start_location_scene(location)


func _should_arm_chrysalis_followup(location: LocationData) -> bool:
	if _chrysalis_flow.is_encounter_active:
		return false
	if location == null:
		return false
	if GameState.current_mode != GameState.Mode.SANDBOX:
		return false
	if location.id != "zecora_hut":
		return false
	return not GameState.chrysalis_encountered



func _show_daily_limit_reached() -> void :
	if _map_instance and _map_instance.has_method("show_daily_limit_message"):
		_map_instance.show_daily_limit_message()
	else:
		push_warning("[MapManager] Daily visit limit reached")



func decline_visit(_location_id: String) -> void :

	Log.d("MapManager", "Visit declined")


func confirm_house_move_in() -> void :
	if GameState.owns_house:
		return
	GameState.owns_house = true
	GameState.house_offer_shown = true
	refresh_map_ui()
	Log.d("MapManager", "Player moved into house")


func get_train_destinations_from_current_region() -> Array[String]:
	return get_transport_destinations_from_current_region("train")


func get_transport_destinations_from_current_region(mode: String = "") -> Array[String]:
	var modes: Array[String] = []
	if not mode.strip_edges().is_empty():
		modes.append(mode)
	return _get_reachable_region_names_for_active_region(get_current_region(), modes)


func get_transport_modes_for_location(location_id: String) -> Array[String]:
	var normalized_id: = location_id.strip_edges().to_lower()
	var result: Array[String] = []
	if normalized_id.is_empty():
		return result
	if RegionRegistry != null and RegionRegistry.has_method("get_transport_modes_for_hub"):
		for raw_mode in RegionRegistry.get_transport_modes_for_hub(get_current_region(), normalized_id):
			var mode: = str(raw_mode).strip_edges().to_lower()
			if mode.is_empty() or mode in result:
				continue
			result.append(mode)
	if result.is_empty() and _get_bridge_location_ids().has(normalized_id) and not get_train_destinations_from_current_region().is_empty():
		result.append("train")
	result.sort()
	return result


func _has_transport_destinations_for_modes(modes: Array[String]) -> bool:
	for raw_mode in modes:
		if not get_transport_destinations_from_current_region(str(raw_mode)).is_empty():
			return true
	return false


func get_transport_departure_label(destination_region: String, mode: String) -> String:
	if RegionRegistry != null and RegionRegistry.has_method("get_transport_departure_label"):
		return RegionRegistry.get_transport_departure_label(destination_region, mode)
	return tr("Travel To %s") % destination_region


func get_region_action_target_region() -> String:
	var current_region: = get_current_region()
	if RegionRegistry != null and RegionRegistry.has_method("get_fallback_return_region_name"):
		var fallback_region: = str(RegionRegistry.get_fallback_return_region_name(current_region)).strip_edges()
		if not fallback_region.is_empty() and fallback_region != current_region:
			return fallback_region
	return ""


func get_region_action_label() -> String:
	var current_region: = get_current_region()
	if RegionRegistry != null and RegionRegistry.has_method("get_return_label"):
		var label: = str(RegionRegistry.get_return_label(current_region)).strip_edges()
		if not label.is_empty():
			return label
	var target_region: = get_region_action_target_region()
	if target_region.is_empty():
		return ""
	return tr("Return To %s") % (RegionRegistry.get_region_display_name(target_region) if RegionRegistry != null and RegionRegistry.has_method("get_region_display_name") else target_region)


func start_transport_travel_to_region(mode: String, destination_region: String, companion_tag: String = "") -> void :
	await _train_flow.start_transport_travel_to_region(mode, destination_region, companion_tag)


func quick_transport_travel_to_region(mode: String, destination_region: String) -> void :
	_train_flow.quick_transport_travel_to_region(mode, destination_region)


func return_to_region(destination_region: String) -> void :
	_train_flow.return_to_region(destination_region)



func get_progress_text() -> String:
	if GameState.current_mode == GameState.Mode.STORY:
		var visited: = GameState.get_required_visited_count()
		var total: = GameState.get_required_total_count()
		return tr("Friends visited: %d / %d") % [visited, total]
	else:
		var remaining: = GameState.MAX_DAILY_VISITS - GameState.daily_visits
		return tr("Day %d - %s (%d visits remaining)") % [
			GameState.current_day, 
			tr(GameState.get_time_slot_name()), 
			remaining
		]




func restore_ai_scene_visuals() -> void :
	if not AIStateCoordinator.is_active():
		return

	var location: = AIStateCoordinator.get_location()
	var location_id: = AIStateCoordinator.get_location_id()




	if location == null:
		if (
			_is_transport_scene_location_id(location_id)
			or location_id == "dream_realm"
			or location_id == ChrysalisFlow.CHRYSALIS_RUNTIME_LOCATION_ID
		):
			location = _build_runtime_location_for_restore(location_id)
			if _is_transport_scene_location_id(location_id) and location != null:
				_train_flow.is_active = true
			if location_id == ChrysalisFlow.CHRYSALIS_RUNTIME_LOCATION_ID and location != null:
				_chrysalis_flow.is_encounter_active = true
		elif location_id == CustomStartFlow.CUSTOM_START_RUNTIME_LOCATION_ID:
			location = _build_runtime_location_for_restore(location_id)
		elif location_id.is_empty() or location_id == "_timeline_driven":
			location = _infer_runtime_location_for_blank_ai_restore()
			if location == null:




				location = _build_timeline_driven_restore_location()
				_capture_timeline_restore_resume_state()

				if not AIStateCoordinator.session_ended.is_connected(_unpause_dialogic_after_timeline_restore):
					AIStateCoordinator.session_ended.connect(_unpause_dialogic_after_timeline_restore, CONNECT_ONE_SHOT)
				Log.d("MapManager", "Timeline-driven AI conversation, built stub for restore (phase=%s)" % AIStateCoordinator.get_phase_string())
		elif not location_id.is_empty():
			location = _build_runtime_location_for_restore(location_id)

	if location == null:

		push_warning("[MapManager] Could not find location for AI scene restore: %s" % location_id)
		_recover_missing_ai_restore_location(location_id)
		return

	Log.d("MapManager", "Restoring AI scene for: %s (phase: %s)" % [location.id, AIStateCoordinator.get_phase_string()])
	_current_location = location
	if _foreground_controller != null:
		_foreground_controller.set_current_location(location)
	var restored_tags: = AIStateCoordinator.get_character_tags()
	if not restored_tags.is_empty():
		_current_character_tags = restored_tags.duplicate()



	if _should_arm_chrysalis_followup(location):
		_chrysalis_flow.pending_followup_check = true

	if AIStateCoordinator.is_custom_start_active() or location.id == CustomStartFlow.CUSTOM_START_RUNTIME_LOCATION_ID:
		_custom_start_flow.is_active = true
		_custom_start_flow.character_tags = AIStateCoordinator.get_character_tags()
		_current_character_tags = _custom_start_flow.character_tags.duplicate()



	if (
		Dialogic.has_subsystem("Backgrounds")
		and not location.background.is_empty()
	):
		Dialogic.Backgrounds.update_background("", location.background, 0.0)




	if Dialogic.has_subsystem("Styles") and Dialogic.Styles.has_active_layout_node():
		Dialogic.Styles.get_layout_node().hide()



	call_deferred("_restore_ai_scene_full", location)


func prepare_for_load() -> void :
	_load_generation += 1
	_train_flow.is_active = false
	_train_flow._pending_destination_region = ""
	_train_flow._pending_transport_mode = "train"
	_pending_visit_character_tags.clear()
	_pending_visit_scene_brief = ""
	_pending_visit_conversation_prompt = ""
	_pending_visit_keep_scene_brief_in_qa = false
	_current_visit_qa_guidance = ""
	_pending_visit_go_alone = false
	_current_location = null
	_current_character_tags.clear()
	_bridge_managed_scene_flow_active = false
	_chrysalis_flow.pending_followup_check = false
	_chrysalis_flow.pending_custom_qa_prompt = false
	_chrysalis_flow.is_encounter_active = false
	_custom_start_flow.cancel()
	if _scenario_event_flow != null:
		_scenario_event_flow.reset()
	_close_ai_error_dialog()
	_clear_timeline_restore_resume_state()
	clear_sandbox_night_ai_restore()
	_night_flow._cancel_sandbox_end_day_sequence()



	if Dialogic.timeline_ended.is_connected(_on_story_complete_timeline_ended):
		Dialogic.timeline_ended.disconnect(_on_story_complete_timeline_ended)
	_suppress_conversation_completed_during_load = true


func finalize_after_load() -> void :
	_suppress_conversation_completed_during_load = false
	_night_flow._cancel_sandbox_end_day_sequence()


func _build_runtime_location_for_restore(location_id: String) -> LocationData:
	if _is_transport_scene_location_id(location_id):
		var transport_mode: = _get_transport_mode_for_scene_location_id(location_id)
		var target_region: String = GameState.travel_companion_region
		if target_region.is_empty() and not GameState.companion_in_canterlot_today.is_empty():
			target_region = "Canterlot"
		if target_region.is_empty():
			target_region = _get_default_train_destination_region(get_current_region())
		var target_display_name: String = RegionRegistry.get_region_display_name(target_region) if RegionRegistry != null and RegionRegistry.has_method("get_region_display_name") else target_region
		var transport_location: = _train_flow.build_transport_location(transport_mode, get_current_region(), target_display_name)
		var tags: = AIStateCoordinator.get_character_tags()
		if tags.is_empty() and not GameState.travel_companion_tag.is_empty():
			tags.append(GameState.travel_companion_tag)
		if tags.is_empty() and not GameState.train_companion_tag.is_empty():
			tags.append(GameState.train_companion_tag)
		transport_location.characters = tags
		return transport_location
	if location_id == "dream_realm":
		var dream_location: = LocationData.new()
		dream_location.id = "dream_realm"
		dream_location.display_name = "Dream Realm"
		dream_location.background = DREAM_BACKGROUND_PATH
		dream_location.music = DREAM_MUSIC_PATH
		dream_location.region = get_current_region()
		dream_location.has_map_position = false
		var tags: = AIStateCoordinator.get_character_tags()
		if tags.is_empty():
			tags = ["luna"]
		dream_location.characters = tags
		dream_location.sandbox_dialogue = "The dream realm shimmers around you."
		return dream_location
	if location_id == CustomStartFlow.CUSTOM_START_RUNTIME_LOCATION_ID:
		var custom_location: = LocationData.new()
		custom_location.id = CustomStartFlow.CUSTOM_START_RUNTIME_LOCATION_ID
		custom_location.display_name = "Custom Start Scene"
		custom_location.background = CustomStartFlow.BLACK_BACKGROUND_PATH
		custom_location.region = _get_default_region_name()
		custom_location.has_map_position = false
		custom_location.story_intro_dialogue = "A custom opening scene that can establish its own location with runtime commands."
		var tags: = AIStateCoordinator.get_character_tags()
		custom_location.characters = tags
		return custom_location
	if location_id == ChrysalisFlow.CHRYSALIS_RUNTIME_LOCATION_ID:
		return _chrysalis_flow.build_runtime_location()
	var registered_location: = LocationDatabase.get_location(location_id)
	if registered_location != null:
		return registered_location
	return _build_core_content_location_for_restore(location_id)





func _build_timeline_driven_restore_location() -> LocationData:
	var loc: = LocationData.new()
	loc.id = "_timeline_driven"
	loc.display_name = "Timeline Scene"
	loc.region = get_current_region()
	loc.has_map_position = false
	loc.background = Dialogic.current_state_info.get("background_argument", "")
	loc.characters = AIStateCoordinator.get_character_tags()
	return loc


func _infer_runtime_location_for_blank_ai_restore() -> LocationData:
	if GameState.current_mode != GameState.Mode.SANDBOX:
		return null
	if SleepoverSystem != null and not SleepoverSystem.flow_location_id.is_empty():
		return _build_runtime_location_for_restore(SleepoverSystem.flow_location_id)
	var home_location_id: = _night_flow._resolve_night_residence_location_id()
	if home_location_id.is_empty():
		return null
	return _build_runtime_location_for_restore(home_location_id)


func _build_core_content_location_for_restore(location_id: String) -> LocationData:
	var folder_path: = _find_core_location_folder(location_id)
	if folder_path.is_empty():
		return null

	var region: = folder_path.get_base_dir().get_file()
	var json_data: = JsonFile.load_dict(folder_path.path_join("location.json"))
	var location: = LocationData.new()
	location.id = str(json_data.get("id", location_id)).strip_edges()
	if location.id.is_empty():
		location.id = location_id
	location.display_name = str(json_data.get("name", _get_location_display_name(location.id))).strip_edges()
	if location.display_name.is_empty():
		location.display_name = _get_location_display_name(location.id)
	location.region = str(json_data.get("region", region)).strip_edges()
	if location.region.is_empty():
		location.region = region if not region.is_empty() else _get_default_region_name()
	location.background = _find_core_location_asset_logical_path(folder_path, ["background.png", "background.jpg", "background.jpeg", "background.webp"])
	location.foreground = _find_core_location_asset_logical_path(folder_path, ["foreground.png", "foreground.jpg", "foreground.jpeg", "foreground.webp"])
	location.music = MusicMixManager.get_default_music_for_folder(folder_path)
	location.context_description = str(json_data.get("context_description", json_data.get("description", ""))).strip_edges()
	location.sandbox_dialogue = str(json_data.get("sandbox_dialogue", "You arrive at %s." % location.display_name))
	location.story_intro_dialogue = str(json_data.get("story_intro_dialogue", ""))
	location.character_scale = float(json_data.get("character_scale", 1.0))
	location.character_offset_x = float(json_data.get("character_offset_x", 0.0))
	location.character_offset_y = float(json_data.get("character_offset_y", 0.0))
	location.apply_sleep_metadata_from_dict(json_data)
	location.sandbox_only = bool(json_data.get("sandbox_only", true))
	location.has_map_position = false
	location.source_folder = folder_path
	LocationSleepOverrides.apply(location)

	var active_tags: = AIStateCoordinator.get_character_tags()
	for raw_tag in active_tags:
		var tag: = str(raw_tag).strip_edges().to_lower()
		if tag.is_empty() or tag in location.characters:
			continue
		location.characters.append(tag)

	return location


func _find_core_location_folder(location_id: String) -> String:
	var core_root: = ContentPaths.get_locations_core_dir()
	var root_dir: = DirAccess.open(core_root)
	if root_dir == null:
		return ""

	root_dir.list_dir_begin()
	var entry: = root_dir.get_next()
	while entry != "":
		if root_dir.current_is_dir() and not entry.begins_with("."):
			var candidate: = core_root.path_join(entry).path_join(location_id)
			if DirAccess.dir_exists_absolute(candidate):
				root_dir.list_dir_end()
				return candidate
		entry = root_dir.get_next()
	root_dir.list_dir_end()
	return ""


func _find_core_location_asset_logical_path(folder_path: String, file_names: Array[String]) -> String:
	for file_name in file_names:
		var candidate: = folder_path.path_join(file_name)
		if FileAccess.file_exists(candidate):
			return ContentPaths.to_logical_path(candidate)
	return ""



func _restore_ai_scene_full(location: LocationData) -> void :
	var restoring_qa: = AIStateCoordinator.is_in_qa_conversation()


	if Dialogic.has_subsystem("Styles"):
		if not Dialogic.Styles.has_active_layout_node():
			Dialogic.Styles.load_style()
		await get_tree().process_frame
		if Dialogic.Styles.has_active_layout_node() and not restoring_qa:
			Dialogic.Styles.get_layout_node().show()




	_reset_dialogic_textbox_animation_state()

	if _foreground_controller != null:
		_foreground_controller.set_current_location(location)


	if not location.background.is_empty():
		Log.d("MapManager", "Restoring background: %s" % location.background)
		Dialogic.Backgrounds.update_background("", location.background, 0.0)




	await get_tree().process_frame
	if location.id == "_timeline_driven" and Dialogic.has_subsystem("Audio"):
		var audio_info: Dictionary = Dialogic.current_state_info.get("audio", {})
		for channel_name in audio_info:
			var channel_data: Dictionary = audio_info[channel_name]
			if channel_data.has("path") and not channel_data.path.is_empty():
				if not Dialogic.Audio.is_channel_playing(channel_name):
					Log.d("MapManager", "Manually restoring audio channel '%s': %s" % [channel_name, channel_data.path])
					Dialogic.Audio.update_audio(channel_name, channel_data.path, channel_data.get("settings_overrides", {}))


	if _resume_sandbox_night_ai_after_load and location.id == "dream_realm":
		clear_sandbox_night_ai_restore()
		if _night_flow.resume_sandbox_night_ai_after_load(location):
			return

	if AIStateCoordinator.is_in_scene_generation():
		_restore_scene_generation(location)
	elif AIStateCoordinator.is_in_qa_conversation():
		_restore_qa_conversation(location)
	else:

		_show_restore_fallback_message()


	_refresh_music_switcher_after_restore()


func _recover_missing_ai_restore_location(location_id: String) -> void :
	var safe_region: = get_current_region()
	if RegionRegistry != null and RegionRegistry.has_method("has_region") and not RegionRegistry.has_region(safe_region):
		safe_region = _get_default_region_name()
	set_current_region(safe_region)

	AIStateCoordinator.end_session()
	_current_location = null
	_current_character_tags.clear()
	_pending_visit_character_tags.clear()
	CharacterPortraitService.clear_scene_layout_state()

	if Dialogic.has_subsystem("Text"):
		Dialogic.Text.hide_textbox()
	if Dialogic.has_subsystem("Backgrounds") and Dialogic.Backgrounds.has_background():
		Dialogic.Backgrounds.update_background("", "", 0.0)
	if Dialogic.has_subsystem("Audio"):
		Dialogic.Audio.stop_all_channels(0.0)
	if Dialogic.has_subsystem("Styles") and Dialogic.Styles.has_active_layout_node():
		Dialogic.Styles.get_layout_node().hide()

	Log.d("MapManager", "Recovered missing AI restore location '%s' by returning to map region '%s'" % [location_id, safe_region])
	call_deferred("open_map")



func _restore_scene_generation(location: LocationData) -> void :
	if not AIStateCoordinator.has_pending_scene_state():
		Log.d("MapManager", "No scene generation state to restore, showing fallback")
		_show_restore_fallback_message()
		return

	Log.d("MapManager", "Restoring scene generation state")
	var scene_state: = AIStateCoordinator.get_pending_scene_state()
	AIStateCoordinator.clear_pending_scene_state()
	AIStateCoordinator.register_scene_generator(_scene_generator)
	_scene_generator.restore_from_save_state(scene_state, location)




func _restore_qa_conversation(location: LocationData) -> void :
	if not AIStateCoordinator.has_pending_conversation_state():
		Log.d("MapManager", "No Q&A conversation state to restore; attempting fresh Q&A recovery")
		var recovery_tags: = _filter_valid_character_tags(AIStateCoordinator.get_character_tags(), "Q&A restore recovery coordinator tags")
		if recovery_tags.is_empty() and SleepoverSystem != null and SleepoverSystem.is_sleepover_flow_active():
			recovery_tags = _resolve_sleepover_conversation_tags([], "Q&A restore recovery")
		if recovery_tags.is_empty():
			recovery_tags = _filter_valid_character_tags(location.characters, "Q&A restore recovery location tags")
		if recovery_tags.is_empty():
			_show_restore_fallback_message()
			return
		_current_location = location
		_current_character_tags = recovery_tags.duplicate()
		AIStateCoordinator.update_runtime_location(location)
		AIStateCoordinator.update_runtime_character_tags(recovery_tags)
		var recovery_prompt: = ""
		if SleepoverSystem != null and (
			SleepoverSystem.flow_phase == SleepoverSystem.FLOW_NIGHT_QA
			or SleepoverSystem.nighttime_conversation_active
		):
			recovery_prompt = SleepoverSystem.get_nighttime_conversation_prompt(location.id, recovery_tags)
		else:
			recovery_prompt = _resolve_visit_conversation_prompt(location, _chrysalis_flow.consume_pending_qa_prompt(recovery_tags), recovery_tags)
		if location.id == "_timeline_driven":
			AIConversation.start_conversation(recovery_tags, "", true, recovery_prompt)
		elif _conversation_bridge:
			_conversation_bridge.start_conversation(recovery_tags, "", true, recovery_prompt)
		else:
			AIConversation.start_conversation(recovery_tags, "", true, recovery_prompt)
		return




	if location.id == "_timeline_driven":
		Log.d("MapManager", "Restoring timeline-driven Q&A via autoload bridge")
		AIConversation.restore_conversation_from_save()
	elif _conversation_bridge:
		Log.d("MapManager", "Restoring Q&A conversation via MapManager bridge")
		_conversation_bridge.restore_conversation_from_save()
	else:
		Log.d("MapManager", "Restoring Q&A conversation via autoload bridge (fallback)")
		AIConversation.restore_conversation_from_save()



func _show_restore_fallback_message() -> void :
	if Dialogic.has_subsystem("Text"):
		Dialogic.Text.update_dialog_text("[i]%s[/i]" % tr("Scene restored. The AI conversation cannot be fully resumed from this save.\nPlease continue interacting or return to the map."), true)
		Dialogic.Text.show_textbox()
	Log.d("MapManager", "AI scene visuals restored (fallback mode)")


func _refresh_music_switcher_after_restore() -> void :
	var switchers: = get_tree().get_nodes_in_group("music_switcher")
	if switchers.is_empty():
		return
	var switcher: = switchers[0]
	if switcher:
		switcher.call_deferred("refresh_for_current_location")


func _finalize_bridge_managed_ai_session(context: String = "") -> void :
	if not AIStateCoordinator.is_active():
		return
	var suffix: = "" if context.is_empty() else " after %s" % context
	Log.d("MapManager", "Ending bridge-managed AI session%s" % suffix)
	AIStateCoordinator.end_session()


func _unpause_dialogic_after_timeline_restore() -> void :
	if _suppress_conversation_completed_during_load:
		Log.d("MapManager", "Skipping Dialogic timeline resume during load/reset")
		_clear_timeline_restore_resume_state()
		return
	Log.d("MapManager", "Resuming Dialogic timeline after timeline-driven AI session ended")
	_ensure_story_complete_timeline_end_hook_for_identifier(_timeline_restore_resume_path)


	Dialogic.set_meta("_block_call_event", false)
	_ensure_timeline_resumed_after_timeline_restore.call_deferred()


func _capture_timeline_restore_resume_state() -> void :
	var captured_path: = str(Dialogic.current_state_info.get("current_timeline", "")).strip_edges()
	var captured_event_idx: = int(Dialogic.current_state_info.get("current_event_idx", -1))
	if captured_path == "<null>":
		captured_path = ""
	if captured_path.is_empty() or captured_event_idx < 0:
		Log.d(
			"MapManager", 
			"Captured timeline restore resume state: path=<none> event_idx=%d (preserving_existing=%s)" % [
				captured_event_idx, 
				str( not _timeline_restore_resume_path.is_empty() and _timeline_restore_resume_event_idx >= 0), 
			]
		)
		return

	_timeline_restore_resume_path = captured_path
	_timeline_restore_resume_event_idx = captured_event_idx
	Log.d(
		"MapManager", 
		"Captured timeline restore resume state: path=%s event_idx=%d" % [
			_timeline_restore_resume_path if not _timeline_restore_resume_path.is_empty() else "<none>", 
			_timeline_restore_resume_event_idx, 
		]
	)


func capture_timeline_restore_resume_state_from_dialogic_state(state: Dictionary) -> void :
	if state.is_empty():
		_clear_timeline_restore_resume_state()
		Log.d("MapManager", "Captured timeline restore resume state from slot: path=<none> event_idx=-1")
		return

	_timeline_restore_resume_path = str(state.get("current_timeline", "")).strip_edges()
	if _timeline_restore_resume_path == "<null>":
		_timeline_restore_resume_path = ""
	_timeline_restore_resume_event_idx = int(state.get("current_event_idx", -1))
	Log.d(
		"MapManager", 
		"Captured timeline restore resume state from slot: path=%s event_idx=%d" % [
			_timeline_restore_resume_path if not _timeline_restore_resume_path.is_empty() else "<none>", 
			_timeline_restore_resume_event_idx, 
		]
	)


func _clear_timeline_restore_resume_state() -> void :
	_timeline_restore_resume_path = ""
	_timeline_restore_resume_event_idx = -1


func _ensure_timeline_resumed_after_timeline_restore() -> void :
	if _timeline_restore_resume_path.is_empty() or _timeline_restore_resume_event_idx < 0:
		Log.d(
			"MapManager", 
			"Timeline restore has no saved resume pointer; trying heuristic fallback (location=%s)" % [
				_current_location.id if _current_location != null else "<none>"
			]
		)
		if _resume_known_timeline_restore_fallback():
			if _current_location != null and _current_location.id == "_timeline_driven":
				_current_location = null
			_clear_timeline_restore_resume_state()
			return
		if _current_location != null and _current_location.id == "_timeline_driven":
			_current_location = null
		_clear_timeline_restore_resume_state()
		return

	var resume_path: = _timeline_restore_resume_path
	var resume_event_idx: = _timeline_restore_resume_event_idx
	await get_tree().process_frame



	if Dialogic.current_timeline != null:
		Log.d("MapManager", "Timeline restore resumed via Dialogic call event: %s" % Dialogic.current_timeline.resource_path)
		if _current_location != null and _current_location.id == "_timeline_driven":
			_current_location = null
		_clear_timeline_restore_resume_state()
		return

	Log.d(
		"MapManager", 
		"Timeline restore fallback triggered: restarting %s from event %d" % [
			resume_path, 
			resume_event_idx + 1, 
		]
	)
	Dialogic.start_timeline(resume_path, resume_event_idx + 1)
	if _current_location != null and _current_location.id == "_timeline_driven":
		_current_location = null
	_clear_timeline_restore_resume_state()


func _resume_known_timeline_restore_fallback() -> bool:




	if GameState.current_mode != GameState.Mode.STORY:
		return false
	if _current_location == null or _current_location.id != "_timeline_driven":
		return false
	if str(_current_location.background).strip_edges() != DREAM_BACKGROUND_PATH:
		return false

	var tags: Array = []
	if _current_location != null:
		tags = _current_location.characters
	var has_luna: = false
	for raw_tag in tags:
		var tag: = str(raw_tag).strip_edges().to_lower()
		if tag == "luna":
			has_luna = true
			break
	if not has_luna:
		Log.d("MapManager", "Timeline restore heuristic skipped: no luna tag in stub location")
		return false

	Log.d("MapManager", "Timeline restore heuristic triggered: resuming story_complete_return at after_luna_dream_ai")
	_ensure_story_complete_timeline_end_hook()
	Dialogic.start_timeline("story_complete_return", "after_luna_dream_ai")
	return true


func _ensure_story_complete_timeline_end_hook() -> void :
	if not Dialogic.timeline_ended.is_connected(_on_story_complete_timeline_ended):
		Dialogic.timeline_ended.connect(_on_story_complete_timeline_ended, CONNECT_ONE_SHOT)
		Log.d("MapManager", "Connected story_complete_return timeline end hook")


func _ensure_story_complete_timeline_end_hook_for_identifier(identifier: String) -> void :
	var normalized: = identifier.strip_edges()
	if normalized.is_empty():
		return
	if normalized.contains("story_complete_return"):
		_ensure_story_complete_timeline_end_hook()




func _reset_dialogic_textbox_animation_state() -> void :
	for tn in get_tree().get_nodes_in_group("dialogic_dialog_text"):
		if not ("textbox_root" in tn):
			continue

		var textbox_root = tn.textbox_root
		if textbox_root == null:
			continue

		var current = textbox_root.get_parent()
		while current:
			if current.name == "AnimationParent" and current is CanvasItem:
				current.position = Vector2.ZERO
				current.rotation = 0.0
				current.scale = Vector2.ONE
				current.modulate = Color(1, 1, 1, 1)
				break
			current = current.get_parent()







func _hide_ui_during_loading() -> void :

	var menu_button: = _find_dialogic_menu_button()
	if menu_button:
		menu_button.visible = false
		Log.d("MapManager", "Hidden MenuButton during loading")






func show_ui_after_loading() -> void :

	var menu_button: = _find_dialogic_menu_button()
	if menu_button:
		menu_button.visible = true
		Log.d("MapManager", "Shown MenuButton after loading")




	for rollback_history in get_tree().get_nodes_in_group("rollback_history"):
		if rollback_history.has_method("ensure_navigation_buttons"):
			rollback_history.call_deferred("ensure_navigation_buttons")



func _find_dialogic_menu_button() -> Node:
	if not Dialogic.has_subsystem("Styles") or not Dialogic.Styles.has_active_layout_node():
		return null

	var layout_node: = Dialogic.Styles.get_layout_node()
	if layout_node == null:
		return null

	return _find_node_recursive(layout_node, "MenuButton")



func _find_node_recursive(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found: = _find_node_recursive(child, target_name)
		if found:
			return found
	return null

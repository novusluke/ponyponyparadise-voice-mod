class_name AIConversationBridge
extends Node





var _ai_conversation: DialogicAIConversation = null


var _scene_generator: AISceneGenerator = null
var _shared_scene_generator: AISceneGenerator = null
var _rollback_owner_key: String = "ai_conversation_bridge"


var _in_conversation: = false
var _bridge_error_canvas: CanvasLayer = null
var _bridge_error_result: Dictionary = {}
var _reset_generation: = 0


signal conversation_completed
signal bridge_error_choice_selected(choice: String)


var _scene_wait_done: = false
var _scene_wait_failed: = false
var _scene_wait_token: int = 0
var _scene_wait_context: String = ""


func _ready() -> void :
	AIStateCoordinator.session_ended.connect(_on_session_reset)
	_apply_rollback_owner_key()


func set_rollback_owner_key(owner_key: String) -> void :
	var normalized: = owner_key.strip_edges()
	_rollback_owner_key = normalized if not normalized.is_empty() else "ai_conversation_bridge"
	_apply_rollback_owner_key()


func _apply_rollback_owner_key() -> void :
	if _ai_conversation != null and is_instance_valid(_ai_conversation):
		_ai_conversation.set_rollback_owner_key(_rollback_owner_key)
	if _scene_generator != null and is_instance_valid(_scene_generator):
		_scene_generator.set_rollback_owner_key(_rollback_owner_key)
	if _shared_scene_generator != null and is_instance_valid(_shared_scene_generator):
		_shared_scene_generator.set_rollback_owner_key(_rollback_owner_key)



func _on_session_reset() -> void :
	_reset_generation += 1
	_in_conversation = false
	_invalidate_scene_wait("session_reset")
	_close_bridge_error_dialog()


func _exit_tree() -> void :
	_on_session_reset()


func set_shared_scene_generator(scene_generator: AISceneGenerator) -> void :
	if _shared_scene_generator == scene_generator:
		return
	_disconnect_scene_wait_signals()
	_shared_scene_generator = scene_generator
	if _shared_scene_generator != null:
		_shared_scene_generator.set_rollback_owner_key(_rollback_owner_key)





func scene_with_duo(tag1: String, tag2: String, scene_brief: String = "", location_context: String = "", custom_system_prompt: String = "") -> void :
	Log.d("AIConversationBridge", "scene_with_duo called: tags=[%s, %s] in_conv=%s coordinator_active=%s pending_scene=%s pending_qa=%s" % [
		tag1, tag2, str(_in_conversation), str(AIStateCoordinator.is_active()), 
		str(AIStateCoordinator.has_pending_scene_state()), str(AIStateCoordinator.has_pending_conversation_state())
	])
	_sync_conversation_flag()



	if await _try_restore_from_save([tag1, tag2], location_context):
		return

	if _in_conversation:
		Log.d(
			"AIConversationBridge", 
			"Rejecting scene_with_duo because bridge is still marked active (node_active=%s, coordinator_phase=%s)" % [
				str(_ai_conversation != null and _ai_conversation.is_active()), 
				AIStateCoordinator.get_phase_string(), 
			]
		)
		push_warning("[AIConversationBridge] Already in a conversation")
		return

	if not await _require_configured_api_for_timeline(
		tr("AI Setup Required"), 
		tr("This scene needs a working AI configuration before it can generate the intro and continue the conversation.")
	):
		return

	var scene_generator: = _get_scene_generator(true)
	if scene_generator == null:
		push_warning("[AIConversationBridge] No scene generator available")
		return


	var temp_location: = LocationData.new()
	var ctx: = location_context.strip_edges()
	if not ctx.is_empty():

		var parts: = ctx.split(" - ", false, 2)
		temp_location.display_name = parts[0] if not parts.is_empty() else "Ponyville"
		temp_location.story_intro_dialogue = ctx
	else:
		temp_location.display_name = "Ponyville"
		temp_location.story_intro_dialogue = ""

	var coordinator_location: = _get_current_map_location_for_ai(temp_location)
	if not AIStateCoordinator.is_active():
		AIStateCoordinator.begin_scene_generation(coordinator_location, [tag1, tag2])
	AIStateCoordinator.register_scene_generator(scene_generator)


	var story_context: = _get_dialogic_story_context()
	var scene_token: = _begin_scene_wait(scene_generator, "scene_with_duo(%s,%s)" % [tag1, tag2])
	scene_generator.generate_scene(temp_location, [tag1, tag2], story_context, scene_brief)

	while scene_token == _scene_wait_token and not _scene_wait_done:
		await get_tree().process_frame

	if scene_token != _scene_wait_token:
		Log.d("AIConversationBridge", "scene_with_duo aborted as stale scene token=%d current=%d" % [scene_token, _scene_wait_token])
		return

	if _scene_wait_failed:
		push_warning("[AIConversationBridge] Intro scene failed; continuing to Q&A anyway")
	if AIStateCoordinator.is_in_scene_generation():
		AIStateCoordinator.unregister_scene_generator()
		AIStateCoordinator.transition_to_qa_conversation()
	else:
		Log.d("AIConversationBridge", "scene_with_duo skipping Q&A start because phase changed to %s" % AIStateCoordinator.get_phase_string())
		return


	await start_conversation([tag1, tag2], "", false, custom_system_prompt)





func scene_with_single(tag: String, scene_brief: String = "", location_context: String = "", custom_system_prompt: String = "", prefill_scope: String = "") -> void :
	Log.d("AIConversationBridge", "scene_with_single called: tag=%s in_conv=%s coordinator_active=%s pending_scene=%s pending_qa=%s" % [
		tag, str(_in_conversation), str(AIStateCoordinator.is_active()), 
		str(AIStateCoordinator.has_pending_scene_state()), str(AIStateCoordinator.has_pending_conversation_state())
	])
	_sync_conversation_flag()



	if await _try_restore_from_save([tag], location_context):
		return

	if _in_conversation:
		Log.d(
			"AIConversationBridge", 
			"Rejecting start_conversation because bridge is still marked active (node_active=%s, coordinator_phase=%s)" % [
				str(_ai_conversation != null and _ai_conversation.is_active()), 
				AIStateCoordinator.get_phase_string(), 
			]
		)
		push_warning("[AIConversationBridge] Already in a conversation")
		return

	if not await _require_configured_api_for_timeline(
		tr("AI Setup Required"), 
		tr("This scene needs a working AI configuration before it can generate the intro and continue the conversation.")
	):
		return

	var scene_generator: = _get_scene_generator(true)
	if scene_generator == null:
		push_warning("[AIConversationBridge] No scene generator available")
		return


	var temp_location: = LocationData.new()
	var ctx: = location_context.strip_edges()
	if not ctx.is_empty():
		var parts: = ctx.split(" - ", false, 2)
		temp_location.display_name = parts[0] if not parts.is_empty() else "Ponyville"
		temp_location.story_intro_dialogue = ctx
	else:
		temp_location.display_name = "Ponyville"
		temp_location.story_intro_dialogue = ""

	var coordinator_location: = _get_current_map_location_for_ai(temp_location)
	if not AIStateCoordinator.is_active():
		AIStateCoordinator.begin_scene_generation(coordinator_location, [tag])
	AIStateCoordinator.register_scene_generator(scene_generator)


	var story_context: = _get_dialogic_story_context()
	var scene_token: = _begin_scene_wait(scene_generator, "scene_with_single(%s)" % tag)
	scene_generator.generate_scene(temp_location, [tag], story_context, scene_brief, "", "", {}, prefill_scope)

	while scene_token == _scene_wait_token and not _scene_wait_done:
		await get_tree().process_frame

	if scene_token != _scene_wait_token:
		Log.d("AIConversationBridge", "scene_with_single aborted as stale scene token=%d current=%d" % [scene_token, _scene_wait_token])
		return

	if _scene_wait_failed:
		push_warning("[AIConversationBridge] Intro scene failed; continuing to Q&A anyway")
	if AIStateCoordinator.is_in_scene_generation():
		AIStateCoordinator.unregister_scene_generator()
		AIStateCoordinator.transition_to_qa_conversation()
	else:
		Log.d("AIConversationBridge", "scene_with_single skipping Q&A start because phase changed to %s" % AIStateCoordinator.get_phase_string())
		return


	await start_conversation([tag], "", false, custom_system_prompt)





func start_conversation(character_tags: Array, _background_path: String = "", preload_initial_portraits: bool = false, custom_system_prompt: String = "", require_api: bool = true) -> void :
	var reset_generation: = _reset_generation
	_sync_conversation_flag()
	if APIConfigManager.is_debug_enabled():
		var timeline_path: = Dialogic.current_timeline.resource_path if Dialogic.current_timeline else "<none>"
		print("[AIConversationBridge][Debug] start_conversation: paused=%s state=%s event_idx=%s timeline=%s pending_ai_state=%s in_conv=%s" % [
			str(Dialogic.paused), 
			str(Dialogic.current_state), 
			str(Dialogic.current_event_idx), 
			timeline_path, 
			"present" if AIStateCoordinator.has_pending_conversation_state() else "empty", 
			str(_in_conversation), 
		])




	if AIStateCoordinator.has_pending_conversation_state():
		Log.d("AIConversationBridge", "Restoring AI conversation from save state")

		_in_conversation = false
		await restore_conversation_from_save(character_tags)
		return

	if _in_conversation:
		Log.d(
			"AIConversationBridge", 
			"Rejecting start_conversation because bridge is still marked active (node_active=%s, coordinator_phase=%s)" % [
				str(_ai_conversation != null and _ai_conversation.is_active()), 
				AIStateCoordinator.get_phase_string(), 
			]
		)
		push_warning("[AIConversationBridge] Already in a conversation")
		return

	if require_api and not await _require_configured_api_for_timeline(
		tr("AI Setup Required"), 
		tr("This conversation needs a working AI configuration before it can start.")
	):
		return


	if _ai_conversation != null and _ai_conversation.is_active() and not _in_conversation:
		push_warning("[AIConversationBridge] Detected stale active conversation node, recreating it")
		_ensure_ai_conversation_instance(true)


	_ensure_ai_conversation_instance()


	var tags: Array[String] = []
	await AIDialogueShared.cancel_pending_dialogue_ending()
	if reset_generation != _reset_generation:
		return
	for tag in character_tags:
		tags.append(str(tag))

	_in_conversation = true



	if not AIStateCoordinator.is_active():
		AIStateCoordinator.begin_qa_conversation(tags)
	elif AIStateCoordinator.get_location_id().is_empty():
		var current_location: = _get_current_map_location_for_ai()
		if current_location != null:
			AIStateCoordinator.update_runtime_location(current_location)
	AIStateCoordinator.register_conversation(_ai_conversation)


	var story_context: = _get_dialogic_story_context()


	_ai_conversation.start_conversation(tags, story_context, custom_system_prompt)
	await get_tree().process_frame
	if reset_generation != _reset_generation:
		return
	if not _ai_conversation.is_active():
		push_warning("[AIConversationBridge] Conversation failed to activate, rebuilding AI conversation node and retrying once")
		_ensure_ai_conversation_instance(true)
		AIStateCoordinator.register_conversation(_ai_conversation)
		_ai_conversation.start_conversation(tags, story_context, custom_system_prompt)
		await get_tree().process_frame
		if reset_generation != _reset_generation:
			return
		if not _ai_conversation.is_active():
			push_error("[AIConversationBridge] Conversation failed to activate after retry")
			_in_conversation = false
			AIStateCoordinator.unregister_conversation()
			if AIStateCoordinator.is_active() and AIStateCoordinator.get_location_id().is_empty():
				AIStateCoordinator.end_session()
			return

	if preload_initial_portraits and _ai_conversation.has_method("show_initial_character_portraits"):
		await _ai_conversation.show_initial_character_portraits(tags)
		if reset_generation != _reset_generation:
			return

	Log.d("AIConversationBridge", "start_conversation called; ai_active=%s" % str(_ai_conversation.is_active() if _ai_conversation else false))
	if _ai_conversation:
		_ai_conversation.call_deferred("debug_dump_state", "bridge_after_start")


	while _in_conversation and reset_generation == _reset_generation:
		await get_tree().process_frame






func _try_restore_from_save(_tags: Array, _location_context: String = "") -> bool:
	var reset_generation: = _reset_generation


	if AIStateCoordinator.is_active():
		Log.d("AIConversationBridge", "_try_restore_from_save: coordinator active, blocking until session ends")

		while AIStateCoordinator.is_active() and reset_generation == _reset_generation:
			await get_tree().process_frame
		Log.d("AIConversationBridge", "_try_restore_from_save: session ended, unblocking")
		return true

	return false




func restore_conversation_from_save(_character_tags: Array = []) -> void :
	var reset_generation: = _reset_generation

	_ensure_ai_conversation_instance()

	_in_conversation = true


	var conversation_state: = AIStateCoordinator.get_pending_conversation_state()
	AIStateCoordinator.clear_pending_conversation_state()
	Log.d("AIConversationBridge", "restore_conversation_from_save: state_keys=%s history_size=%s" % [
		str(conversation_state.keys()), 
		str(conversation_state.get("history", []).size()) if conversation_state.has("history") else "n/a"
	])


	AIStateCoordinator.register_conversation(_ai_conversation)


	await _ai_conversation.restore_from_save_state(conversation_state)


	while _in_conversation and reset_generation == _reset_generation:
		await get_tree().process_frame




func _get_dialogic_story_context() -> String:
	if StorySummaryManager != null:
		return StorySummaryManager.build_active_context()

	return ""



func _get_character_tag(display_name: String) -> String:
	return CharacterPortraitService.get_character_tag(display_name)


func _get_current_map_location_for_ai(fallback: LocationData = null) -> LocationData:



	if Dialogic.current_timeline != null:
		if fallback != null:
			if fallback.id.is_empty():
				fallback.id = "_timeline_driven"
			if fallback.background.is_empty():
				fallback.background = str(Dialogic.current_state_info.get("background_argument", ""))
		return fallback

	if MapManager != null and MapManager.has_method("get_current_location"):
		var current_location: LocationData = MapManager.get_current_location()
		if current_location != null and not current_location.id.is_empty():
			return current_location
	return fallback




func talk_to_twilight(_background_path: String = "") -> void :
	await start_conversation(["twi"], "", false, "", false)




func talk_to_duo(tag1: String, tag2: String) -> void :
	await start_conversation([tag1, tag2])




func start_multi_conversation(character_tags: Array, _background_path: String = "") -> void :
	await start_conversation(character_tags)



func _on_conversation_completed() -> void :
	_in_conversation = false
	_close_bridge_error_dialog()


	AIStateCoordinator.unregister_conversation()

	var loc_id: = AIStateCoordinator.get_location_id()
	if AIStateCoordinator.is_active() and (loc_id.is_empty() or loc_id == "_timeline_driven"):
		AIStateCoordinator.end_session()

	conversation_completed.emit()



func is_in_conversation() -> bool:
	return _in_conversation


func _sync_conversation_flag() -> void :
	if _in_conversation and (_ai_conversation == null or not _ai_conversation.is_active()):
		Log.d("AIConversationBridge", "Clearing stale in-conversation flag (conversation node inactive)")
		_in_conversation = false


func _require_configured_api_for_timeline(title_text: String, message_text: String) -> bool:
	var reset_generation: = _reset_generation
	while not APIConfigManager.is_configured():
		push_warning("[AIConversationBridge] API not configured for timeline-driven AI flow")
		var choice: = await _prompt_bridge_error_dialog(title_text, message_text)
		if reset_generation != _reset_generation:
			return false
		match choice:
			"retry":
				continue
			"settings":
				await _open_api_settings_and_wait()
				if reset_generation != _reset_generation:
					return false
			_:
				return false
	return true


func _prompt_bridge_error_dialog(title_text: String, message_text: String) -> String:
	_close_bridge_error_dialog()

	var result: = {"choice": ""}
	_bridge_error_result = result

	var canvas: = CanvasLayer.new()
	canvas.layer = 102
	add_child(canvas)
	_bridge_error_canvas = canvas

	var blocker: = Control.new()
	blocker.name = "AIBridgeErrorBlocker"
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.add_to_group("ui_blocking_overlay")
	canvas.add_child(blocker)

	var dimmer: = ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.01, 0.01, 0.03, 0.7)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.add_child(dimmer)

	var panel: = PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -260
	panel.offset_top = -135
	panel.offset_right = 260
	panel.offset_bottom = 135
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(panel)

	var panel_style: = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.09, 0.07, 0.14, 0.98)
	panel_style.set_border_width_all(2)
	panel_style.border_color = Color(0.85, 0.45, 0.56, 0.95)
	panel_style.set_corner_radius_all(14)
	panel_style.shadow_color = Color(0, 0, 0, 0.3)
	panel_style.shadow_size = 10
	panel_style.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", panel_style)

	var margin: = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var root: = VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title: = Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.96))
	root.add_child(title)

	var message: = Label.new()
	message.text = message_text
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size", 14)
	message.add_theme_color_override("font_color", Color(0.86, 0.83, 0.92))
	root.add_child(message)

	var button_row: = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 10)
	root.add_child(button_row)

	var retry_button: = Button.new()
	retry_button.text = "Retry"
	retry_button.custom_minimum_size = Vector2(110, 40)
	_style_bridge_error_button(retry_button, Color(0.42, 0.72, 0.48), Color(0.22, 0.42, 0.24))
	retry_button.pressed.connect( func() -> void :
		if _bridge_error_canvas == canvas:
			_close_bridge_error_dialog("retry")
	)
	button_row.add_child(retry_button)

	var settings_button: = Button.new()
	settings_button.text = "API Settings"
	settings_button.custom_minimum_size = Vector2(130, 40)
	_style_bridge_error_button(settings_button, Color(0.48, 0.42, 0.78), Color(0.24, 0.22, 0.46))
	settings_button.pressed.connect( func() -> void :
		if _bridge_error_canvas == canvas:
			_close_bridge_error_dialog("settings")
	)
	button_row.add_child(settings_button)

	var continue_button: = Button.new()
	continue_button.text = "Continue"
	continue_button.custom_minimum_size = Vector2(110, 40)
	_style_bridge_error_button(continue_button, Color(0.78, 0.44, 0.48), Color(0.44, 0.2, 0.24))
	continue_button.pressed.connect( func() -> void :
		if _bridge_error_canvas == canvas:
			_close_bridge_error_dialog("continue")
	)
	button_row.add_child(continue_button)

	while str(result["choice"]).is_empty() and is_inside_tree():
		await get_tree().process_frame
	return str(result["choice"]) if not str(result["choice"]).is_empty() else "cancelled"


func _close_bridge_error_dialog(choice: String = "cancelled") -> void :
	var canvas: = _bridge_error_canvas
	var result: = _bridge_error_result
	_bridge_error_canvas = null
	_bridge_error_result = {}
	if canvas and is_instance_valid(canvas):
		canvas.queue_free()
	if not result.is_empty():
		result["choice"] = choice
		bridge_error_choice_selected.emit(choice)


func _style_bridge_error_button(button: Button, fill_color: Color, border_color: Color) -> void :
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


func _open_api_settings_and_wait() -> void :
	var current_scene: = get_tree().current_scene
	if current_scene == null or not current_scene.has_method("open_api_settings_menu"):
		await get_tree().process_frame
		return

	current_scene.call("open_api_settings_menu")
	var menu = current_scene.get("api_config_menu")
	if menu != null and menu.has_signal("closed"):
		await menu.closed
	else:
		await get_tree().process_frame


func _ensure_ai_conversation_instance(force_recreate: bool = false) -> void :
	if force_recreate and _ai_conversation != null:
		if _ai_conversation.conversation_completed.is_connected(_on_conversation_completed):
			_ai_conversation.conversation_completed.disconnect(_on_conversation_completed)
		_ai_conversation.queue_free()
		_ai_conversation = null

	if _ai_conversation == null:
		_ai_conversation = DialogicAIConversation.new()
		_ai_conversation.set_rollback_owner_key(_rollback_owner_key)
		add_child(_ai_conversation)
		_ai_conversation.conversation_completed.connect(_on_conversation_completed)


func _begin_scene_wait(scene_generator: AISceneGenerator, context: String = "") -> int:
	_scene_wait_token += 1
	_scene_wait_context = context
	_scene_wait_done = false
	_scene_wait_failed = false
	_disconnect_scene_wait_signals()
	if scene_generator == null:
		return _scene_wait_token
	Log.d("AIConversationBridge", "Scene wait started token=%d context=%s" % [_scene_wait_token, _scene_wait_context])
	scene_generator.scene_playback_completed.connect(_on_scene_wait_completed, CONNECT_ONE_SHOT)
	scene_generator.scene_generation_failed.connect(_on_scene_wait_failed, CONNECT_ONE_SHOT)
	return _scene_wait_token


func _on_scene_wait_completed() -> void :
	Log.d("AIConversationBridge", "Scene wait completed token=%d context=%s" % [_scene_wait_token, _scene_wait_context])
	_scene_wait_done = true
	_scene_wait_failed = false


func _on_scene_wait_failed(_error: String) -> void :
	Log.d("AIConversationBridge", "Scene wait failed token=%d context=%s" % [_scene_wait_token, _scene_wait_context])
	_scene_wait_done = true
	_scene_wait_failed = true


func _get_scene_generator(create_if_missing: bool = false) -> AISceneGenerator:
	if _shared_scene_generator != null and is_instance_valid(_shared_scene_generator):
		return _shared_scene_generator

	if create_if_missing and (_scene_generator == null or not is_instance_valid(_scene_generator)):
		_scene_generator = AISceneGenerator.new()
		_scene_generator.set_rollback_owner_key(_rollback_owner_key)
		add_child(_scene_generator)

	if _scene_generator != null and is_instance_valid(_scene_generator):
		return _scene_generator

	return null


func _disconnect_scene_wait_signals() -> void :
	for scene_generator in [_shared_scene_generator, _scene_generator]:
		if scene_generator == null or not is_instance_valid(scene_generator):
			continue
		if scene_generator.scene_playback_completed.is_connected(_on_scene_wait_completed):
			scene_generator.scene_playback_completed.disconnect(_on_scene_wait_completed)
		if scene_generator.scene_generation_failed.is_connected(_on_scene_wait_failed):
			scene_generator.scene_generation_failed.disconnect(_on_scene_wait_failed)


func _invalidate_scene_wait(reason: String) -> void :
	_scene_wait_token += 1
	_scene_wait_context = reason
	_scene_wait_done = false
	_scene_wait_failed = false
	_disconnect_scene_wait_signals()
	Log.d("AIConversationBridge", "Scene wait invalidated token=%d reason=%s" % [_scene_wait_token, reason])

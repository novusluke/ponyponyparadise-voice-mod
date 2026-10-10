class_name AISceneGenerator
extends Node




signal scene_generation_failed(error: String)
signal scene_playback_completed
signal scene_interrupted

const LocationDescriptionStorage: = preload("res://scripts/services/location_description_storage.gd")
const TouchScrollGesture: = preload("res://scripts/ui/touch_scroll_gesture.gd")
const MAX_VISIBLE_LAYOUT_CHARACTERS: = 6
const STAGE_ROTATION_FADE: = 0.18
const CACHE_SCENE_RUNTIME_REFERENCE: = "Provided in the final scene request."


var _ai_client: AIConversationClient


var _prompt_manager: PromptManager


var _line_processor: DialogueLineProcessor


var _current_location: LocationData = null
var _scene_start_location_id: String = ""
var _prefill_scope: = "scene"
const AssistantPrefill: = preload("res://scripts/api/assistant_prefill.gd")


var _character_data: Array[CharacterData] = []
var _dialogic_characters: Dictionary = {}


var _sprite_states: Dictionary = {}


var _joined_characters: Dictionary = {}
var _joined_character_order: Array[String] = []


var _rotated_out_tags: Array[String] = []
var _stage_recency: Array[String] = []


var _scene_queue: Array = []


var _is_playing: = false


var _interrupt_requested: = false



var _story_context: String = ""



var _custom_scene_brief: String = ""
var _custom_system_prompt_override: String = ""
var _custom_user_prompt_override: String = ""
var _management_context_override: Dictionary = {}


var _control_panel: PanelContainer = null


var _interrupt_panel: PanelContainer = null
var _edit_panel: PanelContainer = null
var _show_edit_button: = false
var _is_editing: = false
var _edit_text_edit: TextEdit = null
var _current_displayed_text: = ""
var _edit_dialog_panel: PanelContainer = null
var _show_interrupt_before_edit: = false
var _edit_enabled: = false
var _edit_just_closed: = false




var _rollback_owner_key: String = ""


var _thinking_controller: ThinkingAnimationController = null


var _dialog_text_node: RichTextLabel = null
var _dialog_text_parent: Control = null


var _session_id: int = 0

var _request_session_id: int = -1


var _displayed_lines: Array = []


var _cancel_advance_wait: bool = false


var _is_waiting_for_advance: bool = false


var _is_displaying_line: bool = false


var _initial_dialogic_history_length: int = -1


func _ready() -> void :
	add_to_group("ai_scene_generator")

	RollbackManager.ai_state_changed.connect(_on_rollback_ai_state_changed)
	RollbackManager.snapshot_type_changed.connect(_on_rollback_snapshot_type_changed)
	_create_ai_client()

	_prompt_manager = PromptManager.new()
	_line_processor = DialogueLineProcessor.new()


	_thinking_controller = ThinkingAnimationController.new()
	_thinking_controller.setup(self)


func set_rollback_owner_key(owner_key: String) -> void :
	_rollback_owner_key = owner_key.strip_edges()


func get_rollback_owner_key() -> String:
	return _rollback_owner_key


func get_rollback_owner_kind() -> String:
	return "scene"


func owns_rollback_snapshot(ai_data: Dictionary) -> bool:
	var owner_kind: = str(ai_data.get("rollback_owner_kind", "")).strip_edges()
	if not owner_kind.is_empty() and owner_kind != get_rollback_owner_kind():
		return false
	var owner_key: = str(ai_data.get("rollback_owner_key", "")).strip_edges()

	return owner_key.is_empty() or owner_key == _rollback_owner_key


func _exit_tree() -> void :
	var voice_mod = get_tree().root.get_node_or_null("PonyVoiceMod")
	if voice_mod != null:
		voice_mod.stop()
	_cleanup()
	if _interrupt_panel:
		_interrupt_panel.queue_free()
		_interrupt_panel = null
	if _edit_panel:
		_edit_panel.queue_free()
		_edit_panel = null
	if _edit_dialog_panel:
		_edit_dialog_panel.queue_free()
		_edit_dialog_panel = null


func _process(_delta: float) -> void :

	if (is_instance_valid(_interrupt_panel) and _interrupt_panel.visible) or (is_instance_valid(_edit_panel) and _edit_panel.visible):
		_update_interrupt_button_position()



func generate_scene(
	location: LocationData, 
	character_tags: Array[String], 
	story_context: String = "", 
	scene_brief: String = "", 
	custom_system_prompt: String = "", 
	custom_user_prompt: String = "", 
	management_context_override: Dictionary = {}, 
	prefill_scope: String = ""
) -> void :
	if _is_playing:
		push_warning("[AISceneGenerator] Already generating/playing a scene")
		return


	_session_id += 1
	var ending_session := _session_id
	await AIDialogueShared.cancel_pending_dialogue_ending()
	if ending_session != _session_id:
		return
	_current_location = location
	_scene_start_location_id = location.id if location != null else ""
	var scope_location: = _scene_start_location_id if not _scene_start_location_id.is_empty() else MapManager.get_current_runtime_location_id()
	_prefill_scope = prefill_scope if prefill_scope in AssistantPrefill.SCOPES else AssistantPrefill.resolve_scope("scene", scope_location)
	if AIStateCoordinator.is_active():
		AIStateCoordinator.set_prefill_context(_prefill_scope)
	_story_context = story_context
	if (
		APIConfigManager != null
		and APIConfigManager.is_prompt_cache_enabled()
		and AIStateCoordinator != null
		and AIStateCoordinator.is_active()
	):
		AIStateCoordinator.set_prompt_cache_scene_story_prefix(_story_context)
	_custom_scene_brief = scene_brief
	_custom_system_prompt_override = custom_system_prompt.strip_edges()
	_custom_user_prompt_override = custom_user_prompt.strip_edges()
	_management_context_override = _sanitize_management_context_override(management_context_override)
	_character_data.clear()
	_dialogic_characters.clear()
	_sprite_states.clear()
	_joined_characters.clear()
	_joined_character_order.clear()
	_rotated_out_tags.clear()
	_stage_recency.clear()
	_scene_queue.clear()
	_displayed_lines.clear()
	_interrupt_requested = false
	_cancel_advance_wait = false
	_show_edit_button = false
	_current_displayed_text = ""
	_is_editing = false
	_edit_just_closed = false
	_edit_enabled = false
	_mark_dialogic_history_start_for_retry()


	for tag in character_tags:
		var char_data: = _prompt_manager.load_character(tag)
		if char_data != null:
			_character_data.append(char_data)
			var dialogic_char: = CharacterPortraitService.find_dialogic_character(tag)
			if dialogic_char:
				_dialogic_characters[tag] = dialogic_char
				_sprite_states[tag] = "neutral"

	if _character_data.is_empty():
		push_error("[AISceneGenerator] No valid characters found")
		scene_generation_failed.emit(tr("No valid characters"))
		return


	var valid_tags: Array[String] = []
	for char_data in _character_data:
		valid_tags.append(char_data.tag)
	_line_processor.set_valid_tags(valid_tags)
	_line_processor.set_known_character_tags(_get_known_character_tags())


	_find_dialog_text_node()


	_show_thinking_indicator()


	_request_session_id = _session_id
	_send_scene_request()



func retry_scene() -> void :
	if _current_location == null or _character_data.is_empty():
		push_warning("[AISceneGenerator] Cannot retry - no previous scene")
		return


	if RollbackManager.is_in_rollback_mode():
		Log.d("AISceneGenerator", "Exiting rollback mode before retry")
		RollbackManager.exit_rollback_mode()
	_discard_previous_attempt_snapshots()
	if _ai_client != null and _ai_client.is_requesting():
		_replace_ai_client()



	if _initial_dialogic_history_length >= 0 and Dialogic.has_subsystem("History"):
		var current_history_size: int = Dialogic.History.simple_history_content.size()
		if current_history_size > _initial_dialogic_history_length:
			Log.d("AISceneGenerator", "Truncating Dialogic history from %d to %d for retry" % [current_history_size, _initial_dialogic_history_length])
			Dialogic.History.simple_history_content.resize(_initial_dialogic_history_length)


	_session_id += 1
	_cancel_advance_wait = true
	_is_waiting_for_advance = false
	_is_displaying_line = false
	_is_playing = false
	_scene_queue.clear()
	_interrupt_requested = false
	_current_displayed_text = ""
	_show_edit_button = false
	_edit_enabled = false
	_restore_scene_start_location_for_retry()
	_hide_control_panel()


	await _leave_all_characters()
	_joined_characters.clear()
	_joined_character_order.clear()
	_rotated_out_tags.clear()
	_stage_recency.clear()
	_sprite_states.clear()
	_displayed_lines.clear()
	CharacterPortraitService.clear_scene_layout_state()
	_cancel_advance_wait = false

	_show_thinking_indicator()
	_request_session_id = _session_id
	_refresh_story_context_for_retry()
	_send_scene_request()






func _refresh_story_context_for_retry() -> void :
	if StorySummaryManager == null:
		return
	_story_context = StorySummaryManager.build_active_context()
	if (
		APIConfigManager != null
		and APIConfigManager.is_prompt_cache_enabled()
		and AIStateCoordinator != null
		and AIStateCoordinator.is_active()
	):
		AIStateCoordinator.set_prompt_cache_scene_story_prefix(_story_context)










func _discard_previous_attempt_snapshots() -> void :
	var snapshot_count: int = RollbackManager.get_snapshot_count()
	for i in range(snapshot_count):
		var snapshot: Dictionary = RollbackManager.get_snapshot_metadata(i)
		var snapshot_type: int = snapshot.get("type", RollbackManager.SnapshotType.SCRIPTED)
		if snapshot_type != RollbackManager.SnapshotType.AI_CONVERSATION_START and snapshot_type != RollbackManager.SnapshotType.AI_EXCHANGE:
			continue
		var ai_data: Dictionary = snapshot.get("ai_data", {})
		if bool(ai_data.get("is_scene_generated", false)) and owns_rollback_snapshot(ai_data):
			RollbackManager.discard_snapshots_from(i)
			return





const STORY_SLOT: = "{{history}}"



func _custom_system_prompt() -> String:
	return _custom_system_prompt_override.replace(STORY_SLOT, _prompt_story())



func _moves_story() -> bool:
	return APIConfigManager != null and AssistantPrefill.moves_story(APIConfigManager.get_config(), _prefill_scope)




func _prompt_story() -> String:
	return AssistantPrefill.MOVED_STORY_NOTE if _moves_story() else _story_context


func _send_scene_request() -> void :
	var moved_story: = _story_context if _moves_story() else ""
	if APIConfigManager != null and APIConfigManager.is_prompt_cache_enabled():
		var prefix_messages: Array = []
		if AIStateCoordinator != null and AIStateCoordinator.is_active() and moved_story.is_empty():
			prefix_messages = AIStateCoordinator.get_prompt_cache_story_messages(false)
		var session_prompt: = _prompt_manager.build_interactive_cache_session_prompt(
			PromptManager.CACHE_OPERATION_SCENE
		)
		var runtime_context: = _build_scene_cache_runtime_context()
		var live_contract_override: = str(session_prompt.get("runtime_override", "")).strip_edges()
		if not live_contract_override.is_empty():
			runtime_context = "%s\n\n%s" % [runtime_context.strip_edges(), live_contract_override]
		_ai_client.ask(
			str(session_prompt.get("system", "")), 
			"Generate the opening scene now.", 
			prefix_messages, 
			-1.0, 
			false, 
			false, 
			AIConversationClient.INTERACTIVE_CACHE_FAMILY, 
			runtime_context, 
			_prefill_scope, 
			moved_story
		)
		return


	var scene_prompts: = _build_budgeted_scene_request_prompts()
	_ai_client.ask(
		str(scene_prompts.get("system", "")), 
		str(scene_prompts.get("user", "")), 
		[], 
		-1.0, 
		false, 
		false, 
		"scene", 
		"", 
		_prefill_scope, 
		moved_story
	)


func _restore_scene_start_location_for_retry() -> void :
	if _scene_start_location_id.is_empty():
		return
	if not MapManager.has_method("restore_conversation_location"):
		return
	if not MapManager.restore_conversation_location(_scene_start_location_id, 0.35, true):
		push_warning("[AISceneGenerator] Failed to restore scene start location before retry: %s" % _scene_start_location_id)



func accept_scene() -> void :
	_hide_control_panel()
	_is_playing = false
	_reset_speaker_focus()



	if RollbackManager.is_in_rollback_mode():
		var ai_data: = RollbackManager.get_current_ai_data()
		if not ai_data.is_empty() and ai_data.get("is_scene_generated", false):
			var snapshot_lines: Array = ai_data.get("displayed_lines", [])
			if not snapshot_lines.is_empty():
				Log.d("AISceneGenerator", "Restoring displayed_lines from rollback snapshot (%d lines)" % snapshot_lines.size())
				_displayed_lines = snapshot_lines.duplicate(true)


			var history_length: = RollbackManager.get_visible_dialogic_history_size(ai_data)
			if history_length >= 0 and Dialogic.has_subsystem("History"):
				var current_history_size: int = Dialogic.History.simple_history_content.size()
				if current_history_size > history_length:
					Log.d("AISceneGenerator", "Truncating Dialogic history from %d to %d entries" % [current_history_size, history_length])
					Dialogic.History.simple_history_content.resize(history_length)

		Log.d("AISceneGenerator", "Exiting rollback mode before scene completion")
		RollbackManager.exit_rollback_mode()

	scene_playback_completed.emit()



func interrupt_playback() -> void :
	if _ai_client != null and _ai_client.is_requesting():
		_replace_ai_client()
	_session_id += 1
	_request_session_id = -1
	_interrupt_requested = true
	_cancel_advance_wait = true
	_is_waiting_for_advance = false
	_is_displaying_line = false
	_show_edit_button = false
	_hide_edit_button()
	_edit_enabled = false
	_is_playing = false
	_scene_queue.clear()
	_reset_speaker_focus()
	_stop_thinking_animation()
	_cleanup()
	scene_interrupted.emit()


func _create_ai_client() -> void :
	_ai_client = AIConversationClient.new()
	add_child(_ai_client)
	_ai_client.response_received.connect(_on_ai_response_received)
	_ai_client.request_failed.connect(_on_ai_request_failed)


func _replace_ai_client() -> void :
	var previous: = _ai_client
	if previous != null:
		previous.cancel_request()
		if previous.response_received.is_connected(_on_ai_response_received):
			previous.response_received.disconnect(_on_ai_response_received)
		if previous.request_failed.is_connected(_on_ai_request_failed):
			previous.request_failed.disconnect(_on_ai_request_failed)
		previous.queue_free()
	_create_ai_client()



func is_playing() -> bool:
	return _is_playing




func is_request_in_flight() -> bool:
	return _ai_client != null and _ai_client.is_requesting()


func _build_scene_request_prompts() -> Dictionary:
	var use_cache_layout: = (
		APIConfigManager != null
		and APIConfigManager.is_prompt_cache_enabled()
		and _custom_system_prompt_override.is_empty()
		and _custom_user_prompt_override.is_empty()
	)
	return {
		"system": _custom_system_prompt() if not _custom_system_prompt_override.is_empty() else _build_scene_system_prompt(use_cache_layout), 
		"user": _custom_user_prompt_override if not _custom_user_prompt_override.is_empty() else _build_scene_user_prompt(use_cache_layout), 
	}


func _build_scene_request_prompts_with_context(story_context: String) -> Dictionary:
	var original_context: = _story_context
	_story_context = story_context
	var prompts: = _build_scene_request_prompts()
	_story_context = original_context
	return prompts


func _build_budgeted_scene_request_prompts() -> Dictionary:
	var prompts: = _build_scene_request_prompts()
	if not _scene_prompts_exceed_budget(prompts):
		return prompts

	if _story_context.strip_edges().is_empty():
		return prompts

	var trimmed_context: = _trim_story_context_for_scene_budget(_story_context)
	if trimmed_context == _story_context:
		return prompts

	var trimmed_prompts: = _build_scene_request_prompts_with_context(trimmed_context)
	if APIConfigManager != null and APIConfigManager.is_debug_enabled():
		print("[AISceneGenerator] Trimmed scene story context from %d to %d chars to preserve scene setup." % [
			_story_context.length(), 
			trimmed_context.length(), 
		])
	return trimmed_prompts


func _scene_prompts_exceed_budget(prompts: Dictionary) -> bool:
	var input_budget: = _get_scene_input_token_budget()
	if input_budget <= 0:
		return false
	return _estimate_scene_prompt_tokens(prompts) > input_budget


func _get_scene_input_token_budget() -> int:
	if APIConfigManager == null:
		return -1
	var context_size: = int(APIConfigManager.get_context_size())
	if context_size <= 0:
		return -1
	var response_budget: = int(APIConfigManager.get_max_response_tokens())
	var prefix: = str(AssistantPrefill.for_request(APIConfigManager.get_config(), _prefill_scope)["text"])
	var prefix_tokens: = AIDialogueShared.estimate_text_tokens(prefix) + AIDialogueShared.MESSAGE_OVERHEAD_TOKENS if not prefix.is_empty() else 0
	return maxi(1, context_size - response_budget - AIDialogueShared.CONTEXT_OVERHEAD_TOKENS - prefix_tokens)


func _estimate_scene_prompt_tokens(prompts: Dictionary) -> int:
	return _estimate_scene_prompt_tokens_for_lengths(
		str(prompts.get("system", "")).length(), 
		str(prompts.get("user", "")).length()
	)


func _estimate_scene_prompt_tokens_for_lengths(system_len: int, user_len: int) -> int:
	return ceili(system_len / AIDialogueShared.APPROX_CHARS_PER_TOKEN)\
	+ ceili(user_len / AIDialogueShared.APPROX_CHARS_PER_TOKEN)\
	+ AIDialogueShared.MESSAGE_OVERHEAD_TOKENS * 2


func _trim_story_context_for_scene_budget(story_context: String) -> String:
	var normalized: = story_context.strip_edges()
	if normalized.is_empty():
		return ""






	var candidate: = normalized
	var lines: = candidate.split("\n")
	while lines.size() > 1:
		var drop_count: = maxi(1, int(lines.size() / 10.0))
		lines = lines.slice(drop_count)
		candidate = "\n".join(lines).strip_edges()
		if candidate.is_empty():
			break
		if not _scene_prompts_exceed_budget(_build_scene_request_prompts_with_context(candidate)):
			return candidate

	var max_chars: = candidate.length()
	while max_chars > 0:
		max_chars = int(floor(float(max_chars) * 0.8))
		if max_chars <= 0:
			break
		candidate = normalized.substr(maxi(0, normalized.length() - max_chars), max_chars).strip_edges()
		if candidate.is_empty():
			break
		if not _scene_prompts_exceed_budget(_build_scene_request_prompts_with_context(candidate)):
			return candidate

	if not _scene_prompts_exceed_budget(_build_scene_request_prompts_with_context("")):
		return ""
	return normalized





func _build_scene_cache_runtime_context() -> String:
	var sections: Array[String] = [
		"## Selected Operation\nOpening Scene", 
		"## Story Context Source\n" + (AssistantPrefill.MOVED_STORY_NOTE if _moves_story() else "Use the trusted story-context messages before this request."), 
	]
	var character_lines: Array[String] = []
	var character_names: Array[String] = []
	for char_data in _character_data:
		character_lines.append(char_data.format_for_prompt())
		character_names.append(char_data.name)
	_append_scene_cache_runtime_section(sections, "Characters In This Scene", "\n".join(character_lines))
	_append_scene_cache_runtime_section(sections, "Runtime Character Guidance", _build_scene_character_runtime_note())
	_append_scene_cache_runtime_section(sections, "Player Persona", _build_persona_context_content())
	_append_scene_cache_runtime_section(
		sections, 
		"Scenario Lore", 
		ScenarioPromptLoader.load_active_rules_block("scene")
	)

	var location_name: = _current_location.display_name if _current_location != null else "Ponyville"
	var location_desc: = (
		LocationDescriptionStorage.get_effective_description(_current_location)
		if _current_location != null
		else ""
	)
	var has_twilight: = false
	for char_data in _character_data:
		if char_data.tag == "twi":
			has_twilight = true
			break
	var intro_line: = "the player visits %s at %s." % [" and ".join(character_names), location_name]
	if _is_story_mode_twilight_guided_visit(has_twilight, character_names.size()):
		var other_names: Array[String] = []
		for char_data in _character_data:
			if char_data.tag != "twi":
				other_names.append(char_data.name)
		intro_line = "Twilight Sparkle brings the player (a visitor from another world who woke up in the Everfree Forest) to meet %s at %s." % [
			" and ".join(other_names), 
			location_name, 
		]
	var request_lines: Array[String] = [
		"Arrival: " + intro_line, 
		"Location: " + location_name, 
		"Characters present: " + " and ".join(character_names), 
	]
	_append_scene_cache_runtime_section(sections, "Scene Request Values", "\n".join(request_lines))
	_append_scene_cache_runtime_section(sections, "Location Context", location_desc)
	_append_scene_cache_runtime_section(sections, "Calendar Context", _build_calendar_context_content())
	_append_scene_cache_runtime_section(sections, "Scene Brief", _custom_scene_brief)
	_append_scene_cache_runtime_section(sections, "Lorebook Context", _build_lorebook_context_content("scene"))
	if _should_add_story_mode_visit_notice(has_twilight, character_names.size()):
		_append_scene_cache_runtime_section(sections, "Story Visit Note", _build_story_mode_visit_notice())
	_append_scene_cache_runtime_section(
		sections, 
		"Custom Scene System Override (Supersedes Conflicting Opening Scene Contract Text)", 
		_custom_system_prompt()
	)
	_append_scene_cache_runtime_section(
		sections, 
		"Custom Scene Request Override (Supersedes Conflicting Opening Scene Request Text)", 
		_custom_user_prompt_override
	)
	return "\n\n".join(sections)


func _append_scene_cache_runtime_section(sections: Array[String], title: String, content: String) -> void :
	var normalized: = content.strip_edges()
	if normalized.is_empty():
		return
	sections.append("## %s\n%s" % [title, normalized])



func _build_scene_system_prompt(cache_friendly: bool = false) -> String:
	var char_info: = ""
	for char_data in _character_data:
		char_info += char_data.format_for_prompt() + "\n"

	var template: = PromptConfigManager.get_scene_system_prompt_template()
	var scenario_lore: = ScenarioPromptLoader.load_active_rules_block("scene")
	var lorebook_context: = _build_lorebook_context_content("scene")
	var system_history: = CACHE_SCENE_RUNTIME_REFERENCE if cache_friendly else _prompt_story()
	var system_lorebook_context: = CACHE_SCENE_RUNTIME_REFERENCE if cache_friendly else lorebook_context
	var prompt: = PromptConfigManager.apply_template(template, {
			"characters": char_info.strip_edges(), 
			"history": system_history, 
			"scene_runtime_guidance": _build_scene_character_runtime_note(), 
			"persona_context": _build_persona_context_content(), 
			"scenario_lore": scenario_lore, 
			"lorebook_context": system_lorebook_context, 
		})
	prompt = _append_optional_scene_section_if_placeholder_missing(
		prompt, 
		template, 
		"scene_runtime_guidance", 
		"Runtime Character Continuity", 
		_build_scene_character_runtime_note()
	)
	prompt = _append_optional_scene_section_if_placeholder_missing(
		prompt, 
		template, 
		"persona_context", 
		"Player Persona", 
		_build_persona_context_content()
	)
	if not scenario_lore.is_empty():
		prompt = _append_optional_scene_section_if_placeholder_missing(
			prompt, 
			template, 
			"scenario_lore", 
			"Scenario Lore", 
			scenario_lore
		)
	if not lorebook_context.is_empty():
		prompt = _append_optional_scene_section_if_placeholder_missing(
			prompt, 
			template, 
			"lorebook_context", 
			"Lorebook Context", 
			system_lorebook_context
		)
	return prompt


func _build_scene_character_runtime_note() -> String:
	var lines: Array[String] = []
	if _is_dynamic_character_mode_enabled():
		lines.append("Dynamic character management is ENABLED for this scene.")
		lines.append("- If a character leaves physically, emit [character_exit: TAG] on its own line before describing them as gone.")
		lines.append("- If they return later, emit [character_enter: TAG] before their next [sprite: TAG emotion] or TAG \"...\" line.")
		lines.append("- Use [character_step_aside: TAG] for temporary off-screen presence.")
		lines.append("- Never narrate arrivals/departures without the matching command.")
		lines.append("- Keep tags limited to the characters in this scene.")
	else:
		lines.append("Character roster changes are DISABLED for this scene.")
		lines.append("- Do not narrate any character leaving, arriving, or stepping aside.")
		lines.append("- Keep all listed characters physically present for the entire scene.")
	return "\n".join(lines)


func _build_persona_context_content() -> String:
	if PersonaManager == null or not PersonaManager.has_method("get_active_persona_text"):
		return ""
	var persona_text: = str(PersonaManager.get_active_persona_text()).strip_edges()
	return persona_text


func _build_lorebook_context_content(applies_to: String) -> String:
	if LorebookManager == null or not LorebookManager.has_method("build_lore_block"):
		return ""
	var active_tags: Array[String] = []
	for char_data in _character_data:
		if char_data == null:
			continue
		var tag: = char_data.tag.strip_edges().to_lower()
		if tag.is_empty() or tag in active_tags:
			continue
		active_tags.append(tag)

	var location_id: = ""
	var region_id: = ""
	var location_desc: = ""
	if _current_location != null:
		location_id = _current_location.id
		region_id = _current_location.region
		location_desc = LocationDescriptionStorage.get_effective_description(_current_location)
	if region_id.strip_edges().is_empty() and GameState != null:
		region_id = str(GameState.current_region)

	var game_mode: = ""
	if GameState != null:
		game_mode = "sandbox" if GameState.current_mode == GameState.Mode.SANDBOX else "story"

	return str(LorebookManager.build_lore_block(applies_to, {
		"active_character_tags": active_tags, 
		"location_id": location_id, 
		"region_id": region_id, 
		"game_mode": game_mode, 
		"scenario_id": ScenarioManager.get_active_scenario_id() if ScenarioManager != null else "", 
		"scene_brief": _custom_scene_brief, 
		"location_desc": location_desc, 
		"match_text": _custom_scene_brief, 
		"story_context": _story_context, 
	})).strip_edges()


func _build_calendar_context_content() -> String:
	if CalendarManager == null or not CalendarManager.has_method("get_ai_context_string"):
		return ""
	var calendar_context: = str(CalendarManager.get_ai_context_string()).strip_edges()
	var time_of_day: = ""
	if GameState != null and GameState.has_method("get_time_slot_name"):
		time_of_day = str(GameState.get_time_slot_name()).strip_edges()
	if calendar_context.is_empty() and time_of_day.is_empty():
		return ""
	var lines: Array[String] = []
	if not calendar_context.is_empty():
		lines.append(calendar_context)
	if not time_of_day.is_empty():
		lines.append("Current Time of Day: %s" % time_of_day)
	return "\n".join(lines)


func _append_optional_scene_section_if_placeholder_missing(
	prompt: String, 
	template: String, 
	placeholder: String, 
	title: String, 
	content: String
) -> String:
	if content.strip_edges().is_empty():
		return prompt
	if template.find("{{%s}}" % placeholder) != -1:
		return prompt
	return (prompt + "\n\n## %s\n%s" % [title, content]).strip_edges()


func _should_add_story_mode_visit_notice(has_twilight: bool, character_count: int) -> bool:
	return _is_story_mode_twilight_guided_visit(has_twilight, character_count)


func _is_story_mode_twilight_guided_visit(has_twilight: bool, character_count: int) -> bool:
	return GameState.current_mode == GameState.Mode.STORY and has_twilight and character_count > 1


func _build_story_mode_visit_notice() -> String:
	return "Twilight's friend was not warned in advance about this visit by letter or any other message."



func _build_scene_user_prompt(cache_friendly: bool = false) -> String:
	var location_name: = _current_location.display_name if _current_location else "Ponyville"
	var location_desc: = ""


	if _current_location:
		location_desc = LocationDescriptionStorage.get_effective_description(_current_location)


	var char_names: Array[String] = []
	for char_data in _character_data:
		char_names.append(char_data.name)
	var char_names_str: = " and ".join(char_names)


	var has_twilight: = false
	for char_data in _character_data:
		if char_data.tag == "twi":
			has_twilight = true
			break

	var intro_line: = ""

	if _is_story_mode_twilight_guided_visit(has_twilight, char_names.size()):

		var other_chars: Array[String] = []
		for char_data in _character_data:
			if char_data.tag != "twi":
				other_chars.append(char_data.name)
		intro_line = "Twilight Sparkle brings the player (a visitor from another world who woke up in the Everfree Forest) to meet %s at %s." % [" and ".join(other_chars), location_name]
	else:
		intro_line = "the player visits %s at %s." % [char_names_str, location_name]

	var template: = PromptConfigManager.get_scene_user_prompt_template()
	var replacements: = {
		"intro_line": intro_line, 
		"location_name": location_name, 
		"location_desc": location_desc, 
		"character_names": char_names_str, 
		"history": CACHE_SCENE_RUNTIME_REFERENCE if cache_friendly else _prompt_story(), 
		"scene_brief": _custom_scene_brief.strip_edges(), 
		"calendar_context": _build_calendar_context_content(), 
	}
	var lorebook_context: = ""
	if cache_friendly:
		lorebook_context = _build_lorebook_context_content("scene")
		replacements["lorebook_context"] = lorebook_context
	var prompt: = PromptConfigManager.apply_template(template, replacements)
	prompt = _append_optional_scene_section_if_placeholder_missing(
		prompt, 
		template, 
		"location_desc", 
		"Location Context", 
		location_desc
	)
	prompt = _append_optional_scene_section_if_placeholder_missing(
		prompt, 
		template, 
		"calendar_context", 
		"Calendar Context", 
		_build_calendar_context_content()
	)
	if cache_friendly:
		prompt = _append_optional_scene_section_if_placeholder_missing(
			prompt, 
			template, 
			"history", 
			"Story So Far", 
			CACHE_SCENE_RUNTIME_REFERENCE
		)
		prompt = _append_optional_scene_section_if_placeholder_missing(
			prompt, 
			template, 
			"lorebook_context", 
			"Lorebook Context", 
			lorebook_context
		)
	if _should_add_story_mode_visit_notice(has_twilight, char_names.size()):
		prompt = (prompt + "\n\n## Story Visit Note\n" + _build_story_mode_visit_notice()).strip_edges()
	return prompt



func _on_ai_response_received(response: String) -> void :


	if _request_session_id != _session_id:
		return
	_stop_thinking_animation()

	var lines: = _line_processor.parse_response(response)
	var valid_lines: = _line_processor.filter_valid_lines(lines, _management_context_override)
	var dropped_validation_errors: = _line_processor.get_last_validation_errors()
	var unknown_lines: = _line_processor.get_last_unknown_lines()

	if APIConfigManager.is_debug_enabled():
		print("[AISceneGenerator] Received %d valid lines" % valid_lines.size())
		_line_processor.debug_print_lines(valid_lines)
		for raw in unknown_lines:
			print("[AISceneGenerator] Unknown line: " + raw)
		for err in dropped_validation_errors:
			print("[AISceneGenerator] Dropped line: " + err)

	if valid_lines.is_empty():
		var parse_parts: Array[String] = []
		var unknown_summary: = _summarize_unknown_lines(unknown_lines)
		if not unknown_summary.is_empty():
			parse_parts.append(unknown_summary)
		if not dropped_validation_errors.is_empty():
			parse_parts.append(tr("%d validation drop(s)") % dropped_validation_errors.size())
		var parse_suffix: = ""
		if not parse_parts.is_empty():
			parse_suffix = " (%s)" % " | ".join(parse_parts)
		scene_generation_failed.emit(tr("No valid lines in AI response%s") % parse_suffix)
		return


	for line in valid_lines:
		match line.type:
			DialogueLineProcessor.LineType.SPRITE:
				_scene_queue.append({
					"type": "sprite", 
					"tag": line.tag, 
					"emotion": line.content
				})
			DialogueLineProcessor.LineType.LOCATION:
				_scene_queue.append({
					"type": "command", 
					"command": "location", 
					"location_id": line.content
				})
			DialogueLineProcessor.LineType.CHARACTER_ENTER:
				_scene_queue.append({
					"type": "command", 
					"command": "character_enter", 
					"tag": line.tag
				})
			DialogueLineProcessor.LineType.CHARACTER_EXIT:
				_scene_queue.append({
					"type": "command", 
					"command": "character_exit", 
					"tag": line.tag
				})
			DialogueLineProcessor.LineType.CHARACTER_STEP_ASIDE:
				_scene_queue.append({
					"type": "command", 
					"command": "character_step_aside", 
					"tag": line.tag
				})
			DialogueLineProcessor.LineType.NARRATOR:
				_scene_queue.append({
					"type": "dialogue", 
					"speaker": "narrator", 
					"text": line.content, 
					"is_narrator": true
				})
			DialogueLineProcessor.LineType.DIALOGUE:
				_scene_queue.append({
					"type": "dialogue", 
					"speaker": line.tag, 
					"text": line.content, 
					"is_narrator": false
				})



	var voice_mod: Node = preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree())
	voice_mod.prefetch_response(_scene_queue)

	var char_tags: Array[String] = []
	for char_data in _character_data:
		char_tags.append(char_data.tag)
	var scene_start_history_size: = -1
	if Dialogic.has_subsystem("History"):
		scene_start_history_size = Dialogic.History.simple_history_content.size()
	RollbackManager.register_ai_conversation_start(self, char_tags, {
		"sprite_states": _sprite_states.duplicate(true), 
		"joined_characters": _joined_characters.duplicate(true), 
		"joined_character_order": _joined_character_order.duplicate(), 
		"rotated_out_tags": _rotated_out_tags.duplicate(), 
		"stage_recency": _stage_recency.duplicate(), 
		"remaining_queue": _scene_queue.duplicate(true), 
		"displayed_lines": [], 
		"story_context": _story_context, 
		"management_context_override": _management_context_override.duplicate(true), 
		"prefill_scope": _prefill_scope, 
		"location_id": _get_current_runtime_location_id_for_save(), 
		"scene_start_location_id": _scene_start_location_id, 
		"is_scene_generated": true, 
		"dialogic_history_length": scene_start_history_size, 
		"scene_start_dialogic_history_length": scene_start_history_size, 
		"music_state": _get_current_music_state_for_rollback(), 
		"time_slot": GameState.current_time_slot, 
		"daily_visits": GameState.daily_visits, 
		"pass_time_state": GameState.capture_pass_time_rollback_state(), 
	})


	_is_playing = true
	_show_interrupt_button()


	MapManager.show_ui_after_loading()

	_play_next_line()



func _on_ai_request_failed(error: String) -> void :
	if _request_session_id != _session_id:
		return
	_stop_thinking_animation()
	push_error("[AISceneGenerator] AI request failed: " + error)
	scene_generation_failed.emit(error)


func _mark_dialogic_history_start_for_retry() -> void :
	if not Dialogic.has_subsystem("History"):
		_initial_dialogic_history_length = -1
		return
	_initial_dialogic_history_length = Dialogic.History.simple_history_content.size()
	Log.d("AISceneGenerator", "Initial Dialogic history length: %d" % _initial_dialogic_history_length)


func _summarize_unknown_lines(lines: Array[String]) -> String:
	if lines.is_empty():
		return ""

	var preview: Array[String] = []
	for i in range(mini(2, lines.size())):
		var sample: = str(lines[i]).strip_edges()
		if sample.length() > 60:
			sample = sample.substr(0, 60) + "..."
		preview.append(sample)

	var label: = tr("%d bad-format line(s)") % lines.size()
	if preview.is_empty():
		return label
	return "%s: %s" % [label, " / ".join(preview)]









func _play_next_line(my_session_id: int = -1) -> void :
	preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree()).stop()

	if my_session_id == -1:
		my_session_id = _session_id

	Log.d("AISceneGenerator", "_play_next_line called - session=%d, queue_size=%d, _is_playing=%s" % [my_session_id, _scene_queue.size(), _is_playing])


	if my_session_id != _session_id:
		Log.d("AISceneGenerator", "Stale coroutine detected (session %d != %d), stopping" % [my_session_id, _session_id])
		return


	if not _is_playing:
		_is_displaying_line = false
		_show_edit_button = true
		_edit_enabled = false
		Log.d("AISceneGenerator", "_play_next_line EXIT: _is_playing=false")
		return


	if _interrupt_requested:
		_is_displaying_line = false
		_show_edit_button = false
		Log.d("AISceneGenerator", "_play_next_line EXIT: _interrupt_requested=true")
		_interrupt_requested = false
		_scene_queue.clear()
		_hide_interrupt_button()
		_show_control_panel()
		return

	if _scene_queue.is_empty():

		_is_displaying_line = false
		_show_edit_button = false
		Log.d("AISceneGenerator", "_play_next_line: queue empty, showing control panel")
		_show_control_panel()
		return

	var response_voice: Node = preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree())
	var response_valid := func(): return my_session_id == _session_id and _is_playing and not RollbackManager.is_in_rollback_mode() and not _interrupt_requested
	if not await response_voice.prepare_response(_scene_queue.duplicate(true), response_valid):
		_is_displaying_line = false
		if my_session_id == _session_id and _interrupt_requested:
			_interrupt_requested = false
			_scene_queue.clear()
			_hide_interrupt_button()
			_show_control_panel()
		return
	var entry: Dictionary = _scene_queue.pop_front()


	if entry.get("type") == "sprite":
		_is_displaying_line = false
		_show_edit_button = false
		await _handle_sprite_change(entry["tag"], entry["emotion"])
		_play_next_line(my_session_id)
		return


	if entry.get("type") == "command":
		var command: = str(entry.get("command", ""))
		if command == "location":
			var target_location_id: = str(entry.get("location_id", "")).strip_edges()
			if not target_location_id.is_empty():
				if MapManager.try_change_conversation_location(target_location_id, 0.45, true):
					_sync_current_location_from_runtime_location(target_location_id)
		elif command == "character_enter":
			await _handle_runtime_character_enter(str(entry.get("tag", "")))
		elif command == "character_exit":
			await _handle_runtime_character_exit(str(entry.get("tag", "")))
		elif command == "character_step_aside":
			await _handle_runtime_character_step_aside(str(entry.get("tag", "")))
		_displayed_lines.append(entry)
		_play_next_line(my_session_id)
		return

	var speaker: String = entry["speaker"]
	var normalized_speaker: = _normalize_speaker_tag(speaker)
	var text: String = entry["text"]
	var is_narrator: bool = entry["is_narrator"]
	entry.merge(preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree()).history_metadata("narrator" if is_narrator else speaker, text), true)


	if not is_narrator and normalized_speaker in _rotated_out_tags:
		await _handle_sprite_change(normalized_speaker, str(_sprite_states.get(normalized_speaker, "neutral")))
		if my_session_id != _session_id:
			return
	elif not is_narrator:
		_note_stage_activity(normalized_speaker)


	_displayed_lines.append(entry)
	_is_displaying_line = true
	_current_displayed_text = text
	_show_edit_button = true
	_edit_enabled = false
	_show_edit_button_panel()


	var dialogic_char: DialogicCharacter = null
	var char_name: String = normalized_speaker if not normalized_speaker.is_empty() else speaker
	var char_id: String = ""
	if not is_narrator:
		dialogic_char = _get_dialogic_character_for_speaker(speaker)
		if dialogic_char:
			char_name = dialogic_char.display_name
			char_id = dialogic_char.resource_path

			if char_id.is_empty():
				char_id = dialogic_char.get_identifier()
	elif is_narrator:
		dialogic_char = DialogicResourceUtil.get_character_resource("narrator")
		char_name = "Narrator"
		if dialogic_char:
			char_id = dialogic_char.resource_path


	_register_scene_line_with_rollback(char_name, char_id, text, is_narrator)


	var raw_history_index: = AIDialogueShared.store_dialogic_history_entry(text, dialogic_char, is_narrator)
	AIDialogueShared.tag_last_displayed_dialogue_history_index(_displayed_lines, raw_history_index)
	_tag_last_scene_snapshot_history_index(raw_history_index)


	if Dialogic.Text:
		Dialogic.Text.update_name_label(dialogic_char)


	_update_active_portrait_for_line(dialogic_char, normalized_speaker, is_narrator)
	_apply_speaker_focus_for_line(normalized_speaker, is_narrator)


	if Dialogic.Text:
		var typing_portrait: String = ""
		if not is_narrator:
			typing_portrait = str(_sprite_states.get(normalized_speaker, "neutral"))
		CharacterSpriteLoader.call("apply_typing_sound_for_dialogic_character", dialogic_char, typing_portrait)
		var voice_controller: Node = preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree())
		AIDialogueShared.maybe_resume_dialogic_if_safe(self, _is_editing)
		var voice_valid := func(): return my_session_id == _session_id and _is_playing and not RollbackManager.is_in_rollback_mode()
		if not await voice_controller.prepare_line("narrator" if is_narrator else speaker, Dialogic.Text.parse_text(text, 0), voice_valid):
			return
		await Dialogic.Text.update_textbox(text, false)


		if my_session_id != _session_id or not _is_playing:
			return

		var voice_text: String = Dialogic.Text.update_dialog_text(text)
		voice_controller.speak("narrator" if is_narrator else speaker, Dialogic.Text.parse_text(text, 0))

		await Dialogic.Text.text_finished


		if my_session_id != _session_id or not _is_playing:
			return

		if _interrupt_requested:
			_interrupt_requested = false
			_scene_queue.clear()
			_hide_interrupt_button()
			_hide_edit_button()
			_show_control_panel()
			return

		Dialogic.Text.show_next_indicators()
		_edit_enabled = true
		_show_edit_button_panel()


		Dialogic.current_state = Dialogic.States.IDLE
		await _wait_for_advance()
		_is_displaying_line = false
		_show_edit_button = false


		if my_session_id != _session_id or not _is_playing:
			Log.d("AISceneGenerator", "After wait: session/playing check failed, stopping")
			Dialogic.Text.hide_next_indicators()
			return


		if RollbackManager.is_in_rollback_mode():
			Log.d("AISceneGenerator", "After wait: in rollback mode, stopping playback")
			Dialogic.Text.hide_next_indicators()
			return

		Dialogic.Text.hide_next_indicators()
		_edit_enabled = false


	_play_next_line(my_session_id)


func _update_active_portrait_for_line(dialogic_char: DialogicCharacter, speaker: String, is_narrator: bool) -> void :
	if dialogic_char == null or is_narrator:
		return
	if not Dialogic.Portraits.is_character_joined(dialogic_char):
		return

	var portrait: String = _sprite_states.get(speaker, "neutral")
	if not dialogic_char.portraits.has(portrait):
		return
	if AIDialogueShared.is_portrait_current(dialogic_char, portrait):
		return

	Dialogic.Portraits.change_character_portrait(dialogic_char, portrait)

	_apply_group_scale_deferred(dialogic_char, portrait)

	_apply_group_scale_deferred.call_deferred(dialogic_char, portrait)



func _wait_for_advance() -> void :
	Log.d("AISceneGenerator", "_wait_for_advance START - Dialogic.current_state=%s, IDLE=%s" % [Dialogic.current_state, Dialogic.States.IDLE])


	var request := {"ready": false, "mouse": false}
	var advance_input: Node = Dialogic.Inputs
	var on_advance := func():
		if not Dialogic.paused and not _is_editing and not AIDialogueShared.is_ui_blocking_input(self):
			request.ready = true
			request.mouse = bool(advance_input.input_was_mouse_input)
	advance_input.dialogic_action.connect(on_advance)
	AIDialogueShared.consume_touch_advance_request()
	_is_waiting_for_advance = true
	var cancelled := false
	var frame_count: = 0
	while Dialogic.current_state == Dialogic.States.IDLE:
		frame_count += 1


		if not _is_playing:
			Log.d("AISceneGenerator", "_wait_for_advance EXIT: _is_playing=false")
			_is_waiting_for_advance = false
			cancelled = true
			break


		if _cancel_advance_wait:
			Log.d("AISceneGenerator", "_wait_for_advance EXIT: _cancel_advance_wait=true")
			_cancel_advance_wait = false
			_is_waiting_for_advance = false
			cancelled = true
			break

		if _interrupt_requested:
			Log.d("AISceneGenerator", "_wait_for_advance BREAK: _interrupt_requested=true")
			break


		if RollbackManager.is_in_rollback_mode():
			if frame_count % 60 == 1:
				Log.d("AISceneGenerator", "_wait_for_advance: in rollback mode, waiting...")
			await get_tree().process_frame
			continue


		if Dialogic.paused or _is_editing:
			AIDialogueShared.maybe_resume_dialogic_if_safe(self, _is_editing)
			await get_tree().process_frame
			continue

		if AIDialogueShared.is_dialogic_input_blocked():
			await get_tree().process_frame
			continue


		if AIDialogueShared.is_ui_blocking_input(self):
			if APIConfigManager.is_debug_enabled() and frame_count % 60 == 1:
				print("[AISceneGenerator] _wait_for_advance: UI overlay open, blocking input")
			await get_tree().process_frame
			continue




		if _edit_just_closed:
			_edit_just_closed = false
			await _drain_resumed_history_advance_input()
			continue
		if bool(request.ready) and not bool(request.mouse):
			break
		if Input.is_action_just_pressed("ui_accept"):
			break
		if Input.is_action_just_pressed("dialogic_default_action") and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			break



		var is_hovering_ui: = false
		if _interrupt_panel and _interrupt_panel.visible:
			if _interrupt_panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
				is_hovering_ui = true
		if _control_panel and _control_panel.visible:
			if _control_panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
				is_hovering_ui = true
		if _edit_panel and _edit_panel.visible:
			if _edit_panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
				is_hovering_ui = true


		if not is_hovering_ui:
			is_hovering_ui = AIDialogueShared.is_hovering_music_switcher(self)


		if not is_hovering_ui:
			is_hovering_ui = AIDialogueShared.is_hovering_dialogue_scrollbar(self)


		if not is_hovering_ui:

			if bool(request.ready):
				break

			if TouchScrollGesture.is_touch_platform():
				if AIDialogueShared.consume_touch_advance_request():
					Log.d("AISceneGenerator", "_wait_for_advance BREAK: touch tap advance")
					break
			# Mouse releases arrive through dialogic_action after drag validation.
			if Input.is_action_just_pressed("ui_accept"):
				Log.d("AISceneGenerator", "_wait_for_advance BREAK: ui_accept pressed")
				break
		await get_tree().process_frame

	Log.d("AISceneGenerator", "_wait_for_advance END - exited loop after %d frames, Dialogic.current_state=%s" % [frame_count, Dialogic.current_state])
	if advance_input.dialogic_action.is_connected(on_advance):
		advance_input.dialogic_action.disconnect(on_advance)
	_is_waiting_for_advance = false
	if cancelled:
		return
	await get_tree().create_timer(0.1).timeout


func _wait_on_restored_history_line_before_continue() -> bool:
	Log.d(
		"AISceneGenerator", 
		"Waiting on restored history line before continuing (text_len=%d, queue=%d)" % [
			_current_displayed_text.length(), 
			_scene_queue.size(), 
		]
	)

	if Dialogic.Text:
		Dialogic.Text.show_next_indicators()

	_edit_enabled = not _current_displayed_text.is_empty()
	_show_edit_button = _edit_enabled
	_show_edit_button_panel()
	Dialogic.current_state = Dialogic.States.IDLE

	await _drain_resumed_history_advance_input()

	await _wait_for_advance()

	if not _is_playing:
		Log.d("AISceneGenerator", "Restored-line wait aborted because scene stopped")
		if Dialogic.Text:
			Dialogic.Text.hide_next_indicators()
		_show_edit_button = false
		return false

	if RollbackManager.is_in_rollback_mode():
		Log.d("AISceneGenerator", "Restored-line wait aborted because rollback resumed")
		if Dialogic.Text:
			Dialogic.Text.hide_next_indicators()
		_show_edit_button = false
		return false

	if _interrupt_requested:
		Log.d("AISceneGenerator", "Restored-line wait interrupted; showing control panel")
		_interrupt_requested = false
		_scene_queue.clear()
		_hide_interrupt_button()
		_hide_edit_button()
		_show_control_panel()
		if Dialogic.Text:
			Dialogic.Text.hide_next_indicators()
		_show_edit_button = false
		return false

	if Dialogic.Text:
		Dialogic.Text.hide_next_indicators()
	_edit_enabled = false
	_show_edit_button = false
	return true


func _drain_resumed_history_advance_input() -> void :
	Log.d("AISceneGenerator", "Draining resume input before restored-line wait")



	await get_tree().process_frame

	var frame_count: = 0
	while Input.is_action_pressed("dialogic_default_action") or Input.is_action_pressed("ui_accept"):
		frame_count += 1
		if frame_count % 30 == 1:
			Log.d("AISceneGenerator", "Still draining held advance input (%d frames)" % frame_count)
		await get_tree().process_frame



	await get_tree().process_frame
	Log.d("AISceneGenerator", "Resume input drained after %d frame(s)" % frame_count)



func _handle_sprite_change(tag: String, emotion: String) -> void :
	var final_emotion: = CharacterPortraitService.get_final_emotion(tag, emotion)
	_sprite_states[tag] = final_emotion

	if _dialogic_characters.has(tag):
		var dialogic_char: DialogicCharacter = _dialogic_characters[tag]
		if not _joined_characters.get(tag, false):
			var stage_ready: bool = await _make_room_on_stage(tag)
			if not stage_ready:
				return
		_note_stage_activity(tag)
		var total_chars: = _get_total_visible_for_layout(tag)


		if not _joined_characters.get(tag, false):
			var position_id: = _get_position_for_character(tag)
			var should_mirror: = CharacterPortraitService.should_mirror_at_position(position_id)
			Log.d(
				"AISceneGenerator", 
				"Join request | tag=%s portrait=%s slot=%s mirrored=%s total_chars=%d" % [
					tag, 
					final_emotion, 
					position_id, 
					str(should_mirror), 
					total_chars, 
				]
			)

			var join_node: = await CharacterPortraitService.join_character_safe(
				dialogic_char, final_emotion, position_id, should_mirror, 0, "", "", 0.3, false, total_chars
			)
			var joined: = join_node != null and Dialogic.Portraits.is_character_joined(dialogic_char)
			_joined_characters[tag] = joined
			if joined:
				_remember_joined_character_order(tag)
				_refresh_group_layout(total_chars, true)
			else:
				push_warning("[AISceneGenerator] Failed to join character '%s' with portrait '%s'" % [tag, final_emotion])
		elif Dialogic.Portraits.is_character_joined(dialogic_char):

			if dialogic_char.portraits.has(final_emotion):
				if not AIDialogueShared.is_portrait_current(dialogic_char, final_emotion):
					Log.d(
						"AISceneGenerator", 
						"Portrait change request | tag=%s portrait=%s total_chars=%d current_slot=%s" % [
							tag, 
							final_emotion, 
							total_chars, 
							_get_position_for_character(tag), 
						]
					)
					_prepare_group_layout_before_portrait_change(tag, dialogic_char, total_chars)
					Dialogic.Portraits.change_character_portrait(dialogic_char, final_emotion)

					_apply_group_scale_deferred(dialogic_char, final_emotion)

					_apply_group_scale_deferred.call_deferred(dialogic_char, final_emotion)


func _is_dynamic_character_mode_enabled() -> bool:
	if _has_forced_dynamic_character_mode():
		return true
	return (
		GameState.current_mode == GameState.Mode.SANDBOX
		and APIConfigManager != null
		and APIConfigManager.is_dynamic_character_management_enabled()
	)


func _has_forced_dynamic_character_mode() -> bool:
	return (
		bool(_management_context_override.get("sandbox_mode", false))
		and str(_management_context_override.get("character_mode", "")).to_lower() in [
			AICommandValidator.MODE_DYNAMIC, 
			AICommandValidator.MODE_DYNAMIC_PLUS, 
		]
	)


func _sanitize_management_context_override(context_override: Dictionary) -> Dictionary:
	if context_override.is_empty():
		return {}
	var sanitized: = AICommandValidator.get_runtime_management_context(context_override)
	return {
		"sandbox_mode": bool(sanitized.get("sandbox_mode", false)), 
		"character_mode": str(sanitized.get("character_mode", AICommandValidator.MODE_OFF)), 
		"location_mode": str(sanitized.get("location_mode", AICommandValidator.MODE_OFF)), 
	}


func _handle_runtime_character_enter(tag: String) -> void :
	var normalized: = tag.strip_edges().to_lower()
	if normalized.is_empty():
		return
	if not _is_dynamic_character_mode_enabled():
		return
	if not _ensure_runtime_character_registered(normalized):
		push_warning("[AISceneGenerator] Character enter ignored - unknown tag: %s" % normalized)
		return

	var emotion: = str(_sprite_states.get(normalized, "neutral"))
	await _handle_sprite_change(normalized, emotion)


func _handle_runtime_character_exit(tag: String) -> void :
	var normalized: = tag.strip_edges().to_lower()
	if normalized.is_empty():
		return
	if not _is_dynamic_character_mode_enabled():
		return
	if not _dialogic_characters.has(normalized):
		push_warning("[AISceneGenerator] Character exit ignored - unknown tag: %s" % normalized)
		return

	var dialogic_char: DialogicCharacter = _dialogic_characters[normalized]
	if Dialogic.Portraits.is_character_joined(dialogic_char):
		Dialogic.Portraits.leave_character(dialogic_char, "", 0.22)
		await get_tree().create_timer(0.24).timeout
	_joined_characters[normalized] = false
	_forget_joined_character_order(normalized)
	_rotated_out_tags.erase(normalized)
	_stage_recency.erase(normalized)
	_refresh_group_layout(_get_total_visible_for_layout())


func _handle_runtime_character_step_aside(tag: String) -> void :
	await _handle_runtime_character_exit(tag)


func _is_stage_crowded() -> bool:
	return _character_data.size() > MAX_VISIBLE_LAYOUT_CHARACTERS




func _make_room_on_stage(tag: String) -> bool:
	var on_stage: = _get_ordered_joined_character_tags()
	if on_stage.size() < MAX_VISIBLE_LAYOUT_CHARACTERS:
		return true
	var quiet_tag: = ""
	for recent_tag in _stage_recency:
		if recent_tag != tag and recent_tag in on_stage:
			quiet_tag = recent_tag
			break
	if quiet_tag.is_empty():
		for stage_tag in on_stage:
			if stage_tag != tag:
				quiet_tag = stage_tag
				break
	if quiet_tag.is_empty() or not _dialogic_characters.has(quiet_tag):
		return true

	var session_id: = _session_id
	var vacated_slot: = _joined_character_order.find(quiet_tag)
	var quiet_char: DialogicCharacter = _dialogic_characters[quiet_tag]
	CharacterPortraitService.remove_character_from_group_state(quiet_char)


	var leave_animation: = str(ProjectSettings.get_setting("dialogic/animations/leave_default", "Fade Out Down"))
	if leave_animation.is_empty():
		leave_animation = "__no_animation__"
	Dialogic.Portraits.leave_character(quiet_char, leave_animation, STAGE_ROTATION_FADE, false)
	await get_tree().create_timer(STAGE_ROTATION_FADE + 0.03).timeout
	if session_id != _session_id:
		return false
	if Dialogic.Portraits.is_character_joined(quiet_char):
		Dialogic.Portraits.remove_character(quiet_char)
	_joined_characters[quiet_tag] = false
	_forget_joined_character_order(quiet_tag)
	_stage_recency.erase(quiet_tag)
	if not quiet_tag in _rotated_out_tags:
		_rotated_out_tags.append(quiet_tag)
	_rotated_out_tags.erase(tag)
	_joined_character_order.erase(tag)
	_joined_character_order.insert(clampi(vacated_slot, 0, _joined_character_order.size()), tag)
	return true


func _note_stage_activity(tag: String) -> void :
	_stage_recency.erase(tag)
	_stage_recency.append(tag)





func _restore_stage_rotation(raw_rotated_out: Variant, raw_recency: Variant = []) -> void :
	_rotated_out_tags.clear()
	_stage_recency.clear()
	if raw_rotated_out is Array:
		for raw_tag in raw_rotated_out:
			var tag: = str(raw_tag).strip_edges()
			if not tag.is_empty() and not tag in _rotated_out_tags and not bool(_joined_characters.get(tag, false)):
				_rotated_out_tags.append(tag)
	var on_stage: Array[String] = []
	for tag in _joined_character_order:
		if on_stage.size() < MAX_VISIBLE_LAYOUT_CHARACTERS:
			on_stage.append(tag)
			continue
		_joined_characters[tag] = false
		if not tag in _rotated_out_tags:
			_rotated_out_tags.append(tag)
	for tag in _rotated_out_tags:
		_joined_character_order.erase(tag)

	var recent: Array[String] = []
	if raw_recency is Array:
		for raw_tag in raw_recency:
			var tag: = str(raw_tag).strip_edges()
			if tag in on_stage and not tag in recent:
				recent.append(tag)
	for tag in on_stage:
		if not tag in recent:
			_stage_recency.append(tag)
	_stage_recency.append_array(recent)


func _get_known_character_tags() -> Array[String]:
	var tags: Array[String] = []
	if CharacterSpriteLoader != null:
		if CharacterSpriteLoader.has_method("is_loaded") and not CharacterSpriteLoader.is_loaded():
			CharacterSpriteLoader.load_all_characters()
		for raw_tag in CharacterSpriteLoader.get_all_tags():
			var tag: = str(raw_tag).strip_edges().to_lower()
			if tag.is_empty() or tag in tags:
				continue
			tags.append(tag)
	return tags


func _ensure_runtime_character_registered(tag: String) -> bool:
	var normalized: = tag.strip_edges().to_lower()
	if normalized.is_empty():
		return false

	if not normalized in _get_known_character_tags():
		return false

	var found_data: = false
	for char_data in _character_data:
		if char_data != null and str(char_data.tag).strip_edges().to_lower() == normalized:
			found_data = true
			break
	if not found_data:
		var loaded_data: = _prompt_manager.load_character(normalized)
		if loaded_data != null:
			_character_data.append(loaded_data)

	if not _dialogic_characters.has(normalized):
		var dialogic_char: = CharacterPortraitService.find_dialogic_character(normalized)
		if dialogic_char == null:
			return false
		_dialogic_characters[normalized] = dialogic_char

	if not _sprite_states.has(normalized):
		_sprite_states[normalized] = CharacterPortraitService.get_final_emotion(normalized, "neutral")
	if not _joined_characters.has(normalized):
		_joined_characters[normalized] = false

	var valid_tags: Array[String] = []
	for char_data in _character_data:
		if char_data == null:
			continue
		var data_tag: = str(char_data.tag).strip_edges().to_lower()
		if data_tag.is_empty() or data_tag in valid_tags:
			continue
		valid_tags.append(data_tag)
	_line_processor.set_valid_tags(valid_tags)
	_line_processor.set_known_character_tags(_get_known_character_tags())
	return true


func _get_joined_character_tags() -> Array[String]:
	var joined: Array[String] = []
	for raw_tag in _dialogic_characters.keys():
		var tag: = str(raw_tag)
		var dialogic_char: DialogicCharacter = _dialogic_characters.get(tag, null)
		if dialogic_char != null and Dialogic.Portraits.is_character_joined(dialogic_char):
			joined.append(tag)
	return joined


func _remember_joined_character_order(tag: String) -> void :
	var normalized: = tag.strip_edges()
	if normalized.is_empty() or _joined_character_order.has(normalized):
		return
	_joined_character_order.append(normalized)


func _forget_joined_character_order(tag: String) -> void :
	var normalized: = tag.strip_edges()
	if normalized.is_empty():
		return
	_joined_character_order.erase(normalized)


func _restore_joined_character_order(raw_order: Variant) -> void :
	_joined_character_order.clear()
	if raw_order is Array:
		for raw_tag in raw_order:
			var tag: = str(raw_tag).strip_edges()
			if tag.is_empty():
				continue
			if not bool(_joined_characters.get(tag, false)):
				continue
			_remember_joined_character_order(tag)

	for raw_tag in _joined_characters.keys():
		var tag: = str(raw_tag).strip_edges()
		if tag.is_empty():
			continue
		if bool(_joined_characters.get(tag, false)):
			_remember_joined_character_order(tag)


func _get_ordered_joined_character_tags() -> Array[String]:
	var ordered: Array[String] = []
	var joined_tags: = _get_joined_character_tags()

	if _is_dynamic_character_mode_enabled() or _is_stage_crowded():
		for raw_tag in _joined_character_order:
			var tag: = str(raw_tag).strip_edges()
			if tag.is_empty() or not joined_tags.has(tag) or ordered.has(tag):
				continue
			ordered.append(tag)

		for tag in joined_tags:
			if tag.is_empty() or ordered.has(tag):
				continue
			ordered.append(tag)

		return ordered

	for char_data in _character_data:
		if char_data == null:
			continue
		var tag: = str(char_data.tag).strip_edges()
		if tag.is_empty() or not joined_tags.has(tag) or ordered.has(tag):
			continue
		ordered.append(tag)

	for tag in joined_tags:
		if tag.is_empty() or ordered.has(tag):
			continue
		ordered.append(tag)

	return ordered


func _get_total_visible_for_layout(pending_tag: String = "") -> int:
	if not _is_dynamic_character_mode_enabled():
		return clampi(_character_data.size(), 1, MAX_VISIBLE_LAYOUT_CHARACTERS)

	var layout_tags: = _get_ordered_joined_character_tags()
	if not pending_tag.is_empty() and not layout_tags.has(pending_tag):
		layout_tags.append(pending_tag)

	return clampi(layout_tags.size(), 1, MAX_VISIBLE_LAYOUT_CHARACTERS)


func _sync_joined_character_base_layout(total_chars: int) -> void :
	if total_chars <= 0:
		return

	var ordered_tags: = _get_ordered_joined_character_tags()
	for i in range(min(total_chars, ordered_tags.size())):
		var tag: = str(ordered_tags[i]).strip_edges()
		if tag.is_empty() or not _dialogic_characters.has(tag):
			continue

		var dialogic_char: DialogicCharacter = _dialogic_characters[tag]
		if dialogic_char == null or not Dialogic.Portraits.is_character_joined(dialogic_char):
			continue

		var position_id: = CharacterPortraitService.get_position_for_character(i, total_chars)
		CharacterPortraitService.force_character_position(dialogic_char, position_id)


func _reapply_solo_scale_to_joined_characters() -> void :
	for tag in _get_ordered_joined_character_tags():
		var normalized_tag: = str(tag).strip_edges()
		if normalized_tag.is_empty() or not _dialogic_characters.has(normalized_tag):
			continue

		var dialogic_char: DialogicCharacter = _dialogic_characters[normalized_tag]
		if dialogic_char == null or not Dialogic.Portraits.is_character_joined(dialogic_char):
			continue

		CharacterPortraitService.apply_solo_scale_to_character(dialogic_char)



func _apply_group_scale_deferred(dialogic_char: DialogicCharacter, portrait: String) -> void :
	if dialogic_char == null or not Dialogic.Portraits.is_character_joined(dialogic_char):
		return
	var tag: = _get_tag_for_dialogic_character(dialogic_char)
	var current_total: = _get_total_visible_for_layout(tag)
	Log.d(
		"AISceneGenerator", 
		"Apply group scale | char=%s portrait=%s total_chars=%d" % [
			dialogic_char.get_identifier(), 
			portrait, 
			current_total, 
		]
	)

	if current_total <= 1:
		_refresh_group_layout(current_total)
		return
	if current_total == 2:
		if CharacterPortraitService.is_duo_scene():
			CharacterPortraitService.apply_duo_scale_to_character(dialogic_char)
			_check_duo_positions()
		else:
			_refresh_group_layout(current_total)
		return
	if current_total >= 3 and current_total <= MAX_VISIBLE_LAYOUT_CHARACTERS:
		CharacterPortraitService.apply_group_scale_to_character(dialogic_char, portrait, current_total)
		_check_group_positions(current_total)
		return


func _prepare_group_layout_before_portrait_change(tag: String, dialogic_char: DialogicCharacter, total_chars: int) -> void :
	if dialogic_char == null or not Dialogic.Portraits.is_character_joined(dialogic_char):
		return
	if total_chars >= 2 and total_chars <= MAX_VISIBLE_LAYOUT_CHARACTERS:
		CharacterPortraitService.reapply_group_scale(dialogic_char, _get_position_for_character(tag), total_chars)



func _check_duo_positions() -> void :
	if _get_total_visible_for_layout() != 2:
		return

	var joined_tags: = _get_ordered_joined_character_tags()
	if joined_tags.size() != 2:
		return

	var left_tag: = joined_tags[0]
	var right_tag: = joined_tags[1]
	if not _dialogic_characters.has(left_tag) or not _dialogic_characters.has(right_tag):
		return

	var left_char: DialogicCharacter = _dialogic_characters[left_tag]
	var right_char: DialogicCharacter = _dialogic_characters[right_tag]
	var left_portrait: String = str(_sprite_states.get(left_tag, "neutral"))
	var right_portrait: String = str(_sprite_states.get(right_tag, "neutral"))

	if left_char != null and right_char != null:
		CharacterPortraitService.ensure_duo_state(
			left_char, 
			right_char, 
			left_portrait, 
			right_portrait
		)





func _check_group_positions(count: int) -> void :
	if _get_total_visible_for_layout() != count:
		return
	var joined_tags: = _get_ordered_joined_character_tags()
	if joined_tags.size() != count:
		return
	var characters: Array[DialogicCharacter] = []
	var portraits: Array[String] = []
	for tag in joined_tags:
		if not _dialogic_characters.has(tag):
			return
		var dialogic_char: DialogicCharacter = _dialogic_characters[tag]
		if not Dialogic.Portraits.is_character_joined(dialogic_char):
			return
		characters.append(dialogic_char)
		portraits.append(str(_sprite_states.get(tag, "neutral")))
	if characters.size() == count:
		CharacterPortraitService.ensure_group_state(characters, portraits, count)





func _refresh_group_layout(target_layout_count: int, preserve_target_layout_during_join: bool = false) -> void :
	var visible_count: = _get_joined_character_tags().size()

	if visible_count <= 0:
		CharacterPortraitService.clear_scene_layout_state()
		return

	var layout_count: = clampi(target_layout_count, 0, MAX_VISIBLE_LAYOUT_CHARACTERS)
	if layout_count <= 0:
		layout_count = _get_total_visible_for_layout()
	elif preserve_target_layout_during_join and _is_dynamic_character_mode_enabled():
		layout_count = max(layout_count, _get_total_visible_for_layout())

	if layout_count <= 1:

		CharacterPortraitService.clear_scene_layout_state(1, true)
		_sync_joined_character_base_layout(1)
		_reapply_solo_scale_to_joined_characters()
		return
	if layout_count >= 2 and layout_count <= MAX_VISIBLE_LAYOUT_CHARACTERS:
		for other_count in range(2, MAX_VISIBLE_LAYOUT_CHARACTERS + 1):
			if other_count != layout_count and CharacterPortraitService.is_group_scene(other_count):

				CharacterPortraitService.clear_group_state(other_count, true)
		_sync_joined_character_base_layout(layout_count)
		if visible_count >= layout_count:
			if layout_count == 2:
				_check_duo_positions()
			else:
				_check_group_positions(layout_count)



func _get_position_for_character(tag: String) -> String:
	if _is_stage_crowded():

		var joined_tags: = _get_joined_character_tags()
		var stage_order: Array[String] = []
		for order_tag in _joined_character_order:
			if order_tag == tag or order_tag in joined_tags:
				stage_order.append(order_tag)
		if not tag in stage_order:
			stage_order.append(tag)
		var stage_total: = _get_total_visible_for_layout(tag)
		return CharacterPortraitService.get_position_for_character(mini(stage_order.find(tag), stage_total - 1), stage_total)

	if not _is_dynamic_character_mode_enabled():
		var total_chars: = clampi(_character_data.size(), 1, MAX_VISIBLE_LAYOUT_CHARACTERS)
		for i in range(_character_data.size()):
			if _character_data[i].tag == tag:
				return CharacterPortraitService.get_position_for_character(i, total_chars)
		var joined_count: = _get_joined_character_tags().size()
		return CharacterPortraitService.get_position_for_character(joined_count, total_chars)

	var layout_tags: = _get_ordered_joined_character_tags()
	if not layout_tags.has(tag):
		layout_tags.append(tag)

	var total_chars: = clampi(layout_tags.size(), 1, MAX_VISIBLE_LAYOUT_CHARACTERS)
	var tag_index: = layout_tags.find(tag)
	if tag_index < 0:
		tag_index = clampi(layout_tags.size(), 0, total_chars - 1)

	return CharacterPortraitService.get_position_for_character(tag_index, total_chars)


func _get_tag_for_dialogic_character(dialogic_char: DialogicCharacter) -> String:
	if dialogic_char == null:
		return ""
	for raw_tag in _dialogic_characters.keys():
		var tag: = str(raw_tag)
		if _dialogic_characters.get(tag, null) == dialogic_char:
			return tag
	return ""


func _is_speaker_focus_enabled() -> bool:
	if APIConfigManager and APIConfigManager.has_method("is_speaker_focus_enabled"):
		return APIConfigManager.is_speaker_focus_enabled()
	return true


func _get_non_speaker_alpha() -> float:
	var fallback_alpha: = 0.65
	if APIConfigManager and APIConfigManager.has_method("get_non_speaker_alpha"):
		return APIConfigData.sanitize_non_speaker_alpha(
			float(APIConfigManager.get_non_speaker_alpha()), 
			fallback_alpha
		)
	return fallback_alpha


func _apply_speaker_focus_for_line(speaker: String, is_narrator: bool) -> void :
	CharacterPortraitService.apply_speaker_focus(
		_dialogic_characters, 
		speaker, 
		is_narrator, 
		_is_speaker_focus_enabled(), 
		_get_non_speaker_alpha()
	)


func _reset_speaker_focus() -> void :
	CharacterPortraitService.reset_speaker_focus(_dialogic_characters)


func _normalize_speaker_tag(tag: String) -> String:
	return tag.strip_edges().to_lower()


func _get_dialogic_character_for_speaker(speaker: String) -> DialogicCharacter:
	var normalized: = _normalize_speaker_tag(speaker)
	if _dialogic_characters.has(normalized):
		return _dialogic_characters[normalized]
	if _dialogic_characters.has(speaker):
		return _dialogic_characters[speaker]
	return CharacterPortraitService.find_dialogic_character(normalized)


func _resolve_speaker_tag_from_ai_data(ai_data: Dictionary) -> String:
	var character_id: = str(ai_data.get("character_id", "")).strip_edges()
	if character_id.is_empty():
		return ""

	for raw_tag in _dialogic_characters.keys():
		var tag: = str(raw_tag)
		var character: DialogicCharacter = _dialogic_characters.get(tag, null)
		if character == null:
			continue
		if character.resource_path == character_id or character.get_identifier() == character_id:
			return tag
	return ""



func _find_dialog_text_node() -> void :
	var text_nodes = get_tree().get_nodes_in_group("dialogic_dialog_text")
	if not text_nodes.is_empty():
		_dialog_text_node = text_nodes[0]
		_dialog_text_parent = _dialog_text_node.get_parent()



func _show_thinking_indicator() -> void :

	_show_edit_button = false
	_edit_enabled = false
	_hide_edit_button()
	_thinking_controller.start(tr("Generating scene"), true)



func _stop_thinking_animation() -> void :
	_thinking_controller.stop(true)



func _show_control_panel() -> void :
	_hide_interrupt_button()
	_hide_edit_button()
	_show_edit_button = false
	_reset_speaker_focus()
	Log.d("AISceneGenerator", "_show_control_panel (rollback=%s, playing=%s, queue=%d)" % [
		str(RollbackManager.is_in_rollback_mode()), 
		str(_is_playing), 
		_scene_queue.size()
	])
	if _control_panel != null:
		_control_panel.queue_free()


	var parent_node: Node = null
	if _dialog_text_parent:
		var current = _dialog_text_parent
		while current:
			if current is CanvasLayer:
				parent_node = current
				break
			current = current.get_parent()
	if not parent_node:
		parent_node = get_tree().current_scene

	if not parent_node:
		accept_scene()
		return


	_control_panel = PanelContainer.new()
	_control_panel.z_index = 100
	_control_panel.add_to_group("ui_blocking_overlay")
	_control_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_control_panel.mouse_filter = Control.MOUSE_FILTER_STOP


	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(1, 0.953, 0.969, 0.95)
	panel_style.border_color = Color(0.914, 0.42, 0.71, 1)
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(15)
	panel_style.shadow_color = Color(0, 0, 0, 0.2)
	panel_style.shadow_size = 5
	_control_panel.add_theme_stylebox_override("panel", panel_style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	_control_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)


	var label = Label.new()
	label.text = "How was that intro?"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.4, 0.25, 0.35))
	label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(label)


	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 15)
	vbox.add_child(hbox)


	var keep_btn = Button.new()
	keep_btn.text = "Continue"
	keep_btn.custom_minimum_size = Vector2(100, 40)
	_style_button(keep_btn, Color(0.4, 0.75, 0.4))
	keep_btn.pressed.connect( func():
		Log.d("AISceneGenerator", "Continue pressed (rollback=%s)" % str(RollbackManager.is_in_rollback_mode()))
		accept_scene()
	)
	hbox.add_child(keep_btn)


	var retry_btn = Button.new()
	retry_btn.text = "Retry"
	retry_btn.custom_minimum_size = Vector2(100, 40)
	_style_button(retry_btn, Color(0.914, 0.42, 0.71))
	retry_btn.pressed.connect( func():
		Log.d("AISceneGenerator", "Retry pressed (rollback=%s)" % str(RollbackManager.is_in_rollback_mode()))
		retry_scene()
	)
	hbox.add_child(retry_btn)

	parent_node.add_child(_control_panel)


	await get_tree().process_frame
	var viewport_size = get_viewport().get_visible_rect().size
	_control_panel.position = Vector2(
		(viewport_size.x - _control_panel.size.x) / 2, 
		viewport_size.y - _control_panel.size.y - 220
	)



func _style_button(btn: Button, color: Color) -> void :
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = color
	normal_style.border_color = color.darkened(0.2)
	normal_style.set_border_width_all(2)
	normal_style.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style = normal_style.duplicate()
	hover_style.bg_color = color.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style = normal_style.duplicate()
	pressed_style.bg_color = color.darkened(0.15)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 16)



func _hide_control_panel() -> void :
	if _control_panel:
		_control_panel.queue_free()
		_control_panel = null




func get_active_character_tags() -> Array[String]:
	var tags: Array[String] = []
	if _is_dynamic_character_mode_enabled():
		for raw_tag in _get_ordered_joined_character_tags():
			var joined_tag: = str(raw_tag).strip_edges()
			if joined_tag.is_empty() or joined_tag in tags:
				continue
			tags.append(joined_tag)

		for rotated_tag in _rotated_out_tags:
			if not rotated_tag in tags:
				tags.append(rotated_tag)
		if not tags.is_empty():
			return tags

	for char_data in _character_data:
		if char_data == null:
			continue
		var tag: = str(char_data.tag).strip_edges()
		if tag.is_empty():
			continue
		if _joined_characters.has(tag) and not bool(_joined_characters.get(tag, false)) and not tag in _rotated_out_tags:
			continue
		if not tag in tags:
			tags.append(tag)
	return tags



func _leave_all_characters() -> void :
	for tag in _joined_characters:
		if _joined_characters[tag] and _dialogic_characters.has(tag):
			var dialogic_char: DialogicCharacter = _dialogic_characters[tag]
			if Dialogic.Portraits.is_character_joined(dialogic_char):
				Dialogic.Portraits.leave_character(dialogic_char, "", 0.3)
	await get_tree().create_timer(0.35).timeout



func _cleanup() -> void :
	# Cleanup also runs during shutdown, when adding root children is forbidden.
	var voice_mod := get_tree().root.get_node_or_null("PonyVoiceMod")
	if voice_mod != null:
		voice_mod.stop()
	_hide_control_panel()
	_hide_interrupt_button()
	_hide_edit_button()
	if _edit_dialog_panel:
		_edit_dialog_panel.visible = false
	_is_editing = false
	if _thinking_controller:
		_thinking_controller.cleanup()

	CharacterPortraitService.clear_scene_layout_state()







func _create_interrupt_button() -> void :
	if _interrupt_panel != null:
		_interrupt_panel.queue_free()


	var parent_node: Node = null
	if _dialog_text_parent:
		var current = _dialog_text_parent
		while current:
			if current is CanvasLayer:
				parent_node = current
				break
			current = current.get_parent()
	if not parent_node:
		parent_node = get_tree().current_scene

	if not parent_node:
		return


	_interrupt_panel = PanelContainer.new()
	_interrupt_panel.z_index = 100
	_interrupt_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_interrupt_panel.mouse_filter = Control.MOUSE_FILTER_STOP


	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.11, 0.14, 0.95)
	panel_style.border_color = Color(0.25, 0.22, 0.3, 0.6)
	panel_style.border_width_left = 0
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.set_corner_radius_all(0)
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 4
	panel_style.content_margin_right = 4
	panel_style.content_margin_top = 4
	panel_style.content_margin_bottom = 4
	_interrupt_panel.add_theme_stylebox_override("panel", panel_style)


	var btn = Button.new()
	btn.flat = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.focus_mode = Control.FOCUS_NONE


	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE


	var btn_content = VBoxContainer.new()
	btn_content.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_content.add_theme_constant_override("separation", -1)
	btn_content.mouse_filter = Control.MOUSE_FILTER_IGNORE


	var accent_color: = Color("#FFE09B")
	var normal_icon_color: = accent_color.lerp(Color.WHITE, 0.15)
	var hover_icon_color: = accent_color.lerp(Color.WHITE, 0.5)
	var normal_text_color: = Color(0.6, 0.58, 0.65, 0.9)
	var hover_text_color: = Color(0.85, 0.83, 0.9, 1.0)


	var icon_label = Label.new()
	icon_label.text = UIFonts.pick("⚡", "↯")
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_label.add_theme_font_size_override("font_size", 16)
	icon_label.add_theme_color_override("font_color", normal_icon_color)
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE


	var text_label = Label.new()
	text_label.text = "Interrupt"
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	text_label.add_theme_font_size_override("font_size", 8)
	text_label.add_theme_color_override("font_color", normal_text_color)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	btn_content.add_child(icon_label)
	btn_content.add_child(text_label)
	center.add_child(btn_content)
	btn.add_child(center)


	btn.mouse_entered.connect( func():
		icon_label.add_theme_color_override("font_color", hover_icon_color)
		text_label.add_theme_color_override("font_color", hover_text_color)
	)
	btn.mouse_exited.connect( func():
		icon_label.add_theme_color_override("font_color", normal_icon_color)
		text_label.add_theme_color_override("font_color", normal_text_color)
	)

	btn.pressed.connect(_on_interrupt_button_pressed)
	_interrupt_panel.add_child(btn)
	_interrupt_panel.set_meta("button", btn)
	UISettingsManager.register_dialogue_control(_interrupt_panel, "interrupt", text_label, icon_label)

	parent_node.add_child(_interrupt_panel)


	call_deferred("_position_interrupt_button")



func _create_edit_button() -> void :
	if _edit_panel != null:
		_edit_panel.queue_free()


	var parent_node: Node = null
	if _dialog_text_parent:
		var current = _dialog_text_parent
		while current:
			if current is CanvasLayer:
				parent_node = current
				break
			current = current.get_parent()
	if not parent_node:
		parent_node = get_tree().current_scene
	if not parent_node:
		return

	_edit_panel = PanelContainer.new()
	_edit_panel.z_index = 100
	_edit_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_edit_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.11, 0.14, 0.95)
	panel_style.border_color = Color(0.25, 0.22, 0.3, 0.6)
	panel_style.border_width_left = 0
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.set_corner_radius_all(0)
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 4
	panel_style.content_margin_right = 4
	panel_style.content_margin_top = 4
	panel_style.content_margin_bottom = 4
	_edit_panel.add_theme_stylebox_override("panel", panel_style)

	var btn = Button.new()
	btn.flat = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.focus_mode = Control.FOCUS_NONE

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var btn_content = VBoxContainer.new()
	btn_content.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_content.add_theme_constant_override("separation", -1)
	btn_content.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var accent_color: = Color("#FFD3A1")
	var normal_icon_color: = accent_color.lerp(Color.WHITE, 0.15)
	var hover_icon_color: = accent_color.lerp(Color.WHITE, 0.5)
	var normal_text_color: = Color(0.6, 0.58, 0.65, 0.9)
	var hover_text_color: = Color(0.85, 0.83, 0.9, 1.0)

	var icon_label = Label.new()
	icon_label.text = "✎"
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_label.add_theme_font_size_override("font_size", 16)
	icon_label.add_theme_color_override("font_color", normal_icon_color)
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var text_label = Label.new()
	text_label.text = "Edit"
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	text_label.add_theme_font_size_override("font_size", 8)
	text_label.add_theme_color_override("font_color", normal_text_color)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	btn_content.add_child(icon_label)
	btn_content.add_child(text_label)
	center.add_child(btn_content)
	btn.add_child(center)

	btn.mouse_entered.connect( func():
		icon_label.add_theme_color_override("font_color", hover_icon_color)
		text_label.add_theme_color_override("font_color", hover_text_color)
	)
	btn.mouse_exited.connect( func():
		icon_label.add_theme_color_override("font_color", normal_icon_color)
		text_label.add_theme_color_override("font_color", normal_text_color)
	)

	btn.pressed.connect(_on_edit_button_pressed)
	_edit_panel.add_child(btn)
	_edit_panel.set_meta("button", btn)
	UISettingsManager.register_dialogue_control(_edit_panel, "edit", text_label, icon_label)
	parent_node.add_child(_edit_panel)

	call_deferred("_position_interrupt_button")



func _position_interrupt_button() -> void :

	await get_tree().create_timer(0.1).timeout

	if not _interrupt_panel and not _edit_panel:
		return


	if not _dialog_text_parent:
		_find_dialog_text_node()
		await get_tree().process_frame


	var dialog_box_rect: Rect2 = _find_dialog_box_rect()


	var retry_count: = 0
	while dialog_box_rect.size == Vector2.ZERO and retry_count < 5:
		await get_tree().process_frame
		_find_dialog_text_node()
		dialog_box_rect = _find_dialog_box_rect()
		retry_count += 1

	if dialog_box_rect.size == Vector2.ZERO:

		var viewport_size = get_viewport().get_visible_rect().size
		dialog_box_rect = Rect2(0, viewport_size.y - 200, viewport_size.x, 200)


	var box_right: = dialog_box_rect.position.x + dialog_box_rect.size.x
	var box_top: = dialog_box_rect.position.y
	var box_height: = dialog_box_rect.size.y

	var panels: Array = []
	if _interrupt_panel and _interrupt_panel.visible:
		panels.append(_interrupt_panel)
	if _edit_panel and _edit_panel.visible:
		panels.append(_edit_panel)

	var button_width: = 60.0
	var button_height: float = box_height / max(1, panels.size())

	var y_offset: = box_top
	for panel in panels:
		panel.position = Vector2(box_right, y_offset)
		panel.custom_minimum_size = Vector2(button_width, button_height)
		panel.size = Vector2(button_width, button_height)
		y_offset += button_height


	_verify_interrupt_position.call_deferred()


func _verify_interrupt_position() -> void :
	await get_tree().process_frame



func _update_interrupt_button_position() -> void :
	if not _interrupt_panel and not _edit_panel:
		return

	var dialog_box_rect: = _find_dialog_box_rect()
	if dialog_box_rect.size == Vector2.ZERO:
		return

	var box_right: = dialog_box_rect.position.x + dialog_box_rect.size.x
	var box_top: = dialog_box_rect.position.y
	var box_height: = dialog_box_rect.size.y

	var panels: Array = []
	if _interrupt_panel and _interrupt_panel.visible:
		panels.append(_interrupt_panel)
	if _edit_panel and _edit_panel.visible:
		panels.append(_edit_panel)

	var button_width: = 60.0
	var button_height: float = box_height / max(1, panels.size())

	var y_offset: = box_top
	for panel in panels:
		panel.position = Vector2(box_right, y_offset)
		panel.custom_minimum_size = Vector2(button_width, button_height)
		panel.size = Vector2(button_width, button_height)
		y_offset += button_height



func _find_dialog_box_rect() -> Rect2:
	if _dialog_text_node:
		var textbox_root = _dialog_text_node.get("textbox_root")
		if textbox_root and textbox_root is Control:
			var root_rect: Rect2 = textbox_root.get_global_rect()
			if root_rect.size != Vector2.ZERO:
				return root_rect

	if not _dialog_text_parent:
		Log.d("AISceneGenerator", "_find_dialog_box_rect: No dialog_text_parent")
		return Rect2()

	var current = _dialog_text_parent
	Log.d("AISceneGenerator", "_find_dialog_box_rect: Starting from %s" % [_dialog_text_parent.name if _dialog_text_parent else "null"])

	while current:
		var is_panel: bool = current is PanelContainer
		var has_dialog_name: bool = current.name.contains("DialogText") or current.name.contains("Dialogue")
		Log.d("AISceneGenerator", "_find_dialog_box_rect: Checking %s (is_panel=%s, has_dialog_name=%s)" % [current.name, is_panel, has_dialog_name])

		if is_panel or has_dialog_name:
			var rect: = current.get_global_rect()
			Log.d("AISceneGenerator", "_find_dialog_box_rect: Found candidate %s, rect=%s" % [current.name, rect])
			if rect.size != Vector2.ZERO:
				return rect
		current = current.get_parent()


	var fallback_rect: = _dialog_text_parent.get_global_rect()
	Log.d("AISceneGenerator", "_find_dialog_box_rect: Using fallback rect from text_parent=%s" % [fallback_rect])
	return fallback_rect



func _on_interrupt_button_pressed() -> void :
	Log.d("AISceneGenerator", "Interrupt pressed (rollback=%s, playing=%s, queue=%d)" % [
		str(RollbackManager.is_in_rollback_mode()), 
		str(_is_playing), 
		_scene_queue.size()
	])
	_hide_interrupt_button()
	if RollbackManager.is_in_rollback_mode():


		RollbackManager.discard_future_snapshots_from_current(false)
	_interrupt_requested = true
	_scene_queue.clear()

	_show_control_panel()



func _show_interrupt_button() -> void :
	if _interrupt_panel == null:
		_create_interrupt_button()
	if _interrupt_panel:
		UISettingsManager.set_dialogue_control_available(_interrupt_panel, true)
		call_deferred("_position_interrupt_button")
	_update_action_buttons_visibility()



func _hide_interrupt_button() -> void :
	if _interrupt_panel:
		UISettingsManager.set_dialogue_control_available(_interrupt_panel, false)
	_update_action_buttons_visibility()



func _show_edit_button_panel() -> void :
	if _edit_panel == null:
		_create_edit_button()
	if _edit_panel:
		UISettingsManager.set_dialogue_control_available(_edit_panel, true)
	_update_action_buttons_visibility()



func _hide_edit_button() -> void :





	_show_edit_button = false
	if _edit_panel:
		UISettingsManager.set_dialogue_control_available(_edit_panel, false)



func _update_action_buttons_visibility() -> void :
	if _edit_panel:
		UISettingsManager.set_dialogue_control_available(_edit_panel, _show_edit_button and not _is_editing)
		_set_panel_enabled(_edit_panel, _edit_enabled)



func _set_panel_enabled(panel: PanelContainer, enabled: bool) -> void :
	var button: Button = panel.get_meta("button", null)
	if button:
		button.disabled = not enabled
	panel.modulate = Color(1, 1, 1, 1) if enabled else Color(0.6, 0.6, 0.6, 0.7)







func _on_edit_button_pressed() -> void :
	if _is_editing:
		return
	if RollbackManager.is_in_rollback_mode() and not _sync_history_view_state_from_current_snapshot():
		return
	if _current_displayed_text.is_empty():
		return
	_open_edit_dialog()



func _open_edit_dialog() -> void :
	if RollbackManager.is_in_rollback_mode() and not _sync_history_view_state_from_current_snapshot():
		return
	if _edit_dialog_panel == null:
		_create_edit_dialog()
	if _edit_dialog_panel == null:
		return

	_is_editing = true
	_show_interrupt_before_edit = UISettingsManager.is_dialogue_control_available(_interrupt_panel)
	_hide_interrupt_button()
	_show_edit_button = false
	_edit_enabled = false
	_update_action_buttons_visibility()

	_edit_text_edit.text = _current_displayed_text
	_edit_dialog_panel.visible = true
	_position_edit_dialog()
	_edit_text_edit.grab_focus()

	Dialogic.paused = true



func _create_edit_dialog() -> void :
	var parent_node: Node = null
	if _dialog_text_parent:
		var current = _dialog_text_parent
		while current:
			if current is CanvasLayer:
				parent_node = current
				break
			current = current.get_parent()
	if not parent_node:
		parent_node = get_tree().current_scene
	if not parent_node:
		return

	_edit_dialog_panel = PanelContainer.new()
	_edit_dialog_panel.z_index = 200
	_edit_dialog_panel.custom_minimum_size = Vector2(640, 220)
	_edit_dialog_panel.add_to_group("ui_blocking_overlay")
	_edit_dialog_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.11, 0.14, 0.98)
	panel_style.border_color = Color(0.25, 0.22, 0.3, 0.8)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	_edit_dialog_panel.add_theme_stylebox_override("panel", panel_style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_edit_dialog_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	_edit_text_edit = TextEdit.new()
	_edit_text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_edit_text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_edit_text_edit.drag_and_drop_selection_enabled = false
	_edit_text_edit.custom_minimum_size = Vector2(600, 130)
	vbox.add_child(_edit_text_edit)

	var buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	vbox.add_child(buttons)

	var save_btn = Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(_apply_edit_text)
	buttons.add_child(save_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_close_edit_dialog)
	buttons.add_child(cancel_btn)

	_edit_dialog_panel.visible = false
	parent_node.add_child(_edit_dialog_panel)



func _position_edit_dialog() -> void :
	if _edit_dialog_panel == null:
		return
	var viewport_size: = get_viewport().get_visible_rect().size
	var size: = _edit_dialog_panel.custom_minimum_size
	_edit_dialog_panel.position = (viewport_size - size) / 2.0



func _close_edit_dialog() -> void :
	if _edit_dialog_panel:
		_edit_dialog_panel.visible = false
	_is_editing = false
	_edit_just_closed = true
	if _show_interrupt_before_edit:
		_show_interrupt_button()
	_show_edit_button = _is_displaying_line
	_edit_enabled = _is_displaying_line
	_update_action_buttons_visibility()
	Dialogic.paused = false



func _apply_edit_text() -> void :
	if _edit_text_edit == null:
		_close_edit_dialog()
		return

	if RollbackManager.is_in_rollback_mode() and not _sync_history_view_state_from_current_snapshot():
		_close_edit_dialog()
		return

	var new_text: = _edit_text_edit.text.strip_edges()
	if new_text.is_empty():
		_close_edit_dialog()
		return

	var previous_text: = _current_displayed_text
	_current_displayed_text = new_text

	if Dialogic.Text:
		Dialogic.Text.update_dialog_text(new_text, true)

	_update_last_displayed_line(new_text)
	_update_last_dialogic_history_line(new_text, previous_text)
	_update_scene_snapshots_after_edit(new_text, previous_text)

	_close_edit_dialog()


func _tag_last_scene_snapshot_history_index(raw_history_index: int) -> void :
	if raw_history_index < 0:
		return

	var snapshot_count: int = RollbackManager.get_snapshot_count()
	for i in range(snapshot_count - 1, -1, -1):
		var snap: Dictionary = RollbackManager.get_snapshot(i)
		if snap.get("type", RollbackManager.SnapshotType.SCRIPTED) != RollbackManager.SnapshotType.AI_EXCHANGE:
			continue
		var ai_data: Dictionary = snap.get("ai_data", {})
		if not ai_data.get("is_scene_generated", false):
			continue


		if not owns_rollback_snapshot(ai_data):
			continue

		var displayed_lines: Array = ai_data.get("displayed_lines", []).duplicate(true)
		for j in range(displayed_lines.size() - 1, -1, -1):
			var entry: Dictionary = displayed_lines[j]
			if entry.get("type", "dialogue") != "dialogue":
				continue
			entry["raw_history_index"] = raw_history_index
			displayed_lines[j] = entry
			ai_data["displayed_lines"] = displayed_lines
			ai_data["dialogic_history_length"] = maxi(
				int(ai_data.get("dialogic_history_length", -1)), 
				raw_history_index + 1
			)
			snap["ai_data"] = ai_data
			RollbackManager.set_snapshot(i, snap)
			return



func _update_last_displayed_line(new_text: String) -> void :
	for i in range(_displayed_lines.size() - 1, -1, -1):
		var entry: Dictionary = _displayed_lines[i]
		if entry.get("type", "dialogue") == "dialogue":
			entry["text"] = new_text
			_displayed_lines[i] = entry
			break


func _update_last_dialogic_history_line(new_text: String, previous_text: String = "") -> void :
	if not Dialogic.has_subsystem("History"):
		return

	var last_dialogue_entry: = _find_last_dialogue_entry_in_lines(_displayed_lines)
	var raw_history_index: = int(last_dialogue_entry.get("raw_history_index", -1))
	if raw_history_index < 0:
		raw_history_index = _find_matching_dialogic_history_index(previous_text, last_dialogue_entry)

	if raw_history_index < 0:
		return
	StorySummaryManager.rewrite_history_line(raw_history_index, new_text)



func _update_scene_snapshots_after_edit(new_text: String, previous_text: String) -> void :
	var snapshot_count: int = RollbackManager.get_snapshot_count()
	var edited_entry: = _find_last_dialogue_entry_in_lines(_displayed_lines)
	if edited_entry.is_empty():
		return

	var edited_history_index: = int(edited_entry.get("raw_history_index", -1))
	var start_index: = -1
	if RollbackManager.is_in_rollback_mode():
		var current: = RollbackManager.get_current_snapshot()
		if not current.is_empty():
			start_index = RollbackManager.get_current_position()

	if start_index < 0:
		for i in range(snapshot_count - 1, -1, -1):
			var latest_snap: Dictionary = RollbackManager.get_snapshot_metadata(i)
			if latest_snap.get("type", RollbackManager.SnapshotType.SCRIPTED) != RollbackManager.SnapshotType.AI_EXCHANGE:
				continue
			var latest_ai_data: Dictionary = latest_snap.get("ai_data", {})
			if not latest_ai_data.get("is_scene_generated", false):
				continue
			if not owns_rollback_snapshot(latest_ai_data):
				continue
			start_index = i
			break

	if start_index < 0:
		return

	for i in range(start_index, snapshot_count):
		var snap: Dictionary = RollbackManager.get_snapshot(i)
		if snap.get("type", RollbackManager.SnapshotType.SCRIPTED) != RollbackManager.SnapshotType.AI_EXCHANGE:
			continue

		var ai_data: Dictionary = snap.get("ai_data", {})
		if not ai_data.get("is_scene_generated", false):
			continue


		if not owns_rollback_snapshot(ai_data):
			continue

		var displayed_lines: Array = ai_data.get("displayed_lines", []).duplicate(true)
		var match_index: = _find_matching_displayed_line_index(displayed_lines, edited_history_index, previous_text, edited_entry)
		if match_index < 0:
			continue

		var entry: Dictionary = displayed_lines[match_index]
		entry["text"] = new_text
		if edited_history_index >= 0:
			entry["raw_history_index"] = edited_history_index
		displayed_lines[match_index] = entry
		ai_data["displayed_lines"] = displayed_lines

		if match_index == _find_last_dialogue_index_in_lines(displayed_lines):
			ai_data["displayed_text"] = new_text
			snap["display_text"] = new_text

		snap["ai_data"] = ai_data
		RollbackManager.set_snapshot(i, snap)


func _find_last_dialogue_entry_in_lines(lines: Array) -> Dictionary:
	for i in range(lines.size() - 1, -1, -1):
		var entry: Dictionary = lines[i]
		if entry.get("type", "dialogue") == "dialogue":
			return entry
	return {}


func _find_last_dialogue_index_in_lines(lines: Array) -> int:
	for i in range(lines.size() - 1, -1, -1):
		var entry: Dictionary = lines[i]
		if entry.get("type", "dialogue") == "dialogue":
			return i
	return -1


func _find_matching_displayed_line_index(lines: Array, edited_history_index: int, previous_text: String, expected_entry: Dictionary) -> int:
	var expected_text: = previous_text.strip_edges()
	var expected_is_narrator: = bool(expected_entry.get("is_narrator", false))
	var expected_speaker: = _normalize_speaker_tag(str(expected_entry.get("speaker", "")).strip_edges())

	for i in range(lines.size() - 1, -1, -1):
		var entry: Dictionary = lines[i]
		if entry.get("type", "dialogue") != "dialogue":
			continue

		if edited_history_index >= 0 and int(entry.get("raw_history_index", -1)) == edited_history_index:
			return i

		if expected_text.is_empty() or str(entry.get("text", "")).strip_edges() != expected_text:
			continue
		if bool(entry.get("is_narrator", false)) != expected_is_narrator:
			continue

		var entry_speaker: = _normalize_speaker_tag(str(entry.get("speaker", "")).strip_edges())
		if not expected_speaker.is_empty() and entry_speaker != expected_speaker:
			continue

		return i

	return -1


func _find_matching_dialogic_history_index(previous_text: String, dialogue_entry: Dictionary = {}) -> int:
	if not Dialogic.has_subsystem("History"):
		return -1

	var expected_text: = previous_text.strip_edges()
	if expected_text.is_empty():
		expected_text = str(dialogue_entry.get("text", "")).strip_edges()
	if expected_text.is_empty():
		return -1

	var expected_character: = _resolve_dialogue_entry_character_name(dialogue_entry)
	for i in range(Dialogic.History.simple_history_content.size() - 1, -1, -1):
		var history_entry: Dictionary = Dialogic.History.simple_history_content[i]
		if str(history_entry.get("event_type", "")).strip_edges() != "Text":
			continue
		if str(history_entry.get("text", "")).strip_edges() != expected_text:
			continue

		var actual_character: = str(history_entry.get("character", "")).strip_edges()
		if actual_character == "null":
			actual_character = ""
		if not expected_character.is_empty() and actual_character != expected_character:
			continue

		return i

	return -1


func _resolve_dialogue_entry_character_name(dialogue_entry: Dictionary) -> String:
	if bool(dialogue_entry.get("is_narrator", false)):
		return ""

	var speaker_tag: = _normalize_speaker_tag(str(dialogue_entry.get("speaker", "")).strip_edges())
	if not speaker_tag.is_empty() and _dialogic_characters.has(speaker_tag):
		var dialogic_char: DialogicCharacter = _dialogic_characters[speaker_tag]
		if dialogic_char != null:
			return dialogic_char.display_name.strip_edges()

	return str(dialogue_entry.get("speaker", "")).strip_edges()







func _sync_current_location_from_runtime_location(location_id: String) -> void :
	var normalized_id: = location_id.strip_edges()
	if normalized_id.is_empty():
		return
	var location: = LocationDatabase.get_location(normalized_id)
	if location != null:
		_current_location = location


func _get_current_runtime_location_id_for_save() -> String:
	if MapManager != null and MapManager.has_method("get_current_runtime_location_id"):
		var runtime_id: = str(MapManager.get_current_runtime_location_id()).strip_edges()
		if not runtime_id.is_empty():
			return runtime_id
	return _current_location.id if _current_location else ""


func _get_current_music_state_for_rollback() -> Dictionary:
	if not Dialogic.has_subsystem("Audio"):
		return {}
	var audio_state: Variant = Dialogic.current_state_info.get("audio", {})
	if not (audio_state is Dictionary):
		return {}
	var music_state: Variant = (audio_state as Dictionary).get("music", {})
	if not (music_state is Dictionary):
		return {}
	return (music_state as Dictionary).duplicate(true)


func _get_dialogic_history_size_for_scene_save(ai_data: Dictionary = {}) -> int:
	if not ai_data.is_empty() and ai_data.has("dialogic_history_length"):
		var snapshot_length: = RollbackManager.get_visible_dialogic_history_size(ai_data)
		if snapshot_length >= 0:
			return snapshot_length
	if Dialogic.has_subsystem("History"):
		return Dialogic.History.simple_history_content.size()
	return -1


func _count_displayed_dialogue_lines(lines: Array) -> int:
	var count: = 0
	for raw_entry in lines:
		if raw_entry is Dictionary and (raw_entry as Dictionary).get("type", "dialogue") == "dialogue":
			count += 1
	return count



func get_save_state() -> Dictionary:
	if not _is_playing:
		return {}

	if RollbackManager.is_in_rollback_mode():
		var rollback_ai_data: = RollbackManager.get_current_ai_data()
		if not rollback_ai_data.is_empty() and rollback_ai_data.get("is_scene_generated", false):
			return _build_normalized_history_view_save_state(rollback_ai_data)


	var char_tags: Array[String] = []
	for char_data in _character_data:
		char_tags.append(char_data.tag)

	return {
		"is_playing": _is_playing, 
		"rollback_owner_key": _rollback_owner_key, 
		"location_id": _get_current_runtime_location_id_for_save(), 
		"scene_start_location_id": _scene_start_location_id, 
		"character_tags": char_tags, 
		"sprite_states": _sprite_states.duplicate(), 
		"joined_characters": _joined_characters.duplicate(), 
		"joined_character_order": _joined_character_order.duplicate(), 
		"rotated_out_tags": _rotated_out_tags.duplicate(), 
		"stage_recency": _stage_recency.duplicate(), 
		"scene_queue": _scene_queue.duplicate(true), 
		"displayed_lines": _displayed_lines.duplicate(true), 
		"story_context": _story_context, 
		"management_context_override": _management_context_override.duplicate(true), 
		"prefill_scope": _prefill_scope, 
		"is_waiting_for_advance": _is_waiting_for_advance, 
		"is_displaying_line": _is_displaying_line, 
		"dialogic_history_size": _get_dialogic_history_size_for_scene_save(), 
		"scene_start_dialogic_history_length": _initial_dialogic_history_length, 
		"audio_state": RollbackManager.get_selected_audio_state(), 
	}


func _build_normalized_history_view_save_state(ai_data: Dictionary) -> Dictionary:
	var char_tags: Array[String] = []
	for raw_tag in ai_data.get("character_tags", []):
		var tag: = str(raw_tag).strip_edges()
		if not tag.is_empty():
			char_tags.append(tag)

	var displayed_lines: Array = ai_data.get("displayed_lines", []).duplicate(true)
	var remaining_queue: Array = ai_data.get("remaining_queue", []).duplicate(true)
	var has_visible_line: = not displayed_lines.is_empty()
	var dialogic_history_size: = _get_dialogic_history_size_for_scene_save(ai_data)

	return {
		"is_playing": true, 
		"rollback_owner_key": str(ai_data.get("rollback_owner_key", _rollback_owner_key)), 
		"location_id": str(ai_data.get("location_id", "")).strip_edges(), 
		"scene_start_location_id": _scene_start_location_id, 
		"character_tags": char_tags, 
		"sprite_states": ai_data.get("sprite_states", {}).duplicate(true), 
		"joined_characters": ai_data.get("joined_characters", {}).duplicate(true), 
		"joined_character_order": ai_data.get("joined_character_order", []).duplicate(true), 
		"rotated_out_tags": ai_data.get("rotated_out_tags", []).duplicate(true), 
		"stage_recency": ai_data.get("stage_recency", []).duplicate(true), 
		"scene_queue": remaining_queue, 
		"displayed_lines": displayed_lines, 
		"story_context": str(ai_data.get("story_context", _story_context)), 
		"management_context_override": _management_context_override.duplicate(true), 
		"prefill_scope": _prefill_scope, 
		"is_waiting_for_advance": has_visible_line, 
		"is_displaying_line": false, 
		"dialogic_history_size": dialogic_history_size, 
		"scene_start_dialogic_history_length": int(ai_data.get(
			"scene_start_dialogic_history_length", 
			maxi(0, dialogic_history_size - _count_displayed_dialogue_lines(displayed_lines)) if dialogic_history_size >= 0 else -1
		)), 
		"audio_state": RollbackManager.get_selected_audio_state(), 
	}



func restore_from_save_state(state: Dictionary, location: LocationData) -> void :
	if state.is_empty() or not state.get("is_playing", false):
		return

	Log.d("AISceneGenerator", "Restoring from save state")
	if _rollback_owner_key.is_empty():
		_rollback_owner_key = str(state.get("rollback_owner_key", "")).strip_edges()


	_session_id += 1
	Log.d("AISceneGenerator", "New session ID: %d" % _session_id)

	_current_location = location
	_scene_start_location_id = str(state.get("scene_start_location_id", location.id if location else ""))
	_prefill_scope = str(state.get("prefill_scope", AssistantPrefill.resolve_scope("scene", _scene_start_location_id, AIStateCoordinator.is_custom_start_active())))
	_story_context = state.get("story_context", "")
	_management_context_override = _sanitize_management_context_override(
		state.get("management_context_override", {})
	)
	_is_playing = true
	_interrupt_requested = false
	_cancel_advance_wait = false
	_is_waiting_for_advance = state.get("is_waiting_for_advance", false)
	_is_displaying_line = state.get("is_displaying_line", false)
	_show_edit_button = false
	_current_displayed_text = ""
	_edit_enabled = false


	_character_data.clear()
	_dialogic_characters.clear()
	_sprite_states = state.get("sprite_states", {}).duplicate()
	_joined_characters = state.get("joined_characters", {}).duplicate()
	_restore_joined_character_order(state.get("joined_character_order", []))
	_restore_stage_rotation(state.get("rotated_out_tags", []), state.get("stage_recency", []))
	_displayed_lines = state.get("displayed_lines", []).duplicate(true)

	var char_tags: Array = state.get("character_tags", [])
	for tag in char_tags:
		var char_data: = _prompt_manager.load_character(tag)
		if char_data != null:
			_character_data.append(char_data)
			var dialogic_char: = CharacterPortraitService.find_dialogic_character(tag)
			if dialogic_char:
				_dialogic_characters[tag] = dialogic_char


	var valid_tags: Array[String] = []
	for char_data in _character_data:
		valid_tags.append(char_data.tag)
	_line_processor.set_valid_tags(valid_tags)
	_line_processor.set_known_character_tags(_get_known_character_tags())


	_scene_queue.clear()
	var queue: Array = state.get("scene_queue", [])
	for item in queue:
		_scene_queue.append(item)

	var saved_dialogic_history_size: = int(state.get("dialogic_history_size", -1))
	_initial_dialogic_history_length = int(state.get(
		"scene_start_dialogic_history_length", 
		maxi(0, saved_dialogic_history_size - _count_displayed_dialogue_lines(_displayed_lines)) if saved_dialogic_history_size >= 0 else -1
	))
	if saved_dialogic_history_size >= 0 and Dialogic.has_subsystem("History"):
		var current_dialogic_history_size: = Dialogic.History.simple_history_content.size()
		if current_dialogic_history_size > saved_dialogic_history_size:
			Dialogic.History.simple_history_content.resize(saved_dialogic_history_size)
	if state.has("audio_state") and state.get("audio_state") is Dictionary:
		RollbackManager.restore_audio_from_snapshot(
			(state.get("audio_state") as Dictionary).duplicate(true), 
			true
		)


	_find_dialog_text_node()


	_restore_sprite_states()


	if _is_waiting_for_advance or _is_displaying_line or not _scene_queue.is_empty():
		_show_interrupt_button()


	if (_is_waiting_for_advance or _is_displaying_line) and not _displayed_lines.is_empty():
		Log.d("AISceneGenerator", "Restored from save, waiting at current line (%d remaining)" % _scene_queue.size())
		_resume_wait_from_saved_line(_displayed_lines[-1])
	elif not _scene_queue.is_empty():
		Log.d("AISceneGenerator", "Resuming scene playback with %d items in queue" % _scene_queue.size())
		_play_next_line()
	else:

		Log.d("AISceneGenerator", "Scene queue empty, showing control panel")
		_show_control_panel()



func _restore_sprite_states() -> void :
	var _sprite_sound_scope: = SpriteSoundManager.suppress()
	var total_chars: = 0
	for tag in _joined_characters:
		if _joined_characters[tag]:
			total_chars += 1
	total_chars = clampi(total_chars, 1, 6)
	var portraits_state: Dictionary = Dialogic.current_state_info.get("portraits", {})


	CharacterPortraitService.clear_scene_layout_state()

	for tag in _rotated_out_tags:
		var rotated_char: DialogicCharacter = _dialogic_characters.get(tag, null)
		if rotated_char != null and Dialogic.Portraits.is_character_joined(rotated_char):
			Dialogic.Portraits.remove_character(rotated_char)

	for tag in _joined_characters:
		if not _joined_characters[tag]:
			continue
		if not _dialogic_characters.has(tag):
			continue

		var dialogic_char: DialogicCharacter = _dialogic_characters[tag]
		var portrait: String = _sprite_states.get(tag, "neutral")
		var position_id: = _get_position_for_character(tag)
		var should_mirror: = CharacterPortraitService.should_mirror_at_position(position_id)


		if not Dialogic.Portraits.is_character_joined(dialogic_char):
			CharacterPortraitService.join_character_safe(dialogic_char, portrait, position_id, should_mirror, 0, "", "", 0.0, false, total_chars)
		elif dialogic_char.portraits.has(portrait):



			if total_chars >= 3 and total_chars <= MAX_VISIBLE_LAYOUT_CHARACTERS:
				CharacterPortraitService.reapply_group_scale(dialogic_char, position_id, total_chars)
			Dialogic.Portraits.change_character_portrait(dialogic_char, portrait)


		if Dialogic.Portraits.is_character_joined(dialogic_char):
			if total_chars == 2:
				var saved_pos: = position_id
				var char_id: = dialogic_char.resource_path
				if portraits_state.has(char_id):
					saved_pos = portraits_state[char_id].get("position_id", saved_pos)
				CharacterPortraitService.register_duo_character(dialogic_char, saved_pos, portrait)

			_apply_group_scale_deferred(dialogic_char, portrait)
			_apply_group_scale_deferred.call_deferred(dialogic_char, portrait)


	_refresh_group_layout(total_chars)
	if total_chars <= 1:
		for tag in _joined_characters:
			if not _joined_characters[tag]:
				continue
			if not _dialogic_characters.has(tag):
				continue
			var dialogic_char: DialogicCharacter = _dialogic_characters[tag]
			if dialogic_char != null and Dialogic.Portraits.is_character_joined(dialogic_char):
				CharacterPortraitService.apply_solo_scale_to_character(dialogic_char)



func _resume_wait_from_saved_line(entry: Dictionary) -> void :
	var speaker: String = entry.get("speaker", "")
	var normalized_speaker: = _normalize_speaker_tag(speaker)
	var text: String = entry.get("text", "")
	var is_narrator: bool = entry.get("is_narrator", false)

	var dialogic_char: DialogicCharacter = null
	if not is_narrator:
		dialogic_char = _get_dialogic_character_for_speaker(speaker)
	elif is_narrator:
		dialogic_char = DialogicResourceUtil.get_character_resource("narrator")

	if Dialogic.has_subsystem("Text"):
		Dialogic.Text.update_name_label(dialogic_char)
		_apply_speaker_focus_for_line(normalized_speaker, is_narrator)
		var typing_portrait: String = ""
		if not is_narrator:
			typing_portrait = str(_sprite_states.get(normalized_speaker, "neutral"))
		CharacterSpriteLoader.call("apply_typing_sound_for_dialogic_character", dialogic_char, typing_portrait)
		Dialogic.Text.update_dialog_text(text, true)
		preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree()).replay_history(entry, "narrator" if is_narrator else speaker, text)
		Dialogic.Text.show_textbox()
		Dialogic.Text.show_next_indicators()

	Dialogic.current_state = Dialogic.States.IDLE
	_is_playing = true
	_is_waiting_for_advance = true
	_current_displayed_text = text
	_show_edit_button = true
	_edit_enabled = true
	_show_interrupt_button()
	_show_edit_button_panel()

	await _wait_for_advance()

	if not _is_playing:
		Dialogic.Text.hide_next_indicators()
		return

	if RollbackManager.is_in_rollback_mode():
		Dialogic.Text.hide_next_indicators()
		return

	Dialogic.Text.hide_next_indicators()
	_play_next_line()







func _register_scene_line_with_rollback(char_name: String, char_id: String, text: String, is_narrator: bool) -> void :
	Log.d("AISceneGenerator", "_register_scene_line_with_rollback: char=%s, in_rollback=%s" % [char_name, RollbackManager.is_in_rollback_mode()])


	if RollbackManager.is_in_rollback_mode():
		Log.d("AISceneGenerator", "Skipping registration - in rollback mode")
		return


	var char_tags: Array[String] = []
	for char_data in _character_data:
		char_tags.append(char_data.tag)


	var dialogic_history_length: int = -1
	if Dialogic.has_subsystem("History"):
		dialogic_history_length = Dialogic.History.simple_history_content.size()


	var ai_data: = {
		"rollback_owner_key": _rollback_owner_key, 
		"rollback_owner_kind": get_rollback_owner_kind(), 
		"character_tags": char_tags, 
		"sprite_states": _sprite_states.duplicate(), 
		"joined_characters": _joined_characters.duplicate(), 
		"joined_character_order": _joined_character_order.duplicate(), 
		"rotated_out_tags": _rotated_out_tags.duplicate(), 
		"stage_recency": _stage_recency.duplicate(), 
		"character_name": char_name, 
		"character_id": char_id, 
		"displayed_text": text, 
		"is_narrator": is_narrator, 
		"remaining_queue": _scene_queue.duplicate(true), 
		"displayed_lines": _displayed_lines.duplicate(true), 
		"story_context": _story_context, 
		"management_context_override": _management_context_override.duplicate(true), 
		"prefill_scope": _prefill_scope, 
		"location_id": _get_current_runtime_location_id_for_save(), 
		"scene_start_location_id": _scene_start_location_id, 
		"is_scene_generated": true, 
		"dialogic_history_length": dialogic_history_length, 
		"scene_start_dialogic_history_length": _initial_dialogic_history_length, 
		"time_slot": GameState.current_time_slot, 
		"daily_visits": GameState.daily_visits, 
		"pass_time_state": GameState.capture_pass_time_rollback_state(), 
	}

	RollbackManager.register_ai_exchange(ai_data)
	Log.d("AISceneGenerator", "Registered AI line: displayed_lines=%s text='%s'" % [
		str(_displayed_lines.size()), 
		str(text)
	])



func _on_rollback_ai_state_changed(is_in_ai: bool, ai_data: Dictionary) -> void :
	Log.d("AISceneGenerator", "_on_rollback_ai_state_changed: is_in_ai=%s, is_scene_generated=%s" % [is_in_ai, ai_data.get("is_scene_generated", false)])

	if not is_in_ai:

		_hide_interrupt_button()
		_hide_edit_button()
		_reset_speaker_focus()
		return


	if not ai_data.get("is_scene_generated", false):
		_hide_interrupt_button()
		_hide_edit_button()
		return
	if not owns_rollback_snapshot(ai_data):
		_hide_interrupt_button()
		_hide_edit_button()
		_reset_speaker_focus()
		return


	_cancel_advance_wait = true
	_sync_history_view_state_from_ai_data(ai_data)
	_show_edit_button = not _current_displayed_text.is_empty()
	_edit_enabled = _show_edit_button

	if RollbackManager.is_in_rollback_mode():
		_show_interrupt_button()
	_update_action_buttons_visibility()
	var is_narrator: = bool(ai_data.get("is_narrator", false))
	var speaker_tag: = _resolve_speaker_tag_from_ai_data(ai_data)
	_apply_speaker_focus_for_line(speaker_tag, is_narrator)



func _on_rollback_snapshot_type_changed(snapshot_type: RollbackManager.SnapshotType) -> void :
	Log.d("AISceneGenerator", "_on_rollback_snapshot_type_changed: type=%s, in_rollback=%s" % [snapshot_type, RollbackManager.is_in_rollback_mode()])


	if RollbackManager.is_in_rollback_mode():
		_cancel_advance_wait = true
		if is_request_in_flight():


			_replace_ai_client()
			_request_session_id = -1
			_stop_thinking_animation()


		if _control_panel:
			_control_panel.visible = false
		var ai_data: = RollbackManager.get_current_ai_data()
		if not ai_data.is_empty() and ai_data.get("is_scene_generated", false) and owns_rollback_snapshot(ai_data):
			_sync_history_view_state_from_ai_data(ai_data)
			_show_edit_button = not _current_displayed_text.is_empty()
			_edit_enabled = _show_edit_button


			_show_interrupt_button()
			_update_action_buttons_visibility()
			var is_narrator: = bool(ai_data.get("is_narrator", false))
			var speaker_tag: = _resolve_speaker_tag_from_ai_data(ai_data)
			_apply_speaker_focus_for_line(speaker_tag, is_narrator)
		else:

			_hide_interrupt_button()
			_hide_edit_button()


func _sync_history_view_state_from_current_snapshot() -> bool:
	if not RollbackManager.is_in_rollback_mode():
		return true
	var ai_data: = RollbackManager.get_current_ai_data()
	if ai_data.is_empty() or not bool(ai_data.get("is_scene_generated", false)) or not owns_rollback_snapshot(ai_data):
		return false
	_sync_history_view_state_from_ai_data(ai_data)
	return not _current_displayed_text.is_empty()


func _sync_history_view_state_from_ai_data(ai_data: Dictionary) -> void :
	_restore_runtime_metadata_from_rollback(ai_data)
	_current_displayed_text = str(ai_data.get("displayed_text", ""))

	_displayed_lines.clear()
	for item in ai_data.get("displayed_lines", []):
		if item is Dictionary:
			_displayed_lines.append((item as Dictionary).duplicate(true))
		else:
			_displayed_lines.append(item)

	_scene_queue.clear()
	for item in ai_data.get("remaining_queue", []):
		if item is Dictionary:
			_scene_queue.append((item as Dictionary).duplicate(true))
		else:
			_scene_queue.append(item)


func _restore_runtime_metadata_from_rollback(ai_data: Dictionary) -> void :
	_story_context = str(ai_data.get("story_context", _story_context))
	_management_context_override = _sanitize_management_context_override(
		ai_data.get("management_context_override", _management_context_override)
	)
	_scene_start_location_id = str(ai_data.get("scene_start_location_id", _scene_start_location_id)).strip_edges()
	_prefill_scope = str(ai_data.get("prefill_scope", AssistantPrefill.resolve_scope("scene", _scene_start_location_id, AIStateCoordinator.is_custom_start_active())))
	_sync_current_location_from_runtime_location(str(ai_data.get("location_id", "")))

	var restored_tags: Array[String] = []
	for raw_tag in ai_data.get("character_tags", []):
		var tag: = str(raw_tag).strip_edges()
		if not tag.is_empty() and not tag in restored_tags:
			restored_tags.append(tag)
	if restored_tags.is_empty():
		return

	_character_data.clear()
	_dialogic_characters.clear()
	for tag in restored_tags:
		var char_data: = _prompt_manager.load_character(tag)
		if char_data != null:
			_character_data.append(char_data)
		var dialogic_char: = CharacterPortraitService.find_dialogic_character(tag)
		if dialogic_char != null:
			_dialogic_characters[tag] = dialogic_char
	_line_processor.set_valid_tags(restored_tags)
	_line_processor.set_known_character_tags(_get_known_character_tags())









func resume_from_history() -> bool:
	if not RollbackManager.is_in_rollback_mode():
		return false

	var ai_data: = RollbackManager.get_current_ai_data()
	if ai_data.is_empty():
		return false


	if not ai_data.get("is_scene_generated", false) or not owns_rollback_snapshot(ai_data):
		return false

	Log.d(
		"AISceneGenerator", 
		"Resuming from history (remaining_queue=%d, location_id=%s, displayed_lines=%d)" % [
			int(ai_data.get("remaining_queue", []).size()), 
			str(ai_data.get("location_id", "")), 
			int(ai_data.get("displayed_lines", []).size()), 
		]
	)

	var rollback_location_id: = str(ai_data.get("location_id", "")).strip_edges()
	var rollback_audio_state: = RollbackManager.consume_resume_audio_state()
	var rollback_audio: Dictionary = rollback_audio_state.get("channels", {}).duplicate(true)
	var authoritative_audio: = bool(rollback_audio_state.get("authoritative", false))
	var music_state: Variant = ai_data.get("music_state", {})
	if ai_data.has("music_state") and music_state is Dictionary:
		rollback_audio["music"] = (music_state as Dictionary).duplicate(true)
		authoritative_audio = true





	RollbackManager.discard_future_snapshots_from_current(false)


	RollbackManager.exit_rollback_mode()


	_session_id += 1


	_cancel_advance_wait = false
	_interrupt_requested = false

	if not rollback_location_id.is_empty() and rollback_location_id != "_timeline_driven":
		if MapManager.has_method("restore_conversation_location"):
			var location_restored: = MapManager.restore_conversation_location(rollback_location_id, 0.35, false)
			if not location_restored:
				push_warning("[AISceneGenerator] Failed to restore rollback location on resume: %s" % rollback_location_id)




	RollbackManager.restore_audio_from_snapshot(rollback_audio, authoritative_audio)




	GameState.restore_pass_time_rollback_state(ai_data)


	_restore_runtime_metadata_from_rollback(ai_data)
	_sprite_states = ai_data.get("sprite_states", {}).duplicate()
	_joined_characters = ai_data.get("joined_characters", {}).duplicate()
	_restore_joined_character_order(ai_data.get("joined_character_order", []))
	_restore_stage_rotation(ai_data.get("rotated_out_tags", []), ai_data.get("stage_recency", []))
	_displayed_lines = ai_data.get("displayed_lines", []).duplicate(true)


	_scene_queue.clear()
	var remaining: Array = ai_data.get("remaining_queue", [])
	for item in remaining:
		_scene_queue.append(item)


	_restore_sprite_states()
	var is_narrator: = bool(ai_data.get("is_narrator", false))
	var speaker_tag: = _resolve_speaker_tag_from_ai_data(ai_data)
	_apply_speaker_focus_for_line(speaker_tag, is_narrator)


	if _scene_queue.is_empty():
		Log.d("AISceneGenerator", "History resume reached queue end; showing control panel")



		_is_playing = true
		_show_control_panel()
	elif _displayed_lines.is_empty():


		Log.d("AISceneGenerator", "History resume from scene start; playing initial queued line")
		_is_playing = true
		_show_interrupt_button()
		_play_next_line()
	else:
		Log.d("AISceneGenerator", "History resume restoring interruptible wait on current line before continuing playback")
		_is_playing = true
		_show_interrupt_button()
		_resume_restored_line_playback()
	return true


func _resume_restored_line_playback() -> void :
	var should_continue: = await _wait_on_restored_history_line_before_continue()
	if should_continue:
		Log.d("AISceneGenerator", "Restored-line wait completed; continuing queued playback")
		_play_next_line()

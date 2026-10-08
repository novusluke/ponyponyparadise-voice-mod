class_name DialogicAIConversation
extends Node

const AssistantPrefill: = preload("res://scripts/api/assistant_prefill.gd")
var _prefill_scope: = "qa"




signal conversation_completed

const LocationDescriptionStorage: = preload("res://scripts/services/location_description_storage.gd")
const TouchMetrics: = preload("res://scripts/ui/touch_metrics.gd")
const TouchScrollGesture: = preload("res://scripts/ui/touch_scroll_gesture.gd")
const MAX_DYNAMIC_VISIBLE_CHARACTERS: = 6
const INPUT_SPEAKER_PLAYER: = 0
const INPUT_SPEAKER_NARRATOR: = 1
const SPEAKER_POPUP_PLAYER_NAME: = 1
const SPEAKER_POPUP_NARRATOR: = 2
const SPEAKER_POPUP_PLAYER: = 3
const REQUEST_ERROR_CANVAS_LAYER: = 101
const API_SETTINGS_FROM_ERROR_LAYER: = REQUEST_ERROR_CANVAS_LAYER + 1

const GUIDANCE_CANVAS_LAYER: = 95
const SOLO_EXPLORATION_PROMPT_MARKER: = "## Solo Exploration Mode"


var _rpg: AIRPGManager


var _panels: AIConversationPanelManager


var _manual: AIManualOverrideManager


var _stage: AIConversationStage


var _ai_client: AIConversationClient


var _prompt_manager: PromptManager


var _line_processor: DialogueLineProcessor


var _system_prompt: String = ""


var _history: Array = []


var _is_active: = false
var _rollback_owner_key: String = ""


var _dialogue_queue: Array = []


var _displayed_lines: Array = []


var _story_context: String = ""
var _story_context_revision_seen: int = -1


var _input_field: TextEdit = null
var _send_button: Button = null
var _dice_button: Button = null
var _debug_roll_option: OptionButton = null
var _input_container: Control = null

var _textbox_compact_suspend_token: = 0
var _button_row: HBoxContainer = null
var _speaker_popup: PopupMenu = null
var _player_input_display_name: String = ""
var _input_speaker_mode: int = INPUT_SPEAKER_PLAYER



var _interrupt_panel: PanelContainer = null
var _quit_panel: PanelContainer = null
var _regenerate_panel: PanelContainer = null
var _undo_panel: PanelContainer = null
var _edit_panel: PanelContainer = null
var _sleepover_request_panel: PanelContainer = null
var _sleepover_sleep_panel: PanelContainer = null
var _pass_time_panel: PanelContainer = null
var _manual_roster_button: Button = null
var _manual_location_button: Button = null
var _guidance_button: Button = null
var _debug_rand_button: Button = null
var _manual_roster_dialog_panel: PanelContainer = null
var _manual_location_dialog_panel: PanelContainer = null
var _manual_emotion_dialog_panel: PanelContainer = null
var _guidance_canvas: CanvasLayer = null
var _guidance_blocker: Control = null
var _guidance_dialog_panel: PanelContainer = null
var _guidance_text_edit: TextEdit = null
var _guidance_apply_button: Button = null
var _guidance_rewrite_button: Button = null
var _guidance_stop_setup_button: Button = null
var _request_error_canvas: CanvasLayer = null
var _end_chat_confirm_canvas: CanvasLayer = null
var _dice_result_panel: DiceResultPanel = null


var _show_interrupt_button: = false
var _show_quit_button: = false
var _show_regenerate_button: = false
var _show_edit_button: = false
var _show_sleepover_request_button: = false
var _show_sleepover_sleep_button: = false
var _show_pass_time_button: = false
var _show_manual_roster_button: = false
var _show_manual_location_button: = false


var _is_editing: = false
var _edit_text_edit: TextEdit = null
var _current_displayed_text: = ""
var _edit_dialog_panel: PanelContainer = null
var _show_interrupt_before_edit: = false
var _edit_enabled: = false
var _edit_just_closed: = false


var _interrupt_requested: = false


var _is_displaying_dialogue: = false


var _dialog_text_node: RichTextLabel = null
var _dialog_text_parent: Control = null


var _thinking_controller: ThinkingAnimationController = null


var _last_user_message: String = ""





var _regenerate_unavailable: bool = false
var _last_request_start_location_id: String = ""
var _last_request_start_music_state: Dictionary = {}
var _last_request_start_dialogic_history_size: int = -1
var _failed_request_kind: String = ""
var _failed_request_location_id: String = ""
var _failed_rpg_request: Dictionary = {}
var _failed_request_has_user_entry: = false


var _last_player_turn_speaker_name: String = ""
var _last_player_turn_narrator_mode: bool = false


var _pending_turn_guidance: String = ""
var _last_turn_guidance: String = ""


var _last_rewrite_note: String = ""
var _active_response_management_context: Dictionary = {}
var _last_request_management_context: Dictionary = {}


var _state_snapshots: Array = []
const MAX_SNAPSHOTS: = 10
const MAX_HISTORY_MESSAGES: = 256



var _is_viewing_history: = false


var _cancel_current_advance_wait: = false


var _session_id: int = 0

const SetupPrompt = preload("res://scripts/services/initial_setup_prompt.gd")
var _initial_setup: Dictionary = {}
var _initial_setup_enabled: = false
var _initial_setup_stopped: = false
var _custom_system_prompt_override: String = "":
	set(value):
		var parts: = SetupPrompt.extract(value)
		_custom_system_prompt_override = parts.base
		if parts.has("setup"):
			_initial_setup = parts.setup
			_initial_setup_enabled = not _initial_setup_stopped



var _custom_prompt_baked_tags: Array[String] = []
var _pending_sleepover_invite_request: bool = false
var _is_restoring_turn_state: = false
var _is_request_in_flight: = false



var _is_applying_manual_changes: = false


var _manual_changes_session_id: = -1


var _last_pending_enters: Array[String] = []
var _last_pending_exits: Array[String] = []
var _last_pending_step_asides: Array[String] = []
var _last_pending_location_id: String = ""







func _ready() -> void :
	add_to_group("dialogic_ai_conversation")
	_rpg = AIRPGManager.new(self)
	_panels = AIConversationPanelManager.new(self)
	_manual = AIManualOverrideManager.new(self)
	_stage = AIConversationStage.new(self)
	_ai_client = AIConversationClient.new()
	add_child(_ai_client)

	_prompt_manager = PromptManager.new()
	_line_processor = DialogueLineProcessor.new()
	_stage.dynamic_roster = DynamicCharacterRoster.new()

	_ai_client.response_received.connect(_on_ai_response_received)
	_ai_client.request_failed.connect(_on_ai_request_failed)
	_ai_client.request_started.connect(_on_ai_request_started)


	RollbackManager.ai_state_changed.connect(_on_rollback_ai_state_changed)
	RollbackManager.snapshot_type_changed.connect(_on_rollback_snapshot_type_changed)



	APIConfigManager.config_changed.connect(_on_api_config_changed)


	_thinking_controller = ThinkingAnimationController.new()
	_thinking_controller.setup(self)


func set_rollback_owner_key(owner_key: String) -> void :
	_rollback_owner_key = owner_key.strip_edges()


func get_rollback_owner_key() -> String:
	return _rollback_owner_key


func get_rollback_owner_kind() -> String:
	return "conversation"


func owns_rollback_snapshot(ai_data: Dictionary) -> bool:
	var owner_kind: = str(ai_data.get("rollback_owner_kind", "")).strip_edges()
	if not owner_kind.is_empty() and owner_kind != get_rollback_owner_kind():
		return false
	var owner_key: = str(ai_data.get("rollback_owner_key", "")).strip_edges()
	return owner_key.is_empty() or owner_key == _rollback_owner_key


func _rollback_owner_key_matches(ai_data: Dictionary) -> bool:
	var owner_key: = str(ai_data.get("rollback_owner_key", "")).strip_edges()
	return owner_key.is_empty() or owner_key == _rollback_owner_key


func _process(_delta: float) -> void :

	if _interrupt_panel and is_instance_valid(_interrupt_panel) and _interrupt_panel.is_inside_tree():
		_update_control_button_positions()


func _exit_tree() -> void :
	var voice_mod = get_tree().root.get_node_or_null("PonyVoiceMod")
	if voice_mod != null:
		voice_mod.stop()



	_session_id += 1
	_is_active = false
	if _textbox_compact_suspend_token != 0:
		UISettingsManager.resume_textbox_compact(_textbox_compact_suspend_token)
		_textbox_compact_suspend_token = 0
	_clear_manual_changes_guard()
	if _stage:
		_stage.clear_session()
	if _rpg:
		_rpg.cancel_active_roll()
	_cleanup_input_field()
	_cleanup_control_buttons()

	_edit_dialog_panel = null
	_edit_text_edit = null
	if _thinking_controller:
		_thinking_controller.cleanup()
	if _ai_client:
		_ai_client.queue_free()



func start_conversation(character_tags: Array[String], story_context: String = "", custom_system_prompt: String = "") -> void :
	if APIConfigManager.is_debug_enabled():
		print("[DialogicAIConversation] start_conversation entry active=%s tags=%s text_nodes=%d parent=%s" % [
			str(_is_active), 
			str(character_tags), 
			get_tree().get_nodes_in_group("dialogic_dialog_text").size(), 
			_dialog_text_parent.name if _dialog_text_parent else "null", 
		])
	if _is_active:
		push_warning("[DialogicAIConversation] Already in a conversation")
		return

	_stage.character_data.clear()
	_stage.dialogic_characters.clear()

	_stage.sprite_states.clear()
	_dialogue_queue.clear()
	_state_snapshots.clear()
	_last_user_message = ""
	_pending_turn_guidance = ""
	_last_turn_guidance = ""
	_current_displayed_text = ""
	_show_edit_button = false
	_is_editing = false
	_edit_just_closed = false
	_edit_enabled = false
	_story_context = story_context
	_story_context_revision_seen = -1
	_is_viewing_history = false


	_is_restoring_turn_state = false
	_is_request_in_flight = false
	_clear_manual_changes_guard()




	_cleanup_input_field()
	_stage.current_character_tags.clear()
	_initial_setup = {}
	_initial_setup_enabled = false
	_initial_setup_stopped = false
	_custom_system_prompt_override = custom_system_prompt.strip_edges()
	_prefill_scope = AIStateCoordinator.get_prefill_context()
	if _prefill_scope.is_empty():
		_prefill_scope = AssistantPrefill.resolve_scope("qa", MapManager.get_current_runtime_location_id(), AIStateCoordinator.is_custom_start_active())
	_pending_sleepover_invite_request = false
	_clear_failed_request_retry_state()
	_rpg.clear()
	var narrator_only_mode: = character_tags.is_empty() and not _effective_custom_prompt().is_empty()


	for tag in character_tags:
		var char_data: = _prompt_manager.load_character(tag)
		if char_data != null:
			_stage.character_data.append(char_data)
			if not tag in _stage.current_character_tags:
				_stage.current_character_tags.append(tag)
			var dialogic_char: = CharacterPortraitService.find_dialogic_character(tag)
			if dialogic_char:
				_stage.dialogic_characters[tag] = dialogic_char
				_stage.sprite_states[tag] = "neutral"
		else:
			push_warning("[DialogicAIConversation] Character not found: " + tag)

	if _stage.character_data.is_empty() and not narrator_only_mode:
		push_error("[DialogicAIConversation] No valid characters found")
		return


	var valid_tags: Array[String] = []
	for char_data in _stage.character_data:
		valid_tags.append(char_data.tag)
	_update_line_processor_valid_tags()
	_stage.dynamic_roster.configure(valid_tags, MAX_DYNAMIC_VISIBLE_CHARACTERS)
	if _effective_custom_prompt().is_empty():
		_custom_prompt_baked_tags = []
	else:
		_custom_prompt_baked_tags = _stage.current_character_tags.duplicate()


	_refresh_story_context_from_manager(true, false)
	if (
		APIConfigManager != null
		and APIConfigManager.is_prompt_cache_enabled()
		and AIStateCoordinator != null
		and AIStateCoordinator.is_active()
	):
		AIStateCoordinator.capture_prompt_cache_qa_story(_story_context)
	if _effective_custom_prompt().is_empty():
		_system_prompt = _prompt_manager.build_qa_prompt(_stage.character_data, _story_context)
	else:
		_system_prompt = _effective_custom_prompt()

	_is_active = true
	_stage.begin_session(_session_id, _get_joined_character_tags())
	if SleepoverSystem != null:
		SleepoverSystem.begin_qa_session(MapManager.get_current_runtime_location_id())

	if APIConfigManager.is_debug_enabled():
		print("[DialogicAIConversation] Started with: " + ", ".join(character_tags))


	RollbackManager.register_ai_conversation_start(self, character_tags)


	_find_dialog_text_node()


	_create_control_buttons()


	_show_input_in_textbox()


	_stage.refresh_group_layout(_stage.character_data.size())




func show_initial_character_portraits(tags: Array[String] = [], expected_session_id: int = -1) -> void :
	var my_session_id: = expected_session_id if expected_session_id >= 0 else _session_id
	if not is_session_current(my_session_id):
		return

	var target_tags: Array[String] = []
	if tags.is_empty():
		target_tags = _stage.current_character_tags.duplicate()
	else:
		for tag in tags:
			var normalized: = str(tag).strip_edges()
			if normalized.is_empty():
				continue
			if not normalized in target_tags:
				target_tags.append(normalized)



	for tag in target_tags:
		await _stage.ensure_character_visible(tag, true, my_session_id)
		if not is_session_current(my_session_id):
			return

	_stage.refresh_group_layout(_stage.get_total_visible_for_layout())






func end_conversation() -> void :
	if _pending_sleepover_invite_request and SleepoverSystem != null:
		SleepoverSystem.mark_sleepover_invite_failed()
	_pending_sleepover_invite_request = false
	if _is_request_in_flight:
		_ai_client.cancel_request()
	_is_request_in_flight = false
	_clear_manual_changes_guard()
	_rpg.cancel_active_roll()
	_rpg.pending_request.clear()
	_is_active = false
	_stage.clear_session()
	_is_displaying_dialogue = false
	_interrupt_requested = false
	_is_viewing_history = false
	_is_restoring_turn_state = false


	_session_id += 1
	_stop_thinking_animation()



	if _is_editing:
		_close_edit_dialog()
	_hide_input_field()
	_cleanup_input_field()
	_cleanup_control_buttons()
	_dialogue_queue.clear()
	_history.clear()
	_state_snapshots.clear()
	_pending_turn_guidance = ""
	_last_turn_guidance = ""
	_initial_setup = {}
	_initial_setup_enabled = false
	_initial_setup_stopped = false
	_custom_system_prompt_override = ""
	_custom_prompt_baked_tags = []
	_clear_failed_request_retry_state()
	if _stage.dynamic_roster != null:
		_stage.dynamic_roster.configure([], MAX_DYNAMIC_VISIBLE_CHARACTERS)
	_clear_pending_manual_changes()
	_close_request_error_dialog()
	_close_end_chat_confirm_dialog()
	_dismiss_dice_result_panel()


	_show_interrupt_button = false
	_show_edit_button = false
	_edit_enabled = false
	_show_quit_button = false
	_show_regenerate_button = false
	_show_sleepover_request_button = false
	_show_sleepover_sleep_button = false
	_show_pass_time_button = false
	_show_manual_roster_button = false
	_show_manual_location_button = false




	if not _should_defer_layout_clear_on_end():
		CharacterPortraitService.clear_scene_layout_state()
		_stage.reset_speaker_focus()


	if _dialog_text_node:
		_dialog_text_node.show()
	_prepare_dialogic_for_conversation_handoff()


	RollbackManager.register_ai_conversation_end()

	conversation_completed.emit()



func is_active() -> bool:
	return _is_active


func get_session_id() -> int:
	return _session_id


func is_session_current(expected_session_id: int) -> bool:
	return _is_active and _session_id == expected_session_id


func _prepare_dialogic_for_conversation_handoff() -> void :
	_disable_input_speaker_label_control()
	if Dialogic.Text:
		Dialogic.Text.hide_next_indicators()
		Dialogic.Text.update_name_label(null)
		Dialogic.Text.update_dialog_text("", true)
	_reset_dialogic_input_state()


func get_current_character_tags() -> Array[String]:
	return _stage.current_character_tags.duplicate()


func is_manual_character_mode_enabled() -> bool:
	return _is_manual_character_mode_enabled()


func is_manual_location_mode_enabled() -> bool:
	return _is_manual_location_mode_enabled()


func get_prompt_manager() -> PromptManager:
	return _prompt_manager




func interrupt() -> void :
	if not _is_active:
		return

	Log.d("DialogicAIConversation", "Interrupted externally")
	if _pending_sleepover_invite_request and SleepoverSystem != null:
		SleepoverSystem.mark_sleepover_invite_failed()
	_pending_sleepover_invite_request = false


	_session_id += 1
	_clear_manual_changes_guard()
	_rpg.cancel_active_roll()


	if _is_request_in_flight:
		_ai_client.cancel_request()
	_is_request_in_flight = false
	_interrupt_requested = true
	_cancel_current_advance_wait = true
	_is_displaying_dialogue = false
	_is_viewing_history = false
	_is_restoring_turn_state = false


	_stop_thinking_animation()



	if _is_editing:
		_close_edit_dialog()


	_dialogue_queue.clear()
	_history.clear()
	_pending_turn_guidance = ""
	_last_turn_guidance = ""
	_initial_setup = {}
	_initial_setup_enabled = false
	_initial_setup_stopped = false
	_custom_system_prompt_override = ""
	_custom_prompt_baked_tags = []
	if _stage.dynamic_roster != null:
		_stage.dynamic_roster.configure([], MAX_DYNAMIC_VISIBLE_CHARACTERS)
	_clear_pending_manual_changes()


	_hide_input_field()
	_cleanup_input_field()
	_cleanup_control_buttons()
	_close_request_error_dialog()
	_close_end_chat_confirm_dialog()
	_dismiss_dice_result_panel()


	_show_interrupt_button = false
	_show_edit_button = false
	_edit_enabled = false
	_current_displayed_text = ""
	_show_quit_button = false
	_show_regenerate_button = false
	_show_sleepover_request_button = false
	_show_sleepover_sleep_button = false
	_show_pass_time_button = false
	_show_manual_roster_button = false
	_show_manual_location_button = false


	CharacterPortraitService.clear_scene_layout_state()
	_stage.reset_speaker_focus()


	if _dialog_text_node:
		_dialog_text_node.show()


	_is_active = false
	_stage.clear_session()











func _input(event: InputEvent) -> void :
	if not _is_active:
		return

	if event.is_action_pressed("ui_cancel"):



		get_viewport().set_input_as_handled()
		if _is_editing:
			_close_edit_dialog()
			return
		if _is_guidance_dialog_visible():
			_hide_guidance_dialog()
			return
		if _manual != null and _manual.is_any_dialog_visible():
			_manual.hide_panels()
			return
		if _request_error_canvas != null and is_instance_valid(_request_error_canvas):

			_close_request_error_dialog()
			return
		if _end_chat_confirm_canvas != null and is_instance_valid(_end_chat_confirm_canvas):
			_close_end_chat_confirm_dialog()
			return
		_show_end_chat_confirm_dialog()








func _find_dialog_text_node() -> void :
	var text_nodes = get_tree().get_nodes_in_group("dialogic_dialog_text")
	if not text_nodes.is_empty():
		_dialog_text_node = text_nodes[0]
		_dialog_text_parent = _dialog_text_node.get_parent()


func _set_dialogic_layout_visible(visible: bool) -> void :
	if not Dialogic.has_subsystem("Styles"):
		return
	if not Dialogic.Styles.has_active_layout_node():
		return
	var layout_node: = Dialogic.Styles.get_layout_node()
	if layout_node == null:
		return
	if visible:
		layout_node.show()
	else:
		layout_node.hide()


func _should_defer_layout_clear_on_end() -> bool:
	return AIStateCoordinator.is_active() and not AIStateCoordinator.get_location_id().is_empty()


func _register_restore_character_tag(raw_tag: String) -> void :
	var tag: = str(raw_tag).strip_edges()
	if tag.is_empty():
		return

	var already_loaded: = _stage.dialogic_characters.has(tag)
	if not already_loaded:
		var char_data: = _prompt_manager.load_character(tag)
		if char_data:
			_stage.character_data.append(char_data)
			var dialogic_char: = CharacterPortraitService.find_dialogic_character(tag)
			if dialogic_char:
				_stage.dialogic_characters[tag] = dialogic_char
		else:
			var fallback_dialogic_char: = CharacterPortraitService.find_dialogic_character(tag)
			if fallback_dialogic_char:
				_stage.dialogic_characters[tag] = fallback_dialogic_char

	if not _stage.current_character_tags.has(tag):
		_stage.current_character_tags.append(tag)


func _is_dynamic_character_mode_enabled() -> bool:
	return (
		GameState.current_mode == GameState.Mode.SANDBOX
		and APIConfigManager != null
		and _mode_allows_dynamic_management(APIConfigManager.get_character_management_mode())
	)


func _is_dynamic_location_mode_enabled() -> bool:
	return (
		GameState.current_mode == GameState.Mode.SANDBOX
		and APIConfigManager != null
		and _mode_allows_dynamic_management(APIConfigManager.get_location_management_mode())
	)


func _is_manual_character_mode_enabled() -> bool:
	return (
		GameState.current_mode == GameState.Mode.SANDBOX
		and APIConfigManager != null
		and _mode_allows_manual_controls(APIConfigManager.get_character_management_mode())
	)


func _is_manual_location_mode_enabled() -> bool:
	return (
		GameState.current_mode == GameState.Mode.SANDBOX
		and APIConfigManager != null
		and _mode_allows_manual_controls(APIConfigManager.get_location_management_mode())
	)


func _mode_allows_dynamic_management(mode: String) -> bool:
	return mode in [
		APIConfigData.MANAGEMENT_MODE_DYNAMIC, 
		APIConfigData.MANAGEMENT_MODE_DYNAMIC_PLUS, 
	]


func _mode_allows_manual_controls(mode: String) -> bool:
	return mode in [
		APIConfigData.MANAGEMENT_MODE_MANUAL, 
		APIConfigData.MANAGEMENT_MODE_DYNAMIC_PLUS, 
	]


func _clear_pending_manual_changes() -> void :
	_manual.clear_pending()


	_last_pending_enters.clear()
	_last_pending_exits.clear()
	_last_pending_step_asides.clear()
	_last_pending_location_id = ""


func _begin_manual_changes(session_id: int) -> void :
	_manual_changes_session_id = session_id
	_is_applying_manual_changes = true


func _finish_manual_changes(session_id: int) -> void :
	if _manual_changes_session_id != session_id:
		return
	_manual_changes_session_id = -1
	_is_applying_manual_changes = false


func _clear_manual_changes_guard() -> void :
	_manual_changes_session_id = -1
	_is_applying_manual_changes = false


func _is_rpg_mode_enabled() -> bool:
	return _rpg.is_rpg_mode_enabled()


func _has_active_persona_for_rpg() -> bool:
	return _rpg.has_active_persona()


func _get_sleepover_character_tags() -> Array[String]:
	var tags: Array[String] = []
	for char_data in _stage.character_data:
		var tag: = str(char_data.tag).strip_edges().to_lower()
		if tag.is_empty():
			continue
		if not tag in tags:
			tags.append(tag)
	return tags


func _get_sleepover_location_id() -> String:
	var location: LocationData = MapManager.get_current_location()
	if location == null:
		return MapManager.get_current_runtime_location_id()
	return location.id


func _resolve_sleepover_location_id(tags: Array[String]) -> String:
	if SleepoverSystem == null:
		return ""
	var current_location_id: = _get_sleepover_location_id()
	var initial_location_id: = SleepoverSystem.qa_session_start_location_id
	if SleepoverSystem.has_method("resolve_sleepover_location"):
		return str(SleepoverSystem.resolve_sleepover_location(current_location_id, tags, initial_location_id)).strip_edges()
	if SleepoverSystem.can_sleepover(current_location_id, tags, initial_location_id):
		return current_location_id
	return ""


func _can_show_sleepover_request_action() -> bool:
	if SleepoverSystem == null:
		return false
	if RollbackManager.is_in_rollback_mode() or _is_viewing_history:
		return false

	if not _show_regenerate_button:
		return false
	var tags: = _get_sleepover_character_tags()
	if tags.is_empty():
		return false
	var location_id: = _resolve_sleepover_location_id(tags)
	if location_id.is_empty():
		return false
	if SleepoverSystem.sleepover_morning or SleepoverSystem.nighttime_conversation_active:
		return false
	return ( not SleepoverSystem.sleepover_planned) or SleepoverSystem.sleepover_error_recovery


func _can_show_sleepover_sleep_action() -> bool:
	if SleepoverSystem == null:
		return false
	if GameState.current_mode != GameState.Mode.SANDBOX:
		return false
	if RollbackManager.is_in_rollback_mode() or _is_viewing_history:
		return false

	if not _show_regenerate_button:
		return false
	if SleepoverSystem.sleepover_morning or SleepoverSystem.nighttime_conversation_active:
		return false
	if SleepoverSystem.sleepover_error_recovery:
		return false
	return SleepoverSystem.sleepover_planned


func _refresh_sleepover_button_state() -> void :
	_show_sleepover_request_button = _can_show_sleepover_request_action()
	_show_sleepover_sleep_button = _can_show_sleepover_sleep_action()
	_show_pass_time_button = _can_show_pass_time_action()





func _can_show_pass_time_action() -> bool:
	if UISettingsManager == null or not UISettingsManager.get_qa_pass_time_enabled():
		return false
	if GameState == null or GameState.current_mode != GameState.Mode.SANDBOX:
		return false
	if GameState.current_time_slot != 0:
		return false
	if RollbackManager.is_in_rollback_mode() or _is_viewing_history:
		return false



	if SleepoverSystem != null and (SleepoverSystem.sleepover_morning or SleepoverSystem.nighttime_conversation_active):
		return false
	return true


func _on_pass_time_pressed() -> void :
	if _is_request_in_flight or _is_applying_manual_changes or not _can_show_pass_time_action():
		return
	if not GameState.pass_to_afternoon():
		return



	var note: = "Time passes — the morning slips away, and the afternoon settles in."
	_history.append({
		"role": "user", 
		"content": "Narrator: %s" % note
	})
	AIDialogueShared.store_dialogic_history_entry(note, null, true)
	_refresh_sleepover_button_state()
	_update_button_visibility()


func _capture_request_start_state(existing_user_turn_in_dialogic_history: bool = false) -> void :
	_last_request_start_location_id = MapManager.get_current_runtime_location_id()
	_last_request_start_music_state = _get_current_music_state_for_rollback()
	_last_request_start_dialogic_history_size = _get_dialogic_history_size_for_request_start(existing_user_turn_in_dialogic_history)


func _get_dialogic_history_size_for_request_start(existing_user_turn_in_dialogic_history: bool = false) -> int:
	if not Dialogic.has_subsystem("History"):
		return -1

	var current_size: = Dialogic.History.simple_history_content.size()
	if not existing_user_turn_in_dialogic_history or current_size <= 0:
		return current_size

	var last_entry: Dictionary = Dialogic.History.simple_history_content[current_size - 1]
	if _is_player_dialogic_history_entry(last_entry):
		return current_size - 1

	return current_size


func _is_player_dialogic_history_entry(entry: Dictionary) -> bool:
	if str(entry.get("event_type", "")).strip_edges() != "Text":
		return false

	var character_name: = str(entry.get("character", "")).strip_edges()
	if character_name.is_empty():
		return false

	return _is_player_character_name(character_name)


func _is_player_character_name(character_name: String) -> bool:
	var normalized: = character_name.strip_edges()
	if normalized.is_empty():
		return false
	if normalized == "Player":
		return true
	if not _player_input_display_name.strip_edges().is_empty() and normalized == _player_input_display_name.strip_edges():
		return true

	var player_char: DialogicCharacter = DialogicResourceUtil.get_character_resource("player")
	if player_char and not player_char.display_name.strip_edges().is_empty():
		return normalized == player_char.display_name.strip_edges()

	return false


func _restore_location_for_regenerate(location_id: String, update_music: bool = false, context: String = "regenerate") -> void :
	var target_id: = location_id.strip_edges()
	if target_id.is_empty():
		return
	if not MapManager.has_method("restore_conversation_location"):
		return


	if not MapManager.restore_conversation_location(target_id, 0.35, update_music):
		push_warning("[DialogicAIConversation] Failed to restore location for %s: %s" % [context, target_id])
		return
	_last_request_start_location_id = target_id



func _find_rollback_history(node: Node) -> Node:
	if node.get_script():
		var script_path = node.get_script().resource_path
		if script_path.ends_with("rollback_history.gd"):
			return node
	for child in node.get_children():
		var found = _find_rollback_history(child)
		if found:
			return found
	return null







func _get_base_system_prompt(current_user_text: String = "") -> String:
	_refresh_story_context_from_manager()
	if not _effective_custom_prompt().is_empty():
		_system_prompt = _build_custom_system_prompt_with_story_context(
			_effective_custom_prompt(), 
			_is_solo_exploration_custom_prompt()
		)


		var added_sheets: = _prompt_manager.build_added_character_sheets_section(
			_get_characters_missing_from_custom_prompt()
		)
		if not added_sheets.is_empty():
			_system_prompt = "%s\n\n%s" % [_system_prompt, added_sheets]
		return _system_prompt

	_system_prompt = _prompt_manager.build_qa_prompt(
		_stage.character_data, 
		_story_context, 
		_get_current_location_context_description(), 
		current_user_text
	)
	return _system_prompt


func _effective_custom_prompt() -> String:
	if _initial_setup_enabled and not _initial_setup.is_empty():
		return (_custom_system_prompt_override + "\n\n" + str(_initial_setup.text)).strip_edges()
	return _custom_system_prompt_override


func _get_initial_setup_section_start() -> int:
	return 0 if _initial_setup_enabled and not _initial_setup.is_empty() else -1


func _refresh_initial_setup_button() -> void :
	if _guidance_stop_setup_button != null:
		_guidance_stop_setup_button.visible = _get_initial_setup_section_start() >= 0


func _on_stop_sending_initial_setup_pressed() -> void :
	if not _initial_setup_enabled: return
	_initial_setup_enabled = false
	_initial_setup_stopped = true
	_system_prompt = ""
	_refresh_initial_setup_button()


func _restore_initial_setup(state: Dictionary) -> void :
	var stopped: = _initial_setup_stopped or bool(state.get("initial_setup_stopped", false))
	var parts: Dictionary
	if state.has("initial_setup"):
		parts = {"base": state.get("custom_system_prompt_override", ""), "setup": state.initial_setup}
	else:
		parts = SetupPrompt.migrate_legacy(str(state.get("custom_system_prompt_override", "")))
	_custom_system_prompt_override = str(parts.base)
	_initial_setup = parts.get("setup", {}).duplicate(true)
	_initial_setup_stopped = stopped or bool(parts.get("stopped", false))
	_initial_setup_enabled = not _initial_setup_stopped and bool(state.get("initial_setup_enabled", not _initial_setup.is_empty()))
	_system_prompt = ""
	_refresh_initial_setup_button()


func _get_characters_missing_from_custom_prompt() -> Array[CharacterData]:
	var added: Array[CharacterData] = []
	for char_data in _stage.character_data:
		if char_data == null:
			continue
		if char_data.tag in _custom_prompt_baked_tags:
			continue
		added.append(char_data)
	return added


func _build_request_system_prompt(
	manual_instruction: String = "", 
	management_context: Dictionary = {}, 
	current_user_text: String = "", 
	turn_guidance: String = "", 
	rewrite_note: String = ""
) -> String:
	return _build_request_system_prompt_from_base(
		_get_base_system_prompt(current_user_text), 
		manual_instruction, 
		_effective_custom_prompt().is_empty(), 
		management_context, 
		turn_guidance, 
		rewrite_note
	)


func _build_request_system_prompt_from_base(
	base_system_prompt: String, 
	manual_instruction: String = "", 
	base_includes_location_context: bool = false, 
	management_context: Dictionary = {}, 
	turn_guidance: String = "", 
	rewrite_note: String = ""
) -> String:
	return _prompt_manager.build_request_system_prompt_from_base(
		base_system_prompt, 
		manual_instruction, 
		base_includes_location_context, 
		management_context, 
		_stage.character_data, 
		_get_roster_active_tags(), 
		turn_guidance, 
		rewrite_note
	)




func _build_request_prompt_data(
	manual_instruction: String = "", 
	management_context: Dictionary = {}, 
	current_user_text: String = "", 
	turn_guidance: String = "", 
	rewrite_note: String = ""
) -> Dictionary:
	if APIConfigManager == null or not APIConfigManager.is_prompt_cache_enabled():
		return {
			"system": _build_request_system_prompt(manual_instruction, management_context, current_user_text, turn_guidance, rewrite_note), 
			"runtime": "", 
			"family": _get_conversation_cache_family(), 
		}

	_refresh_story_context_from_manager()
	if AIStateCoordinator != null and AIStateCoordinator.is_active():


		AIStateCoordinator.capture_prompt_cache_qa_story(_story_context)
	var session_prompt: = _prompt_manager.build_interactive_cache_session_prompt(
		PromptManager.CACHE_OPERATION_QA
	)
	var stable_system: = str(session_prompt.get("system", ""))
	var runtime_sections: Array[String] = []
	var base_includes_location_context: = false
	var qa_sections: = _prompt_manager.build_qa_prompt_sections(
		_stage.character_data, 
		_story_context, 
		_get_current_location_context_description(), 
		current_user_text
	)
	var qa_runtime: = str(qa_sections.get("runtime", ""))
	if not qa_runtime.is_empty():
		runtime_sections.append(qa_runtime)
	var live_contract_override: = str(session_prompt.get("runtime_override", "")).strip_edges()
	if not live_contract_override.is_empty():
		runtime_sections.append(live_contract_override)
	if AIStateCoordinator != null and AIStateCoordinator.is_active():
		var story_update: = AIStateCoordinator.get_prompt_cache_runtime_story_update(_story_context)
		if not story_update.is_empty():
			runtime_sections.append("## Story Context Update\n" + story_update)
	base_includes_location_context = true
	if not _effective_custom_prompt().is_empty():
		runtime_sections.append(
			"## Custom Q&A System Override (Supersedes Conflicting Q&A Contract Text)\n"
			+ _effective_custom_prompt().strip_edges()
		)

	var request_runtime: = _prompt_manager.build_request_runtime_prompt(
		manual_instruction, 
		base_includes_location_context, 
		management_context, 
		_stage.character_data, 
		_get_roster_active_tags(), 
		turn_guidance, 
		rewrite_note
	)
	if not request_runtime.is_empty():
		runtime_sections.append(request_runtime)
	_system_prompt = stable_system
	return {
		"system": stable_system, 
		"runtime": "\n\n".join(runtime_sections), 
		"family": AIConversationClient.INTERACTIVE_CACHE_FAMILY, 
	}


func _build_sleepover_request_prompt_data(
	location_id: String, 
	tags: Array[String], 
	manual_instruction: String, 
	management_context: Dictionary, 
	turn_guidance: String = "", 
	rewrite_note: String = ""
) -> Dictionary:
	if APIConfigManager == null or not APIConfigManager.is_prompt_cache_enabled():
		var full_prompt: = _build_sleepover_request_base_prompt(location_id, tags)
		return {
			"system": _build_request_system_prompt_from_base(
				full_prompt, 
				manual_instruction, 
				false, 
				management_context, 
				turn_guidance, 
				rewrite_note
			), 
			"runtime": "", 
			"prefill_scope": "sleepover", 
			"family": "sleepover-invite", 
		}

	_refresh_story_context_from_manager()
	var session_prompt: = _prompt_manager.build_interactive_cache_session_prompt()
	var stable_system: = str(session_prompt.get("system", ""))
	var runtime_sections: Array[String] = [
		"## Selected Operation\nSleepover Invitation", 
		"## Sleepover Operation Instructions\n" + SleepoverSystem.get_sleepover_prompt(location_id, tags), 
		"## Story Context Source\nUse the trusted story-context messages and conversation history before this request.", 
	]
	var request_runtime: = _prompt_manager.build_request_runtime_prompt(
		manual_instruction, 
		false, 
		management_context, 
		_stage.character_data, 
		_get_roster_active_tags(), 
		turn_guidance, 
		rewrite_note
	)
	if not request_runtime.is_empty():
		runtime_sections.append(request_runtime)
	return {
		"system": stable_system, 
		"runtime": "\n\n".join(runtime_sections), 
		"prefill_scope": "sleepover", 
		"family": AIConversationClient.INTERACTIVE_CACHE_FAMILY, 
	}


func _get_conversation_cache_family() -> String:
	if APIConfigManager != null and APIConfigManager.is_prompt_cache_enabled():
		return AIConversationClient.INTERACTIVE_CACHE_FAMILY
	if not _effective_custom_prompt().is_empty():
		return "qa-custom-" + _effective_custom_prompt().sha256_text().substr(0, 12)
	if GameState != null and GameState.current_mode == GameState.Mode.SANDBOX:
		return "qa-sandbox"
	return "qa-story"


func _ask_with_prompt_data(prompt_data: Dictionary, user_message: String) -> void :
	var context_history: = _get_context_history()
	if (
		APIConfigManager != null
		and APIConfigManager.is_prompt_cache_enabled()
		and AIStateCoordinator != null
		and AIStateCoordinator.is_active()
	):
		context_history = (
			AIStateCoordinator.get_prompt_cache_story_messages(true)
			+ context_history
		)
	_ai_client.ask(
		str(prompt_data.get("system", "")), 
		user_message, 
		context_history, 
		-1.0, 
		false, 
		true, 
		str(prompt_data.get("family", "qa")), 
		str(prompt_data.get("runtime", "")), 
		str(prompt_data.get("prefill_scope", _prefill_scope))
	)


func _get_roster_active_tags() -> Array:
	return _stage.dynamic_roster.get_active_tags() if _stage.dynamic_roster != null else []


func _build_rpg_roll_system_prompt(
	action_text: String, 
	roll: int, 
	manual_instruction: String = "", 
	management_context: Dictionary = {}, 
	turn_guidance: String = "", 
	rewrite_note: String = ""
) -> String:
	var prompt_builder: = func(instruction: String) -> String:
		return _build_request_system_prompt(instruction, management_context, action_text, turn_guidance, rewrite_note)
	return _rpg.build_rpg_roll_system_prompt(action_text, roll, manual_instruction, prompt_builder)


func _build_rpg_roll_prompt_data(
	action_text: String, 
	roll: int, 
	manual_instruction: String = "", 
	management_context: Dictionary = {}, 
	turn_guidance: String = "", 
	rewrite_note: String = ""
) -> Dictionary:
	if APIConfigManager == null or not APIConfigManager.is_prompt_cache_enabled():
		return {
			"system": _build_rpg_roll_system_prompt(action_text, roll, manual_instruction, management_context, turn_guidance, rewrite_note), 
			"runtime": "", 
			"prefill_scope": "rpg", 
			"family": "rpg", 
		}

	var base_prompt_data: = _build_request_prompt_data(
		manual_instruction, 
		management_context, 
		action_text, 
		turn_guidance, 
		rewrite_note
	)
	var rpg_session_prompt: = _prompt_manager.build_interactive_cache_session_prompt(
		PromptManager.CACHE_OPERATION_RPG
	)
	var runtime_base: = str(base_prompt_data.get("runtime", "")).strip_edges()
	var live_rpg_contract_override: = str(
		rpg_session_prompt.get("runtime_override", "")
	).strip_edges()
	if not live_rpg_contract_override.is_empty():
		runtime_base = "%s\n\n%s" % [runtime_base, live_rpg_contract_override]
	var rpg_sections: = _rpg.build_rpg_roll_prompt_sections(
		action_text, 
		roll, 
		str(rpg_session_prompt.get("system", base_prompt_data.get("system", ""))), 
		runtime_base
	)
	return {
		"system": str(rpg_sections.get("system", "")), 
		"runtime": str(rpg_sections.get("runtime", "")), 
		"prefill_scope": "rpg", 
		"family": AIConversationClient.INTERACTIVE_CACHE_FAMILY, 
	}


func _build_sleepover_request_base_prompt(location_id: String, tags: Array[String]) -> String:
	_refresh_story_context_from_manager()
	var base_prompt: = SleepoverSystem.get_sleepover_prompt(location_id, tags)
	return _prompt_manager.build_sleepover_request_prompt(base_prompt, _story_context)


func _build_custom_system_prompt_with_story_context(
	base_prompt: String, 
	include_player_persona: bool = false
) -> String:
	var player_persona_context: = ""
	if include_player_persona:
		player_persona_context = _prompt_manager.get_player_persona_context()
	return _prompt_manager.build_custom_system_prompt_with_story_context(
		base_prompt, 
		_story_context, 
		player_persona_context
	)


func _is_solo_exploration_custom_prompt() -> bool:
	return _custom_system_prompt_override.contains(SOLO_EXPLORATION_PROMPT_MARKER)


func _get_current_location_context_description() -> String:
	var current_location: LocationData = MapManager.get_current_location()
	if current_location == null:
		return ""
	return LocationDescriptionStorage.get_effective_description(current_location)


func _get_story_summary_context_revision() -> int:
	if StorySummaryManager == null or not StorySummaryManager.has_method("get_effective_context_revision"):
		return -1
	return int(StorySummaryManager.get_effective_context_revision())


func _refresh_story_context_from_manager(force: bool = false, invalidate_live_history: bool = true) -> void :
	if StorySummaryManager == null:
		return

	var current_revision: = _get_story_summary_context_revision()
	var revision_changed: = (
		not force
		and invalidate_live_history
		and _story_context_revision_seen >= 0
		and current_revision >= 0
		and current_revision != _story_context_revision_seen
	)

	if force or revision_changed or _story_context.is_empty():
		_story_context = StorySummaryManager.build_active_context()

	if current_revision >= 0:
		_story_context_revision_seen = current_revision

	if revision_changed:
		_invalidate_live_history_for_context_revision_change()


func _maybe_trigger_auto_story_summary() -> void :
	if StorySummaryManager == null or _ai_client == null:
		return
	if not StorySummaryManager.has_method("notify_estimated_context_tokens"):
		return
	if not _ai_client.has_method("get_last_budget_info"):
		return

	var budget_info: Dictionary = _ai_client.get_last_budget_info()
	if budget_info.is_empty():
		return

	var estimated_tokens: = int(budget_info.get("estimated_input_tokens_before", 0))
	StorySummaryManager.notify_estimated_context_tokens(estimated_tokens)


func _invalidate_live_history_for_context_revision_change() -> void :
	_history.clear()
	_state_snapshots.clear()
	_last_user_message = ""
	_show_regenerate_button = false
	_pending_sleepover_invite_request = false
	_rpg.last_request.clear()
	_rpg.pending_request.clear()
	_clear_failed_request_retry_state()


func _apply_pending_manual_changes(expected_session_id: int = -1) -> String:
	var session_id: = expected_session_id if expected_session_id >= 0 else _session_id
	if not is_session_current(session_id):
		return ""

	var owned_enters: Array[String] = _manual.pending_enters.duplicate()
	var owned_exits: Array[String] = _manual.pending_exits.duplicate()
	var owned_step_asides: Array[String] = _manual.pending_step_asides.duplicate()
	var owned_location_id: = _manual.pending_location_id
	_last_pending_enters = owned_enters.duplicate()
	_last_pending_exits = owned_exits.duplicate()
	_last_pending_step_asides = owned_step_asides.duplicate()
	_last_pending_location_id = owned_location_id

	if not _manual.has_pending_changes():
		return ""

	var applied_lines: Array[String] = []
	_begin_manual_changes(session_id)



	_manual.clear_pending()

	if _is_manual_character_mode_enabled():
		await _stage.apply_batch_roster_changes(
			owned_enters, 
			owned_exits, 
			owned_step_asides, 
			session_id
		)
		if not is_session_current(session_id):
			_finish_manual_changes(session_id)
			return ""

		if not owned_enters.is_empty():
			applied_lines.append("Characters entered: %s." % ", ".join(owned_enters))
		if not owned_exits.is_empty():
			applied_lines.append("Characters exited: %s." % ", ".join(owned_exits))
		if not owned_step_asides.is_empty():
			applied_lines.append("Characters stepped aside: %s." % ", ".join(owned_step_asides))




	if _is_manual_location_mode_enabled() and not owned_location_id.is_empty():
		var location_id: String = owned_location_id
		var queued_loc: LocationData = LocationDatabase.get_location(location_id)
		if APIConfigManager.is_debug_enabled():
			if queued_loc != null:
				print("[DialogicAIConversation] Applying queued manual location: %s (%s)" % [queued_loc.display_name, location_id])
			else:
				print("[DialogicAIConversation] Applying queued manual location: %s (not found in database)" % location_id)
		if _apply_runtime_location_change(location_id):
			var loc: LocationData = LocationDatabase.get_location(location_id)
			var display_name: String = location_id
			if loc != null and not loc.display_name.is_empty():
				display_name = loc.display_name
			applied_lines.append("Location changed to %s (%s)." % [display_name, location_id])
	if not is_session_current(session_id):
		_finish_manual_changes(session_id)
		return ""

	_finish_manual_changes(session_id)
	return _manual.build_instruction_lines(applied_lines)


func _build_effective_request_management_context() -> Dictionary:
	var context: = AICommandValidator.get_runtime_management_context()
	var character_mode: = str(context.get("character_mode", AICommandValidator.MODE_OFF))
	var location_mode: = str(context.get("location_mode", AICommandValidator.MODE_OFF))

	if character_mode == APIConfigData.MANAGEMENT_MODE_DYNAMIC_PLUS:
		character_mode = (
			AICommandValidator.MODE_MANUAL
			if _manual.has_pending_character_changes()
			else AICommandValidator.MODE_DYNAMIC
		)
	if location_mode == APIConfigData.MANAGEMENT_MODE_DYNAMIC_PLUS:
		location_mode = (
			AICommandValidator.MODE_MANUAL
			if _manual.has_pending_location_change()
			else AICommandValidator.MODE_DYNAMIC
		)

	return {
		"character_mode": character_mode, 
		"location_mode": location_mode, 
		"sandbox_mode": bool(context.get("sandbox_mode", false)), 
	}


func _remember_request_management_context(context: Dictionary) -> void :
	_last_request_management_context = context.duplicate(true)
	_active_response_management_context = context.duplicate(true)


func _restore_request_management_context(raw_context: Variant) -> void :
	_last_request_management_context.clear()
	_active_response_management_context.clear()
	if raw_context is Dictionary and not (raw_context as Dictionary).is_empty():
		_last_request_management_context = AICommandValidator.get_runtime_management_context(raw_context as Dictionary)
		_active_response_management_context = _last_request_management_context.duplicate(true)


func _get_regenerate_management_context() -> Dictionary:
	if not _last_request_management_context.is_empty():
		_active_response_management_context = _last_request_management_context.duplicate(true)
		return _last_request_management_context.duplicate(true)
	var context: = _build_effective_request_management_context()
	_remember_request_management_context(context)
	return context


func _build_valid_tags() -> Array[String]:
	var valid_tags: Array[String] = []

	for raw_tag in _stage.current_character_tags:
		var tag: = str(raw_tag).strip_edges()
		if tag.is_empty():
			continue
		if not tag in valid_tags:
			valid_tags.append(tag)

	if _stage.dynamic_roster != null:
		for tag in _stage.dynamic_roster.get_active_tags():
			if tag.is_empty():
				continue
			if not tag in valid_tags:
				valid_tags.append(tag)

	return valid_tags


func _update_line_processor_valid_tags() -> void :
	_line_processor.set_valid_tags(_build_valid_tags())
	_line_processor.set_known_character_tags(_get_known_character_tags())


func _get_known_character_tags() -> Array[String]:
	var tags: Array[String] = []
	if CharacterSpriteLoader == null:
		return tags
	if CharacterSpriteLoader.has_method("is_loaded") and not CharacterSpriteLoader.is_loaded():
		CharacterSpriteLoader.load_all_characters()
	for raw_tag in CharacterSpriteLoader.get_all_tags():
		var tag: = str(raw_tag).strip_edges().to_lower()
		if tag.is_empty() or tag in tags:
			continue
		tags.append(tag)
	return tags



func _get_context_history() -> Array:
	var context: Array = []
	for i in range(_history.size() - 1):
		context.append(_history[i])
	return context


func _trim_conversation_history() -> void :
	if _history.size() <= MAX_HISTORY_MESSAGES:
		return
	var remove_count: = _history.size() - MAX_HISTORY_MESSAGES

	if remove_count % 2 != 0:
		remove_count += 1
	remove_count = mini(remove_count, _history.size() - 2)
	if remove_count <= 0:
		return
	_history = _history.slice(remove_count)
	for snapshot in _state_snapshots:
		if snapshot is Dictionary:
			snapshot["history_size"] = maxi(0, int(snapshot.get("history_size", 0)) - remove_count)


func _migrate_legacy_context_override_entries_from_state(data: Dictionary) -> void :
	if StorySummaryManager == null or not StorySummaryManager.has_method("migrate_legacy_context_override_entries"):
		return
	var raw_entries: Variant = data.get("context_override_entries", [])
	if not (raw_entries is Array) or (raw_entries as Array).is_empty():
		return
	var migration_result: Variant = StorySummaryManager.migrate_legacy_context_override_entries((raw_entries as Array).duplicate(true))
	if migration_result is Dictionary and bool((migration_result as Dictionary).get("migrated", false)):
		Log.info("DialogicAIConversation", "Migrated legacy context overrides (real_ops=%d cosmetic=%d ambiguous=%d)" % [
			int((migration_result as Dictionary).get("real_ops_created", 0)), 
			int((migration_result as Dictionary).get("cosmetic_overrides_created", 0)), 
			int((migration_result as Dictionary).get("ambiguous_entries", 0)), 
		])


func _summarize_validation_errors(errors: Array[String]) -> String:
	if errors.is_empty():
		return ""

	var unknown_tags: Array[String] = []
	var blocked_character_cmd: = false
	var blocked_location_cmd: = false
	var invalid_command_format: = false

	for err in errors:
		var text: = str(err)
		if text.contains("Unknown character tag"):
			var first_quote: = text.find("'")
			var second_quote: = text.find("'", first_quote + 1) if first_quote >= 0 else -1
			if first_quote >= 0 and second_quote > first_quote:
				var tag: = text.substr(first_quote + 1, second_quote - first_quote - 1)
				if not tag.is_empty() and not unknown_tags.has(tag):
					unknown_tags.append(tag)
		elif text.contains("Character command"):
			blocked_character_cmd = true
		elif text.contains("Location command"):
			blocked_location_cmd = true
		elif text.contains("Invalid"):
			invalid_command_format = true

	var parts: Array[String] = []
	if blocked_character_cmd:
		parts.append("Character command dropped (sandbox + dynamic required)")
	if blocked_location_cmd:
		parts.append("Location command dropped (sandbox + dynamic required)")
	if invalid_command_format:
		parts.append("Malformed command dropped")
	if not unknown_tags.is_empty():
		parts.append("Unknown tags dropped: %s" % ", ".join(unknown_tags))

	if parts.is_empty():
		return "Some AI lines were dropped due to validation."
	return " | ".join(parts)


func _summarize_unknown_lines(lines: Array[String]) -> String:
	if lines.is_empty():
		return ""

	var preview: Array[String] = []
	for i in range(mini(2, lines.size())):
		var sample: = str(lines[i]).strip_edges()
		if sample.length() > 60:
			sample = sample.substr(0, 60) + "..."
		preview.append(sample)

	var label: = "%d line(s) skipped for bad format" % lines.size()
	if preview.is_empty():
		return label
	return "%s: %s" % [label, " / ".join(preview)]







func _clear_failed_request_retry_state() -> void :
	_failed_request_kind = ""
	_failed_request_location_id = ""
	_failed_rpg_request.clear()
	_failed_request_has_user_entry = false
	_regenerate_unavailable = false
	_last_rewrite_note = ""


func _can_retry_failed_request() -> bool:
	match _failed_request_kind:
		"rpg":
			return not _failed_rpg_request.is_empty()
		"standard", "sleepover_invite":
			return not _last_user_message.is_empty()
	return false


func _on_retry_failed_request_pressed() -> void :
	if not _can_retry_failed_request():
		return

	var retry_kind: = _failed_request_kind
	var retry_location_id: = _failed_request_location_id
	var retry_text: = _last_user_message
	var retry_guidance: = _capture_turn_guidance_for_redo()
	var retry_rewrite_note: = _last_rewrite_note
	var failed_rpg_request: = _failed_rpg_request.duplicate(true)
	var retry_has_user_entry: = _failed_request_has_user_entry


	var saved_request_start_dialogic_size: = _last_request_start_dialogic_history_size
	_clear_failed_request_retry_state()

	_last_rewrite_note = retry_rewrite_note

	_interrupt_requested = false
	_cancel_current_advance_wait = false
	_is_viewing_history = false

	if retry_kind == "rpg" and failed_rpg_request.is_empty():
		return
	if retry_kind != "rpg" and retry_text.is_empty():
		return

	_restore_location_for_regenerate(retry_location_id)


	var retry_history_content: = retry_text
	if _last_player_turn_narrator_mode and retry_text != "...":
		retry_history_content = "Narrator: %s" % retry_text
	var should_append_user: = not retry_has_user_entry
	if retry_has_user_entry:
		should_append_user = (
			_history.is_empty()
			or _history[-1].get("role") != "user"
			or _history[-1].get("content", "") != retry_history_content
		)
	if should_append_user:
		_history.append({"role": "user", "content": retry_history_content})

	_hide_input_field()
	_show_quit_button = false
	_show_regenerate_button = false
	_show_sleepover_request_button = false
	_show_sleepover_sleep_button = false
	_show_pass_time_button = false
	_update_button_visibility()
	_show_thinking_indicator()

	if retry_kind == "rpg":
		var saved_roll: int = int(failed_rpg_request.get("roll", 1))
		var saved_action: String = str(failed_rpg_request.get("action_text", retry_text))
		_rpg.pending_request = failed_rpg_request
		var retry_management_context: = _get_regenerate_management_context()
		var rpg_request_prompt_data: = _build_rpg_roll_prompt_data(saved_action, saved_roll, "", retry_management_context, retry_guidance, retry_rewrite_note)
		_capture_request_start_state(false)
		_last_request_start_dialogic_history_size = saved_request_start_dialogic_size
		if not retry_has_user_entry:
			_restore_player_turn_into_history(retry_text, _last_player_turn_speaker_name, _last_player_turn_narrator_mode)
		_is_request_in_flight = true
		_ask_with_prompt_data(rpg_request_prompt_data, saved_action)
		return

	var retry_management_context: = _get_regenerate_management_context()
	var request_prompt_data: = _build_request_prompt_data("", retry_management_context, retry_text, retry_guidance, retry_rewrite_note)
	if retry_kind == "sleepover_invite" and SleepoverSystem != null:
		var tags: = _get_sleepover_character_tags()
		var location_id: = _resolve_sleepover_location_id(tags)
		if not location_id.is_empty() and not tags.is_empty():
			SleepoverSystem.begin_sleepover_invite(location_id, tags)
			_pending_sleepover_invite_request = true
			request_prompt_data = _build_sleepover_request_prompt_data(location_id, tags, "", retry_management_context, retry_guidance, retry_rewrite_note)
	_capture_request_start_state(false)
	_last_request_start_dialogic_history_size = saved_request_start_dialogic_size
	if not retry_has_user_entry:
		_restore_player_turn_into_history(retry_text, _last_player_turn_speaker_name, _last_player_turn_narrator_mode)
	_is_request_in_flight = true
	_ask_with_prompt_data(request_prompt_data, retry_history_content)


func _show_request_error_dialog(title_text: String, message_text: String, allow_retry: bool = true) -> void :
	_close_request_error_dialog()

	var canvas: = CanvasLayer.new()
	canvas.layer = REQUEST_ERROR_CANVAS_LAYER
	add_child(canvas)
	_request_error_canvas = canvas

	var blocker: = Control.new()
	blocker.name = "AIRequestErrorBlocker"
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
	retry_button.disabled = not allow_retry
	_style_request_error_button(retry_button, Color(0.42, 0.72, 0.48), Color(0.22, 0.42, 0.24))
	retry_button.pressed.connect( func() -> void :
		_close_request_error_dialog()
		_on_retry_failed_request_pressed.call_deferred()
	)
	button_row.add_child(retry_button)

	var settings_button: = Button.new()
	settings_button.text = "API Settings"
	settings_button.custom_minimum_size = Vector2(130, 40)
	_style_request_error_button(settings_button, Color(0.48, 0.42, 0.78), Color(0.24, 0.22, 0.46))
	settings_button.pressed.connect(_open_api_settings_from_error_dialog)
	button_row.add_child(settings_button)

	var keep_button: = Button.new()
	keep_button.text = "Keep Chat Open"
	keep_button.custom_minimum_size = Vector2(130, 40)
	_style_request_error_button(keep_button, Color(0.38, 0.48, 0.72), Color(0.2, 0.28, 0.46))
	keep_button.pressed.connect(_close_request_error_dialog)
	button_row.add_child(keep_button)

	var quit_button: = Button.new()
	quit_button.text = "Quit Chat"
	quit_button.custom_minimum_size = Vector2(110, 40)
	_style_request_error_button(quit_button, Color(0.78, 0.44, 0.48), Color(0.44, 0.2, 0.24))
	quit_button.pressed.connect( func() -> void :
		_close_request_error_dialog()
		end_conversation.call_deferred()
	)
	button_row.add_child(quit_button)


func _close_request_error_dialog() -> void :
	if _request_error_canvas and is_instance_valid(_request_error_canvas):
		_request_error_canvas.queue_free()
	_request_error_canvas = null



func _show_end_chat_confirm_dialog() -> void :
	_close_end_chat_confirm_dialog()

	var canvas: = CanvasLayer.new()
	canvas.layer = REQUEST_ERROR_CANVAS_LAYER
	add_child(canvas)
	_end_chat_confirm_canvas = canvas

	var blocker: = Control.new()
	blocker.name = "AIEndChatConfirmBlocker"
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
	panel.offset_left = -240
	panel.offset_top = -105
	panel.offset_right = 240
	panel.offset_bottom = 105
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(panel)

	var panel_style: = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.09, 0.07, 0.14, 0.98)
	panel_style.set_border_width_all(2)
	panel_style.border_color = Color(0.72, 0.62, 0.42, 0.95)
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
	title.text = "End this chat?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.88))
	root.add_child(title)

	var message: = Label.new()
	message.text = "This ends the conversation and finishes the visit. You cannot return to it afterward."
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size", 14)
	message.add_theme_color_override("font_color", Color(0.86, 0.83, 0.92))
	root.add_child(message)

	var button_row: = HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 10)
	root.add_child(button_row)

	var keep_button: = Button.new()
	keep_button.text = "Keep Chatting"
	keep_button.custom_minimum_size = Vector2(130, 40)
	_style_request_error_button(keep_button, Color(0.38, 0.48, 0.72), Color(0.2, 0.28, 0.46))
	keep_button.pressed.connect(_close_end_chat_confirm_dialog)
	button_row.add_child(keep_button)

	var end_button: = Button.new()
	end_button.text = "End Chat"
	end_button.custom_minimum_size = Vector2(110, 40)
	_style_request_error_button(end_button, Color(0.78, 0.44, 0.48), Color(0.44, 0.2, 0.24))
	end_button.pressed.connect( func() -> void :
		_close_end_chat_confirm_dialog()
		end_conversation.call_deferred()
	)
	button_row.add_child(end_button)

	keep_button.grab_focus()


func _close_end_chat_confirm_dialog() -> void :
	if _end_chat_confirm_canvas and is_instance_valid(_end_chat_confirm_canvas):
		_end_chat_confirm_canvas.queue_free()
	_end_chat_confirm_canvas = null
	if _input_field != null and _input_container != null and _input_container.visible:
		_input_field.grab_focus()


func _style_request_error_button(button: Button, fill_color: Color, border_color: Color) -> void :
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


func _open_api_settings_from_error_dialog() -> void :
	var current_scene: = get_tree().current_scene
	if current_scene and current_scene.has_method("open_api_settings_menu"):
		current_scene.call_deferred("open_api_settings_menu", API_SETTINGS_FROM_ERROR_LAYER)


func _build_request_error_message(compact_error: String) -> String:
	if compact_error.is_empty():
		return "I couldn't reach the AI service for this turn."
	return "I couldn't complete this AI turn.\n\n%s" % compact_error








func _show_input_in_textbox(prefill_text: String = "") -> void :
	var input_session := _session_id
	# The writable player turn is a new slide on every visit, including after
	# rolling back and advancing. Do not carry the previous line's voice here.
	preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree()).stop()
	if not _dialog_text_parent:
		_find_dialog_text_node()

	if not _dialog_text_parent:
		push_error("[DialogicAIConversation] Could not find dialogue text parent")
		return


	# The textbox can still be sliding/fading in after a scene transition.
	# Creating/focusing input before that animation ends places Ask below the
	# viewport and makes its first clicks disappear.
	await _ensure_textbox_visible()
	if not is_session_current(input_session) or not is_instance_valid(_dialog_text_parent):
		return


	if Dialogic.Text:
		var player_char: = DialogicResourceUtil.get_character_resource("player")
		if player_char:
			Dialogic.Text.update_name_label(player_char)
		else:

			for name_label in get_tree().get_nodes_in_group("dialogic_name_label"):
				name_label.text = "You"
				name_label.self_modulate = Color(0.6, 0.8, 1.0)
	_apply_input_speaker_label()


	if _dialog_text_node:
		_dialog_text_node.hide()


	for indicator in get_tree().get_nodes_in_group("dialogic_next_indicator"):
		indicator.hide()


	if _input_container == null:
		_create_input_field()

	_input_container.show()


	if _textbox_compact_suspend_token == 0:
		_textbox_compact_suspend_token = UISettingsManager.suspend_textbox_compact()
	_apply_input_speaker_label()
	if _input_field:
		_input_field.text = prefill_text
		_input_field.grab_focus()
	_update_rpg_button_visibility()
	_current_displayed_text = ""



	_show_interrupt_button = false
	_show_edit_button = false
	_edit_enabled = false
	_show_quit_button = true
	_show_regenerate_button = not _last_user_message.is_empty() and not _regenerate_unavailable
	_show_manual_roster_button = _is_manual_character_mode_enabled()
	_show_manual_location_button = _is_manual_location_mode_enabled()
	_refresh_sleepover_button_state()
	_manual.refresh_option_data()
	_manual.update_panel_state()
	_update_button_visibility()
	_reset_dialogic_input_state()
	AIDialogueShared.maybe_resume_dialogic_if_safe(self, _is_editing)




func _on_api_config_changed() -> void :
	if _input_container == null:
		return
	if _is_active and _input_container.visible and not _is_editing and not _is_viewing_history:

		var typed_text: = _input_field.text if _input_field != null else ""
		_cleanup_input_field()
		_show_input_in_textbox(typed_text)
	else:


		_cleanup_input_field()



func _hide_input_field() -> void :
	_manual.hide_panels()
	_hide_guidance_dialog()
	_disable_input_speaker_label_control()
	if _input_container:
		_input_container.hide()
	if _textbox_compact_suspend_token != 0:
		UISettingsManager.resume_textbox_compact(_textbox_compact_suspend_token)
		_textbox_compact_suspend_token = 0

	if _dialog_text_node:
		_dialog_text_node.show()


func _get_player_input_display_name() -> String:
	var custom_name: = _player_input_display_name.strip_edges()
	if not custom_name.is_empty():
		return custom_name
	var player_char: = DialogicResourceUtil.get_character_resource("player")
	if player_char != null and not player_char.display_name.strip_edges().is_empty():
		return player_char.display_name.strip_edges()
	return "Player"


func _get_active_input_speaker_name() -> String:
	if _input_speaker_mode == INPUT_SPEAKER_NARRATOR:
		return "Narrator"
	return _get_player_input_display_name()


func _apply_input_speaker_label() -> void :
	var display_name: = _get_active_input_speaker_name()
	for raw_label in get_tree().get_nodes_in_group("dialogic_name_label"):
		var name_label: = raw_label as Label
		if name_label == null:
			continue
		name_label.text = "%s  ▾" % display_name
		name_label.mouse_filter = Control.MOUSE_FILTER_STOP
		name_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		name_label.tooltip_text = "Change who submits the next line."
		if _input_speaker_mode == INPUT_SPEAKER_NARRATOR:
			name_label.self_modulate = Color(0.85, 0.78, 1.0)
		elif name_label.self_modulate == Color(0.85, 0.78, 1.0):
			name_label.self_modulate = Color.WHITE
		if not bool(name_label.get_meta("ai_speaker_popup_connected", false)):
			name_label.gui_input.connect(_on_input_speaker_label_gui_input.bind(name_label))
			name_label.set_meta("ai_speaker_popup_connected", true)


func _disable_input_speaker_label_control() -> void :
	for raw_label in get_tree().get_nodes_in_group("dialogic_name_label"):
		var name_label: = raw_label as Label
		if name_label == null:
			continue
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.tooltip_text = ""


func _on_input_speaker_label_gui_input(event: InputEvent, name_label: Label) -> void :
	if _input_container == null or not _input_container.visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_show_input_speaker_popup(name_label)


func _ensure_input_speaker_popup() -> PopupMenu:
	if _speaker_popup != null and is_instance_valid(_speaker_popup):
		return _speaker_popup
	_speaker_popup = PopupMenu.new()
	_speaker_popup.name = "AIInputSpeakerPopup"
	_speaker_popup.id_pressed.connect(_on_input_speaker_popup_id_pressed)
	add_child(_speaker_popup)
	return _speaker_popup


func _show_input_speaker_popup(name_label: Label) -> void :
	var popup: = _ensure_input_speaker_popup()
	popup.clear()
	var player_name: = _get_player_input_display_name()
	popup.add_check_item("Use %s" % player_name, SPEAKER_POPUP_PLAYER)
	popup.set_item_checked(popup.get_item_index(SPEAKER_POPUP_PLAYER), _input_speaker_mode == INPUT_SPEAKER_PLAYER)
	popup.add_check_item("Use Narrator", SPEAKER_POPUP_NARRATOR)
	popup.set_item_checked(popup.get_item_index(SPEAKER_POPUP_NARRATOR), _input_speaker_mode == INPUT_SPEAKER_NARRATOR)
	popup.add_separator()
	popup.add_item("Change Display Name...", SPEAKER_POPUP_PLAYER_NAME)
	var rect: = name_label.get_global_rect()
	popup.position = Vector2i(int(rect.position.x), int(rect.end.y + 4.0))
	popup.popup()


func _on_input_speaker_popup_id_pressed(id: int) -> void :
	match id:
		SPEAKER_POPUP_PLAYER:
			_input_speaker_mode = INPUT_SPEAKER_PLAYER
			_apply_input_speaker_label()
			if _input_field != null:
				_input_field.grab_focus()
		SPEAKER_POPUP_NARRATOR:
			_input_speaker_mode = INPUT_SPEAKER_NARRATOR
			_apply_input_speaker_label()
			if _input_field != null:
				_input_field.grab_focus()
		SPEAKER_POPUP_PLAYER_NAME:
			_open_player_display_name_dialog()


func _open_player_display_name_dialog() -> void :
	var dialog: = AcceptDialog.new()
	dialog.title = "Display Name"
	dialog.exclusive = true
	dialog.add_to_group("ui_blocking_overlay")
	var margin: = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	dialog.add_child(margin)
	var line_edit: = LineEdit.new()
	line_edit.placeholder_text = _get_player_input_display_name()
	line_edit.text = _player_input_display_name
	line_edit.custom_minimum_size = Vector2(260, 34)
	margin.add_child(line_edit)
	dialog.confirmed.connect( func() -> void :
		_player_input_display_name = line_edit.text.strip_edges()
		_input_speaker_mode = INPUT_SPEAKER_PLAYER
		_apply_input_speaker_label()
		if _input_field != null:
			_input_field.grab_focus()
		dialog.queue_free()
	)
	dialog.canceled.connect( func() -> void :
		if _input_field != null:
			_input_field.grab_focus()
		dialog.queue_free()
	)
	var parent: = get_tree().current_scene
	if parent == null:
		parent = self
	parent.add_child(dialog)
	dialog.popup_centered()
	line_edit.grab_focus()



func _create_input_field() -> void :

	var needs_button_row: = true



	if needs_button_row:
		var vbox: = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 6)
		_input_container = vbox
	else:
		var hbox: = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		_input_container = hbox

	_input_container.name = "AIInputContainer"
	_input_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_input_container.set_anchors_preset(Control.PRESET_FULL_RECT)


	_input_field = TextEdit.new()
	_input_field.name = "AIInputField"
	_input_field.placeholder_text = "What would you like to say?"
	_input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_input_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_input_field.drag_and_drop_selection_enabled = false
	_input_field.scroll_fit_content_height = false
	_input_field.add_theme_font_size_override("font_size", 16)


	_send_button = Button.new()
	_send_button.name = "AISendButton"
	_send_button.text = UISettingsManager.get_main_button_label()
	_send_button.custom_minimum_size = TouchMetrics.text_button_min(Vector2(70, 32))
	_send_button.add_theme_font_size_override("font_size", 14)


	_dice_button = Button.new()
	_dice_button.name = "AILaunchDiceButton"
	_dice_button.text = UISettingsManager.get_dice_button_label()
	_dice_button.custom_minimum_size = TouchMetrics.text_button_min(Vector2(110, 32))
	_dice_button.add_theme_font_size_override("font_size", 14)


	if APIConfigManager != null and APIConfigManager.is_debug_enabled():
		_debug_roll_option = OptionButton.new()
		_debug_roll_option.name = "AIDebugRollOption"
		_debug_roll_option.custom_minimum_size = Vector2(106, 0)
		_debug_roll_option.tooltip_text = "Debug: force the next d20 roll value."
		_debug_roll_option.add_item("Roll: Auto", AIRPGManager.DEBUG_ROLL_AUTO_ID)
		for value in range(AIRPGManager.DEBUG_ROLL_MIN, AIRPGManager.DEBUG_ROLL_MAX + 1):
			_debug_roll_option.add_item("Roll: %d" % value, value)
		_debug_roll_option.select(0)

		_debug_roll_option.add_theme_font_size_override("font_size", 13)
	else:
		_debug_roll_option = null


	_manual_roster_button = _create_inline_manual_button(UISettingsManager.get_roster_button_label())
	_manual_roster_button.pressed.connect(_on_manual_roster_pressed)
	_manual_roster_button.visible = false
	_manual.roster_button = _manual_roster_button

	_manual_location_button = _create_inline_manual_button(UISettingsManager.get_location_button_label())
	_manual_location_button.pressed.connect(_on_manual_location_pressed)
	_manual_location_button.visible = false
	_manual.location_button = _manual_location_button

	_guidance_button = _create_inline_manual_button("Guidance")
	_guidance_button.name = "AITurnGuidanceButton"
	_guidance_button.tooltip_text = "Set temporary guidance for the next AI response, including Retry and Regenerate. Never added to conversation history."
	_guidance_button.pressed.connect(_on_guidance_pressed)
	_refresh_guidance_button_state()


	_debug_rand_button = _create_inline_manual_button("Emotion")
	_debug_rand_button.name = "AIDebugRandButton"
	_debug_rand_button.pressed.connect(_on_debug_rand_emotions_pressed)
	_debug_rand_button.visible = false


	if needs_button_row:

		_button_row = HBoxContainer.new()
		_button_row.name = "AIButtonRow"
		_button_row.add_theme_constant_override("separation", 10)
		_button_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var spacer: = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		_input_container.add_child(_input_field)
		_button_row.add_child(_send_button)
		_button_row.add_child(_dice_button)
		if _debug_roll_option != null:
			_button_row.add_child(_debug_roll_option)
		_button_row.add_child(_manual_roster_button)
		_button_row.add_child(_manual_location_button)
		_button_row.add_child(_guidance_button)
		_button_row.add_child(_debug_rand_button)
		_button_row.add_child(spacer)
		_input_container.add_child(_button_row)
	else:

		_send_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_send_button.custom_minimum_size = Vector2(70, 0)
		_input_container.add_child(_input_field)
		_input_container.add_child(_send_button)


	_dialog_text_parent.add_child(_input_container)
	_create_guidance_dialog()


	_input_field.gui_input.connect(_on_input_field_gui_input)
	_send_button.pressed.connect(_on_send_pressed)
	_dice_button.pressed.connect(_on_launch_dice_pressed)
	_register_ui_settings_targets()
	apply_ui_settings()
	_update_rpg_button_visibility()



func _create_inline_manual_button(label_text: String) -> Button:
	var btn: = Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(80, 32)
	btn.add_theme_font_size_override("font_size", 14)
	return btn


func _create_guidance_dialog() -> void :
	if _guidance_canvas != null and is_instance_valid(_guidance_canvas):
		return


	_guidance_canvas = CanvasLayer.new()
	_guidance_canvas.layer = GUIDANCE_CANVAS_LAYER
	add_child(_guidance_canvas)

	_guidance_blocker = Control.new()
	_guidance_blocker.name = "TurnGuidanceBlocker"
	_guidance_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_guidance_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_guidance_blocker.add_to_group("ui_blocking_overlay")
	_guidance_blocker.gui_input.connect(_on_guidance_blocker_gui_input)
	_guidance_blocker.hide()
	_guidance_canvas.add_child(_guidance_blocker)

	var dimmer: = ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.01, 0.01, 0.03, 0.5)
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guidance_blocker.add_child(dimmer)

	_guidance_dialog_panel = PanelContainer.new()
	_guidance_dialog_panel.name = "TurnGuidanceDialogPanel"
	_guidance_dialog_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_layout_guidance_dialog_panel()
	_guidance_blocker.add_child(_guidance_dialog_panel)

	var margin: = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	_guidance_dialog_panel.add_child(margin)

	var root: = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var header: = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)
	var title: = Label.new()
	title.text = "Guidance"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UIPalette.TEXT_LIGHT)
	header.add_child(title)
	var header_spacer: = Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)
	var close_button: = Button.new()
	close_button.text = "✕"
	close_button.custom_minimum_size = TouchMetrics.icon_button_min(Vector2(32, 32))
	close_button.tooltip_text = "Close without saving changes (Esc)"
	close_button.pressed.connect(_hide_guidance_dialog)
	header.add_child(close_button)

	var help: = Label.new()
	help.text = "Steers only the next AI response, including a Retry or Regenerate. It is never saved into the conversation history."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(UIPalette.TEXT_LIGHT, 0.6))
	root.add_child(help)

	_guidance_text_edit = TextEdit.new()
	_guidance_text_edit.name = "TurnGuidanceTextEdit"
	_guidance_text_edit.placeholder_text = "Example: Keep the reply lighthearted and let Fluttershy take the lead."
	_guidance_text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_guidance_text_edit.drag_and_drop_selection_enabled = false
	_guidance_text_edit.custom_minimum_size = Vector2(0, 110)
	_guidance_text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_guidance_text_edit.add_theme_font_size_override("font_size", 15)
	_guidance_text_edit.gui_input.connect(_on_guidance_text_edit_gui_input)
	_guidance_text_edit.text_changed.connect(_refresh_guidance_rewrite_button_state)
	root.add_child(_guidance_text_edit)

	var rewrite_row: = HBoxContainer.new()
	rewrite_row.add_theme_constant_override("separation", 8)
	root.add_child(rewrite_row)
	_guidance_rewrite_button = Button.new()
	_guidance_rewrite_button.text = "↻ Rewrite Last Response"
	_guidance_rewrite_button.custom_minimum_size = Vector2(200, 36)
	_guidance_rewrite_button.tooltip_text = "Discard the last response and rewrite it following the text above. The story before it is unchanged."
	_guidance_rewrite_button.pressed.connect(_on_guidance_rewrite_pressed)
	rewrite_row.add_child(_guidance_rewrite_button)
	var rewrite_hint: = Label.new()
	rewrite_hint.text = "Uses this text as one-shot rewrite instructions for the last response."
	rewrite_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rewrite_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rewrite_hint.add_theme_font_size_override("font_size", 11)
	rewrite_hint.add_theme_color_override("font_color", Color(UIPalette.TEXT_LIGHT, 0.4))
	rewrite_row.add_child(rewrite_hint)

	_guidance_stop_setup_button = Button.new()
	_guidance_stop_setup_button.name = "StopSendingInitialSetupButton"
	_guidance_stop_setup_button.text = "Stop sending initial setup"
	_guidance_stop_setup_button.custom_minimum_size = Vector2(0, 32)
	_guidance_stop_setup_button.tooltip_text = "Stops repeating the opening setup from the next request onward in this conversation. Takes effect immediately; past dialogue and other scenario instructions are kept."
	_guidance_stop_setup_button.pressed.connect(_on_stop_sending_initial_setup_pressed)
	root.add_child(_guidance_stop_setup_button)
	_refresh_initial_setup_button()

	var footer: = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	root.add_child(footer)
	var clear_button: = Button.new()
	clear_button.text = "Clear"
	clear_button.custom_minimum_size = Vector2(90, 36)
	clear_button.tooltip_text = "Remove the staged guidance"
	clear_button.pressed.connect(_on_guidance_clear_pressed)
	footer.add_child(clear_button)
	var footer_hint: = Label.new()
	footer_hint.text = "Ctrl+Enter applies"
	footer_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer_hint.add_theme_font_size_override("font_size", 11)
	footer_hint.add_theme_color_override("font_color", Color(UIPalette.TEXT_LIGHT, 0.4))
	footer.add_child(footer_hint)
	var cancel_button: = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(90, 36)
	cancel_button.pressed.connect(_hide_guidance_dialog)
	footer.add_child(cancel_button)
	_guidance_apply_button = Button.new()
	_guidance_apply_button.text = "Apply"
	_guidance_apply_button.custom_minimum_size = Vector2(100, 36)
	_guidance_apply_button.tooltip_text = "Stage this guidance for the next AI response (Ctrl+Enter)"
	_guidance_apply_button.pressed.connect(_on_guidance_apply_pressed)
	footer.add_child(_guidance_apply_button)

	_refresh_guidance_rewrite_button_state()
	_register_ui_settings_targets()
	apply_ui_settings()


func _layout_guidance_dialog_panel() -> void :
	if _guidance_dialog_panel == null or not is_instance_valid(_guidance_dialog_panel):
		return
	var viewport_size: = get_viewport().get_visible_rect().size if get_viewport() else Vector2(1280, 720)
	var panel_width: = minf(620.0, viewport_size.x - 80.0)
	var panel_height: = minf(400.0, viewport_size.y - 80.0)
	_guidance_dialog_panel.set_anchors_preset(Control.PRESET_CENTER)
	_guidance_dialog_panel.offset_left = - panel_width * 0.5
	_guidance_dialog_panel.offset_top = - panel_height * 0.5
	_guidance_dialog_panel.offset_right = panel_width * 0.5
	_guidance_dialog_panel.offset_bottom = panel_height * 0.5


func _on_manual_roster_pressed() -> void :
	_hide_guidance_dialog()
	_manual.on_roster_pressed()


func _on_manual_location_pressed() -> void :
	_hide_guidance_dialog()
	_manual.on_location_pressed()


func _on_guidance_pressed() -> void :
	if _guidance_blocker == null or not is_instance_valid(_guidance_blocker):
		_create_guidance_dialog()
	if _guidance_blocker == null:
		return
	_manual.hide_panels()
	if _guidance_blocker.visible:
		_hide_guidance_dialog()
		return
	if _guidance_text_edit != null:
		_guidance_text_edit.text = _pending_turn_guidance
	_refresh_initial_setup_button()
	_refresh_guidance_rewrite_button_state()
	_layout_guidance_dialog_panel()
	_guidance_blocker.show()
	if _guidance_text_edit != null:
		_guidance_text_edit.grab_focus()


func _hide_guidance_dialog() -> void :
	if _guidance_blocker != null and is_instance_valid(_guidance_blocker):
		_guidance_blocker.hide()
	if _input_field != null and _input_container != null and _input_container.visible:
		_input_field.grab_focus()


func _is_guidance_dialog_visible() -> bool:
	return _guidance_blocker != null and is_instance_valid(_guidance_blocker) and _guidance_blocker.visible


func _on_guidance_blocker_gui_input(event: InputEvent) -> void :

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_hide_guidance_dialog()


func _on_guidance_apply_pressed() -> void :
	_set_pending_turn_guidance(_guidance_text_edit.text if _guidance_text_edit != null else "")
	_hide_guidance_dialog()


func _on_guidance_clear_pressed() -> void :
	if _guidance_text_edit != null:
		_guidance_text_edit.text = ""
	_set_pending_turn_guidance("")
	_refresh_guidance_rewrite_button_state()




func _find_last_assistant_response() -> String:
	for index in range(_history.size() - 1, -1, -1):
		var entry: Variant = _history[index]
		if entry is Dictionary and str(entry.get("role", "")) == "assistant":
			return str(entry.get("content", ""))
	return ""


func _can_rewrite_last_response() -> bool:


	return (
		_show_regenerate_button
		and not _regenerate_unavailable
		and not _is_restoring_turn_state
		and not _is_request_in_flight
		and not _find_last_assistant_response().is_empty()
	)


func _refresh_guidance_rewrite_button_state() -> void :
	if _guidance_rewrite_button == null or not is_instance_valid(_guidance_rewrite_button):
		return
	var instruction: = _guidance_text_edit.text.strip_edges() if _guidance_text_edit != null else ""
	var can_rewrite: = _can_rewrite_last_response()
	_guidance_rewrite_button.disabled = instruction.is_empty() or not can_rewrite
	if not can_rewrite:
		_guidance_rewrite_button.tooltip_text = "Available after a completed response, when Retry is available."
	elif instruction.is_empty():
		_guidance_rewrite_button.tooltip_text = "Type rewrite instructions above first."
	else:
		_guidance_rewrite_button.tooltip_text = "Discard the last response and rewrite it following the text above. The story before it is unchanged."


func _on_guidance_rewrite_pressed() -> void :
	var instruction: = _guidance_text_edit.text.strip_edges() if _guidance_text_edit != null else ""
	if instruction.is_empty() or not _can_rewrite_last_response():
		return


	_hide_guidance_dialog()
	_on_regenerate_pressed(instruction)


func _on_guidance_text_edit_gui_input(event: InputEvent) -> void :
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and (event.ctrl_pressed or event.meta_pressed):
			get_viewport().set_input_as_handled()
			_on_guidance_apply_pressed()
		elif event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_hide_guidance_dialog()


func _set_pending_turn_guidance(value: String) -> void :
	_pending_turn_guidance = value.strip_edges()
	_refresh_guidance_button_state()


func _refresh_guidance_button_state() -> void :
	if _guidance_button == null:
		return
	_guidance_button.text = "Guidance •" if not _pending_turn_guidance.is_empty() else "Guidance"
	var guidance_enabled: = UISettingsManager == null or UISettingsManager.get_qa_guidance_enabled()
	_guidance_button.visible = guidance_enabled
	if (
		not guidance_enabled
		and _guidance_blocker != null
		and is_instance_valid(_guidance_blocker)
		and _guidance_blocker.visible
	):
		_hide_guidance_dialog()


func _capture_pending_turn_guidance() -> String:
	_last_turn_guidance = _pending_turn_guidance.strip_edges()
	_set_pending_turn_guidance("")
	return _last_turn_guidance


func _restore_pending_turn_guidance_for_resend() -> void :
	_set_pending_turn_guidance(_last_turn_guidance)





func _capture_turn_guidance_for_redo() -> String:
	if not _pending_turn_guidance.is_empty():
		_last_turn_guidance = _pending_turn_guidance
	_set_pending_turn_guidance("")
	return _last_turn_guidance


func _cleanup_guidance_dialog() -> void :
	if _guidance_canvas != null and is_instance_valid(_guidance_canvas):
		_guidance_canvas.queue_free()
	_guidance_canvas = null
	_guidance_blocker = null
	_guidance_dialog_panel = null
	_guidance_text_edit = null
	_guidance_apply_button = null
	_guidance_rewrite_button = null
	_guidance_stop_setup_button = null



func _cleanup_input_field() -> void :
	_cleanup_guidance_dialog()
	if _speaker_popup != null:
		_speaker_popup.queue_free()
		_speaker_popup = null
	if _input_container:
		_input_container.queue_free()
		_input_container = null
		_input_field = null
		_send_button = null
		_dice_button = null
		_button_row = null
		_debug_roll_option = null
		_manual_roster_button = null
		_manual_location_button = null
		_guidance_button = null
		_debug_rand_button = null
		if _manual != null:
			_manual.roster_button = null
			_manual.location_button = null



func _ensure_textbox_visible() -> void :
	if Dialogic.has_subsystem("Styles") and Dialogic.Styles.has_active_layout_node():
		var layout_node: = Dialogic.Styles.get_layout_node()
		if layout_node:
			layout_node.show()

	if Dialogic.Text and Dialogic.Text.has_method("show_textbox"):
		await Dialogic.Text.show_textbox()
	# A previous timeline's ending may have hidden the layout while the textbox
	# animation yielded. Restore the actual canvas as well as its text panel.
	if _is_active and Dialogic.has_subsystem("Styles") and Dialogic.Styles.has_active_layout_node():
		Dialogic.Styles.get_layout_node().show()


	for tn in get_tree().get_nodes_in_group("dialogic_dialog_text"):
		if tn is CanvasItem:
			tn.show()
			if tn.modulate.a < 1.0:
				tn.modulate.a = 1.0


		if "textbox_root" in tn:
			var tbr = tn.textbox_root
			tbr.show()
			var p = tbr.get_parent()
			while p:
				if p.name == "AnimationParent" and p is CanvasItem:
					p.show()
					if p.modulate.a < 1.0:
						p.modulate.a = 1.0
					if p.position != Vector2.ZERO:
						p.position = Vector2.ZERO
					break
				p = p.get_parent()



func _reset_dialogic_input_state() -> void :
	Dialogic.current_state = Dialogic.States.IDLE
	if DialogicUtil.autoload():
		var inputs: Node = DialogicUtil.autoload().get("Inputs") as Node
		if inputs:
			inputs.action_was_consumed = false
			if inputs.has_method("stop_timers"):
				inputs.stop_timers()
	if Dialogic.has_subsystem("Inputs") and Dialogic.Inputs and Dialogic.Inputs.manual_advance:
		Dialogic.Inputs.manual_advance.disabled_until_next_event = false
		Dialogic.Inputs.manual_advance.system_enabled = true



func _on_input_field_gui_input(event: InputEvent) -> void :
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if not event.shift_pressed:
				_input_field.get_viewport().set_input_as_handled()
				await _submit_input()



func _on_send_pressed() -> void :
	await _submit_input()


func _on_launch_dice_pressed() -> void :
	await _submit_dice_input()


func _on_debug_rand_emotions_pressed() -> void :
	_hide_guidance_dialog()
	_manual.on_emotion_pressed()


func _on_sleepover_request_pressed() -> void :
	await _submit_sleepover_invite_request()


func _on_sleepover_sleep_pressed() -> void :
	if SleepoverSystem == null:
		return
	var tags: = _get_sleepover_character_tags()
	var location_id: = str(SleepoverSystem.flow_location_id).strip_edges()
	if location_id.is_empty():
		location_id = _resolve_sleepover_location_id(tags)
	if location_id.is_empty() or tags.is_empty():
		return
	SleepoverSystem.request_sleep_action(location_id, tags)
	end_conversation()



func _submit_input() -> void :
	if not _input_field:
		return

	var text: = _input_field.text.strip_edges()
	if text.is_empty():
		return
	var narrator_mode: = _input_speaker_mode == INPUT_SPEAKER_NARRATOR
	var speaker_name: = _get_active_input_speaker_name()
	var request_text: = text
	var history_text: = text
	if narrator_mode:
		request_text = "Narrator: %s" % text
		history_text = request_text


	_interrupt_requested = false
	_cancel_current_advance_wait = false
	_is_viewing_history = false
	_clear_failed_request_retry_state()

	_hide_input_field()


	_last_user_message = text
	_last_player_turn_speaker_name = speaker_name
	_last_player_turn_narrator_mode = narrator_mode
	_rpg.last_request.clear()
	var turn_guidance: = _capture_pending_turn_guidance()



	var my_session_id: = _session_id
	var request_management_context: = _build_effective_request_management_context()
	var manual_instruction: = await _apply_pending_manual_changes(my_session_id)
	if not is_session_current(my_session_id):
		return
	var request_prompt_data: = _build_request_prompt_data(manual_instruction, request_management_context, text, turn_guidance)


	_history.append({
		"role": "user", 
		"content": history_text
	})
	if APIConfigManager.is_debug_enabled():
		print("[DialogicAIConversation] User input queued len=%d history_size=%d speaker=%s" % [text.length(), _history.size(), speaker_name])
	_remember_request_management_context(request_management_context)
	_capture_request_start_state(false)
	if narrator_mode:
		AIDialogueShared.store_dialogic_history_entry(text, null, true)
	else:
		_store_player_history_entry(text, speaker_name)
	_register_player_turn_with_rollback(text, speaker_name, narrator_mode)


	_show_thinking_indicator()


	_is_request_in_flight = true
	_ask_with_prompt_data(request_prompt_data, request_text)


func _submit_dice_input() -> void :
	if not _input_field:
		return
	if not _is_rpg_mode_enabled():
		return
	if not _has_active_persona_for_rpg():
		return

	var text: = _input_field.text.strip_edges()
	if text.is_empty():
		return

	_interrupt_requested = false
	_cancel_current_advance_wait = false
	_is_viewing_history = false
	_clear_failed_request_retry_state()

	_hide_input_field()


	_last_user_message = text
	_last_player_turn_speaker_name = ""
	_last_player_turn_narrator_mode = false
	var turn_guidance: = _capture_pending_turn_guidance()



	var my_session_id: = _session_id
	var request_management_context: = _build_effective_request_management_context()
	var manual_instruction: = await _apply_pending_manual_changes(my_session_id)
	if not is_session_current(my_session_id):
		return
	var debug_override: = _rpg.get_debug_roll_override(_debug_roll_option)
	var roll: = _rpg.roll_d20(_debug_roll_option)
	roll = await _rpg.play_dice_roll_animation(roll, self)
	if not is_session_current(my_session_id):
		return
	var active_stats: = PersonaManager.get_active_persona_stats() if PersonaManager != null else {}
	_rpg.pending_request = {
		"action_text": text, 
		"roll": roll, 
		"stats": active_stats.duplicate(true), 
	}
	var request_prompt_data: = _build_rpg_roll_prompt_data(text, roll, manual_instruction, request_management_context, turn_guidance)

	_history.append({
		"role": "user", 
		"content": text
	})
	_remember_request_management_context(request_management_context)
	_capture_request_start_state(false)
	_store_player_history_entry(text)
	_register_player_turn_with_rollback(text)

	_show_thinking_indicator()
	_is_request_in_flight = true
	_ask_with_prompt_data(request_prompt_data, text)


func _submit_sleepover_invite_request() -> void :
	if SleepoverSystem == null:
		return
	if not _can_show_sleepover_request_action():
		return

	var tags: = _get_sleepover_character_tags()
	var location_id: = _resolve_sleepover_location_id(tags)
	if location_id.is_empty() or tags.is_empty():
		return

	_interrupt_requested = false
	_cancel_current_advance_wait = false
	_is_viewing_history = false
	_clear_failed_request_retry_state()

	_hide_input_field()

	SleepoverSystem.begin_sleepover_invite(location_id, tags)
	_pending_sleepover_invite_request = true
	_last_user_message = "..."
	_last_player_turn_speaker_name = ""
	_last_player_turn_narrator_mode = false
	var turn_guidance: = _capture_pending_turn_guidance()
	_history.append({
		"role": "user", 
		"content": "..."
	})




	var my_session_id: = _session_id
	var request_management_context: = _build_effective_request_management_context()
	var manual_instruction: = await _apply_pending_manual_changes(my_session_id)
	if not is_session_current(my_session_id):
		return
	var request_prompt_data: = _build_sleepover_request_prompt_data(
		location_id, 
		tags, 
		manual_instruction, 
		request_management_context, 
		turn_guidance
	)

	_show_thinking_indicator()
	_remember_request_management_context(request_management_context)
	_capture_request_start_state(false)
	_is_request_in_flight = true
	_ask_with_prompt_data(request_prompt_data, "...")



func _show_thinking_indicator() -> void :

	_show_interrupt_button = true
	_show_edit_button = false
	_edit_enabled = false
	_show_quit_button = false
	_show_regenerate_button = false
	_show_sleepover_request_button = false
	_show_sleepover_sleep_button = false
	_show_pass_time_button = false
	_show_manual_roster_button = false
	_show_manual_location_button = false
	_manual.hide_panels()
	_panels.set_panel_text(_panels.interrupt_panel, "Cancel")
	_update_button_visibility()

	if Dialogic.Text:

		if not _stage.character_data.is_empty():
			var first_tag: String = _stage.character_data[0].tag
			if _stage.dialogic_characters.has(first_tag):
				Dialogic.Text.update_name_label(_stage.dialogic_characters[first_tag])


	_thinking_controller.start("Thinking", false)



func _stop_thinking_animation() -> void :
	_thinking_controller.stop(false)





func _update_rpg_button_visibility() -> void :
	if _dice_button == null:
		return
	var enabled: = _is_rpg_mode_enabled()
	var has_persona: = _has_active_persona_for_rpg()
	_dice_button.visible = enabled
	_dice_button.disabled = not enabled
	if enabled and not has_persona:
		_dice_button.tooltip_text = "Set an active persona in Persona Menu to use Launch Dice."
	else:
		_dice_button.tooltip_text = "Roll dice and resolve this turn as an RPG action."
	if _debug_roll_option:
		var show_debug_override: = enabled and APIConfigManager != null and APIConfigManager.is_debug_enabled()
		_debug_roll_option.visible = show_debug_override
		_debug_roll_option.disabled = not enabled





func _restore_input_mode(reason: String) -> void :
	preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree()).stop()
	_is_request_in_flight = false
	_interrupt_requested = false
	_is_displaying_dialogue = false
	_show_interrupt_button = false
	_show_edit_button = false
	_edit_enabled = false
	_stage.reset_speaker_focus()
	_show_input_in_textbox()
	if APIConfigManager.is_debug_enabled():
		debug_dump_state(reason)








func _autosave_accepted_reply() -> void :
	if not _is_active or _is_viewing_history or _dialogue_queue.is_empty():
		return

	AutosaveManager.save_ai_reply(self)


func _on_ai_response_received(response: String) -> void :


	if not _is_active or not _is_request_in_flight:
		return

	_stop_thinking_animation()
	_is_request_in_flight = false
	_panels.set_panel_text(_panels.interrupt_panel, "Stop")



	var in_flight_rewrite_note: = _last_rewrite_note
	_clear_failed_request_retry_state()
	_maybe_trigger_auto_story_summary()


	if _rpg.has_pending_request():
		await _handle_rpg_ai_response(response, in_flight_rewrite_note)
		return

	var was_sleepover_invite: = _pending_sleepover_invite_request
	_pending_sleepover_invite_request = false


	var lines: = _line_processor.parse_response(response)
	var valid_lines: = _line_processor.filter_valid_lines(lines, _active_response_management_context)
	var dropped_validation_errors: = _line_processor.get_last_validation_errors()
	var unknown_lines: = _line_processor.get_last_unknown_lines()

	if APIConfigManager.is_debug_enabled():
		print("[DialogicAIConversation] AI response len=%d parsed=%d valid=%d" % [
			response.length(), 
			lines.size(), 
			valid_lines.size()
		])
		_line_processor.debug_print_lines(valid_lines)
		for raw in unknown_lines:
			print("[DialogicAIConversation] Unknown line: " + raw)
		for err in dropped_validation_errors:
			print("[DialogicAIConversation] Dropped line: " + err)
	elif not dropped_validation_errors.is_empty() or not unknown_lines.is_empty():
		Log.d(
			"DialogicAIConversation", 
			"Dropped %d validated line(s), %d unknown line(s)" % [dropped_validation_errors.size(), unknown_lines.size()]
		)

	var dropped_summary: = _summarize_validation_errors(dropped_validation_errors)
	var unknown_summary: = _summarize_unknown_lines(unknown_lines)
	var parse_summary_parts: Array[String] = []
	if not unknown_summary.is_empty():
		parse_summary_parts.append(unknown_summary)
	if not dropped_summary.is_empty():
		parse_summary_parts.append(dropped_summary)
	var parse_summary: = " | ".join(parse_summary_parts)
	if not parse_summary.is_empty():
		if APIConfigManager.is_debug_enabled():
			print("[DialogicAIConversation] Parse summary: " + parse_summary)

	if valid_lines.is_empty():
		if was_sleepover_invite:
			_failed_request_kind = "sleepover_invite"
		else:
			_failed_request_kind = "standard"
		_failed_request_location_id = _last_request_start_location_id
		_failed_rpg_request.clear()
		_failed_request_has_user_entry = true
		_regenerate_unavailable = true


		_last_rewrite_note = in_flight_rewrite_note
		if was_sleepover_invite and SleepoverSystem != null:
			SleepoverSystem.mark_sleepover_invite_failed()
		push_warning("[DialogicAIConversation] No valid lines in AI response")
		_restore_pending_turn_guidance_for_resend()
		if Dialogic.Text:
			Dialogic.Text.update_dialog_text("[i]I couldn't parse a usable reply. You can ask again or press Retry.[/i]", true)
		await get_tree().create_timer(0.7).timeout
		_restore_input_mode("invalid_response_show_input")
		_show_request_error_dialog(
			"AI Reply Failed", 
			"The AI returned a reply, but it could not be parsed into usable dialogue lines."
		)
		return


	_interrupt_requested = false
	_cancel_current_advance_wait = false
	_hide_input_field()


	_displayed_lines.clear()

	_history.append({
		"role": "assistant", 
		"content": response
	})
	_trim_conversation_history()
	if APIConfigManager.is_debug_enabled():
		print("[DialogicAIConversation] Assistant response queued history_size=%d" % _history.size())


	_save_state_snapshot()

	_append_valid_lines_to_queue(valid_lines)

	if was_sleepover_invite and SleepoverSystem != null:
		SleepoverSystem.mark_sleepover_invite_succeeded()


	if bool(_initial_setup.get("once", false)):
		_on_stop_sending_initial_setup_pressed()
	_autosave_accepted_reply()
	_display_next_dialogue()



func _on_ai_request_failed(error: String) -> void :

	if not _is_active or not _is_request_in_flight:
		return

	_stop_thinking_animation()
	_is_request_in_flight = false
	_panels.set_panel_text(_panels.interrupt_panel, "Stop")
	var had_rpg_request: = _rpg.has_pending_request()
	var failed_rpg_request: = _rpg.pending_request.duplicate(true)
	_rpg.pending_request.clear()
	if had_rpg_request:
		_failed_request_kind = "rpg"
		_failed_rpg_request = failed_rpg_request
	elif _pending_sleepover_invite_request:
		_failed_request_kind = "sleepover_invite"
		_failed_rpg_request.clear()
	else:
		_failed_request_kind = "standard"
		_failed_rpg_request.clear()
	_failed_request_location_id = _last_request_start_location_id
	_failed_request_has_user_entry = false
	_regenerate_unavailable = true
	if _pending_sleepover_invite_request and SleepoverSystem != null:
		SleepoverSystem.mark_sleepover_invite_failed()
	_pending_sleepover_invite_request = false

	push_error("[DialogicAIConversation] AI request failed: " + error)
	var compact_error: = error.strip_edges()
	if compact_error.length() > 120:
		compact_error = compact_error.substr(0, 120) + "..."

	if Dialogic.Text:
		if had_rpg_request:
			Dialogic.Text.update_dialog_text("[i]I couldn't resolve the RPG roll right now. You can try Launch Dice again.[/i]", true)
		else:
			Dialogic.Text.update_dialog_text("[i]I couldn't reach the AI service just now. You can ask again or press Retry.[/i]", true)






	var history_size_before: = _history.size()
	if not _history.is_empty() and _history[-1].get("role") == "user":
		_history.pop_back()
		history_size_before = _history.size()
	if _last_request_start_dialogic_history_size >= 0 and Dialogic.has_subsystem("History"):
		var current_size: = Dialogic.History.simple_history_content.size()
		if current_size > _last_request_start_dialogic_history_size:
			Dialogic.History.simple_history_content.resize(_last_request_start_dialogic_history_size)
	_prune_rollback_snapshots_after_history_size(history_size_before)




	var my_session_id: = _session_id
	if not (_last_pending_enters.is_empty() and _last_pending_exits.is_empty()
			and _last_pending_step_asides.is_empty() and _last_pending_location_id.is_empty()):

		await _restore_pre_send_scene_state()
		if my_session_id != _session_id or not _is_active:
			return
	_restore_pending_turn_guidance_for_resend()

	await get_tree().create_timer(0.8).timeout
	if my_session_id != _session_id or not _is_active:
		return
	_restore_input_mode("request_failed_show_input")
	_show_request_error_dialog(
		"AI Request Failed", 
		_build_request_error_message(compact_error), 
		_can_retry_failed_request()
	)



func _on_ai_request_started() -> void :
	_is_request_in_flight = true





func _handle_rpg_ai_response(response: String, in_flight_rewrite_note: String = "") -> void :
	_pending_sleepover_invite_request = false
	_clear_failed_request_retry_state()

	var request_data: = _rpg.pending_request.duplicate(true)
	var result: = _rpg.process_rpg_response(response)
	if result.has("error"):
		_rpg.last_request = request_data.duplicate(true)
		_failed_request_kind = "rpg"
		_failed_request_location_id = _last_request_start_location_id
		_failed_rpg_request = request_data.duplicate(true)
		_failed_request_has_user_entry = true
		_regenerate_unavailable = true

		_last_rewrite_note = in_flight_rewrite_note
		_restore_pending_turn_guidance_for_resend()
		push_warning("[DialogicAIConversation] Invalid RPG adjudication JSON")
		if Dialogic.Text:
			Dialogic.Text.update_dialog_text("[i]I couldn't parse the RPG adjudication. You can retry with the same roll.[/i]", true)
		await get_tree().create_timer(0.6).timeout
		_restore_input_mode("rpg_invalid_response")
		_show_request_error_dialog(
			"AI Reply Failed", 
			"The AI returned invalid RPG adjudication data. Retry will reuse the original d20 roll.", 
			true
		)
		return

	var continuation: String = result["continuation"]
	var summary: String = result["summary"]

	var lines: = _line_processor.parse_response(continuation)
	var valid_lines: = _line_processor.filter_valid_lines(lines, _active_response_management_context)
	var dropped_validation_errors: = _line_processor.get_last_validation_errors()
	var unknown_lines: = _line_processor.get_last_unknown_lines()
	var dropped_summary: = _summarize_validation_errors(dropped_validation_errors)
	var unknown_summary: = _summarize_unknown_lines(unknown_lines)
	var parse_summary_parts: Array[String] = []
	if not unknown_summary.is_empty():
		parse_summary_parts.append(unknown_summary)
	if not dropped_summary.is_empty():
		parse_summary_parts.append(dropped_summary)
	var parse_summary: = " | ".join(parse_summary_parts)
	if not parse_summary.is_empty():
		if APIConfigManager.is_debug_enabled():
			print("[DialogicAIConversation] RPG parse summary: " + parse_summary)

	_hide_input_field()
	_displayed_lines.clear()
	_history.append({
		"role": "assistant", 
		"content": continuation, 
	})
	_trim_conversation_history()
	_save_state_snapshot()

	var adjudicated_check: Dictionary = result.get("check", {})
	var queued_lines_start: = _dialogue_queue.size()
	if valid_lines.is_empty():
		_dialogue_queue.append({
			"type": "dialogue", 
			"speaker": "narrator", 
			"text": continuation, 
			"is_narrator": true, 
		})
	else:
		_append_valid_lines_to_queue(valid_lines)
	_attach_rpg_check_to_first_queued_dialogue(adjudicated_check, queued_lines_start)

	_show_dice_result_panel(adjudicated_check)
	if bool(_initial_setup.get("once", false)):
		_on_stop_sending_initial_setup_pressed()
	_autosave_accepted_reply()
	_display_next_dialogue()






func _attach_rpg_check_to_first_queued_dialogue(check: Dictionary, search_from: int) -> void :
	if check.is_empty():
		return
	for i in range(maxi(0, search_from), _dialogue_queue.size()):
		var queued: Dictionary = _dialogue_queue[i]
		if str(queued.get("type", "")) == "dialogue":
			queued["rpg_check"] = check.duplicate(true)
			return






func _stamp_rpg_check_on_history_entry(raw_history_index: int, check: Dictionary) -> void :
	if check.is_empty() or not Dialogic.has_subsystem("History"):
		return
	var history: Array = Dialogic.History.simple_history_content
	if raw_history_index < 0 or raw_history_index >= history.size():
		return
	if history[raw_history_index] is Dictionary:
		history[raw_history_index]["rpg_check"] = check.duplicate(true)



func _show_dice_result_panel(check: Dictionary) -> void :
	if check.is_empty():
		return
	if UISettingsManager == null or not UISettingsManager.get_qa_dice_result_panel_enabled():
		return
	_dismiss_dice_result_panel()
	_dice_result_panel = DiceResultPanel.new()
	add_child(_dice_result_panel)
	_dice_result_panel.show_result(check)


func _dismiss_dice_result_panel() -> void :
	if _dice_result_panel != null and is_instance_valid(_dice_result_panel):
		_dice_result_panel.dismiss()
	_dice_result_panel = null






func _append_valid_lines_to_queue(valid_lines: Array) -> void :
	var voice_mod: Node = preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree())
	for line in valid_lines:
		match line.type:
			DialogueLineProcessor.LineType.SPRITE:
				_dialogue_queue.append({
					"type": "sprite", 
					"tag": line.tag, 
					"emotion": line.content
				})
			DialogueLineProcessor.LineType.LOCATION:
				_dialogue_queue.append({
					"type": "command", 
					"command": "location", 
					"location_id": line.content
				})
			DialogueLineProcessor.LineType.CHARACTER_ENTER:
				_dialogue_queue.append({
					"type": "command", 
					"command": "character_enter", 
					"tag": line.tag
				})
			DialogueLineProcessor.LineType.CHARACTER_EXIT:
				_dialogue_queue.append({
					"type": "command", 
					"command": "character_exit", 
					"tag": line.tag
				})
			DialogueLineProcessor.LineType.CHARACTER_STEP_ASIDE:
				_dialogue_queue.append({
					"type": "command", 
					"command": "character_step_aside", 
					"tag": line.tag
				})
			DialogueLineProcessor.LineType.NARRATOR:
				_dialogue_queue.append({
					"type": "dialogue", 
					"speaker": "narrator", 
					"text": line.content, 
					"is_narrator": true
				})
			DialogueLineProcessor.LineType.DIALOGUE:
				_dialogue_queue.append({
					"type": "dialogue", 
					"speaker": line.tag, 
					"text": line.content, 
					"is_narrator": false
				})
	voice_mod.prefetch_response(_dialogue_queue)









func _display_next_dialogue(my_session_id: int = -1) -> void :
	preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree()).stop()

	if my_session_id == -1:
		my_session_id = _session_id


	if my_session_id != _session_id:
		if APIConfigManager.is_debug_enabled():
			print("[DialogicAIConversation] Stale coroutine detected (session %d != %d), stopping" % [my_session_id, _session_id])
		return


	if not _is_active:
		_is_displaying_dialogue = false
		return


	if _cancel_current_advance_wait:
		_cancel_current_advance_wait = false
		_is_displaying_dialogue = false
		return


	if _interrupt_requested:
		_dialogue_queue.clear()
		_restore_input_mode("display_interrupt")
		return


	if RollbackManager.is_in_rollback_mode():
		_is_displaying_dialogue = false
		return

	if _dialogue_queue.is_empty():
		if _is_request_in_flight:
			_is_displaying_dialogue = false
			return

		_restore_input_mode("queue_empty_show_input")
		return

	_is_displaying_dialogue = true
	var response_voice: Node = preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree())
	var response_valid := func(): return is_session_current(my_session_id) and not RollbackManager.is_in_rollback_mode() and not _interrupt_requested
	if not await response_voice.prepare_response(_dialogue_queue.duplicate(true), response_valid):
		_is_displaying_dialogue = false
		if is_session_current(my_session_id) and _interrupt_requested:
			_dialogue_queue.clear()
			_restore_input_mode("interrupt_audio_preparation")
		return


	_show_interrupt_button = true
	_show_edit_button = true
	_edit_enabled = false
	_show_quit_button = false
	_show_regenerate_button = false
	_show_sleepover_request_button = false
	_show_sleepover_sleep_button = false
	_show_pass_time_button = false
	_update_button_visibility()

	var entry: Dictionary = _dialogue_queue.pop_front()


	if entry.get("type") == "sprite":
		await _stage.handle_sprite_change(entry["tag"], entry["emotion"], my_session_id)
		if not is_session_current(my_session_id) or RollbackManager.is_in_rollback_mode():
			_is_displaying_dialogue = false
			return

		_displayed_lines.append(entry)

		_display_next_dialogue(my_session_id)
		return


	if entry.get("type") == "command":
		var cmd: = str(entry.get("command", ""))
		if _is_dynamic_character_mode_enabled() and cmd in ["character_enter", "character_exit", "character_step_aside"]:

			var batch_enters: Array[String] = []
			var batch_exits: Array[String] = []
			var batch_step_asides: Array[String] = []

			var add_to_batch = func(e: Dictionary) -> void :
				var c_cmd: = str(e.get("command", ""))
				var tag: = str(e.get("tag", "")).strip_edges()
				if tag.is_empty():
					return
				if c_cmd == "character_enter":
					if not batch_enters.has(tag):
						batch_enters.append(tag)
				elif c_cmd == "character_exit":
					if not batch_exits.has(tag):
						batch_exits.append(tag)
				elif c_cmd == "character_step_aside":
					if not batch_step_asides.has(tag):
						batch_step_asides.append(tag)

			add_to_batch.call(entry)

			while not _dialogue_queue.is_empty():
				var next_entry: Dictionary = _dialogue_queue[0]
				if next_entry.get("type") == "command" and str(next_entry.get("command", "")) in ["character_enter", "character_exit", "character_step_aside"]:
					_dialogue_queue.pop_front()
					add_to_batch.call(next_entry)
					_displayed_lines.append(next_entry)
				else:
					break

			await _stage.apply_batch_roster_changes(
				batch_enters, 
				batch_exits, 
				batch_step_asides, 
				my_session_id
			)
		else:
			await _handle_command_entry(entry)
		if not is_session_current(my_session_id) or RollbackManager.is_in_rollback_mode():
			_is_displaying_dialogue = false
			return

		_displayed_lines.append(entry)
		_display_next_dialogue(my_session_id)
		return

	var speaker: String = entry["speaker"]
	var text: String = entry["text"]
	var is_narrator: bool = entry["is_narrator"]
	entry.merge(preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree()).history_metadata("narrator" if is_narrator else speaker, text), true)
	var line_rpg_check: Dictionary = entry.get("rpg_check", {})


	_displayed_lines.append(entry)


	var dialogic_char: DialogicCharacter = null
	if not is_narrator and _stage.dialogic_characters.has(speaker):
		if _is_dynamic_character_mode_enabled():
			await _stage.ensure_character_visible(speaker, false, my_session_id)
			if not is_session_current(my_session_id) or RollbackManager.is_in_rollback_mode():
				_is_displaying_dialogue = false
				return
		dialogic_char = _stage.dialogic_characters[speaker]
	elif is_narrator:
		dialogic_char = DialogicResourceUtil.get_character_resource("narrator")


	if Dialogic.Text:
		Dialogic.Text.update_name_label(dialogic_char)


	if dialogic_char and Dialogic.Portraits.is_character_joined(dialogic_char):
		var portrait: String = _stage.sprite_states.get(speaker, "neutral")
		if dialogic_char.portraits.has(portrait):
			if not AIDialogueShared.is_portrait_current(dialogic_char, portrait):
				_stage.prepare_group_layout_before_portrait_change(speaker, dialogic_char, _stage.get_total_visible_for_layout(speaker))
				await Dialogic.Portraits.change_character_portrait(dialogic_char, portrait)
				if not is_session_current(my_session_id) or RollbackManager.is_in_rollback_mode():
					await _stage._reconcile_stale_join(speaker, dialogic_char)
					_is_displaying_dialogue = false
					return
				_stage.apply_group_scale_deferred.call_deferred(
					dialogic_char, 
					portrait, 
					_stage.get_total_visible_for_layout(speaker), 
					my_session_id
				)

	_stage.apply_speaker_focus_for_line(speaker, is_narrator)


	if Dialogic.Text:
		var typing_portrait: String = ""
		if not is_narrator:
			typing_portrait = str(_stage.sprite_states.get(speaker, "neutral"))
		CharacterSpriteLoader.call("apply_typing_sound_for_dialogic_character", dialogic_char, typing_portrait)
		var voice_controller: Node = preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree())
		# Resume the input/edit pause before revealing a cached first response.
		# Visible menus retain their pause through the normal overlay guard.
		AIDialogueShared.maybe_resume_dialogic_if_safe(self, _is_editing)
		var voice_valid := func(): return is_session_current(my_session_id) and not RollbackManager.is_in_rollback_mode()
		if not await voice_controller.prepare_line("narrator" if is_narrator else speaker, Dialogic.Text.parse_text(text, 0), voice_valid):
			_is_displaying_dialogue = false
			return
		await Dialogic.Text.update_textbox(text, false)


		if my_session_id != _session_id or not _is_active:
			_is_displaying_dialogue = false
			return

		var voice_text: String = Dialogic.Text.update_dialog_text(text)
		voice_controller.speak("narrator" if is_narrator else speaker, Dialogic.Text.parse_text(text, 0))


		var raw_history_index: = AIDialogueShared.store_dialogic_history_entry(text, dialogic_char, is_narrator)
		AIDialogueShared.tag_last_displayed_dialogue_history_index(_displayed_lines, raw_history_index)
		if not line_rpg_check.is_empty():
			_stamp_rpg_check_on_history_entry(raw_history_index, line_rpg_check)


		await Dialogic.Text.text_finished


	if my_session_id != _session_id or not _is_active or _cancel_current_advance_wait or RollbackManager.is_in_rollback_mode():
		_cancel_current_advance_wait = false
		_is_displaying_dialogue = false
		return

	AutosaveManager.finish_ai_reply_thumbnail(self)


	_register_ai_line_with_rollback(speaker, text, is_narrator, line_rpg_check)


	_current_displayed_text = text
	_show_edit_button = true
	_edit_enabled = true
	_update_button_visibility()


	if _interrupt_requested:
		_dialogue_queue.clear()
		_restore_input_mode("interrupt_after_reveal")
		return


	Dialogic.Text.show_next_indicators()


	Dialogic.current_state = Dialogic.States.IDLE
	await _wait_for_advance()


	if my_session_id != _session_id or not _is_active or _cancel_current_advance_wait or RollbackManager.is_in_rollback_mode():
		_cancel_current_advance_wait = false
		_is_displaying_dialogue = false
		_show_edit_button = false
		_edit_enabled = false
		Dialogic.Text.hide_next_indicators()
		return


	Dialogic.Text.hide_next_indicators()
	_update_button_visibility()


	_display_next_dialogue(my_session_id)



func _wait_for_advance() -> void :


	var request := {"ready": false, "mouse": false}
	var advance_input: Node = Dialogic.Inputs
	var on_advance := func():
		if not Dialogic.paused and not _is_editing and not AIDialogueShared.is_ui_blocking_input(self):
			request.ready = true
			request.mouse = bool(advance_input.input_was_mouse_input)
	advance_input.dialogic_action.connect(on_advance)
	AIDialogueShared.consume_touch_advance_request()
	while Dialogic.current_state == Dialogic.States.IDLE:

		if not _is_active:
			break


		if _cancel_current_advance_wait:
			_cancel_current_advance_wait = false
			break


		if _interrupt_requested:
			break


		if RollbackManager.is_in_rollback_mode():
			await get_tree().process_frame
			continue


		if Dialogic.paused:
			AIDialogueShared.maybe_resume_dialogic_if_safe(self, _is_editing)
			await get_tree().process_frame
			continue

		if AIDialogueShared.is_dialogic_input_blocked():
			await get_tree().process_frame
			continue


		if AIDialogueShared.is_ui_blocking_input(self):
			await get_tree().process_frame
			continue




		if _edit_just_closed:
			_edit_just_closed = false
			await _drain_post_edit_advance_input()
			continue

		if bool(request.ready) and not bool(request.mouse):
			break

		# Hover protection prevents mouse clicks on controls from advancing text.
		# Keyboard advance must still work while the pointer rests over a control.
		if Input.is_action_just_pressed("ui_accept"):
			break
		if Input.is_action_just_pressed("dialogic_default_action") and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			break



		var is_hovering_ui: = false
		if _interrupt_panel and _interrupt_panel.visible:
			if _interrupt_panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
				is_hovering_ui = true
		if _edit_panel and _edit_panel.visible:
			if _edit_panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
				is_hovering_ui = true


		if not is_hovering_ui:
			is_hovering_ui = _is_hovering_history_panel()


		if not is_hovering_ui:
			is_hovering_ui = AIDialogueShared.is_hovering_music_switcher(self)


		if not is_hovering_ui:
			is_hovering_ui = AIDialogueShared.is_hovering_dialogue_scrollbar(self)

		if not is_hovering_ui:
			if bool(request.ready):
				break

			if TouchScrollGesture.is_touch_platform():
				if AIDialogueShared.consume_touch_advance_request():
					break
			# Mouse releases arrive through dialogic_action after drag validation.
			if Input.is_action_just_pressed("ui_accept"):
				break
		await get_tree().process_frame

	if is_instance_valid(advance_input) and advance_input.dialogic_action.is_connected(on_advance):
		advance_input.dialogic_action.disconnect(on_advance)
	if is_inside_tree():
		await get_tree().create_timer(0.1).timeout


func _drain_post_edit_advance_input() -> void :
	await get_tree().process_frame

	while Input.is_action_pressed("dialogic_default_action") or Input.is_action_pressed("ui_accept"):
		await get_tree().process_frame



	await get_tree().process_frame



func _is_hovering_history_panel() -> bool:

	var history_nodes = get_tree().get_nodes_in_group("rollback_history")
	if history_nodes.is_empty():

		for node in get_tree().root.get_children():
			var found = _find_rollback_history(node)
			if found:
				history_nodes = [found]
				break

	if history_nodes.is_empty():
		return false

	var history_node = history_nodes[0]


	var click_consumed_val = history_node.get("click_consumed")
	var is_open_val = history_node.get("is_open")

	if click_consumed_val:
		return true


	if not is_open_val:
		return false


	var history_panel = history_node.get_node_or_null("HistoryPanel")
	if history_panel and history_panel.visible:
		if history_panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
			return true


	var dim_overlay = history_node.get_node_or_null("DimOverlay")
	if dim_overlay and dim_overlay.visible:
		if dim_overlay.get_global_rect().has_point(get_viewport().get_mouse_position()):
			return true

	return false


func _handle_command_entry(entry: Dictionary) -> void :
	var command: = str(entry.get("command", ""))
	match command:
		"location":
			_handle_runtime_location_change(str(entry.get("location_id", "")))
		"character_enter":
			await _handle_dynamic_character_enter(str(entry.get("tag", "")))
		"character_exit":
			await _handle_dynamic_character_exit(str(entry.get("tag", "")))
		"character_step_aside":
			await _handle_dynamic_character_step_aside(str(entry.get("tag", "")))


func _store_player_history_entry(text: String, display_name: String = "") -> void :
	if not Dialogic.has_subsystem("History"):
		return

	var extra_info: = {}
	var player_char: DialogicCharacter = DialogicResourceUtil.get_character_resource("player")
	var history_name: = display_name.strip_edges()
	if player_char:
		extra_info["character"] = history_name if not history_name.is_empty() else player_char.display_name
		extra_info["character_color"] = player_char.color
	else:
		extra_info["character"] = history_name if not history_name.is_empty() else "Player"

	Dialogic.History.store_simple_history_entry(text, "Text", extra_info)









func _restore_player_turn_into_history(text: String, speaker_name: String, narrator_mode: bool) -> void :
	if text.is_empty() or text == "...":
		return
	if narrator_mode:
		AIDialogueShared.store_dialogic_history_entry(text, null, true)
	else:
		_store_player_history_entry(text, speaker_name)
	_register_player_turn_with_rollback(text, speaker_name, narrator_mode)







func _get_joined_character_tags() -> Array[String]:
	var joined: Array[String] = []
	for tag in _stage.dialogic_characters.keys():
		var text_tag: = str(tag)
		var dialogic_char: DialogicCharacter = _stage.dialogic_characters[text_tag]
		if dialogic_char != null and Dialogic.Portraits.is_character_joined(dialogic_char):
			joined.append(text_tag)
	return joined


func _get_ordered_joined_character_tags() -> Array[String]:
	var ordered: Array[String] = []
	var joined_tags: = _get_joined_character_tags()

	if _is_dynamic_character_mode_enabled() and _stage.dynamic_roster != null:


		for raw_tag in _stage.dynamic_roster.get_active_tags():
			var tag: = str(raw_tag).strip_edges()
			if tag.is_empty() or not joined_tags.has(tag) or ordered.has(tag):
				continue
			ordered.append(tag)
	else:
		for char_data in _stage.character_data:
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


func _get_dynamic_roster_state() -> Dictionary:
	if _stage.dynamic_roster == null or not _is_dynamic_character_mode_enabled():
		return {}
	return _stage.dynamic_roster.get_state()


func _apply_runtime_location_change(location_id: String) -> bool:
	var target_id: = location_id.strip_edges()
	if target_id.is_empty():
		return false

	var current_location_id: = ""
	if MapManager.has_method("get_current_runtime_location_id"):
		current_location_id = str(MapManager.get_current_runtime_location_id()).strip_edges()

	var should_update_music: = target_id != current_location_id
	if MapManager.try_change_conversation_location(target_id, 0.45, should_update_music):
		if APIConfigManager.is_debug_enabled():
			if should_update_music:
				print("[DialogicAIConversation] Location changed to: " + target_id)
			else:
				print("[DialogicAIConversation] Runtime location refresh kept current music: " + target_id)
		return true
	return false


func _handle_runtime_location_change(location_id: String) -> void :
	if not _is_dynamic_location_mode_enabled():
		return
	_apply_runtime_location_change(location_id)


func _handle_dynamic_character_enter(tag: String) -> void :
	if not _is_dynamic_character_mode_enabled():
		return
	await _stage.apply_character_enter_runtime(tag)


func _handle_dynamic_character_exit(tag: String) -> void :
	if not _is_dynamic_character_mode_enabled():
		return
	await _stage.apply_character_exit_runtime(tag)


func _handle_dynamic_character_step_aside(tag: String) -> void :
	if not _is_dynamic_character_mode_enabled():
		return
	await _stage.apply_character_step_aside_runtime(tag)


func _resolve_speaker_tag_from_ai_data(ai_data: Dictionary) -> String:
	var character_id: = str(ai_data.get("character_id", "")).strip_edges()
	if character_id.is_empty():
		return ""

	for raw_tag in _stage.dialogic_characters.keys():
		var tag: = str(raw_tag)
		var character: DialogicCharacter = _stage.dialogic_characters.get(tag, null)
		if character == null:
			continue
		if character.resource_path == character_id or character.get_identifier() == character_id:
			return tag
	return ""


func _resolve_tag_from_character_id(character_id: String) -> String:
	var normalized_id: = character_id.strip_edges()
	if normalized_id.is_empty():
		return ""

	for raw_tag in _stage.dialogic_characters.keys():
		var tag: = str(raw_tag)
		var character: DialogicCharacter = _stage.dialogic_characters.get(tag, null)
		if character == null:
			continue
		if character.resource_path == normalized_id or character.get_identifier() == normalized_id:
			return tag
	return ""


func _get_tag_for_dialogic_character(dialogic_char: DialogicCharacter) -> String:
	if dialogic_char == null:
		return ""

	var tag: = _resolve_tag_from_character_id(dialogic_char.get_identifier())
	if not tag.is_empty():
		return tag

	if not dialogic_char.resource_path.is_empty():
		tag = _resolve_tag_from_character_id(dialogic_char.resource_path)
		if not tag.is_empty():
			return tag

	for raw_tag in _stage.dialogic_characters.keys():
		var text_tag: = str(raw_tag).strip_edges()
		if text_tag.is_empty():
			continue
		if _stage.dialogic_characters.get(text_tag, null) == dialogic_char:
			return text_tag

	return ""



















func _create_control_buttons() -> void :

	_cleanup_control_buttons()

	_panels.create_control_buttons(
		_dialog_text_parent, 
		_on_interrupt_pressed, 
		_on_quit_pressed, 
		_on_regenerate_pressed, 
		_on_undo_pressed, 
		_on_edit_pressed, 
		_on_sleepover_request_pressed, 
		_on_sleepover_sleep_pressed, 
		_on_pass_time_pressed, 
	)


	_interrupt_panel = _panels.interrupt_panel
	_quit_panel = _panels.quit_panel
	_regenerate_panel = _panels.regenerate_panel
	_undo_panel = _panels.undo_panel
	_edit_panel = _panels.edit_panel
	_sleepover_request_panel = _panels.sleepover_request_panel
	_sleepover_sleep_panel = _panels.sleepover_sleep_panel
	_pass_time_panel = _panels.pass_time_panel



	var panel_parent: Node = _panels.find_canvas_layer_parent(_dialog_text_parent)
	if panel_parent:
		_create_manual_dialogs(panel_parent)


func _create_manual_dialogs(parent_node: Node) -> void :
	_manual.create_dialogs(parent_node)

	_manual_roster_dialog_panel = _manual.roster_dialog_panel
	_manual_location_dialog_panel = _manual.location_dialog_panel
	_manual_emotion_dialog_panel = _manual.emotion_dialog_panel
	_register_ui_settings_targets()
	apply_ui_settings()



func _position_control_buttons() -> void :
	await get_tree().process_frame

	_configure_control_button_styles()

	_update_button_visibility()
	_update_control_button_positions()






func _configure_control_button_styles() -> void :
	_panels.configure_control_button_styles()



func _update_control_button_positions() -> void :
	_panels.update_control_button_positions(_dialog_text_parent)






func _update_button_visibility() -> void :
	var is_thinking: = _thinking_controller != null and _thinking_controller.is_animating()
	var is_busy: = is_thinking or _is_restoring_turn_state
	_panels.update_button_visibility(
		_show_interrupt_button, 
		_interrupt_requested, 
		_show_edit_button, 
		_edit_enabled, 
		_is_editing, 
		is_busy, 
		_show_quit_button, 
		_show_regenerate_button, 
		_last_user_message.is_empty(), 
		_state_snapshots.is_empty(), 
		_show_sleepover_request_button, 
		_show_sleepover_sleep_button, 
		_show_pass_time_button, 
		_show_manual_roster_button, 
		_show_manual_location_button, 
		_is_active, 
		_manual.roster_button, 
		_manual.location_button, 
		_manual.roster_dialog_panel, 
		_manual.location_dialog_panel, 
	)

	if _debug_rand_button != null:


		var emotions_allowed: = APIConfigManager.is_manual_emotions_enabled() if APIConfigManager else false
		_debug_rand_button.visible = emotions_allowed and _is_active and not _is_viewing_history



func _set_panel_enabled(panel: PanelContainer, enabled: bool) -> void :
	_panels.set_panel_enabled(panel, enabled)



func _cleanup_control_buttons() -> void :
	_cleanup_guidance_dialog()
	_manual.hide_panels()
	_manual.cleanup_dialogs()
	_panels.cleanup_control_buttons()

	_interrupt_panel = null
	_quit_panel = null
	_regenerate_panel = null
	_undo_panel = null
	_edit_panel = null


	_edit_dialog_panel = null
	_edit_text_edit = null
	_sleepover_request_panel = null
	_sleepover_sleep_panel = null
	_pass_time_panel = null
	_manual_roster_button = null
	_manual_location_button = null
	_guidance_button = null
	_debug_rand_button = null
	_manual_roster_dialog_panel = null
	_manual_location_dialog_panel = null
	_manual_emotion_dialog_panel = null
	_guidance_dialog_panel = null
	_guidance_text_edit = null


func _register_ui_settings_targets() -> void :
	if _send_button != null and not _send_button.is_in_group("ui_settings_main_button"):
		_send_button.add_to_group("ui_settings_main_button")
	if _dice_button != null and not _dice_button.is_in_group("ui_settings_dice_button"):
		_dice_button.add_to_group("ui_settings_dice_button")
	if _manual_roster_button != null and not _manual_roster_button.is_in_group("ui_settings_roster_button"):
		_manual_roster_button.add_to_group("ui_settings_roster_button")
	if _manual_location_button != null and not _manual_location_button.is_in_group("ui_settings_location_button"):
		_manual_location_button.add_to_group("ui_settings_location_button")
	if _guidance_button != null and not _guidance_button.is_in_group("ui_settings_roster_button"):
		_guidance_button.add_to_group("ui_settings_roster_button")
	if _debug_rand_button != null and not _debug_rand_button.is_in_group("ui_settings_location_button"):
		_debug_rand_button.add_to_group("ui_settings_location_button")

	if _debug_roll_option != null and not _debug_roll_option.is_in_group("ui_settings_dice_option_button"):
		_debug_roll_option.add_to_group("ui_settings_dice_option_button")
	for panel in [_manual_roster_dialog_panel, _manual_location_dialog_panel, _manual_emotion_dialog_panel, _guidance_dialog_panel]:
		if panel != null and not panel.is_in_group("ui_settings_dialogue_popup_panel"):
			panel.add_to_group("ui_settings_dialogue_popup_panel")


func apply_ui_settings() -> void :
	if Dialogic.has_subsystem("Styles") and Dialogic.Styles.has_active_layout_node():
		UISettingsManager.apply_to_dialogic_layout_node(Dialogic.Styles.get_layout_node())

	if _input_field != null:
		UISettingsManager.style_dialogue_text_edit(_input_field)

	if _send_button != null:
		_send_button.text = UISettingsManager.get_main_button_label()
		UISettingsManager.style_dialogue_main_button(_send_button)
	if _dice_button != null:
		_dice_button.text = UISettingsManager.get_dice_button_label()
		UISettingsManager.style_dialogue_dice_button(_dice_button)
	if _manual_roster_button != null:
		_manual_roster_button.text = UISettingsManager.get_roster_button_label()
		UISettingsManager.style_dialogue_roster_button(_manual_roster_button)
	if _manual_location_button != null:
		_manual_location_button.text = UISettingsManager.get_location_button_label()
		UISettingsManager.style_dialogue_location_button(_manual_location_button)
	if _guidance_button != null:
		_refresh_guidance_button_state()
		UISettingsManager.style_dialogue_roster_button(_guidance_button)
	if _debug_rand_button != null:
		UISettingsManager.style_dialogue_location_button(_debug_rand_button)

	if _debug_roll_option != null:
		UISettingsManager.style_dialogue_dice_option_button(_debug_roll_option)
	for panel in [_manual_roster_dialog_panel, _manual_location_dialog_panel, _manual_emotion_dialog_panel, _guidance_dialog_panel]:
		if panel != null:
			UISettingsManager.style_dialogue_popup_panel(panel)
	if _guidance_text_edit != null:
		UISettingsManager.style_dialogue_text_edit(_guidance_text_edit)

	if _manual_roster_dialog_panel != null:
		_style_profile_buttons_in_tree(_manual_roster_dialog_panel, "roster")
	if _manual_location_dialog_panel != null:
		_style_profile_buttons_in_tree(_manual_location_dialog_panel, "location")
	if _manual_emotion_dialog_panel != null:
		_style_profile_buttons_in_tree(_manual_emotion_dialog_panel, "location")
	if _guidance_dialog_panel != null:
		_style_profile_buttons_in_tree(_guidance_dialog_panel, "roster")
	if _guidance_apply_button != null:

		UISettingsManager.style_dialogue_main_button(_guidance_apply_button)

	if is_inside_tree():
		call_deferred("_update_control_button_positions")


func _style_profile_buttons_in_tree(root: Node, profile: String) -> void :
	if root == null:
		return
	for child in root.get_children():
		if child is Button:
			if profile == "location":
				UISettingsManager.style_dialogue_location_button(child)
			else:
				UISettingsManager.style_dialogue_roster_button(child)
		elif child is OptionButton:
			if profile == "location":
				UISettingsManager.style_dialogue_location_option_button(child)
			else:
				UISettingsManager.style_dialogue_roster_option_button(child)
		_style_profile_buttons_in_tree(child, profile)









func _save_state_snapshot() -> void :
	var dialogic_history_size: = _last_request_start_dialogic_history_size
	if dialogic_history_size < 0 and Dialogic.has_subsystem("History"):
		dialogic_history_size = Dialogic.History.simple_history_content.size()
	var snapshot = {
		"history_size": _history.size() - 2, 
		"character_tags": _stage.current_character_tags.duplicate(), 
		"roster_state": _get_dynamic_roster_state(), 
		"sprite_states": _stage.sprite_states.duplicate(), 
		"last_user_message": _last_user_message, 
		"last_player_turn_speaker_name": _last_player_turn_speaker_name, 
		"last_player_turn_narrator_mode": _last_player_turn_narrator_mode, 
		"turn_guidance": _last_turn_guidance, 
		"dialogic_history_size_before_response": dialogic_history_size, 
		"location_id_before_response": _last_request_start_location_id, 
		"music_state_before_response": _last_request_start_music_state.duplicate(true), 
		"story_context_revision": _story_context_revision_seen, 
		"story_summary_state": _get_story_summary_state_for_snapshot(), 
		"external_import_summary_text": _get_external_import_summary_text_for_snapshot(), 
	}

	_state_snapshots.append(snapshot)

	_regenerate_unavailable = false


	while _state_snapshots.size() > MAX_SNAPSHOTS:
		_state_snapshots.pop_front()



func _on_interrupt_pressed() -> void :
	Log.d("DialogicAIConversation", "Interrupt pressed viewing_history=%s displaying=%s in_flight=%s" % [_is_viewing_history, _is_displaying_dialogue, _is_request_in_flight])


	if _is_request_in_flight:
		await _cancel_in_flight_request()
		return


	if _is_viewing_history:

		_truncate_history_to_displayed()


		_truncate_dialogic_history_to_visible_state()
		_refresh_story_context_after_history_cutoff("rollback_interrupt")

		_dialogue_queue.clear()

		RollbackManager.discard_future_snapshots_from_current(false)

		resume_from_history()
		return

	if not _is_displaying_dialogue:

		if _input_container == null or not _input_container.visible:
			_restore_input_mode("interrupt_no_dialogue")
		elif APIConfigManager.is_debug_enabled():
			debug_dump_state("interrupt_no_dialogue")
		return


	_truncate_history_to_displayed()

	_interrupt_requested = true

	_panels.set_panel_text(_panels.interrupt_panel, "Stop")

	_show_interrupt_button = false
	_show_edit_button = false
	_update_button_visibility()




func _cancel_in_flight_request() -> void :
	Log.d("DialogicAIConversation", "Cancelling in-flight request")


	_ai_client.cancel_request()
	_is_request_in_flight = false


	_stop_thinking_animation()


	_rpg.pending_request.clear()
	if _pending_sleepover_invite_request and SleepoverSystem != null:
		SleepoverSystem.mark_sleepover_invite_failed()
	_pending_sleepover_invite_request = false
	_clear_failed_request_retry_state()



	_regenerate_unavailable = true


	var history_size_before: = _history.size()
	if not _history.is_empty() and _history[-1].get("role") == "user":
		_history.pop_back()
		history_size_before = _history.size()


	if _last_request_start_dialogic_history_size >= 0 and Dialogic.has_subsystem("History"):
		var current_size: = Dialogic.History.simple_history_content.size()
		if current_size > _last_request_start_dialogic_history_size:
			Dialogic.History.simple_history_content.resize(_last_request_start_dialogic_history_size)


	_prune_rollback_snapshots_after_history_size(history_size_before)



	var my_session_id: = _session_id
	await _restore_pre_send_scene_state()
	if my_session_id != _session_id or not _is_active:
		return
	_restore_pending_turn_guidance_for_resend()


	_panels.set_panel_text(_panels.interrupt_panel, "Stop")


	_show_input_in_textbox(_last_user_message)






func _restore_pre_send_scene_state() -> void :
	var _sprite_sound_scope: = SpriteSoundManager.suppress()
	var my_session_id: = _session_id




	var pending_user_message: = _last_user_message
	var pending_speaker_name: = _last_player_turn_speaker_name
	var pending_narrator_mode: = _last_player_turn_narrator_mode
	var pending_guidance: = _last_turn_guidance
	var pending_custom_prompt: = _custom_system_prompt_override
	var pending_initial_setup: = _initial_setup.duplicate(true)
	var pending_initial_setup_enabled: = _initial_setup_enabled
	var pending_initial_setup_stopped: = _initial_setup_stopped
	var pending_management_context: = _last_request_management_context.duplicate(true)
	var pending_regenerate_unavailable: = _regenerate_unavailable





	var live_tag_order: Array[String] = _stage.current_character_tags.duplicate()
	var live_active_order: Array[String] = []
	if _stage.dynamic_roster != null:
		live_active_order = _stage.dynamic_roster.get_active_tags()
	var snapshots: = RollbackManager.get_all_snapshots()
	if not snapshots.is_empty():
		var pre_send_snap: = snapshots[-1]
		var ai_data: Dictionary = pre_send_snap.get("ai_data", {})





		for entered_tag in _last_pending_enters:
			var normalized_entered: = str(entered_tag).strip_edges()
			if not normalized_entered.is_empty():
				await _stage.hide_character_sprite(normalized_entered, 0.0, my_session_id)
				if not is_session_current(my_session_id):
					return




		_restore_ai_state_from_data(ai_data)
		_last_user_message = pending_user_message
		_last_player_turn_speaker_name = pending_speaker_name
		_last_player_turn_narrator_mode = pending_narrator_mode
		_last_turn_guidance = pending_guidance



		_custom_system_prompt_override = pending_custom_prompt
		_initial_setup = pending_initial_setup
		_initial_setup_enabled = pending_initial_setup_enabled
		_initial_setup_stopped = pending_initial_setup_stopped
		_system_prompt = ""
		_refresh_initial_setup_button()
		_last_request_management_context = pending_management_context


		_regenerate_unavailable = pending_regenerate_unavailable







		_reorder_roster_to_live_layout(live_tag_order, live_active_order)






		await RollbackManager._restore_snapshot(pre_send_snap, true)
		if my_session_id != _session_id or not _is_active:
			return


		var rollback_location_id: = str(ai_data.get("location_id", "")).strip_edges()
		if not rollback_location_id.is_empty() and rollback_location_id != "_timeline_driven":
			_restore_location_for_regenerate(rollback_location_id, true, "cancel")



		_manual.pending_enters = _last_pending_enters.duplicate()
		_manual.pending_exits = _last_pending_exits.duplicate()
		_manual.pending_step_asides = _last_pending_step_asides.duplicate()
		_manual.pending_location_id = _last_pending_location_id
		_manual.update_panel_state()





		await show_initial_character_portraits([], my_session_id)
		if not is_session_current(my_session_id):
			return


		_stage.refresh_group_layout(-1, false)




func _truncate_history_to_displayed() -> void :
	if _history.is_empty():
		return


	if _history[-1].get("role") != "assistant":
		return


	var truncated_response: = _build_response_from_displayed_lines(_displayed_lines)
	_history[-1]["content"] = truncated_response.strip_edges()


func _count_history_dialogue_entries(lines: Array) -> int:
	var count: = 0
	for raw_line_entry in lines:
		var line_entry: Dictionary = raw_line_entry
		var entry_type: String = line_entry.get("type", "dialogue")
		if entry_type != "sprite" and entry_type != "command":
			count += 1
	return count


func _get_visible_dialogic_history_size(fallback_size: int = -1) -> int:
	var target_size: = -1

	if RollbackManager.is_in_rollback_mode() or _is_viewing_history:
		var rollback_ai_data: = RollbackManager.get_current_ai_data()
		if not rollback_ai_data.is_empty():
			target_size = RollbackManager.get_visible_dialogic_history_size(rollback_ai_data)

	if target_size < 0 and not _state_snapshots.is_empty():
		var last_snapshot: Dictionary = _state_snapshots[-1]
		var before_response_size: = int(last_snapshot.get("dialogic_history_size_before_response", -1))
		if before_response_size >= 0:
			target_size = before_response_size + _count_history_dialogue_entries(_displayed_lines)

	if target_size < 0:
		target_size = fallback_size

	if target_size < 0 and Dialogic.has_subsystem("History"):
		target_size = Dialogic.History.simple_history_content.size()

	return target_size


func _truncate_dialogic_history_to_visible_state() -> void :
	if not Dialogic.has_subsystem("History"):
		return

	var target_size: = _get_visible_dialogic_history_size()
	if target_size < 0:
		return

	var current_size: = Dialogic.History.simple_history_content.size()
	if current_size > target_size:
		if APIConfigManager.is_debug_enabled():
			print("[DialogicAIConversation] Truncating Dialogic history from %d to %d to match visible rollback state" % [
				current_size, 
				target_size
			])
		Dialogic.History.simple_history_content.resize(target_size)


func _rewind_player_turn_to_input_state(rollback_ai_data: Dictionary) -> void :
	var target_history_size: = 0
	var snapshot_history: Variant = rollback_ai_data.get("history", [])
	if snapshot_history is Array:
		target_history_size = maxi(0, (snapshot_history as Array).size() - 1)

	while _history.size() > target_history_size:
		_history.pop_back()







	var kept_state_snapshots: Array = []
	for state_snapshot in _state_snapshots:
		if not state_snapshot is Dictionary:
			continue
		if int((state_snapshot as Dictionary).get("history_size", -1)) < target_history_size:
			kept_state_snapshots.append(state_snapshot)
	_state_snapshots = kept_state_snapshots

	var target_dialogic_size: = int(rollback_ai_data.get("dialogic_history_length", -1))
	if target_dialogic_size > 0 and Dialogic.has_subsystem("History"):
		var resized_target: = maxi(0, target_dialogic_size - 1)
		var current_size: = Dialogic.History.simple_history_content.size()
		if current_size > resized_target:
			Dialogic.History.simple_history_content.resize(resized_target)

	_prune_rollback_snapshots_after_history_size(target_history_size, false)
	_last_user_message = ""
	_last_turn_guidance = ""
	_set_pending_turn_guidance(str(rollback_ai_data.get("last_turn_guidance", "")))
	_refresh_story_context_after_history_cutoff("rollback_player_turn_rewind")


func _refresh_story_context_after_history_cutoff(reason: String) -> void :



	_refresh_story_context_from_manager(true, false)
	if APIConfigManager.is_debug_enabled():
		print("[DialogicAIConversation] Refreshed story context after %s len=%d" % [
			reason, 
			_story_context.length()
		])


func _build_response_from_displayed_lines(lines: Array) -> String:
	var response: = ""
	for raw_line_entry in lines:
		var line_entry: Dictionary = raw_line_entry
		var entry_type: String = line_entry.get("type", "dialogue")

		if entry_type == "sprite":
			var tag: String = line_entry.get("tag", "")
			var emotion: String = line_entry.get("emotion", "")
			response += "[sprite: " + tag + " " + emotion + "]\n"
		elif entry_type == "command":
			var cmd: = str(line_entry.get("command", ""))
			match cmd:
				"location":
					var location_id: = str(line_entry.get("location_id", ""))
					if not location_id.is_empty():
						response += "[location: " + location_id + "]\n"
				"character_enter":
					var enter_tag: = str(line_entry.get("tag", ""))
					if not enter_tag.is_empty():
						response += "[character_enter: " + enter_tag + "]\n"
				"character_exit":
					var exit_tag: = str(line_entry.get("tag", ""))
					if not exit_tag.is_empty():
						response += "[character_exit: " + exit_tag + "]\n"
				"character_step_aside":
					var aside_tag: = str(line_entry.get("tag", ""))
					if not aside_tag.is_empty():
						response += "[character_step_aside: " + aside_tag + "]\n"
		else:
			var speaker: String = line_entry.get("speaker", "")
			var text: String = line_entry.get("text", "")
			var is_narrator: bool = line_entry.get("is_narrator", false)

			if is_narrator:
				response += "narrator \"" + text + "\"\n"
			else:
				response += speaker + " \"" + text + "\"\n"

	return response


func _build_normalized_history_view_save_state(dialogic_history_size: int) -> Dictionary:
	var normalized_history: = _history.duplicate(true)
	if not normalized_history.is_empty() and normalized_history[-1].get("role") == "assistant" and not _displayed_lines.is_empty():
		normalized_history[-1]["content"] = _build_response_from_displayed_lines(_displayed_lines).strip_edges()

	var normalized_dialogic_history_size: = _get_visible_dialogic_history_size(dialogic_history_size)
	var normalized_state_snapshots: Array = []
	for snapshot in _state_snapshots:
		if not snapshot is Dictionary:
			continue
		var snapshot_history_size: = int((snapshot as Dictionary).get("history_size", -1))
		if snapshot_history_size >= normalized_history.size():
			continue
		normalized_state_snapshots.append((snapshot as Dictionary).duplicate(true))
	var prefilled_input_text: = ""
	var prefilled_turn_guidance: = _pending_turn_guidance
	if RollbackManager.is_in_rollback_mode():
		var rollback_ai_data: = RollbackManager.get_current_ai_data()
		if rollback_ai_data.get("is_player_turn", false):
			prefilled_input_text = str(rollback_ai_data.get("player_input_text", rollback_ai_data.get("last_user_message", "")))
			prefilled_turn_guidance = str(rollback_ai_data.get("last_turn_guidance", ""))
			var rollback_dialogic_size: = int(rollback_ai_data.get("dialogic_history_length", -1))
			if rollback_dialogic_size > 0:
				normalized_dialogic_history_size = maxi(0, rollback_dialogic_size - 1)
			if not normalized_history.is_empty():
				var last_entry: Dictionary = normalized_history[-1]
				if last_entry.get("role", "") == "user" and last_entry.get("content", "") == prefilled_input_text:
					normalized_history.pop_back()
					var pruned_snapshots: Array = []
					for snapshot in normalized_state_snapshots:
						if int((snapshot as Dictionary).get("history_size", -1)) < normalized_history.size():
							pruned_snapshots.append(snapshot)
					normalized_state_snapshots = pruned_snapshots

	if APIConfigManager.is_debug_enabled():
		print("[DialogicAIConversation][Save] Normalizing rollback/history save state displayed_lines=%d discarded_queue=%d history_entries=%d undo_snapshots=%d dialogic_history_size=%d" % [
			_displayed_lines.size(), 
			_dialogue_queue.size(), 
			normalized_history.size(), 
			normalized_state_snapshots.size(), 
			normalized_dialogic_history_size
		])

	return {
		"is_active": _is_active, 
		"rollback_owner_key": _rollback_owner_key, 
		"character_tags": _stage.current_character_tags.duplicate(), 
		"roster_state": _get_dynamic_roster_state(), 
		"history": normalized_history, 
			"sprite_states": _stage.sprite_states.duplicate(), 
			"last_user_message": _last_user_message, 
			"last_player_turn_speaker_name": _last_player_turn_speaker_name, 
			"last_player_turn_narrator_mode": _last_player_turn_narrator_mode, 
			"last_turn_guidance": _last_turn_guidance, 
			"pending_turn_guidance": prefilled_turn_guidance, 
			"last_request_management_context": _last_request_management_context.duplicate(true), 
			"system_prompt": _system_prompt, 
		"custom_system_prompt_override": _custom_system_prompt_override, 
		"initial_setup": _initial_setup.duplicate(true), 
		"initial_setup_enabled": _initial_setup_enabled, 
		"initial_setup_stopped": _initial_setup_stopped, 
		"prefill_scope": _prefill_scope, 
		"custom_prompt_baked_tags": _custom_prompt_baked_tags.duplicate(), 
		"story_context": _story_context, 
		"story_context_revision": _story_context_revision_seen, 
		"story_summary_state": _get_story_summary_state_for_snapshot(), 


		"dialogue_queue": [], 
		"displayed_lines": _displayed_lines.duplicate(true), 
		"is_displaying_dialogue": false, 
		"state_snapshots": normalized_state_snapshots, 
		"dialogic_history_size": normalized_dialogic_history_size, 
		"prefilled_input_text": prefilled_input_text, 
		"audio_state": RollbackManager.get_selected_audio_state(), 
	}



func _on_quit_pressed() -> void :
	_show_end_chat_confirm_dialog()







func _on_regenerate_pressed(rewrite_instruction: String = "") -> void :
	if _last_user_message.is_empty() or _regenerate_unavailable or _is_restoring_turn_state:
		return

	_is_restoring_turn_state = true
	_update_button_visibility()

	var snapshot_location_id: String = ""
	var has_snapshot_music_state: = false
	var snapshot_music_state: Dictionary = {}
	var regenerate_text: = _last_user_message
	var regenerate_guidance: = _capture_turn_guidance_for_redo()

	var regenerate_rewrite_note: = _prompt_manager.build_rewrite_request_note(
		_find_last_assistant_response(), 
		rewrite_instruction
	)
	_last_rewrite_note = regenerate_rewrite_note


	var regenerate_history_content: = regenerate_text
	if _last_player_turn_narrator_mode and regenerate_text != "...":
		regenerate_history_content = "Narrator: %s" % regenerate_text
	var should_restore_user_history: = true
	var history_size_before_exchange: = _history.size()


	var visible_player_entry_removed: = false


	if not _state_snapshots.is_empty():
		var last_snapshot: Dictionary = _state_snapshots.pop_back()
		snapshot_location_id = str(last_snapshot.get("location_id_before_response", ""))
		has_snapshot_music_state = last_snapshot.has("music_state_before_response")
		var raw_snapshot_music_state: Variant = last_snapshot.get("music_state_before_response", {})
		if raw_snapshot_music_state is Dictionary:
			snapshot_music_state = (raw_snapshot_music_state as Dictionary).duplicate(true)
		history_size_before_exchange = int(last_snapshot.get("history_size", _history.size()))
		while _history.size() > history_size_before_exchange:
			_history.pop_back()



		var dialogic_size: int = last_snapshot.get("dialogic_history_size_before_response", -1)
		if dialogic_size >= 0 and Dialogic.has_subsystem("History"):
			var current_size: = Dialogic.History.simple_history_content.size()
			if current_size > dialogic_size:
				Dialogic.History.simple_history_content.resize(dialogic_size)
				visible_player_entry_removed = true
		_prune_rollback_snapshots_after_history_size(history_size_before_exchange)
		var my_session_id: = _session_id
		await _restore_pre_response_snapshot(last_snapshot, my_session_id)





		if my_session_id != _session_id or not _is_active:
			_is_restoring_turn_state = false
			_update_button_visibility()
			return
	else:

		if not _history.is_empty() and _history[-1].get("role") == "assistant":
			_history.pop_back()
		if not _history.is_empty() and _history[-1].get("role") == "user" and _history[-1].get("content", "") == regenerate_history_content:
			should_restore_user_history = false
		_prune_rollback_snapshots_after_history_size(_history.size())






	_restore_location_for_regenerate(snapshot_location_id, not has_snapshot_music_state)
	if has_snapshot_music_state:
		_restore_music_state_if_needed(snapshot_music_state)

	if should_restore_user_history:
		_history.append({"role": "user", "content": regenerate_history_content})


	_hide_input_field()
	_show_quit_button = false
	_show_regenerate_button = false
	_show_sleepover_request_button = false
	_show_sleepover_sleep_button = false
	_show_pass_time_button = false
	_is_restoring_turn_state = false
	_update_button_visibility()
	_show_thinking_indicator()


	var regenerate_management_context: = _get_regenerate_management_context()
	if not _rpg.last_request.is_empty():
		var saved_roll: int = int(_rpg.last_request.get("roll", 1))
		var saved_action: String = str(_rpg.last_request.get("action_text", regenerate_text))
		_rpg.pending_request = _rpg.last_request.duplicate(true)
		var request_prompt_data: = _build_rpg_roll_prompt_data(saved_action, saved_roll, "", regenerate_management_context, regenerate_guidance, regenerate_rewrite_note)
		_capture_request_start_state( not should_restore_user_history)
		if visible_player_entry_removed:
			_restore_player_turn_into_history(regenerate_text, _last_player_turn_speaker_name, _last_player_turn_narrator_mode)
		_is_request_in_flight = true
		_ask_with_prompt_data(request_prompt_data, saved_action)
		return


	var request_prompt_data: = _build_request_prompt_data("", regenerate_management_context, regenerate_text, regenerate_guidance, regenerate_rewrite_note)
	if regenerate_text == "..." and SleepoverSystem != null:
		var tags: = _get_sleepover_character_tags()
		var location_id: = _resolve_sleepover_location_id(tags)
		if not location_id.is_empty() and not tags.is_empty():
			SleepoverSystem.begin_sleepover_invite(location_id, tags)
			_pending_sleepover_invite_request = true
			request_prompt_data = _build_sleepover_request_prompt_data(location_id, tags, "", regenerate_management_context, regenerate_guidance, regenerate_rewrite_note)
	_capture_request_start_state( not should_restore_user_history)
	if visible_player_entry_removed:
		_restore_player_turn_into_history(regenerate_text, _last_player_turn_speaker_name, _last_player_turn_narrator_mode)
	_is_request_in_flight = true
	_ask_with_prompt_data(request_prompt_data, regenerate_history_content)



func _on_undo_pressed() -> void :
	if _state_snapshots.is_empty() or _is_restoring_turn_state:
		return

	_is_restoring_turn_state = true
	_update_button_visibility()


	var snapshot: Dictionary = _state_snapshots.pop_back()
	var snapshot_location_id: String = str(snapshot.get("location_id_before_response", ""))
	var has_snapshot_music_state: = snapshot.has("music_state_before_response")
	var snapshot_music_state: Dictionary = {}
	var raw_snapshot_music_state: Variant = snapshot.get("music_state_before_response", {})
	if raw_snapshot_music_state is Dictionary:
		snapshot_music_state = (raw_snapshot_music_state as Dictionary).duplicate(true)


	var target_size: int = snapshot.get("history_size", 0)
	while _history.size() > target_size:
		_history.pop_back()
	_prune_rollback_snapshots_after_history_size(target_size)


	var dialogic_size: int = snapshot.get("dialogic_history_size_before_response", -1)
	if dialogic_size >= 0 and Dialogic.has_subsystem("History"):
		var current_size: = Dialogic.History.simple_history_content.size()
		if current_size > dialogic_size:
			Dialogic.History.simple_history_content.resize(dialogic_size)

	var my_session_id: = _session_id
	await _restore_pre_response_snapshot(snapshot, my_session_id)



	if my_session_id != _session_id or not _is_active:
		_is_restoring_turn_state = false
		_update_button_visibility()
		return
	_restore_location_for_regenerate(snapshot_location_id, not has_snapshot_music_state, "undo")
	if has_snapshot_music_state:
		_restore_music_state_if_needed(snapshot_music_state)



	_last_user_message = ""
	_last_player_turn_speaker_name = ""
	_last_player_turn_narrator_mode = false
	if not _state_snapshots.is_empty():
		var previous_turn: Dictionary = _state_snapshots[-1]
		_last_user_message = str(previous_turn.get("last_user_message", ""))
		_last_player_turn_speaker_name = str(previous_turn.get("last_player_turn_speaker_name", ""))
		_last_player_turn_narrator_mode = bool(previous_turn.get("last_player_turn_narrator_mode", false))
	else:
		for i in range(_history.size() - 1, -1, -1):
			if _history[i].get("role") != "user":
				continue
			_last_user_message = str(_history[i].get("content", ""))
			if _last_user_message.begins_with("Narrator: "):
				_last_user_message = _last_user_message.trim_prefix("Narrator: ")
				_last_player_turn_narrator_mode = true
			if _last_user_message == "...":
				_last_user_message = ""
			break

	_regenerate_unavailable = false


	_rpg.last_request.clear()
	_last_turn_guidance = (
		str(_state_snapshots[-1].get("turn_guidance", ""))
		if not _state_snapshots.is_empty()
		else ""
	)
	_set_pending_turn_guidance("")
	_last_request_management_context.clear()
	_active_response_management_context.clear()


	_dialogue_queue.clear()
	_is_restoring_turn_state = false
	_show_input_in_textbox()


func _prune_rollback_snapshots_after_history_size(history_size_before_exchange: int, reset_rollback_state: bool = true) -> void :
	RollbackManager.prune_ai_snapshots_after_history_size(history_size_before_exchange, reset_rollback_state)


func _extract_snapshot_character_tags(snapshot: Dictionary, roster_state: Dictionary, sprite_states: Dictionary) -> Array[String]:
	var tags: Array[String] = []

	var snapshot_tags_variant = snapshot.get("character_tags", [])
	if snapshot_tags_variant is Array:
		for raw_tag in snapshot_tags_variant:
			var tag: = str(raw_tag).strip_edges()
			if tag.is_empty() or tags.has(tag):
				continue
			tags.append(tag)

	if tags.is_empty():
		var active_variant = roster_state.get("active_tags", [])
		if active_variant is Array:
			for raw_tag in active_variant:
				var tag: = str(raw_tag).strip_edges()
				if tag.is_empty() or tags.has(tag):
					continue
				tags.append(tag)

	if tags.is_empty():
		for raw_tag in sprite_states.keys():
			var tag: = str(raw_tag).strip_edges()
			if tag.is_empty() or tags.has(tag):
				continue
			tags.append(tag)

	return tags


func _get_snapshot_visible_tags(snapshot_tags: Array[String], roster_state: Dictionary) -> Array[String]:
	var visible_tags: Array[String] = []
	var visible_variant = roster_state.get("visible_tags", [])
	if visible_variant is Array:
		for raw_tag in visible_variant:
			var tag: = str(raw_tag).strip_edges()
			if tag.is_empty() or visible_tags.has(tag):
				continue
			if not snapshot_tags.has(tag):
				continue
			visible_tags.append(tag)

	if visible_tags.is_empty():
		visible_tags = snapshot_tags.duplicate()

	return visible_tags


func _restore_character_list_from_tags(tags: Array[String]) -> void :
	_stage.current_character_tags.clear()
	_stage.character_data.clear()

	for raw_tag in tags:
		_stage.add_character_to_conversation(str(raw_tag).strip_edges())








func _reorder_roster_to_live_layout(live_tag_order: Array[String], live_active_order: Array[String] = []) -> void :
	if _stage.dynamic_roster != null and not live_active_order.is_empty():
		_stage.dynamic_roster.reorder_active_tags(live_active_order)

	var restored_tags: = _stage.current_character_tags
	var reordered_tags: Array[String] = []
	for tag in live_tag_order:
		if tag in restored_tags and not tag in reordered_tags:
			reordered_tags.append(tag)
	for tag in restored_tags:
		if not tag in reordered_tags:
			reordered_tags.append(tag)
	if reordered_tags == restored_tags:
		return

	var data_by_tag: = {}
	for entry in _stage.character_data:
		if entry != null:
			data_by_tag[entry.tag] = entry
	var reordered_data: Array[CharacterData] = []
	for tag in reordered_tags:
		if data_by_tag.has(tag):
			reordered_data.append(data_by_tag[tag])
	for entry in _stage.character_data:
		if entry != null and not entry in reordered_data:
			reordered_data.append(entry)

	_stage.current_character_tags = reordered_tags
	_stage.character_data = reordered_data


func _restore_pre_response_snapshot(snapshot: Dictionary, expected_session_id: int = -1) -> void :
	var _sprite_sound_scope: = SpriteSoundManager.suppress()
	var session_id: = expected_session_id if expected_session_id >= 0 else _session_id
	if not is_session_current(session_id):
		return
	var saved_roster_state: Dictionary = snapshot.get("roster_state", {})
	var saved_sprite_states: Dictionary = snapshot.get("sprite_states", {})
	var snapshot_tags: = _extract_snapshot_character_tags(snapshot, saved_roster_state, saved_sprite_states)

	_restore_story_summary_state_from_snapshot(snapshot)
	_restore_external_import_summary_text_from_snapshot(snapshot)
	var restored_story_revision: = _get_story_summary_context_revision()
	if restored_story_revision < 0:
		restored_story_revision = int(snapshot.get("story_context_revision", _story_context_revision_seen))
	_story_context_revision_seen = restored_story_revision
	_refresh_story_context_from_manager(true, false)
	_restore_character_list_from_tags(snapshot_tags)
	_stage.sprite_states = saved_sprite_states.duplicate(true)

	if _stage.dynamic_roster != null:
		if saved_roster_state is Dictionary and not saved_roster_state.is_empty():
			_stage.dynamic_roster.restore_state(saved_roster_state, snapshot_tags)
		elif _is_dynamic_character_mode_enabled():
			_stage.dynamic_roster.configure(snapshot_tags, MAX_DYNAMIC_VISIBLE_CHARACTERS)

	var visible_tags: = _get_snapshot_visible_tags(snapshot_tags, saved_roster_state)
	_stage.begin_session(session_id, visible_tags)

	for joined_tag in _get_joined_character_tags():
		if visible_tags.has(joined_tag):
			continue
		await _stage.hide_character_sprite(joined_tag, 0.0, session_id)
		if not is_session_current(session_id):
			return

	for tag in visible_tags:
		if not _stage.dialogic_characters.has(tag):
			continue

		var dialogic_char: DialogicCharacter = _stage.dialogic_characters[tag]
		var portrait: = str(_stage.sprite_states.get(tag, "neutral"))

		if not Dialogic.Portraits.is_character_joined(dialogic_char):
			await _stage.join_character_for_runtime(tag, portrait, 0.0, true, session_id)
			if not is_session_current(session_id):
				return
		elif dialogic_char.portraits.has(portrait):
			Log.d(
				"DialogicAIConversation", 
				"Restore portrait change | tag=%s portrait=%s total_chars=%d" % [
					tag, 
					portrait, 
					_stage.get_total_visible_for_layout(tag), 
				]
			)
			_stage.prepare_group_layout_before_portrait_change(tag, dialogic_char, _stage.get_total_visible_for_layout(tag))
			await Dialogic.Portraits.change_character_portrait(dialogic_char, portrait)
			if not is_session_current(session_id):
				await _stage._reconcile_stale_join(tag, dialogic_char)
				return
			_stage.apply_group_scale_deferred.call_deferred(
				dialogic_char, 
				portrait, 
				_stage.get_total_visible_for_layout(tag), 
				session_id
			)

	_update_line_processor_valid_tags()
	_stage.refresh_group_layout(_stage.get_total_visible_for_layout())


func _get_external_import_summary_text_for_snapshot() -> String:
	if StorySummaryManager == null or not StorySummaryManager.has_method("has_external_import_context"):
		return ""
	if not StorySummaryManager.has_external_import_context():
		return ""
	var imported_context: Dictionary = StorySummaryManager.get_external_import_context()
	return str(imported_context.get("raw_summary_text", "")).strip_edges()


func _get_story_summary_state_for_snapshot() -> Dictionary:
	if StorySummaryManager == null or not StorySummaryManager.has_method("get_save_state"):
		return {}
	var raw_state: Variant = StorySummaryManager.get_save_state()
	if raw_state is Dictionary:
		return (raw_state as Dictionary).duplicate(true)
	return {}


func _restore_story_summary_state_from_snapshot(snapshot: Dictionary) -> void :
	if StorySummaryManager == null or not StorySummaryManager.has_method("load_save_state"):
		return
	var raw_state: Variant = snapshot.get("story_summary_state", {})
	if raw_state is Dictionary and not (raw_state as Dictionary).is_empty():
		StorySummaryManager.load_save_state((raw_state as Dictionary).duplicate(true))
	else:


		StorySummaryManager.load_save_state({})
	_migrate_legacy_context_override_entries_from_state(snapshot)


func _restore_external_import_summary_text_from_snapshot(snapshot: Dictionary) -> void :
	if StorySummaryManager == null or not StorySummaryManager.has_method("has_external_import_context"):
		return
	if not StorySummaryManager.has_external_import_context():
		return

	var snapshot_summary_text: = str(snapshot.get("external_import_summary_text", "")).strip_edges()
	if snapshot_summary_text.is_empty():
		return

	var imported_context: Dictionary = StorySummaryManager.get_external_import_context()
	var current_summary_text: = str(imported_context.get("raw_summary_text", "")).strip_edges()
	if current_summary_text == snapshot_summary_text:
		return

	StorySummaryManager.edit_external_import_context_text(snapshot_summary_text)



func _on_edit_pressed() -> void :
	if _is_editing:
		return
	if RollbackManager.is_in_rollback_mode() and not _is_viewing_history:
		return
	if RollbackManager.is_in_rollback_mode() and not _sync_history_view_state_from_current_snapshot():
		return
	if _current_displayed_text.is_empty():
		return
	_open_edit_dialog()



func _open_edit_dialog() -> void :
	if RollbackManager.is_in_rollback_mode() and not _sync_history_view_state_from_current_snapshot():
		return
	if _panels.edit_dialog_panel == null:
		_panels.create_edit_dialog(_dialog_text_parent, _apply_edit_text, _close_edit_dialog)

	_edit_dialog_panel = _panels.edit_dialog_panel
	_edit_text_edit = _panels.edit_text_edit

	if _edit_dialog_panel == null:
		return

	_is_editing = true
	_show_interrupt_before_edit = _show_interrupt_button
	_show_interrupt_button = false
	_show_edit_button = false
	_edit_enabled = false
	_update_button_visibility()

	_edit_text_edit.text = _current_displayed_text
	_edit_dialog_panel.visible = true
	_panels.position_edit_dialog()
	_edit_text_edit.grab_focus()

	Dialogic.paused = true



func _close_edit_dialog() -> void :
	if _edit_dialog_panel:
		_edit_dialog_panel.visible = false
	_is_editing = false
	_edit_just_closed = true
	_show_interrupt_button = _show_interrupt_before_edit
	if RollbackManager.is_in_rollback_mode() and _is_viewing_history:
		_show_edit_button = not _current_displayed_text.is_empty()
		_edit_enabled = _show_edit_button
	else:
		_show_edit_button = _is_displaying_dialogue
		_edit_enabled = _is_displaying_dialogue
	_update_button_visibility()
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
	var previous_response: = _build_current_assistant_response_from_runtime_state()
	_current_displayed_text = new_text

	if Dialogic.Text:
		Dialogic.Text.update_dialog_text(new_text, true)

	_update_last_displayed_line(new_text)
	_update_last_dialogic_history_line(new_text, previous_text)
	_refresh_story_context_from_manager(true, false)
	var updated_response: = _build_current_assistant_response_from_runtime_state()
	_sync_last_assistant_history_from_display_state(updated_response)
	_update_last_ai_snapshot(new_text, previous_text, previous_response, updated_response)

	_close_edit_dialog()



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

	var last_dialogue_entry: = _find_last_dialogue_entry()
	var raw_history_index: = -1
	for i in range(_displayed_lines.size() - 1, -1, -1):
		var entry: Dictionary = _displayed_lines[i]
		if entry.get("type", "dialogue") != "dialogue":
			continue
		raw_history_index = int(entry.get("raw_history_index", -1))
		break

	if raw_history_index < 0:
		raw_history_index = _find_matching_dialogic_history_index(previous_text, last_dialogue_entry)

	if raw_history_index < 0:
		return

	if raw_history_index >= Dialogic.History.simple_history_content.size():
		return

	var history_entry: Dictionary = Dialogic.History.simple_history_content[raw_history_index]
	history_entry["text"] = new_text
	Dialogic.History.simple_history_content[raw_history_index] = history_entry
	Dialogic.History.simple_history_changed.emit()


func _find_matching_dialogic_history_index(previous_text: String, dialogue_entry: Dictionary = {}) -> int:
	if not Dialogic.has_subsystem("History"):
		return -1

	var expected_text: = previous_text.strip_edges()
	if expected_text.is_empty():
		expected_text = str(dialogue_entry.get("text", "")).strip_edges()
	if expected_text.is_empty():
		return -1

	var expected_character: = ""
	if not bool(dialogue_entry.get("is_narrator", false)):
		var speaker_tag: = str(dialogue_entry.get("speaker", "")).strip_edges()
		if not speaker_tag.is_empty() and _stage.dialogic_characters.has(speaker_tag):
			var dialogic_char: DialogicCharacter = _stage.dialogic_characters[speaker_tag]
			if dialogic_char != null:
				expected_character = dialogic_char.display_name.strip_edges()

	for i in range(Dialogic.History.simple_history_content.size() - 1, -1, -1):
		var history_entry: Dictionary = Dialogic.History.simple_history_content[i]
		if str(history_entry.get("event_type", "")).strip_edges() != "Text":
			continue
		if str(history_entry.get("text", "")).strip_edges() != expected_text:
			continue
		if _is_player_dialogic_history_entry(history_entry):
			continue
		if not expected_character.is_empty():
			var history_character: = str(history_entry.get("character", "")).strip_edges()
			if history_character != expected_character:
				continue
		return i

	return -1


func _build_current_assistant_response_from_runtime_state() -> String:
	var response_entries: Array = []
	for raw_entry in _displayed_lines:
		if raw_entry is Dictionary:
			response_entries.append((raw_entry as Dictionary).duplicate(true))
	for raw_entry in _dialogue_queue:
		if raw_entry is Dictionary:
			response_entries.append((raw_entry as Dictionary).duplicate(true))
	return _build_response_from_displayed_lines(response_entries).strip_edges()


func _sync_last_assistant_history_from_display_state(rebuilt_response: String = "") -> void :
	if rebuilt_response.is_empty():
		rebuilt_response = _build_current_assistant_response_from_runtime_state()
	if rebuilt_response.is_empty():
		return

	var assistant_index: = _find_last_assistant_history_index(_history)
	if assistant_index < 0:
		return

	var entry: Dictionary = _history[assistant_index]
	entry["content"] = rebuilt_response
	_history[assistant_index] = entry


func _find_last_assistant_history_index(history: Array) -> int:
	for i in range(history.size() - 1, -1, -1):
		var entry: Dictionary = history[i]
		if entry.get("role", "") == "assistant":
			return i
	return -1





func _update_last_ai_snapshot(new_text: String, previous_text: String = "", previous_response: String = "", updated_response: String = "") -> void :
	var assistant_history_index: = _find_last_assistant_history_index(_history)
	if updated_response.is_empty():
		updated_response = _build_current_assistant_response_from_runtime_state()


	var edited_history_index: = -1
	for i in range(_displayed_lines.size() - 1, -1, -1):
		var entry: Dictionary = _displayed_lines[i]
		if entry.get("type", "dialogue") != "dialogue":
			continue
		edited_history_index = int(entry.get("raw_history_index", -1))
		break

	RollbackManager.update_last_ai_snapshot(
		new_text, 
		_history.duplicate(true), 
		_displayed_lines.duplicate(true), 
		_dialogue_queue.duplicate(true), 
		edited_history_index, 
		previous_text, 
		assistant_history_index, 
		previous_response, 
		updated_response, 
		func(lines: Array) -> String: return _build_response_from_displayed_lines(lines)
	)







func _register_player_turn_with_rollback(text: String, speaker_name: String = "You", narrator_mode: bool = false) -> void :
	if text.is_empty():
		return

	var dialogic_history_length: = -1
	if Dialogic.has_subsystem("History"):
		dialogic_history_length = Dialogic.History.simple_history_content.size()

	var player_char: = DialogicResourceUtil.get_character_resource("player")
	var player_char_id: = ""
	if player_char and not narrator_mode:
		player_char_id = player_char.resource_path
		if player_char_id.is_empty():
			player_char_id = player_char.get_identifier()

	var ai_data: = {
		"rollback_owner_key": _rollback_owner_key, 
		"rollback_owner_kind": get_rollback_owner_kind(), 
		"character_tags": _stage.current_character_tags.duplicate(), 
		"roster_state": _get_dynamic_roster_state(), 
		"history": _history.duplicate(true), 
		"sprite_states": _stage.sprite_states.duplicate(), 
		"last_user_message": text, 
		"last_player_turn_speaker_name": speaker_name, 
		"last_player_turn_narrator_mode": narrator_mode, 
		"player_input_text": text, 
		"last_turn_guidance": _last_turn_guidance, 
		"last_request_management_context": _last_request_management_context.duplicate(true), 
		"character_name": speaker_name, 
		"character_id": player_char_id, 
		"system_prompt": _system_prompt, 
		"custom_system_prompt_override": _custom_system_prompt_override, 
		"initial_setup": _initial_setup.duplicate(true), 
		"initial_setup_enabled": _initial_setup_enabled, 
		"initial_setup_stopped": _initial_setup_stopped, 
		"prefill_scope": _prefill_scope, 
		"custom_prompt_baked_tags": _custom_prompt_baked_tags.duplicate(), 
		"story_context": _story_context, 
		"story_context_revision": _story_context_revision_seen, 
		"story_summary_state": _get_story_summary_state_for_snapshot(), 
		"displayed_text": text, 
		"location_id": MapManager.get_current_runtime_location_id(), 
		"dialogic_history_length": dialogic_history_length, 
		"remaining_queue": [], 
		"displayed_lines": [], 
		"is_player_turn": true, 
		"is_narrator_turn": narrator_mode, 
		"music_state": _get_current_music_state_for_rollback(), 
		"time_slot": GameState.current_time_slot, 
		"daily_visits": GameState.daily_visits, 
		"pass_time_state": GameState.capture_pass_time_rollback_state(), 
	}

	RollbackManager.register_ai_player_turn(ai_data)



func _register_ai_line_with_rollback(speaker: String, text: String, is_narrator: bool, rpg_check: Dictionary = {}) -> void :
	var dialogic_history_length: int = -1
	if Dialogic.has_subsystem("History"):
		dialogic_history_length = Dialogic.History.simple_history_content.size()


	var char_name: = speaker
	var char_id: = ""
	if is_narrator:
		char_name = "Narrator"
		var narrator_char: = DialogicResourceUtil.get_character_resource("narrator")
		if narrator_char:
			char_id = narrator_char.resource_path
	elif _stage.dialogic_characters.has(speaker):
		var dialogic_char: DialogicCharacter = _stage.dialogic_characters[speaker]
		if dialogic_char:
			char_name = dialogic_char.display_name
			char_id = dialogic_char.resource_path

			if char_id.is_empty():
				char_id = dialogic_char.get_identifier()
			if char_id.is_empty():
				char_id = speaker



	var ai_data: = {
		"rollback_owner_key": _rollback_owner_key, 
		"rollback_owner_kind": get_rollback_owner_kind(), 
		"character_tags": _stage.current_character_tags.duplicate(), 
		"roster_state": _get_dynamic_roster_state(), 
		"history": _history.duplicate(true), 
			"sprite_states": _stage.sprite_states.duplicate(), 
			"last_user_message": _last_user_message, 
			"last_player_turn_speaker_name": _last_player_turn_speaker_name, 
			"last_player_turn_narrator_mode": _last_player_turn_narrator_mode, 
			"last_turn_guidance": _last_turn_guidance, 
			"regenerate_unavailable": _regenerate_unavailable, 
			"last_request_management_context": _last_request_management_context.duplicate(true), 
			"last_ai_response": text, 
		"character_name": char_name, 
		"character_id": char_id, 
		"system_prompt": _system_prompt, 
		"custom_system_prompt_override": _custom_system_prompt_override, 
		"initial_setup": _initial_setup.duplicate(true), 
		"initial_setup_enabled": _initial_setup_enabled, 
		"initial_setup_stopped": _initial_setup_stopped, 
		"prefill_scope": _prefill_scope, 
		"custom_prompt_baked_tags": _custom_prompt_baked_tags.duplicate(), 
		"story_context": _story_context, 
		"story_context_revision": _story_context_revision_seen, 
		"story_summary_state": _get_story_summary_state_for_snapshot(), 
		"displayed_text": text, 
		"is_narrator": is_narrator, 
		"location_id": MapManager.get_current_runtime_location_id(), 
		"dialogic_history_length": dialogic_history_length, 
		"remaining_queue": _dialogue_queue.duplicate(true), 
		"displayed_lines": _displayed_lines.duplicate(true), 
		"music_state": _get_current_music_state_for_rollback(), 
		"time_slot": GameState.current_time_slot, 
		"daily_visits": GameState.daily_visits, 
		"pass_time_state": GameState.capture_pass_time_rollback_state(), 
	}

	if not rpg_check.is_empty():
		ai_data["rpg_check"] = rpg_check.duplicate(true)

	RollbackManager.register_ai_exchange(ai_data)


func _get_current_music_state_for_rollback() -> Dictionary:
	if not Dialogic.has_subsystem("Audio"):
		return {}

	var audio_state: Variant = Dialogic.current_state_info.get("audio", {})
	if not (audio_state is Dictionary):
		return {}

	var music_state: Variant = (audio_state as Dictionary).get("music", {})
	if not (music_state is Dictionary):
		return {}

	var path: = str((music_state as Dictionary).get("path", "")).strip_edges()
	if path.is_empty():
		return {}

	return (music_state as Dictionary).duplicate(true)


func _restore_music_state_if_needed(music_state: Dictionary, fade_length: float = 0.35) -> void :
	if not Dialogic.has_subsystem("Audio") or Dialogic.Audio == null:
		return

	var target_path: = str(music_state.get("path", "")).strip_edges()
	var current_audio: Dictionary = Dialogic.current_state_info.get("audio", {}).duplicate(true)
	var current_music: Dictionary = current_audio.get("music", {})
	var current_path: = str(current_music.get("path", "")).strip_edges()
	var is_playing: = Dialogic.Audio.is_channel_playing("music")

	if target_path.is_empty():
		if not current_path.is_empty() or is_playing:
			Dialogic.Audio.update_audio("music", "", {"fade_length": maxf(0.2, fade_length)})
		current_audio.erase("music")
		Dialogic.current_state_info["audio"] = current_audio
		return

	if current_path == target_path and is_playing:
		return

	var restore_settings: Dictionary = {}
	var raw_restore_settings: Variant = music_state.get("settings_overrides", {})
	if raw_restore_settings is Dictionary:
		restore_settings = (raw_restore_settings as Dictionary).duplicate(true)
	if not restore_settings.has("fade_length"):
		restore_settings["fade_length"] = maxf(0.2, fade_length)
	if not restore_settings.has("loop"):
		restore_settings["loop"] = true

	Dialogic.Audio.update_audio("music", target_path, restore_settings)



func _on_rollback_ai_state_changed(is_in_ai: bool, ai_data: Dictionary) -> void :
	if RollbackManager.is_in_rollback_mode():



		_session_id += 1
		_clear_manual_changes_guard()
		_rpg.cancel_active_roll()
	if not is_in_ai:

		_stage.reset_speaker_focus()
		if _is_active:
			_hide_ai_ui_for_history_viewing()
		return




	if ai_data.get("is_scene_generated", false):
		_relinquish_ui_for_scene_history(_rollback_owner_key_matches(ai_data))
		return
	if not owns_rollback_snapshot(ai_data):
		_relinquish_ui_for_scene_history(false)
		return


	if ai_data.get("is_player_turn", false):
		_show_player_turn_history_ui(ai_data)
	else:
		_show_ai_ui_for_history_viewing(ai_data)



func _on_rollback_snapshot_type_changed(snapshot_type: RollbackManager.SnapshotType) -> void :

	_cancel_current_advance_wait = true
	_is_displaying_dialogue = false

	Log.d("DialogicAIConversation", "snapshot_type_changed: %s in_rollback=%s" % [snapshot_type, RollbackManager.is_in_rollback_mode()])



	if RollbackManager.is_in_rollback_mode():
		var ai_data: = RollbackManager.get_current_ai_data()
		if not ai_data.is_empty():


			if ai_data.get("is_scene_generated", false):
				_relinquish_ui_for_scene_history(_rollback_owner_key_matches(ai_data))
				return
			if not owns_rollback_snapshot(ai_data):
				_relinquish_ui_for_scene_history(false)
				return

			var remaining: Array = ai_data.get("remaining_queue", [])
			_dialogue_queue.clear()
			for item in remaining:
				_dialogue_queue.append(item)

			_restore_ai_state_from_data(ai_data)
		else:

			_dialogue_queue.clear()

	match snapshot_type:
		RollbackManager.SnapshotType.SCRIPTED:
			_is_viewing_history = true
			if _is_active:
				_hide_ai_ui_for_history_viewing()

		RollbackManager.SnapshotType.AI_CONVERSATION_START:
			_is_viewing_history = true

			_show_ai_start_marker_ui()

		RollbackManager.SnapshotType.AI_PLAYER_TURN:
			_is_viewing_history = true

		RollbackManager.SnapshotType.AI_EXCHANGE:
			_is_viewing_history = true



func _relinquish_ui_for_scene_history(unregister_coordinator: bool = true) -> void :


	if not _is_active and _dialogue_queue.is_empty():
		return
	Log.d("DialogicAIConversation", "Relinquishing Q&A ownership for scene history")
	_dialogue_queue.clear()
	_is_viewing_history = false
	_is_active = false
	_stage.clear_session()
	_hide_input_field()
	_show_interrupt_button = false
	_show_edit_button = false
	_show_quit_button = false
	_show_regenerate_button = false
	_show_sleepover_request_button = false
	_show_sleepover_sleep_button = false
	_show_pass_time_button = false
	if unregister_coordinator and AIStateCoordinator.is_registered_conversation(self):
		AIStateCoordinator.unregister_conversation()
	_stage.reset_speaker_focus()
	_update_button_visibility()



func _hide_ai_ui_for_history_viewing() -> void :
	_is_viewing_history = true
	_stage.reset_speaker_focus()


	_hide_input_field()
	_show_interrupt_button = false
	_show_edit_button = false
	_show_quit_button = false
	_show_regenerate_button = false
	_show_sleepover_request_button = false
	_show_sleepover_sleep_button = false
	_show_pass_time_button = false
	_update_button_visibility()


	if _dialog_text_node:
		_dialog_text_node.show()



func _show_ai_start_marker_ui() -> void :
	_is_viewing_history = true
	_stage.reset_speaker_focus()


	_hide_input_field()
	_show_interrupt_button = true
	_show_edit_button = false
	_show_quit_button = false
	_show_regenerate_button = false
	_show_sleepover_request_button = false
	_show_sleepover_sleep_button = false
	_show_pass_time_button = false
	_update_button_visibility()



func _show_player_turn_history_ui(ai_data: Dictionary) -> void :
	_is_viewing_history = true

	if not _is_active and not ai_data.is_empty():
		_restore_ai_state_from_data(ai_data)

	_hide_input_field()
	_show_interrupt_button = true
	_show_edit_button = false
	_show_quit_button = false
	_show_regenerate_button = false
	_show_sleepover_request_button = false
	_show_sleepover_sleep_button = false
	_show_pass_time_button = false
	_current_displayed_text = str(ai_data.get("displayed_text", ai_data.get("player_input_text", "")))
	_update_button_visibility()

	if _dialog_text_node:
		_dialog_text_node.show()

	if Dialogic.has_subsystem("Text"):
		Dialogic.Text.show_next_indicators()
		if bool(ai_data.get("is_narrator_turn", false)):
			for name_label in get_tree().get_nodes_in_group("dialogic_name_label"):
				name_label.text = "Narrator"
				name_label.self_modulate = Color(0.85, 0.78, 1.0)
		else:
			var turn_name: = str(ai_data.get("character_name", "")).strip_edges()
			var player_char: = DialogicResourceUtil.get_character_resource("player")
			if player_char and (turn_name.is_empty() or turn_name == player_char.display_name):
				Dialogic.Text.update_name_label(player_char)
			else:
				for name_label in get_tree().get_nodes_in_group("dialogic_name_label"):
					name_label.text = turn_name if not turn_name.is_empty() else _get_player_input_display_name()
					name_label.self_modulate = Color.WHITE



func _show_ai_ui_for_history_viewing(ai_data: Dictionary) -> void :
	_is_viewing_history = true


	if not _is_active and not ai_data.is_empty():
		_restore_ai_state_from_data(ai_data)


	_hide_input_field()



	_show_interrupt_button = true
	_current_displayed_text = str(ai_data.get("displayed_text", ai_data.get("last_ai_response", "")))
	_show_edit_button = not _current_displayed_text.is_empty()
	_edit_enabled = _show_edit_button
	_show_quit_button = false
	_show_regenerate_button = false
	_show_sleepover_request_button = false
	_show_sleepover_sleep_button = false
	_show_pass_time_button = false
	_update_button_visibility()


	if not _interrupt_panel:
		_find_dialog_text_node()
		_create_control_buttons()


	if _dialog_text_node:
		_dialog_text_node.show()


	if Dialogic.has_subsystem("Text"):
		Dialogic.Text.show_next_indicators()

	var is_narrator: = bool(ai_data.get("is_narrator", false))
	var speaker_tag: = _resolve_speaker_tag_from_ai_data(ai_data)
	_stage.apply_speaker_focus_for_line(speaker_tag, is_narrator)



func _restore_ai_state_from_data(ai_data: Dictionary) -> void :
	_restore_story_summary_state_from_snapshot(ai_data)


	var tags: Array = ai_data.get("character_tags", [])
	_stage.current_character_tags.clear()
	_stage.character_data.clear()
	_stage.dialogic_characters.clear()

	for raw_tag in tags:
		_register_restore_character_tag(str(raw_tag))



	for raw_tag in ai_data.get("sprite_states", {}).keys():
		_register_restore_character_tag(str(raw_tag))
	var portraits_state: Variant = Dialogic.current_state_info.get("portraits", {})
	if portraits_state is Dictionary:
		for char_id in (portraits_state as Dictionary).keys():
			var resolved_tag: = _resolve_tag_from_character_id(str(char_id))
			_register_restore_character_tag(resolved_tag)


	var valid_tags: Array[String] = []
	for char_data in _stage.character_data:
		valid_tags.append(char_data.tag)
	_update_line_processor_valid_tags()
	if _stage.dynamic_roster != null:
		var roster_state: Dictionary = ai_data.get("roster_state", {})
		if _is_dynamic_character_mode_enabled() and roster_state is Dictionary and not roster_state.is_empty():
			_stage.dynamic_roster.restore_state(roster_state, valid_tags)
		else:
			_stage.dynamic_roster.configure(valid_tags, MAX_DYNAMIC_VISIBLE_CHARACTERS)


	_history = ai_data.get("history", []).duplicate(true)
	_stage.sprite_states = ai_data.get("sprite_states", {}).duplicate()
	_last_user_message = ai_data.get("last_user_message", "")
	if _last_user_message == "...":
		_last_user_message = ""



	_regenerate_unavailable = bool(ai_data.get("regenerate_unavailable", false))
	_last_player_turn_speaker_name = str(ai_data.get(
		"last_player_turn_speaker_name", 
		ai_data.get("character_name", "") if bool(ai_data.get("is_player_turn", false)) else ""
	))
	_last_player_turn_narrator_mode = bool(ai_data.get(
		"last_player_turn_narrator_mode", 
		ai_data.get("is_narrator_turn", false)
	))
	_last_turn_guidance = str(ai_data.get("last_turn_guidance", "")).strip_edges()
	_set_pending_turn_guidance(str(ai_data.get("pending_turn_guidance", "")))
	_restore_request_management_context(ai_data.get("last_request_management_context", {}))
	_system_prompt = ai_data.get("system_prompt", "")
	_restore_initial_setup(ai_data)
	_prefill_scope = str(ai_data.get("prefill_scope", AssistantPrefill.resolve_scope("qa", str(ai_data.get("location_id", "")), AIStateCoordinator.is_custom_start_active())))



	_custom_prompt_baked_tags = []
	var baked_variant: Variant = ai_data.get("custom_prompt_baked_tags", ai_data.get("character_tags", []))
	if baked_variant is Array:
		for raw_baked_tag in (baked_variant as Array):
			var baked_tag: = str(raw_baked_tag).strip_edges()
			if not baked_tag.is_empty() and not baked_tag in _custom_prompt_baked_tags:
				_custom_prompt_baked_tags.append(baked_tag)
	_story_context = ai_data.get("story_context", "")
	_story_context_revision_seen = int(ai_data.get("story_context_revision", _get_story_summary_context_revision()))
	_pending_sleepover_invite_request = false
	_is_request_in_flight = false
	_rpg.pending_request.clear()
	_refresh_story_context_from_manager(true, false)




	if GameState.restore_pass_time_rollback_state(ai_data):
		_refresh_sleepover_button_state()



	var remaining: Array = ai_data.get("dialogue_queue", ai_data.get("remaining_queue", []))
	_dialogue_queue.clear()

	for item in remaining:
		_dialogue_queue.append(item)


	var displayed: Array = ai_data.get("displayed_lines", [])
	_displayed_lines.clear()
	for item in displayed:
		_displayed_lines.append(item)

	_is_active = true
	_stage.begin_session(_session_id, _get_joined_character_tags())


	if not _dialog_text_node:
		_find_dialog_text_node()


func _sync_history_view_state_from_current_snapshot() -> bool:
	if not RollbackManager.is_in_rollback_mode():
		return true
	var ai_data: = RollbackManager.get_current_ai_data()
	if ai_data.is_empty() or bool(ai_data.get("is_scene_generated", false)) or not owns_rollback_snapshot(ai_data):
		return false
	_restore_ai_state_from_data(ai_data)
	_current_displayed_text = str(ai_data.get("displayed_text", ai_data.get("last_ai_response", "")))
	return not _current_displayed_text.is_empty()




func resume_from_history() -> bool:
	if not _is_viewing_history:
		return false
	var rollback_ai_data: = RollbackManager.get_current_ai_data()
	if rollback_ai_data.is_empty() or not owns_rollback_snapshot(rollback_ai_data):
		return false

	_is_viewing_history = false


	_cancel_current_advance_wait = false
	_is_displaying_dialogue = false




	_session_id += 1
	_clear_manual_changes_guard()
	_rpg.cancel_active_roll()
	_stage.begin_session(_session_id, _get_joined_character_tags())

	var current_snapshot_type: = RollbackManager.get_current_snapshot_type()
	var rollback_audio_state: = RollbackManager.consume_resume_audio_state()
	var audio_to_restore: Dictionary = rollback_audio_state.get("channels", {}).duplicate(true)
	var authoritative_audio: = bool(rollback_audio_state.get("authoritative", false))
	var prefilled_input_text: = ""
	if current_snapshot_type == RollbackManager.SnapshotType.AI_PLAYER_TURN:
		prefilled_input_text = str(rollback_ai_data.get("player_input_text", rollback_ai_data.get("last_user_message", "")))

	var snapshot_music_state: Variant = rollback_ai_data.get("music_state", {})
	if rollback_ai_data.has("music_state") and snapshot_music_state is Dictionary:
		audio_to_restore["music"] = (snapshot_music_state as Dictionary).duplicate(true)
		authoritative_audio = true


	RollbackManager.exit_rollback_mode()








	if current_snapshot_type == RollbackManager.SnapshotType.AI_PLAYER_TURN:
		_rewind_player_turn_to_input_state(rollback_ai_data)


		_dialogue_queue.clear()


	AIStateCoordinator.register_conversation(self)

	var rollback_location_id: = str(rollback_ai_data.get("location_id", "")).strip_edges()
	if not rollback_location_id.is_empty() and rollback_location_id != "_timeline_driven":
		if MapManager.has_method("restore_conversation_location"):
			MapManager.restore_conversation_location(rollback_location_id, 0.35, false)

	RollbackManager.restore_audio_from_snapshot(audio_to_restore, authoritative_audio)

	Log.d("DialogicAIConversation", "resume_from_history queue=%d" % _dialogue_queue.size())


	if not _dialogue_queue.is_empty():
		_display_next_dialogue()
	else:

		_show_input_in_textbox(prefilled_input_text)
		if current_snapshot_type == RollbackManager.SnapshotType.AI_PLAYER_TURN:
			_show_regenerate_button = false
			_update_button_visibility()
	return true









func get_save_state() -> Dictionary:
	if not _is_active:
		return {}

	var dialogic_history_size: = -1
	if Dialogic.has_subsystem("History"):
		dialogic_history_size = Dialogic.History.simple_history_content.size()




	if RollbackManager.is_in_rollback_mode() or _is_viewing_history:
		if APIConfigManager.is_debug_enabled():
			print("[DialogicAIConversation][Save] Capturing rollback/history view save in_rollback=%s viewing_history=%s displaying=%s queue=%d displayed=%d" % [
				str(RollbackManager.is_in_rollback_mode()), 
				str(_is_viewing_history), 
				str(_is_displaying_dialogue), 
				_dialogue_queue.size(), 
				_displayed_lines.size()
			])
		return _build_normalized_history_view_save_state(dialogic_history_size)

	if APIConfigManager.is_debug_enabled():
		print("[DialogicAIConversation][Save] Capturing normal save displaying=%s queue=%d displayed=%d history=%d" % [
			str(_is_displaying_dialogue), 
			_dialogue_queue.size(), 
			_displayed_lines.size(), 
			_history.size()
		])

	return {
		"is_active": _is_active, 
		"rollback_owner_key": _rollback_owner_key, 
		"character_tags": _stage.current_character_tags.duplicate(), 
		"roster_state": _get_dynamic_roster_state(), 
		"history": _history.duplicate(true), 
			"sprite_states": _stage.sprite_states.duplicate(), 
			"last_user_message": _last_user_message, 
			"last_player_turn_speaker_name": _last_player_turn_speaker_name, 
			"last_player_turn_narrator_mode": _last_player_turn_narrator_mode, 
			"last_turn_guidance": _last_turn_guidance, 
			"pending_turn_guidance": _pending_turn_guidance, 
			"regenerate_unavailable": _regenerate_unavailable, 
			"last_request_management_context": _last_request_management_context.duplicate(true), 
			"system_prompt": _system_prompt, 
		"custom_system_prompt_override": _custom_system_prompt_override, 
		"initial_setup": _initial_setup.duplicate(true), 
		"initial_setup_enabled": _initial_setup_enabled, 
		"initial_setup_stopped": _initial_setup_stopped, 
		"prefill_scope": _prefill_scope, 
		"custom_prompt_baked_tags": _custom_prompt_baked_tags.duplicate(), 
		"story_context": _story_context, 
		"story_context_revision": _story_context_revision_seen, 
		"story_summary_state": _get_story_summary_state_for_snapshot(), 
		"dialogue_queue": _dialogue_queue.duplicate(true), 
		"displayed_lines": _displayed_lines.duplicate(true), 
		"is_displaying_dialogue": _is_displaying_dialogue, 
		"playback_pending": _is_displaying_dialogue or not _dialogue_queue.is_empty(), 
		"state_snapshots": _state_snapshots.duplicate(true), 
		"dialogic_history_size": dialogic_history_size, 
		"audio_state": RollbackManager.get_selected_audio_state(), 
	}




func restore_from_save_state(state: Dictionary) -> void :
	if state.is_empty() or not state.get("is_active", false):
		return
	if _rollback_owner_key.is_empty():
		_rollback_owner_key = str(state.get("rollback_owner_key", "")).strip_edges()


	_session_id += 1
	_clear_manual_changes_guard()
	_rpg.cancel_active_roll()



	_initial_setup_stopped = false
	_restore_ai_state_from_data(state)
	if state.has("audio_state") and state.get("audio_state") is Dictionary:
		RollbackManager.restore_audio_from_snapshot(
			(state.get("audio_state") as Dictionary).duplicate(true), 
			true
		)

	if APIConfigManager.is_debug_enabled():
		print("[DialogicAIConversation][Load] Restored raw save state displaying=%s queue=%d displayed=%d history=%d" % [
			str(state.get("is_displaying_dialogue", false)), 
			_dialogue_queue.size(), 
			_displayed_lines.size(), 
			_history.size()
		])




	var saved_dialogic_history_size: = int(state.get("dialogic_history_size", -1))
	if saved_dialogic_history_size >= 0 and Dialogic.has_subsystem("History"):
		var current_dialogic_history_size: = Dialogic.History.simple_history_content.size()
		if current_dialogic_history_size > saved_dialogic_history_size:
			Dialogic.History.simple_history_content.resize(saved_dialogic_history_size)


	_state_snapshots.clear()
	var snapshots: Array = state.get("state_snapshots", [])
	for snap in snapshots:
		_state_snapshots.append(snap)


	_is_active = true
	_is_viewing_history = false


	_interrupt_requested = false
	_cancel_current_advance_wait = false
	_is_displaying_dialogue = false
	_is_restoring_turn_state = false



	_is_editing = false
	_edit_just_closed = false
	_rpg.pending_request.clear()


	_cleanup_input_field()




	if not state.get("playback_pending", state.get("is_displaying_dialogue", false)) and not _dialogue_queue.is_empty():
		if APIConfigManager.is_debug_enabled():
			print("[DialogicAIConversation][Load] Clearing stale queue from save while restoring input-wait state queue=%d displayed=%d" % [
				_dialogue_queue.size(), 
				_displayed_lines.size()
			])
		push_warning("[DialogicAIConversation] Clearing stale dialogue queue from save while restoring input-wait state")
		_dialogue_queue.clear()


	_find_dialog_text_node()


	_create_control_buttons()



	_set_dialogic_layout_visible(false)


	var restore_session_id: = _session_id
	await _restore_sprite_states(restore_session_id)
	if not is_session_current(restore_session_id):
		return


	_set_dialogic_layout_visible(true)


	if state.get("playback_pending", state.get("is_displaying_dialogue", false)):


		var last_dialogue_entry: Dictionary = _find_last_dialogue_entry()
		if not last_dialogue_entry.is_empty():
			if APIConfigManager.is_debug_enabled():
				print("[DialogicAIConversation] Restored from save, resuming at current line (%d remaining)" % _dialogue_queue.size())
			_is_displaying_dialogue = true
			_redisplay_dialogue_entry(last_dialogue_entry, restore_session_id)
		elif not _dialogue_queue.is_empty():
			if APIConfigManager.is_debug_enabled():
				print("[DialogicAIConversation] Restored from save, continuing queue (%d items)" % _dialogue_queue.size())
			_is_displaying_dialogue = true
			_display_next_dialogue()
		else:
			_show_input_in_textbox()
	else:

		var prefilled_input_text: = str(state.get("prefilled_input_text", ""))
		_show_input_in_textbox(prefilled_input_text)
		if not prefilled_input_text.is_empty():
			_show_regenerate_button = false
			_update_button_visibility()



func _restore_sprite_states(expected_session_id: int = -1) -> void :
	var _sprite_sound_scope: = SpriteSoundManager.suppress()
	var session_id: = expected_session_id if expected_session_id >= 0 else _session_id
	if not is_session_current(session_id):
		return
	var portraits_state: Dictionary = Dialogic.current_state_info.get("portraits", {})
	var visible_tags: = _stage.get_restore_visible_tags(portraits_state)
	var total_chars: = clampi(visible_tags.size(), 1, MAX_DYNAMIC_VISIBLE_CHARACTERS)
	_stage.begin_session(session_id, visible_tags)


	CharacterPortraitService.clear_scene_layout_state(total_chars)

	for tag in visible_tags:
		if not is_session_current(session_id):
			return
		if _stage.dialogic_characters.has(tag):
			var dialogic_char: DialogicCharacter = _stage.dialogic_characters[tag]
			var portrait: String = _stage.sprite_states.get(tag, "neutral")
			var position_id: = _stage.get_restore_position_for_character(dialogic_char, tag, portraits_state)
			var should_mirror: = CharacterPortraitService.should_mirror_at_position(position_id)
			var joined_before: = Dialogic.Portraits.is_character_joined(dialogic_char)
			Log.d(
				"DialogicAIConversation", 
				"Restore layout request | tag=%s portrait=%s slot=%s mirrored=%s total_chars=%d joined_before=%s" % [
					tag, 
					portrait, 
					position_id, 
					str(should_mirror), 
					total_chars, 
					str(joined_before), 
				]
			)

			CharacterPortraitService.force_character_position(dialogic_char, position_id)


			if not joined_before:
				await CharacterPortraitService.join_character_safe(
					dialogic_char, 
					portrait, 
					position_id, 
					should_mirror, 
					0, 
					"", 
					"__no_animation__", 
					0.0, 
					false, 
					total_chars
				)
				if not is_session_current(session_id):
					await _stage._reconcile_stale_join(tag, dialogic_char)
					return
			elif dialogic_char.portraits.has(portrait):
				_stage.prepare_group_layout_before_portrait_change(tag, dialogic_char, total_chars)
				await Dialogic.Portraits.change_character_portrait(dialogic_char, portrait)
				if not is_session_current(session_id):
					await _stage._reconcile_stale_join(tag, dialogic_char)
					return


			if Dialogic.Portraits.is_character_joined(dialogic_char):
				CharacterPortraitService.refresh_character_transform(dialogic_char)
				if total_chars == 2:
					CharacterPortraitService.register_duo_character(dialogic_char, position_id, portrait)
					_stage.apply_group_scale_deferred(dialogic_char, portrait, total_chars, session_id)
					_stage.apply_group_scale_deferred.call_deferred(dialogic_char, portrait, total_chars, session_id)

	await get_tree().process_frame
	if not is_session_current(session_id):
		return


	_stage.refresh_group_layout(total_chars)
	if _stage.dynamic_roster != null:
		_stage.dynamic_roster.sync_visible_tags(_get_joined_character_tags())
	_update_line_processor_valid_tags()




func _find_last_dialogue_entry() -> Dictionary:

	for i in range(_displayed_lines.size() - 1, -1, -1):
		var entry: Dictionary = _displayed_lines[i]
		if entry.get("type", "dialogue") == "dialogue":
			return entry
	return {}




func _redisplay_dialogue_entry(entry: Dictionary, expected_session_id: int = -1) -> void :
	var session_id: = expected_session_id if expected_session_id >= 0 else _session_id
	if not is_session_current(session_id):
		return
	var speaker: String = entry.get("speaker", "")
	var text: String = entry.get("text", "")
	var is_narrator: bool = entry.get("is_narrator", false)


	var dialogic_char: DialogicCharacter = null
	if not is_narrator and _stage.dialogic_characters.has(speaker):
		dialogic_char = _stage.dialogic_characters[speaker]
	elif is_narrator:
		dialogic_char = DialogicResourceUtil.get_character_resource("narrator")


	if Dialogic.Text:
		Dialogic.Text.update_name_label(dialogic_char)


	if dialogic_char and not is_narrator and Dialogic.Portraits.is_character_joined(dialogic_char):
		var portrait: String = _stage.sprite_states.get(speaker, "neutral")
		if dialogic_char.portraits.has(portrait):
			_stage.prepare_group_layout_before_portrait_change(speaker, dialogic_char, _stage.get_total_visible_for_layout(speaker))
			await Dialogic.Portraits.change_character_portrait(dialogic_char, portrait)
			if not is_session_current(session_id):
				await _stage._reconcile_stale_join(speaker, dialogic_char)
				return
			_stage.apply_group_scale_deferred(dialogic_char, portrait, _stage.get_total_visible_for_layout(speaker), session_id)
			_stage.apply_group_scale_deferred.call_deferred(dialogic_char, portrait, _stage.get_total_visible_for_layout(speaker), session_id)

	_stage.apply_speaker_focus_for_line(speaker, is_narrator)


	if Dialogic.Text:
		var typing_portrait: String = ""
		if not is_narrator:
			typing_portrait = str(_stage.sprite_states.get(speaker, "neutral"))
		CharacterSpriteLoader.call("apply_typing_sound_for_dialogic_character", dialogic_char, typing_portrait)
		await Dialogic.Text.update_textbox(text, false)
		if not is_session_current(session_id):
			return
		Dialogic.Text.update_dialog_text(text, true)
		preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree()).replay_history(entry, "narrator" if is_narrator else speaker, text)
		_current_displayed_text = text
		_show_edit_button = true
		_edit_enabled = true
		_update_button_visibility()


		Dialogic.Text.show_next_indicators()


		Dialogic.current_state = Dialogic.States.IDLE
		await _wait_for_advance()
		if not is_session_current(session_id):
			return


		Dialogic.Text.hide_next_indicators()
		_show_edit_button = false
		_edit_enabled = false
		_update_button_visibility()


	_display_next_dialogue(session_id)

func debug_dump_state(reason: String) -> void :
	if not APIConfigManager.is_debug_enabled():
		return

	var layout_visible: = false
	if Dialogic.has_subsystem("Styles") and Dialogic.Styles.has_active_layout_node():
		var layout_node: = Dialogic.Styles.get_layout_node()
		layout_visible = layout_node.visible if layout_node else false

	var autoload_paused: = false
	var action_consumed: = "<none>"
	var manual_disabled: = "<none>"
	if DialogicUtil.autoload():
		autoload_paused = DialogicUtil.autoload().paused
		var inputs: Node = DialogicUtil.autoload().get("Inputs") as Node
		if inputs:
			action_consumed = str(inputs.action_was_consumed)
	if Dialogic.has_subsystem("Inputs") and Dialogic.Inputs and Dialogic.Inputs.manual_advance:
		manual_disabled = str(Dialogic.Inputs.manual_advance.disabled_until_next_event)

	var blockers: = _get_visible_blockers()

	print("[DialogicAIConversation][State] %s paused=%s autoload_paused=%s state=%s displaying=%s viewing_history=%s input_visible=%s text_visible=%s layout_visible=%s action_consumed=%s manual_disabled=%s blockers=%s" % [
		reason, 
		str(Dialogic.paused), 
		str(autoload_paused), 
		str(Dialogic.current_state), 
		str(_is_displaying_dialogue), 
		str(_is_viewing_history), 
		str(_input_container != null and _input_container.visible), 
		str(_dialog_text_node != null and _dialog_text_node.visible), 
		str(layout_visible), 
		action_consumed, 
		manual_disabled, 
		str(blockers)
	])


func _get_visible_blockers() -> Array[String]:
	var blockers: Array[String] = []
	for node in get_tree().get_nodes_in_group("ui_blocking_overlay"):
		if AIDialogueShared.node_is_visible(node):
			blockers.append("%s:%s" % [node.name, node.get_class()])
	return blockers

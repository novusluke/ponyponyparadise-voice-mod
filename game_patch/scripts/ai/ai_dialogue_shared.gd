class_name AIDialogueShared
extends RefCounted







const APPROX_CHARS_PER_TOKEN: = 4.0
const CONTEXT_OVERHEAD_TOKENS: = 700
const MESSAGE_OVERHEAD_TOKENS: = 8

static func cancel_pending_dialogue_ending() -> void:
	# end_timeline() can start an ending timeline and return before its Clear
	# event runs. That old event must not hide a newly opened custom scene/Q&A.
	if Dialogic.dialog_ending_timeline != null and Dialogic.current_timeline == Dialogic.dialog_ending_timeline:
		await Dialogic.clear(DialogicGameHandler.ClearFlags.TIMELINE_INFO_ONLY)
		Dialogic.Animations.stop_animation()


static func estimate_text_tokens(text: String) -> int:
	return ceili(text.length() / APPROX_CHARS_PER_TOKEN)







static var _touch_advance_requested: = false


static func request_touch_advance() -> void :
	_touch_advance_requested = true


static func consume_touch_advance_request() -> bool:
	var requested: = _touch_advance_requested
	_touch_advance_requested = false
	return requested


static func is_portrait_current(dialogic_char: DialogicCharacter, portrait: String) -> bool:
	if dialogic_char == null:
		return false
	var char_node: = Dialogic.Portraits.get_character_node(dialogic_char)
	if char_node == null:
		return false
	if not char_node.has_meta("portrait"):
		return false
	return str(char_node.get_meta("portrait", "")) == portrait


static func node_is_visible(node: Node) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	if node.has_method("is_visible_in_tree"):
		return node.is_visible_in_tree()
	if node.has_method("is_visible"):
		return node.is_visible()
	if node.has_method("get"):
		return bool(node.get("visible"))
	return false



static func is_ui_blocking_input(host: Node) -> bool:
	var blockers = host.get_tree().get_nodes_in_group("ui_blocking_overlay")
	for node in blockers:
		if node_is_visible(node):
			return true
	return false


static func is_dialogic_input_blocked() -> bool:
	if not DialogicUtil.autoload():
		return false
	var inputs: Node = DialogicUtil.autoload().get("Inputs") as Node
	if inputs and inputs.has_method("is_input_blocked"):
		return inputs.is_input_blocked()
	return false



static func is_hovering_music_switcher(host: Node) -> bool:
	var switchers: = host.get_tree().get_nodes_in_group("music_switcher")
	if switchers.is_empty():
		return false

	var switcher: Node = switchers[0]
	var mouse_pos: = host.get_viewport().get_mouse_position()


	var music_button = switcher.get("_music_button")
	if music_button and music_button.visible and music_button.modulate.a > 0.5:
		if music_button.get_global_rect().has_point(mouse_pos):
			return true


	var track_list = switcher.get("_track_list")
	if track_list and track_list.visible and track_list.modulate.a > 0.5:
		if track_list.get_global_rect().has_point(mouse_pos):
			return true

	for indicator in host.get_tree().get_nodes_in_group("lorebook_activity_indicator"):
		var button = indicator.get("_button")
		if button and button.visible and button.modulate.a > 0.5:
			if button.get_global_rect().has_point(mouse_pos):
				return true

	return false


static func is_hovering_dialogue_scrollbar(host: Node) -> bool:
	var dialog_text_nodes: = host.get_tree().get_nodes_in_group("dialogic_dialog_text")
	if dialog_text_nodes.is_empty():
		return false

	var dialog_text: = dialog_text_nodes[0] as RichTextLabel
	if dialog_text == null or not dialog_text.visible:
		return false

	var scrollbar: = dialog_text.get_v_scroll_bar()
	if scrollbar == null or not scrollbar.visible:
		return false

	return scrollbar.get_global_rect().has_point(host.get_viewport().get_mouse_position())



static func maybe_resume_dialogic_if_safe(host: Node, is_editing: bool) -> void :
	if not Dialogic.paused:
		return
	if is_editing or RollbackManager.is_in_rollback_mode():
		return
	if is_ui_blocking_input(host):
		return
	Dialogic.paused = false
	if DialogicUtil.autoload():
		DialogicUtil.autoload().paused = false




static func store_dialogic_history_entry(text: String, dialogic_char: DialogicCharacter, is_narrator: bool) -> int:
	if not Dialogic.has_subsystem("History"):
		return -1

	var before_size: = Dialogic.History.simple_history_content.size()
	var extra_info: = {}
	if not is_narrator and dialogic_char:
		extra_info["character"] = dialogic_char.display_name
		extra_info["character_color"] = dialogic_char.color

	extra_info["voice_speaker"] = dialogic_char.get_identifier() if not is_narrator and dialogic_char else "narrator"
	Dialogic.History.store_simple_history_entry(text, "Text", extra_info)

	var after_size: = Dialogic.History.simple_history_content.size()
	if after_size == before_size + 1:
		return after_size - 1
	return -1



static func tag_last_displayed_dialogue_history_index(displayed_lines: Array, raw_history_index: int) -> void :
	if raw_history_index < 0:
		return
	for i in range(displayed_lines.size() - 1, -1, -1):
		var entry: Dictionary = displayed_lines[i]
		if entry.get("type", "dialogue") != "dialogue":
			continue
		entry["raw_history_index"] = raw_history_index
		displayed_lines[i] = entry
		return

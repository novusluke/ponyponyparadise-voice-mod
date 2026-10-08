extends Node

const DRAG_SLOP := 6.0
var _pressed := false
var _dragged := false
var _start := Vector2.ZERO

func _input(event: InputEvent) -> void:
	if get_tree().paused:
		_pressed = false
		return
	if event is InputEventMouseMotion and _pressed:
		_dragged = _dragged or event.position.distance_to(_start) >= DRAG_SLOP
		return
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_pressed = _can_advance_at(event.position)
		_start = event.position
		_dragged = event.double_click
	else:
		var clicked: bool = _pressed and not _dragged and event.position.distance_to(_start) < DRAG_SLOP
		_pressed = false
		if clicked and _can_advance_at(event.position):
			call_deferred("_advance")

func _can_advance_at(position: Vector2) -> bool:
	if get_tree().paused:
		return false
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and (owner is LineEdit or owner is TextEdit):
		return false
	if Dialogic.paused or RollbackManager.is_in_rollback_mode() or AIDialogueShared.is_ui_blocking_input(self):
		return false
	if AIDialogueShared.is_dialogic_input_blocked() or AIDialogueShared.is_hovering_music_switcher(self):
		return false
	var texts: Array[Node] = get_tree().get_nodes_in_group("dialogic_dialog_text")
	var hovered := get_viewport().gui_get_hovered_control()
	for node in texts:
		var text := node as RichTextLabel
		if text == null or not text.is_visible_in_tree() or text.get_parsed_text().is_empty():
			continue
		var bar := text.get_v_scroll_bar()
		if bar.visible and bar.get_global_rect().has_point(position):
			return false
		if hovered == null or hovered.is_in_group("dialogic_input"):
			return true
		var ancestor: Node = hovered
		var scene_surface := false
		while ancestor != null:
			if ancestor is BaseButton or ancestor is ScrollBar or ancestor is LineEdit or ancestor is TextEdit or ancestor.is_in_group("rollback_history"):
				return false
			if ancestor.is_in_group("dialogic_background_holders") or ancestor.is_in_group("dialogic_portrait_con_position") or ancestor.is_in_group("dialogic_portrait_con_speaker"):
				scene_surface = true
			ancestor = ancestor.get_parent()
		var root: Node = text.get("textbox_root")
		if scene_surface or hovered == text or text.is_ancestor_of(hovered) or (root != null and (hovered == root or root.is_ancestor_of(hovered))):
			return true
	return false

func _advance() -> void:
	if not _can_advance_at(get_viewport().get_mouse_position()):
		return
	# Native timelines receive the Dialogic action. AI dialogue receives the
	# same validated release before its text-selection hover protection.
	AIDialogueShared.request_touch_advance()
	Dialogic.Inputs.input_was_mouse_input = false
	Dialogic.Inputs.handle_input()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.ctrl_pressed or event.meta_pressed or event.alt_pressed or event.keycode not in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		return
	if get_tree().paused or Dialogic.paused or RollbackManager.is_in_rollback_mode() or AIDialogueShared.is_ui_blocking_input(self) or AIDialogueShared.is_dialogic_input_blocked():
		return
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and (owner is LineEdit or owner is TextEdit):
		return
	for node in get_tree().get_nodes_in_group("dialogic_dialog_text"):
		if node is RichTextLabel and node.is_visible_in_tree() and not node.get_parsed_text().is_empty():
			Dialogic.Inputs.input_was_mouse_input = false
			Dialogic.Inputs.handle_input()
			get_viewport().set_input_as_handled()
			return

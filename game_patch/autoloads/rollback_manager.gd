extends Node















signal rollback_performed(steps: int)

signal ai_state_changed(is_in_ai: bool, ai_data: Dictionary)

signal snapshot_type_changed(snapshot_type: SnapshotType)


enum SnapshotType{
	SCRIPTED, 
	AI_CONVERSATION_START, 
	AI_PLAYER_TURN, 
	AI_EXCHANGE, 
}


@export var max_snapshots: int = 100


var _snapshots: Array[Dictionary] = []


var _current_position: int = -1


var _in_rollback_mode: bool = false


var _restoring: bool = false



var _restore_generation: int = 0



var _audio_snapshot: Dictionary = {}





func _ready() -> void :
	if not Dialogic.timeline_started.is_connected(_on_timeline_started):
		Dialogic.timeline_started.connect(_on_timeline_started)
	if not Dialogic.timeline_ended.is_connected(_on_timeline_ended):
		Dialogic.timeline_ended.connect(_on_timeline_ended)
	if not Dialogic.event_handled.is_connected(_on_event_handled):
		Dialogic.event_handled.connect(_on_event_handled)
	if not AIStateCoordinator.session_ended.is_connected(_on_ai_session_ended):
		AIStateCoordinator.session_ended.connect(_on_ai_session_ended)


func _on_timeline_started() -> void :
	clear_snapshots()


func _on_timeline_ended() -> void :
	if _in_rollback_mode:
		exit_rollback_mode()


func _on_ai_session_ended() -> void :


	if _has_ai_snapshots():
		clear_snapshots()


func _on_event_handled(event: DialogicEvent) -> void :
	if _restoring:
		return



	if AIStateCoordinator.is_in_qa_conversation():
		return




	if event is DialogicTextEvent:
		_create_snapshot(event)
	elif event is DialogicChoiceEvent:

		if not _snapshots.is_empty():
			_snapshots[-1]["has_choices"] = true


func _create_snapshot(text_event: DialogicTextEvent = null) -> void :

	if _current_position >= 0 and _current_position < _snapshots.size() - 1:
		_snapshots.resize(_current_position + 1)

	var snapshot: = _capture_state(text_event)
	snapshot["type"] = SnapshotType.SCRIPTED
	_snapshots.append(snapshot)


	if _snapshots.size() > max_snapshots:


		var evict_index: = 0
		if _snapshots[0].get("type", SnapshotType.SCRIPTED) == SnapshotType.AI_CONVERSATION_START and _snapshots.size() > 1:
			evict_index = 1
		_snapshots.remove_at(evict_index)


	_current_position = -1
	_in_rollback_mode = false
	_emit_state_changed()


func _capture_state(text_event: DialogicTextEvent = null) -> Dictionary:
	var state: = {}


	state["timeline"] = Dialogic.current_timeline.resource_path if Dialogic.current_timeline else ""
	state["event_idx"] = Dialogic.current_event_idx


	state["variables"] = {}
	if Dialogic.current_state_info.has("variables"):
		state["variables"] = Dialogic.current_state_info["variables"].duplicate(true)


	state["portraits"] = {}
	if Dialogic.has_subsystem("Portraits"):
		var portraits_info: Dictionary = Dialogic.current_state_info.get("portraits", {})
		for char_id in portraits_info:
			var char_data: Dictionary = portraits_info[char_id]
			state["portraits"][char_id] = {
				"portrait": char_data.get("portrait", ""), 
				"position_id": char_data.get("position_id", "center"), 
				"custom_mirror": char_data.get("custom_mirror", false), 
				"z_index": char_data.get("z_index", 0)
			}


	state["background"] = {}
	if Dialogic.has_subsystem("Backgrounds"):


		state["background"] = {
			"scene": str(Dialogic.current_state_info.get("background_scene", "")), 
			"path": str(Dialogic.current_state_info.get("background_argument", "")), 
		}




	state["audio"] = {}
	if Dialogic.has_subsystem("Audio"):
		var audio_info: Variant = Dialogic.current_state_info.get("audio", {})
		if audio_info is Dictionary:
			state["audio"] = (audio_info as Dictionary).duplicate(true)


	state["display_text"] = ""
	state["character"] = ""
	state["character_id"] = ""

	if text_event:
		state["display_text"] = text_event.text
		if text_event.character:
			state["character"] = text_event.character.display_name
			state["character_id"] = text_event.character.resource_path
	elif Dialogic.has_subsystem("Text"):
		state["display_text"] = str(Dialogic.current_state_info.get("text", ""))
		var speaker_id: = str(Dialogic.current_state_info.get("speaker", "")).strip_edges()
		var speaker: = _resolve_snapshot_character(speaker_id)
		if speaker != null:
			state["character"] = speaker.display_name
			state["character_id"] = speaker.resource_path if not speaker.resource_path.is_empty() else speaker_id

	var voice_character := _resolve_snapshot_character(str(state.get("character_id", "")))
	state.merge(preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree()).history_metadata(voice_character.get_identifier() if voice_character != null else "narrator", str(state.get("display_text", ""))), true)
	return state


func _is_ai_snapshot(snapshot: Dictionary) -> bool:
	var snap_type: SnapshotType = snapshot.get("type", SnapshotType.SCRIPTED)
	return snap_type in [SnapshotType.AI_CONVERSATION_START, SnapshotType.AI_PLAYER_TURN, SnapshotType.AI_EXCHANGE]


func _has_ai_snapshots() -> bool:
	for snapshot in _snapshots:
		if _is_ai_snapshot(snapshot):
			return true
	return false


func _has_only_ai_snapshots() -> bool:
	if _snapshots.is_empty():
		return false
	for snapshot in _snapshots:
		if not _is_ai_snapshot(snapshot):
			return false
	return true


func _get_dialogic_simple_history_size() -> int:
	if Dialogic.has_subsystem("History"):
		return Dialogic.History.simple_history_content.size()
	return -1


func _update_existing_ai_session_start_snapshot(character_tags: Array[String]) -> void :
	if _snapshots.is_empty():
		return

	var first_snapshot: Dictionary = _snapshots[0]
	if first_snapshot.get("type", SnapshotType.SCRIPTED) != SnapshotType.AI_CONVERSATION_START:
		return

	var ai_data: Dictionary = first_snapshot.get("ai_data", {}).duplicate(true)
	var merged_tags: Array[String] = []
	for raw_tag in ai_data.get("character_tags", []):
		var tag: = str(raw_tag).strip_edges()
		if not tag.is_empty() and not merged_tags.has(tag):
			merged_tags.append(tag)
	for raw_tag in character_tags:
		var tag: = str(raw_tag).strip_edges()
		if not tag.is_empty() and not merged_tags.has(tag):
			merged_tags.append(tag)
	ai_data["character_tags"] = merged_tags
	ai_data["location_id"] = MapManager.get_current_runtime_location_id()
	first_snapshot["ai_data"] = ai_data
	_snapshots[0] = first_snapshot
	_emit_state_changed()





func _restore_snapshot(snapshot: Dictionary, skip_portraits: bool = false) -> bool:
	preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree()).stop()
	Dialogic.invalidate_pending_events()
	var _sprite_sound_scope: = SpriteSoundManager.suppress()
	_restore_generation += 1
	var restore_generation: = _restore_generation
	_restoring = true

	var snap_type: SnapshotType = snapshot.get("type", SnapshotType.SCRIPTED)
	var is_ai: = snap_type in [SnapshotType.AI_CONVERSATION_START, SnapshotType.AI_PLAYER_TURN, SnapshotType.AI_EXCHANGE]
	var ai_data: Dictionary = snapshot.get("ai_data", {}) if is_ai else {}


	if snapshot.has("variables") and snapshot["variables"] is Dictionary:
		Dialogic.current_state_info["variables"] = snapshot["variables"].duplicate(true)


	if not skip_portraits and Dialogic.has_subsystem("Portraits"):
		var portraits_data: Dictionary = snapshot.get("portraits", {})
		var current_portraits: Dictionary = Dialogic.current_state_info.get("portraits", {})
		var total_characters_for_join: = 1
		if is_ai:
			total_characters_for_join = portraits_data.size()
			if total_characters_for_join <= 0:
				var roster_state: Dictionary = ai_data.get("roster_state", {})
				if roster_state is Dictionary and not roster_state.is_empty():
					var raw_visible: Variant = roster_state.get("visible_tags", [])
					var visible_tags: Array = raw_visible if raw_visible is Array else []
					if visible_tags is Array:
						total_characters_for_join = visible_tags.size()
			if total_characters_for_join <= 0:
				total_characters_for_join = ai_data.get("character_tags", []).size()




		var portrait_layout_changed: = false
		var portrait_changes: Array[Dictionary] = []
		if portraits_data.size() != current_portraits.size():
			portrait_layout_changed = true
		else:
			for char_id in portraits_data:
				if not current_portraits.has(char_id):
					portrait_layout_changed = true
					break
				var target_data: Dictionary = portraits_data[char_id]
				var current_data: Dictionary = current_portraits[char_id]
				if (
					str(target_data.get("position_id", "center")) != str(current_data.get("position_id", "center"))
					or bool(target_data.get("custom_mirror", false)) != bool(current_data.get("custom_mirror", false))
					or int(target_data.get("z_index", 0)) != int(current_data.get("z_index", 0))
				):
					portrait_layout_changed = true
					break
				var target_portrait: String = portraits_data[char_id].get("portrait", "")
				var current_portrait: String = current_portraits[char_id].get("portrait", "")
				if target_portrait != current_portrait:
					portrait_changes.append({
						"character_id": str(char_id), 
						"portrait": target_portrait, 
						"position_id": str(target_data.get("position_id", "center")), 
					})



		if not portrait_layout_changed:
			for portrait_change in portrait_changes:
				var character: = _resolve_snapshot_character(str(portrait_change.get("character_id", "")))
				var target_portrait: = str(portrait_change.get("portrait", ""))
				if character and Dialogic.Portraits.is_character_joined(character) and character.portraits.has(target_portrait):
					if total_characters_for_join >= 3 and total_characters_for_join <= 6:
						CharacterPortraitService.reapply_group_scale(
							character, 
							str(portrait_change.get("position_id", "center")), 
							total_characters_for_join
						)
					await Dialogic.Portraits.change_character_portrait(character, target_portrait)
					if restore_generation != _restore_generation:
						return false
					if total_characters_for_join <= 1:
						CharacterPortraitService.apply_solo_scale_to_character(character)


		if portrait_layout_changed:


			await Dialogic.Portraits.leave_all_characters("Instant", 0, false)
			if restore_generation != _restore_generation:
				return false
			if total_characters_for_join >= 2 and total_characters_for_join <= 6:
				CharacterPortraitService.clear_all_group_states(total_characters_for_join == 2)
			for char_id in portraits_data:
				var char_data: Dictionary = portraits_data[char_id]
				var character: = _resolve_snapshot_character(str(char_id))
				if character:

					await CharacterPortraitService.join_character_safe(
						character, 
						char_data.get("portrait", ""), 
						char_data.get("position_id", "center"), 
						char_data.get("custom_mirror", false), 
						char_data.get("z_index", 0), 
						"", "Instant", 0, false, total_characters_for_join
					)
					if restore_generation != _restore_generation:
						return false
			CharacterPortraitService.rebuild_group_state_from_portraits(portraits_data, total_characters_for_join)
		elif total_characters_for_join == 2:


			CharacterPortraitService.reset_duo_tracking()

			var entries: Array[Dictionary] = []
			for char_id in portraits_data:
				var char_data: Dictionary = portraits_data[char_id]
				var character: = _resolve_snapshot_character(str(char_id))
				if character and Dialogic.Portraits.is_character_joined(character):
					var position_id: String = char_data.get("position_id", "center")
					var portrait_name: String = char_data.get("portrait", "")
					entries.append({
						"character": character, 
						"portrait": portrait_name, 
						"position_id": position_id, 
					})

			if entries.size() == 2:
				var viewport_width: = 0.0
				var viewport: = Engine.get_main_loop()
				if viewport is SceneTree:
					viewport_width = (viewport as SceneTree).root.get_visible_rect().size.x

				var first: = entries[0]
				var second: = entries[1]
				var first_x: = CharacterPortraitService.get_position_center_x(first["position_id"], viewport_width)
				var second_x: = CharacterPortraitService.get_position_center_x(second["position_id"], viewport_width)

				var left: = first
				var right: = second
				if second_x < first_x:
					left = second
					right = first

				CharacterPortraitService.ensure_duo_state(
					left["character"], 
					right["character"], 
					left["portrait"], 
					right["portrait"], 
					left["position_id"], 
					right["position_id"]
				)
		elif total_characters_for_join >= 3 and total_characters_for_join <= 6:
			CharacterPortraitService.rebuild_group_state_from_portraits(portraits_data, total_characters_for_join)



	if snapshot.has("background") and Dialogic.has_subsystem("Backgrounds"):
		var bg_data = snapshot.get("background", {})



		if bg_data is Dictionary and (bg_data.has("scene") or bg_data.has("path")):
			var bg_path: String = bg_data.get("path", "")
			var bg_scene: String = bg_data.get("scene", "")
			Dialogic.Backgrounds.update_background(bg_scene, bg_path, 0)


	if snapshot.has("timeline") and snapshot["timeline"] != "":
		Dialogic.current_event_idx = snapshot.get("event_idx", 0)


	if Dialogic.has_subsystem("Text"):
		var display_text: String = snapshot.get("display_text", "")
		var character_id: String = snapshot.get("character_id", "")

		var character: DialogicCharacter = null
		if not character_id.is_empty():
			character = _resolve_snapshot_character(character_id)

		Log.d("RollbackManager", "Name resolve: snap_type=%s snapshot_char_id='%s' snapshot_char='%s' loaded=%s" % [
			str(snap_type), 
			character_id, 
			snapshot.get("character", ""), 
			character.display_name if character else "<null>"
		])



		if snap_type == SnapshotType.AI_PLAYER_TURN:
			var player_display_text: String = ai_data.get("displayed_text", "")
			if player_display_text.is_empty():
				player_display_text = ai_data.get("player_input_text", "")
			if not player_display_text.is_empty():
				display_text = player_display_text

			var player_character: = DialogicResourceUtil.get_character_resource("player")
			if player_character:
				character = player_character
		elif snap_type == SnapshotType.AI_EXCHANGE:
			var ai_display_text: String = ai_data.get("displayed_text", "")
			if ai_display_text.is_empty():
				ai_display_text = ai_data.get("last_ai_response", "")
			if not ai_display_text.is_empty():
				display_text = ai_display_text

			var ai_char_id: String = ai_data.get("character_id", "")
			var ai_char_name: String = ai_data.get("character_name", "")
			Log.d("RollbackManager", "AI_EXCHANGE: ai_data.character_id='%s' ai_data.character_name='%s' ai_data.character_tags=%s" % [
				ai_char_id, ai_char_name, str(ai_data.get("character_tags", []))
			])
			if not ai_char_id.is_empty():
				var ai_character: = _resolve_snapshot_character(ai_char_id)
				Log.d("RollbackManager", "AI_EXCHANGE: resolved ai_char_id -> %s" % [
					ai_character.display_name if ai_character else "<null>"
				])
				if ai_character:
					character = ai_character

			if character == null:
				var char_tags: Array = ai_data.get("character_tags", [])
				Log.d("RollbackManager", "AI_EXCHANGE: character still null, falling back to tags=%s" % [str(char_tags)])
				if not char_tags.is_empty():
					character = _resolve_snapshot_character(str(char_tags[0]))

		Log.d("RollbackManager", "Name final: character=%s display_text='%s'" % [
			character.display_name if character else "<null>", 
			display_text.substr(0, 60) if display_text.length() > 60 else display_text
		])
		Dialogic.Text.update_name_label(character)
		CharacterSpriteLoader.call("apply_typing_sound_for_dialogic_character", character)
		Dialogic.Text.update_dialog_text(display_text, true)
		preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree()).replay_history(snapshot, character.get_identifier() if character != null else "narrator", display_text)
		Dialogic.Text.show_textbox()


	if Dialogic.has_subsystem("Choices"):
		Dialogic.Choices.hide_all_choices()


	Dialogic.paused = false
	Dialogic.current_state = Dialogic.States.IDLE

	if restore_generation != _restore_generation:
		return false
	_restoring = false



	Log.d("RollbackManager", "Restored snapshot: type=%s text='%s' pos=%s" % [
		str(snap_type), 
		str(snapshot.get("display_text", "")), 
		str(_current_position)
	])
	return true


func _resolve_snapshot_character(character_id: String) -> DialogicCharacter:
	var normalized: = character_id.strip_edges()
	if normalized.is_empty():
		return null
	if normalized.begins_with("res://"):
		return load(normalized) as DialogicCharacter
	var character: = DialogicResourceUtil.get_character_resource(normalized)
	if character == null:
		character = CharacterPortraitService.find_dialogic_character(normalized)
	return character


func rollback() -> bool:



	if _restoring:
		return false




	if not _in_rollback_mode and _snapshots.size() <= 1:
		return false

	if not can_rollback():


		if _in_rollback_mode and _snapshots.size() <= 1:
			exit_rollback_mode()
		return false


	if not _in_rollback_mode:
		_capture_audio_snapshot_for_session()
		_in_rollback_mode = true
		_current_position = _snapshots.size() - 1




		var is_text_animating: = Dialogic.current_state != Dialogic.States.IDLE
		if is_text_animating and _current_position > 0:
			_current_position -= 1
			Log.d("RollbackManager", "Entered rollback mode (animating): pos=%s total=%s" % [str(_current_position), str(_snapshots.size())])
			var snap: = _snapshots[_current_position].duplicate(true)
			if not await _restore_snapshot(snap):
				return false
			_emit_state_changed()
			rollback_performed.emit(-1)
			return true

		Log.d("RollbackManager", "Entered rollback mode: pos=%s total=%s" % [str(_current_position), str(_snapshots.size())])



		if _current_position <= 0:
			exit_rollback_mode()
			return false

	if _current_position > 0:
		_current_position -= 1
		var snap: = _snapshots[_current_position]
		Log.d("RollbackManager", "Rollback to pos=%s type=%s text='%s'" % [
			str(_current_position), 
			str(snap.get("type", SnapshotType.SCRIPTED)), 
			str(snap.get("display_text", ""))
		])
		if not await _restore_snapshot(_snapshots[_current_position].duplicate(true)):
			return false
		_emit_state_changed()
		rollback_performed.emit(-1)
		return true


	if _in_rollback_mode and _snapshots.size() <= 1:
		exit_rollback_mode()

	return false


func roll_forward() -> bool:

	if _restoring:
		return false
	if not can_roll_forward():
		return false

	_current_position += 1
	if not await _restore_snapshot(_snapshots[_current_position].duplicate(true)):
		return false
	_emit_state_changed()
	rollback_performed.emit(1)
	return true


func can_rollback() -> bool:
	if _snapshots.is_empty():
		return false
	if _in_rollback_mode:
		return _current_position > 0


	return _snapshots.size() > 1


func can_roll_forward() -> bool:

	return _in_rollback_mode and _current_position < _snapshots.size() - 1


func exit_rollback_mode() -> void :
	_cancel_pending_restore()
	_in_rollback_mode = false
	_current_position = -1
	_audio_snapshot = {}
	_emit_state_changed()


func is_in_rollback_mode() -> bool:
	return _in_rollback_mode


func is_restoring() -> bool:
	return _restoring






func consume_audio_snapshot() -> Dictionary:
	if _audio_snapshot.is_empty():
		return {}

	var audio_to_restore: = _audio_snapshot.duplicate(true)
	_audio_snapshot.clear()
	return audio_to_restore


func restore_audio_from_snapshot(audio_to_restore: Dictionary, authoritative: bool = false) -> void :
	if not Dialogic.has_subsystem("Audio"):
		return

	if audio_to_restore.is_empty() and not authoritative:
		return

	var desired_audio: Dictionary = {}
	for channel_name in audio_to_restore:
		var channel_data: Dictionary = audio_to_restore[channel_name]
		var path: = str(channel_data.get("path", "")).strip_edges()
		if path.is_empty():
			continue
		desired_audio[channel_name] = {
			"path": path, 
			"settings_overrides": channel_data.get("settings_overrides", {})
		}



	var tracked_players: Array = []
	for active_channel in Dialogic.Audio.current_audio_channels:
		var active_player = Dialogic.Audio.current_audio_channels[active_channel]
		if active_player != null and is_instance_valid(active_player):
			tracked_players.append(active_player)
	if Dialogic.Audio.audio_node:
		for child in Dialogic.Audio.audio_node.get_children():
			if child is AudioStreamPlayer and not tracked_players.has(child):
				(child as AudioStreamPlayer).stop()
				child.queue_free()

	var current_audio: Dictionary = Dialogic.current_state_info.get("audio", {}).duplicate(true)


	for channel_name in Dialogic.Audio.current_audio_channels.keys():
		if not desired_audio.has(channel_name):
			Log.d("RollbackManager", "Stopping stale audio channel '%s' after rollback resume" % channel_name)
			Dialogic.Audio.update_audio(channel_name, "", {"fade_length": 0.0})



	for channel_name in desired_audio:
		var channel_data: Dictionary = desired_audio[channel_name]
		var desired_path: = str(channel_data.get("path", ""))
		var current_channel: Dictionary = current_audio.get(channel_name, {})
		var current_path: = str(current_channel.get("path", ""))
		var is_same_path: = current_path == desired_path
		var is_playing: = Dialogic.Audio.is_channel_playing(channel_name)

		if is_same_path and is_playing:
			continue

		Log.d("RollbackManager", "Restoring audio channel '%s': %s" % [channel_name, desired_path])
		Dialogic.Audio.update_audio(channel_name, desired_path, channel_data.get("settings_overrides", {}))



	Dialogic.current_state_info["audio"] = desired_audio.duplicate(true)


func _capture_audio_snapshot_for_session() -> void :
	_audio_snapshot = {}
	if not Dialogic.has_subsystem("Audio"):
		return

	var audio_info: Dictionary = Dialogic.current_state_info.get("audio", {})
	if not audio_info.is_empty():
		_audio_snapshot = audio_info.duplicate(true)


func clear_snapshots() -> void :
	_cancel_pending_restore()
	_snapshots.clear()
	_current_position = -1
	_in_rollback_mode = false
	_audio_snapshot = {}
	_emit_state_changed()


func _cancel_pending_restore() -> void :
	_restore_generation += 1
	_restoring = false


func get_all_snapshots() -> Array[Dictionary]:
	return _snapshots



func get_current_position() -> int:
	return _current_position






func jump_to_snapshot(index: int) -> bool:
	if _restoring:
		return false
	if index < 0 or index >= _snapshots.size():
		return false

	if not _in_rollback_mode:
		_capture_audio_snapshot_for_session()
	_in_rollback_mode = true
	_current_position = index
	if not await _restore_snapshot(_snapshots[index].duplicate(true)):
		return false
	_emit_state_changed()
	return true




func consume_resume_audio_state() -> Dictionary:
	var fallback: = consume_audio_snapshot()
	var snapshot: = get_current_snapshot()
	if snapshot.has("audio") and snapshot.get("audio") is Dictionary:
		return {
			"channels": (snapshot.get("audio") as Dictionary).duplicate(true), 
			"authoritative": true, 
		}
	return {
		"channels": fallback, 
		"authoritative": false, 
	}





func get_selected_audio_state() -> Dictionary:
	if _in_rollback_mode:
		var snapshot: = get_current_snapshot()
		if snapshot.has("audio") and snapshot.get("audio") is Dictionary:
			return (snapshot.get("audio") as Dictionary).duplicate(true)
	if Dialogic.has_subsystem("Audio"):
		var runtime_audio: Variant = Dialogic.current_state_info.get("audio", {})
		if runtime_audio is Dictionary:
			return (runtime_audio as Dictionary).duplicate(true)
	return {}




func get_visible_dialogic_history_size(ai_data: Dictionary) -> int:
	var visible_size: = int(ai_data.get("dialogic_history_length", -1))
	for raw_entry in ai_data.get("displayed_lines", []):
		if not (raw_entry is Dictionary):
			continue
		var raw_index: = int((raw_entry as Dictionary).get("raw_history_index", -1))
		if raw_index >= 0:
			visible_size = maxi(visible_size, raw_index + 1)
	return visible_size





func prune_ai_snapshots_after_history_size(history_size_before_exchange: int, reset_rollback_state: bool = true) -> void :
	var removed: = 0
	while not _snapshots.is_empty():
		var last_snapshot: Dictionary = _snapshots[-1]
		var last_snapshot_type: SnapshotType = last_snapshot.get("type", SnapshotType.SCRIPTED)
		if last_snapshot_type not in [SnapshotType.AI_PLAYER_TURN, SnapshotType.AI_EXCHANGE]:
			break

		var ai_data: Dictionary = last_snapshot.get("ai_data", {})
		if ai_data.get("is_scene_generated", false):
			break

		var snapshot_history: Array = ai_data.get("history", [])
		if snapshot_history.size() <= history_size_before_exchange:
			break

		_snapshots.pop_back()
		removed += 1

	if removed <= 0:
		return

	if reset_rollback_state:
		_current_position = -1
		_in_rollback_mode = false
	elif _current_position >= _snapshots.size():


		_current_position = _snapshots.size() - 1
	if _snapshots.is_empty():
		_current_position = -1
		_in_rollback_mode = false
		_audio_snapshot = {}
	if APIConfigManager.is_debug_enabled():
		print("[RollbackManager] Pruned %d AI snapshot(s); history_size_before_exchange=%d remaining=%d" % [
			removed, 
			history_size_before_exchange, 
			_snapshots.size()
		])
	_emit_state_changed()







func update_last_ai_snapshot(
	new_text: String, 
	history_copy: Array, 
	displayed_lines_copy: Array, 
	remaining_queue_copy: Array, 
	edited_history_index: int, 
	previous_text: String, 
	assistant_history_index: int, 
	previous_response: String, 
	updated_response: String, 
	rebuild_response: Callable
) -> void :
	if is_in_rollback_mode():
		var current: = get_current_snapshot()
		if not current.is_empty():
			var idx: = _snapshots.find(current)
			if idx != -1:
				var snap: Dictionary = _snapshots[idx]
				var ai_data: Dictionary = snap.get("ai_data", {})
				if not ai_data.get("is_scene_generated", false):
					ai_data["displayed_text"] = new_text
					ai_data["last_ai_response"] = new_text
					ai_data["history"] = history_copy
					ai_data["displayed_lines"] = displayed_lines_copy
					ai_data["remaining_queue"] = remaining_queue_copy
					snap["ai_data"] = ai_data
					snap["display_text"] = new_text
					_snapshots[idx] = snap
					_propagate_ai_edit_to_later_snapshots(
						idx, 
						new_text, 
						edited_history_index, 
						previous_text, 
						assistant_history_index, 
						previous_response, 
						updated_response, 
						rebuild_response
					)
					return

	for i in range(_snapshots.size() - 1, -1, -1):
		var snap: Dictionary = _snapshots[i]
		if snap.get("type", SnapshotType.SCRIPTED) != SnapshotType.AI_EXCHANGE:
			continue
		var ai_data: Dictionary = snap.get("ai_data", {})
		if ai_data.get("is_scene_generated", false):
			continue
		ai_data["displayed_text"] = new_text
		ai_data["last_ai_response"] = new_text
		ai_data["history"] = history_copy
		ai_data["displayed_lines"] = displayed_lines_copy
		ai_data["remaining_queue"] = remaining_queue_copy
		snap["ai_data"] = ai_data
		snap["display_text"] = new_text
		_snapshots[i] = snap
		break





func _propagate_ai_edit_to_later_snapshots(
	from_idx: int, 
	new_text: String, 
	edited_history_index: int, 
	previous_text: String, 
	assistant_history_index: int, 
	previous_response: String, 
	updated_response: String, 
	rebuild_response: Callable
) -> void :
	for i in range(from_idx + 1, _snapshots.size()):
		var snap: Dictionary = _snapshots[i]
		var snap_type: int = snap.get("type", SnapshotType.SCRIPTED)
		if snap_type not in [SnapshotType.AI_PLAYER_TURN, SnapshotType.AI_EXCHANGE]:
			continue
		var ai_data: Dictionary = snap.get("ai_data", {})
		if ai_data.get("is_scene_generated", false):
			continue

		var changed: = false

		var snap_displayed: Array = ai_data.get("displayed_lines", []).duplicate(true)
		for j in range(snap_displayed.size()):
			var entry: Dictionary = snap_displayed[j] as Dictionary
			if entry.get("type", "dialogue") != "dialogue":
				continue
			var entry_idx: = int(entry.get("raw_history_index", -1))
			if entry_idx >= 0 and entry_idx == edited_history_index:
				entry["text"] = new_text
				snap_displayed[j] = entry
				changed = true
				break
			if entry_idx < 0 and str(entry.get("text", "")).strip_edges() == previous_text:
				entry["text"] = new_text
				snap_displayed[j] = entry
				changed = true
				break

		var snap_queue: Array = ai_data.get("remaining_queue", []).duplicate(true)
		for j in range(snap_queue.size()):
			var entry: Dictionary = snap_queue[j] as Dictionary
			if entry.get("type", "dialogue") != "dialogue":
				continue
			if str(entry.get("text", "")).strip_edges() == previous_text:
				entry["text"] = new_text
				snap_queue[j] = entry
				changed = true
				break

		var snap_history: Array = ai_data.get("history", []).duplicate(true)
		var history_updated: = false
		if assistant_history_index >= 0 and assistant_history_index < snap_history.size():
			var h_entry: Dictionary = snap_history[assistant_history_index] as Dictionary
			if h_entry.get("role", "") == "assistant" and str(h_entry.get("content", "")).strip_edges() == previous_response:
				h_entry["content"] = updated_response
				snap_history[assistant_history_index] = h_entry
				history_updated = true
		if not history_updated and not previous_response.is_empty():
			for j in range(snap_history.size() - 1, -1, -1):
				var h_entry: Dictionary = snap_history[j] as Dictionary
				if h_entry.get("role", "") != "assistant":
					continue
				if str(h_entry.get("content", "")).strip_edges() != previous_response:
					continue
				h_entry["content"] = updated_response
				snap_history[j] = h_entry
				history_updated = true
				break
		if history_updated:
			changed = true

		if changed and snap_type == SnapshotType.AI_EXCHANGE and history_updated:
			var all_lines: Array = []
			for raw_entry in snap_displayed:
				if raw_entry is Dictionary:
					all_lines.append((raw_entry as Dictionary).duplicate(true))
			for raw_entry in snap_queue:
				if raw_entry is Dictionary:
					all_lines.append((raw_entry as Dictionary).duplicate(true))
			var rebuilt_response: = str(rebuild_response.call(all_lines)).strip_edges()
			if not rebuilt_response.is_empty():
				for j in range(snap_history.size() - 1, -1, -1):
					var h_entry: Dictionary = snap_history[j] as Dictionary
					if h_entry.get("role", "") == "assistant" and str(h_entry.get("content", "")).strip_edges() == updated_response:
						h_entry["content"] = rebuilt_response
						snap_history[j] = h_entry
						break

		if changed:
			ai_data["displayed_lines"] = snap_displayed
			ai_data["remaining_queue"] = snap_queue
			ai_data["history"] = snap_history
			snap["ai_data"] = ai_data
			_snapshots[i] = snap


func get_history_scope_snapshot_indices() -> Array[int]:
	var indices: Array[int] = []
	if _snapshots.is_empty():
		return indices

	if AIStateCoordinator.is_active() and _has_ai_snapshots():
		for i in range(_snapshots.size()):
			if _is_ai_snapshot(_snapshots[i]):
				indices.append(i)
		return indices

	for i in range(_snapshots.size()):
		indices.append(i)
	return indices


func discard_future_snapshots_from_current(emit_state_change: bool = true) -> void :
	if _current_position < 0 or _current_position >= _snapshots.size():
		return

	var target_size: = _current_position + 1
	if target_size >= _snapshots.size():
		return

	_snapshots.resize(target_size)
	if emit_state_change:
		_emit_state_changed()


func get_active_ai_session_dialogic_history_start() -> int:
	if not _has_ai_snapshots():
		return -1

	for snapshot in _snapshots:
		if snapshot.get("type", SnapshotType.SCRIPTED) != SnapshotType.AI_CONVERSATION_START:
			continue
		var ai_data: Dictionary = snapshot.get("ai_data", {})
		var session_start: = int(ai_data.get("session_start_dialogic_history_length", -1))
		if session_start >= 0:
			return session_start
		return int(ai_data.get("dialogic_history_length", -1))

	return -1


func get_active_ai_session_save_state(compact: bool = false) -> Dictionary:
	if not _has_ai_snapshots():
		return {}

	var saved_snapshots: Array = []
	var save_upto_index: = _snapshots.size() - 1
	if _in_rollback_mode and _current_position >= 0:
		save_upto_index = _current_position

	for i in range(mini(save_upto_index + 1, _snapshots.size())):
		var snapshot: Dictionary = _snapshots[i]
		if not _is_ai_snapshot(snapshot):
			continue
		saved_snapshots.append(snapshot if compact else snapshot.duplicate(true))

	if saved_snapshots.is_empty():
		return {}

	if compact:
		return preload("res://scripts/services/rollback_save_codec.gd").encode(saved_snapshots)
	return {"snapshots": saved_snapshots}


func restore_active_ai_session_save_state(state: Dictionary) -> void :
	_cancel_pending_restore()
	_snapshots.clear()
	_current_position = -1
	_in_rollback_mode = false
	_audio_snapshot = {}

	var raw_snapshots: Variant = preload("res://scripts/services/rollback_save_codec.gd").decode(state)
	var saved_snapshots: Array = raw_snapshots if raw_snapshots is Array else []
	for snapshot in saved_snapshots:
		if snapshot is Dictionary and _is_ai_snapshot(snapshot):
			_snapshots.append((snapshot as Dictionary).duplicate(true))
	while _snapshots.size() > max_snapshots:
		var evict_index: = 0
		if _snapshots[0].get("type", SnapshotType.SCRIPTED) == SnapshotType.AI_CONVERSATION_START and _snapshots.size() > 1:
			evict_index = 1
		_snapshots.remove_at(evict_index)

	_emit_state_changed()


func _emit_state_changed() -> void :

	if _in_rollback_mode and _current_position >= 0 and _current_position < _snapshots.size():
		var snapshot = _snapshots[_current_position]
		var snap_type: SnapshotType = snapshot.get("type", SnapshotType.SCRIPTED)
		snapshot_type_changed.emit(snap_type)


		var is_ai = snap_type in [SnapshotType.AI_CONVERSATION_START, SnapshotType.AI_PLAYER_TURN, SnapshotType.AI_EXCHANGE]
		var ai_data = snapshot.get("ai_data", {}) if is_ai else {}
		ai_state_changed.emit(is_ai, ai_data)








func register_ai_conversation_start(ai_node: Node, character_tags: Array[String], initial_ai_data: Dictionary = {}) -> void :
	Log.d("RollbackManager", "register_ai_conversation_start: tags=%s, current_snapshots=%d" % [character_tags, _snapshots.size()])


	if _in_rollback_mode:
		Log.d("RollbackManager", "Skipping - in rollback mode")
		return



	if AIStateCoordinator.is_in_qa_conversation() and _has_only_ai_snapshots():
		_update_existing_ai_session_start_snapshot(character_tags)
		Log.d("RollbackManager", "Preserving existing AI session snapshots for Q&A handoff")
		return




	var old_count: = _snapshots.size()
	_cancel_pending_restore()
	_snapshots.clear()
	_current_position = -1
	_in_rollback_mode = false
	Log.d("RollbackManager", "Cleared %d old snapshots for fresh AI session" % old_count)


	var snapshot: = _capture_state(null)
	var session_start_dialogic_history_length: = _get_dialogic_simple_history_size()
	snapshot["type"] = SnapshotType.AI_CONVERSATION_START
	var start_ai_data: = {
		"character_tags": character_tags, 
		"roster_state": {}, 
		"history": [], 
		"sprite_states": {}, 
		"location_id": MapManager.get_current_runtime_location_id(), 
		"dialogic_history_length": session_start_dialogic_history_length, 
		"session_start_dialogic_history_length": session_start_dialogic_history_length, 
		"time_slot": GameState.current_time_slot, 
		"daily_visits": GameState.daily_visits, 
		"pass_time_state": GameState.capture_pass_time_rollback_state(), 
	}
	start_ai_data.merge(initial_ai_data.duplicate(true), true)
	if ai_node != null:
		if ai_node.has_method("get_rollback_owner_key"):
			start_ai_data["rollback_owner_key"] = str(ai_node.call("get_rollback_owner_key"))
		if ai_node.has_method("get_rollback_owner_kind"):
			start_ai_data["rollback_owner_kind"] = str(ai_node.call("get_rollback_owner_kind"))
	snapshot["ai_data"] = start_ai_data
	snapshot["display_text"] = "── AI Conversation Started ──"
	snapshot["character"] = ""
	_snapshots.append(snapshot)

	Log.d("RollbackManager", "Created AI_CONVERSATION_START snapshot, total=%d" % _snapshots.size())
	_emit_state_changed()


func register_ai_player_turn(ai_data: Dictionary) -> void :
	if not AIStateCoordinator.is_in_qa_conversation():
		push_warning("[RollbackManager] register_ai_player_turn called but Q&A session is not active")
		return

	if _in_rollback_mode:
		return

	if _current_position >= 0 and _current_position < _snapshots.size() - 1:
		_snapshots.resize(_current_position + 1)

	var snapshot: = _capture_state(null)
	snapshot["type"] = SnapshotType.AI_PLAYER_TURN
	snapshot["ai_data"] = ai_data.duplicate(true)
	snapshot["display_text"] = str(ai_data.get("displayed_text", ai_data.get("player_input_text", "")))
	snapshot["character"] = "You"

	var player_char: = DialogicResourceUtil.get_character_resource("player")
	if player_char:
		var player_id: = player_char.resource_path
		if player_id.is_empty():
			player_id = player_char.get_identifier()
		snapshot["character_id"] = player_id

	_append_ai_snapshot(snapshot)




func register_ai_exchange(ai_data: Dictionary) -> void :



	var is_scene_generated: = bool(ai_data.get("is_scene_generated", false))
	if not AIStateCoordinator.is_active() and not is_scene_generated:
		push_warning("[RollbackManager] register_ai_exchange called but no active AI session")
		return
	elif not AIStateCoordinator.is_active() and is_scene_generated and APIConfigManager.is_debug_enabled():
		print("[RollbackManager] register_ai_exchange: accepting scene snapshot while coordinator is idle")


	if _in_rollback_mode:
		return


	if _current_position >= 0 and _current_position < _snapshots.size() - 1:
		_snapshots.resize(_current_position + 1)


	var snapshot: = _capture_state(null)
	snapshot["type"] = SnapshotType.AI_EXCHANGE
	snapshot["ai_data"] = ai_data.duplicate(true)


	var display_text: String = ai_data.get("displayed_text", "")
	if display_text.is_empty():
		display_text = ai_data.get("last_ai_response", "")
	snapshot["display_text"] = display_text
	snapshot["character"] = ai_data.get("character_name", "AI")

	Log.d("RollbackManager", "AI_EXCHANGE register: char_name='%s' ai_data.character_id='%s' snapshot.character_id='%s' text='%s'" % [
		ai_data.get("character_name", ""), 
		ai_data.get("character_id", ""), 
		snapshot.get("character_id", ""), 
		display_text.substr(0, 50) if display_text.length() > 50 else display_text
	])
	Log.d("RollbackManager", "AI_EXCHANGE new: char=%s display_len=%s lines=%s scene=%s snap_count=%s in_rollback=%s pos=%s" % [
		str(snapshot.get("character", "")), 
		str(display_text.length()), 
		str(ai_data.get("displayed_lines", []).size()), 
		str(ai_data.get("is_scene_generated", false)), 
		str(_snapshots.size()), 
		str(_in_rollback_mode), 
		str(_current_position)
	])


	if not _snapshots.is_empty():
		var last: Dictionary = _snapshots[-1]
		if last.get("type", SnapshotType.SCRIPTED) == SnapshotType.AI_EXCHANGE:
			var last_ai: Dictionary = last.get("ai_data", {})
			var last_lines: Array = last_ai.get("displayed_lines", [])
			var new_lines: Array = ai_data.get("displayed_lines", [])
			var same_count: bool = last_lines.size() == new_lines.size()
			var same_char: bool = str(last.get("character", "")) == str(snapshot.get("character", ""))
			var same_mode: bool = bool(last_ai.get("is_scene_generated", false)) == bool(ai_data.get("is_scene_generated", false))

			var last_line_text: = ""
			if not last_lines.is_empty():
				last_line_text = str(last_lines[-1].get("text", ""))
			var new_line_text: = ""
			if not new_lines.is_empty():
				new_line_text = str(new_lines[-1].get("text", ""))
			var same_line_text: bool = last_line_text == new_line_text and not new_line_text.is_empty()
			var same_display: bool = str(last.get("display_text", "")) == str(snapshot.get("display_text", ""))

			Log.d("RollbackManager", "AI_EXCHANGE compare: last_lines=%s new_lines=%s last_text='%s' new_text='%s' same_count=%s same_char=%s same_mode=%s same_line=%s same_display=%s" % [
				str(last_lines.size()), 
				str(new_lines.size()), 
				str(last_line_text), 
				str(new_line_text), 
				str(same_count), 
				str(same_char), 
				str(same_mode), 
				str(same_line_text), 
				str(same_display)
			])

			if same_count and same_char and same_mode and (same_line_text or same_display):
				Log.d("RollbackManager", "AI_EXCHANGE dedupe: same_count=%s same_char=%s same_mode=%s same_line=%s same_display=%s" % [
					str(same_count), 
					str(same_char), 
					str(same_mode), 
					str(same_line_text), 
					str(same_display)
				])
				last["ai_data"] = snapshot["ai_data"]
				last["display_text"] = snapshot["display_text"]
				last["character"] = snapshot["character"]
				_snapshots[-1] = last
				_emit_state_changed()
				return

	_append_ai_snapshot(snapshot)


func _append_ai_snapshot(snapshot: Dictionary) -> void :
	var voice_character := _resolve_snapshot_character(str(snapshot.get("ai_data", {}).get("character_id", snapshot.get("character_id", ""))))
	snapshot.merge(preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree()).history_metadata(voice_character.get_identifier() if voice_character != null else "narrator", str(snapshot.get("display_text", ""))), true)
	_snapshots.append(snapshot)

	if _snapshots.size() > max_snapshots:


		var evict_index: = 0
		if _snapshots[0].get("type", SnapshotType.SCRIPTED) == SnapshotType.AI_CONVERSATION_START and _snapshots.size() > 1:
			evict_index = 1
		_snapshots.remove_at(evict_index)
	_current_position = -1
	_in_rollback_mode = false
	_emit_state_changed()




func register_ai_conversation_end() -> void :

	pass



func get_current_snapshot() -> Dictionary:
	if not _in_rollback_mode or _current_position < 0:
		return {}
	if _current_position < _snapshots.size():
		return _snapshots[_current_position]
	return {}



func get_current_snapshot_type() -> SnapshotType:
	if not _in_rollback_mode or _current_position < 0:
		if AIStateCoordinator.is_in_qa_conversation():
			return SnapshotType.AI_EXCHANGE
		return SnapshotType.SCRIPTED

	if _current_position < _snapshots.size():
		return _snapshots[_current_position].get("type", SnapshotType.SCRIPTED)
	return SnapshotType.SCRIPTED



func get_current_ai_data() -> Dictionary:
	if not _in_rollback_mode or _current_position < 0:
		return {}

	if _current_position < _snapshots.size():
		var snapshot = _snapshots[_current_position]
		if snapshot.get("type", SnapshotType.SCRIPTED) in [SnapshotType.AI_CONVERSATION_START, SnapshotType.AI_PLAYER_TURN, SnapshotType.AI_EXCHANGE]:
			return snapshot.get("ai_data", {})
	return {}

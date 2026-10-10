extends DialogicSubsystem



signal open_requested
signal close_requested




var simple_history_enabled: = false
var simple_history_save: = false
var simple_history_content: Array[Dictionary] = []
signal simple_history_changed






signal simple_history_loaded
const LINE_ID_KEY: = "line_id"
const LINE_ID_PREFIX: = "ln_"
const LINE_ID_COUNTER_KEY: = "history_simple_next_line_id"
var _next_line_id: = 1


var full_event_history_enabled: = false
var full_event_history_save: = false



var full_event_history_content: Array[DialogicEvent] = []


signal full_event_history_changed



var visited_event_history_enabled: = false


var visited_event_history_content: = {}


var _visited_last_event: = false





signal visited_event


signal unvisited_event




var visited_event_save_key: = "visited_event_history_content"


var save_visited_history_on_autosave: = false:
	set(value):
		save_visited_history_on_autosave = value
		_update_saved_connection(value)



var save_visited_history_on_save: = false:
	set(value):
		save_visited_history_on_save = value
		_update_saved_connection(value)



func _update_saved_connection(to_connect: bool) -> void :
	if to_connect:
		if not DialogicUtil.autoload().Save.saved.is_connected(_on_save):
			DialogicUtil.autoload().Save.saved.connect(_on_save)

	else:
		if DialogicUtil.autoload().Save.saved.is_connected(_on_save):
			DialogicUtil.autoload().Save.saved.disconnect(_on_save)





func _ready() -> void :
	dialogic.event_handled.connect(store_full_event)
	dialogic.event_handled.connect(_check_seen)

	simple_history_enabled = ProjectSettings.get_setting("dialogic/history/simple_history_enabled", simple_history_enabled)
	simple_history_save = ProjectSettings.get_setting("dialogic/history/simple_history_save", simple_history_save)
	full_event_history_enabled = ProjectSettings.get_setting("dialogic/history/full_history_enabled", full_event_history_enabled)
	full_event_history_save = ProjectSettings.get_setting("dialogic/history/full_history_save", full_event_history_save)
	visited_event_history_enabled = ProjectSettings.get_setting("dialogic/history/visited_event_history_enabled", visited_event_history_enabled)



func _on_save(info: Dictionary) -> void :
	var is_autosave: bool = info["is_autosave"]

	var save_on_autosave: = save_visited_history_on_autosave and is_autosave
	var save_on_save: = save_visited_history_on_save and not is_autosave

	if save_on_save or save_on_autosave:
		save_visited_history()


func post_install() -> void :
	save_visited_history_on_autosave = ProjectSettings.get_setting("dialogic/history/save_on_autosave", save_visited_history_on_autosave)
	save_visited_history_on_save = ProjectSettings.get_setting("dialogic/history/save_on_save", save_visited_history_on_save)


func clear_game_state(clear_flag: = DialogicGameHandler.ClearFlags.FULL_CLEAR) -> void :
	if clear_flag == DialogicGameHandler.ClearFlags.FULL_CLEAR:
		if simple_history_save:
			simple_history_content = []
			dialogic.current_state_info.erase("history_simple")
		if full_event_history_save:
			full_event_history_content = []
			dialogic.current_state_info.erase("history_full")


func load_game_state(load_flag: = LoadFlags.FULL_LOAD) -> void :
	if load_flag == LoadFlags.FULL_LOAD:
		if simple_history_save and dialogic.current_state_info.has("history_simple"):
			simple_history_content.assign(dialogic.current_state_info["history_simple"])


		_next_line_id = maxi(_next_line_id, int(dialogic.current_state_info.get(LINE_ID_COUNTER_KEY, 1)))
		ensure_line_ids(true)
		simple_history_loaded.emit()

		if full_event_history_save and dialogic.current_state_info.has("history_full"):
			full_event_history_content = []

			for event_text in dialogic.current_state_info["history_full"]:
				var event: DialogicEvent
				for i in DialogicResourceUtil.get_event_cache():
					if i.is_valid_event(event_text):
						event = i.duplicate()
						break
				event.from_text(event_text)
				full_event_history_content.append(event)


func save_game_state() -> void :
	if simple_history_save:
		dialogic.current_state_info["history_simple"] = Array(simple_history_content)
		dialogic.current_state_info[LINE_ID_COUNTER_KEY] = _next_line_id
	else:
		dialogic.current_state_info.erase("history_simple")
		dialogic.current_state_info.erase(LINE_ID_COUNTER_KEY)
	if full_event_history_save:
		dialogic.current_state_info["history_full"] = []
		for event in full_event_history_content:
			dialogic.current_state_info["history_full"].append(event.to_text())
	else:
		dialogic.current_state_info.erase("history_full")


func open_history() -> void :
	open_requested.emit()


func close_history() -> void :
	close_requested.emit()







func store_simple_history_entry(text: String, event_type: String, extra_info: = {}) -> void :
	if !simple_history_enabled: return
	extra_info["text"] = text
	extra_info["event_type"] = event_type
	if not _has_line_id(extra_info):
		extra_info[LINE_ID_KEY] = _take_line_id()
	if event_type == "Text":
		var speaker := str(extra_info.get("voice_speaker", extra_info.get("character", "narrator")))
		extra_info.merge(preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree()).history_metadata(speaker, text), true)
	simple_history_content.append(extra_info)
	simple_history_changed.emit()


func get_simple_history() -> Array:
	return simple_history_content






func ensure_line_ids(fix_duplicates: = false) -> int:
	var needs_work: = fix_duplicates
	if not needs_work:


		for entry in simple_history_content:
			if not entry.has(LINE_ID_KEY):
				needs_work = true
				break
	if not needs_work:
		return 0

	for entry in simple_history_content:
		if _has_line_id(entry):
			_next_line_id = maxi(_next_line_id, _parse_line_id_number(str(entry[LINE_ID_KEY])) + 1)

	var stamped: = 0
	var seen: = {}
	for entry in simple_history_content:
		if not _has_line_id(entry) or (fix_duplicates and seen.has(entry[LINE_ID_KEY])):
			entry[LINE_ID_KEY] = _take_line_id()
			stamped += 1
		seen[entry[LINE_ID_KEY]] = true
	return stamped


func _take_line_id() -> String:
	var line_id: = LINE_ID_PREFIX + "%06d" % _next_line_id
	_next_line_id += 1
	return line_id


func _has_line_id(entry: Dictionary) -> bool:
	return _parse_line_id_number(str(entry.get(LINE_ID_KEY, ""))) >= 0


func _parse_line_id_number(line_id: String) -> int:
	if not line_id.begins_with(LINE_ID_PREFIX):
		return -1
	var suffix: = line_id.trim_prefix(LINE_ID_PREFIX)
	return int(suffix) if suffix.is_valid_int() else -1








func store_full_event(event: DialogicEvent) -> void :
	if !full_event_history_enabled: return
	full_event_history_content.append(event)
	full_event_history_changed.emit()







func _current_event_key() -> String:
	var resource_path: = dialogic.current_timeline.resource_path
	var event_index: = dialogic.current_event_idx
	var event_key: = _get_event_key(event_index, resource_path)

	return event_key





func _get_event_key(event_index: int, timeline_path: String) -> String:
	var event_idx: = str(event_index)
	var event_key: = timeline_path + event_idx

	return event_key



func mark_event_as_visited(event_index: = dialogic.current_event_idx, timeline: = dialogic.current_timeline) -> void :
	if !visited_event_history_enabled:
		return

	var event_key: = _get_event_key(event_index, timeline.resource_path)

	visited_event_history_content[event_key] = event_index



func _check_seen(event: DialogicEvent) -> void :
	if !visited_event_history_enabled:
		return




	if event.event_name != "Text":
		return

	var event_key: = _current_event_key()

	if event_key in visited_event_history_content:
		visited_event.emit()
		_visited_last_event = true

	else:
		unvisited_event.emit()
		_visited_last_event = false




func has_last_event_been_visited() -> bool:
	return _visited_last_event













func has_event_been_visited(event_index: = dialogic.current_event_idx, timeline: = dialogic.current_timeline) -> bool:
	if timeline == null:
		return false

	var event_key: = _get_event_key(event_index, timeline.resource_path)
	var visited: = event_key in visited_event_history_content

	return visited










func save_visited_history() -> void :
	DialogicUtil.autoload().Save.set_global_info(visited_event_save_key, visited_event_history_content)






func load_visited_history() -> void :
	visited_event_history_content = get_saved_visited_history()






func get_saved_visited_history() -> Dictionary:
	return DialogicUtil.autoload().Save.get_global_info(visited_event_save_key, {})







func reset_visited_history(reset_property: = true) -> void :
	DialogicUtil.autoload().Save.set_global_info(visited_event_save_key, {})

	if reset_property:
		visited_event_history_content = {}

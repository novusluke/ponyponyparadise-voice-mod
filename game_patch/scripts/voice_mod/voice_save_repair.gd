extends RefCounted
## Restore lost Dialogic fields from the existing save's rollback snapshots.
## All migration is in memory; the original slot files are never rewritten.

static func recover(saved: Dictionary, info: Dictionary) -> Dictionary:
	var state := saved.duplicate(true)
	if state.has("variables") and state.has("manual_advance"):
		return state
	var ai: Dictionary = info.get("ai_state", {})
	var rollback: Dictionary = ai.get("rollback_state", {})
	var snapshots: Array = rollback.get("snapshots", [])
	for index in range(snapshots.size() - 1, -1, -1):
		if not snapshots[index] is Dictionary:
			continue
		var snapshot: Dictionary = snapshots[index]
		for key in ["variables", "portraits", "audio"]:
			if not state.has(key) and snapshot.get(key) is Dictionary and not snapshot[key].is_empty():
				state[key] = snapshot[key].duplicate(true)
		var background: Dictionary = snapshot.get("background", {})
		if str(state.get("background_argument", "")).is_empty() and not str(background.get("path", "")).is_empty():
			state.background_argument = str(background.path)
			state.background_scene = str(background.get("scene", ""))
		if not state.has("current_timeline") and not str(snapshot.get("timeline", "")).is_empty():
			state.current_timeline = snapshot.timeline
			state.current_event_idx = int(snapshot.get("event_idx", 0))
		if not state.has("text") and not str(snapshot.get("display_text", "")).is_empty():
			state.text = str(snapshot.display_text)
			state.speaker = str(snapshot.get("character_id", ""))
	state.manual_advance = {"enabled": true, "temp_disabled": false}
	if not state.has("variables"):
		state.variables = {}
	return state

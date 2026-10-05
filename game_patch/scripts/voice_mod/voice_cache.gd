extends RefCounted
## Only named voice cache files are removable. Unknown files and links survive.

static func safe_directory(path: String) -> bool:
	path = path.simplify_path()
	if not path.is_absolute_path():
		return false
	var cursor := path
	while not cursor.is_empty() and cursor != cursor.get_base_dir():
		var parent := DirAccess.open(cursor.get_base_dir())
		if parent != null and parent.is_link(cursor.get_file()):
			return false
		cursor = cursor.get_base_dir()
	return true

static func clean(voices: String, runtime: String) -> Dictionary:
	var result := {"audio": 0, "temporary": 0, "error": ""}
	if not safe_directory(voices) or not safe_directory(runtime):
		result.error = "Cache path contains a link; cleanup skipped."
		return result
	# A missing/damaged protection index must never expose the base pack to deletion.
	var index_path := voices.path_join("opening_manifest.json")
	var index = JSON.parse_string(FileAccess.get_file_as_string(index_path)) if FileAccess.file_exists(index_path) else null
	if not index is Dictionary or not index.get("lines") is Array or index.lines.is_empty():
		result.error = "Base voice protection index unavailable; cleanup skipped."
		return result
	var protected := {}
	for file in preload("res://scripts/voice_mod/voice_base_index.gd").FILES:
		protected[file] = true
	var clip_pattern := RegEx.create_from_string("^[a-z]{2,3}(-[a-z0-9]{2,8})*/[a-f0-9]{64}\\.mp3$")
	for row in index.lines:
		if not row is Dictionary or clip_pattern.search(str(row.get("file", ""))) == null:
			result.error = "Invalid base voice protection index; cleanup skipped."
			return result
		protected[str(row.file)] = true
	var directory := DirAccess.open(voices)
	if directory != null:
		for language in directory.get_directories():
			var sub := voices.path_join(language)
			if directory.is_link(language):
				continue
			var clips := DirAccess.open(sub)
			if clips == null:
				continue
			for name in clips.get_files():
				var relative: String = language + "/" + name
				if clip_pattern.search(relative) != null and not protected.has(relative) and not clips.is_link(name):
					if DirAccess.remove_absolute(sub.path_join(name)) == OK:
						result.audio += 1
				elif RegEx.create_from_string("^[a-f0-9]{64}\\.[0-9]+\\.tmp\\.mp3$").search(name) != null and not clips.is_link(name):
					if DirAccess.remove_absolute(sub.path_join(name)) == OK:
						result.temporary += 1
	var sessions := DirAccess.open(runtime)
	if sessions != null:
		for name in sessions.get_directories():
			if sessions.is_link(name):
				continue
			var session := runtime.path_join(name)
			var files := DirAccess.open(session)
			if files == null:
				continue
			var pattern: RegEx
			if RegEx.create_from_string("^session_[0-9]+_[0-9]+$").search(name) != null:
				# Leave another running game's session alone.
				var pid := int(name.split("_")[1])
				if pid != OS.get_process_id() and OS.is_process_running(pid):
					continue
				pattern = RegEx.create_from_string("^((job|active|done)_[a-f0-9]{64}\\.json(\\.tmp)?|worker_state\\.json(\\.tmp)?|heartbeat|worker\\.log|output\\.log)$")
			elif name == "prompts":
				pattern = RegEx.create_from_string("^[a-f0-9]{64}(\\.[0-9]+\\.tmp)?\\.pt$")
			else:
				continue
			for file in files.get_files():
				if pattern.search(file) != null and not files.is_link(file):
					if DirAccess.remove_absolute(session.path_join(file)) == OK:
						result.temporary += 1
			for child in files.get_directories():
				if files.is_link(child) or RegEx.create_from_string("^synthesis_[a-z0-9_]{8}$").search(child) == null:
					continue
				var scratch := DirAccess.open(session.path_join(child))
				if scratch == null:
					continue
				for file in scratch.get_files():
					if not scratch.is_link(file) and RegEx.create_from_string("^(generated|[a-z]{2,3}(-[a-z0-9]{2,8})*-[a-z0-9]+)\\.wav$").search(file) != null:
						if DirAccess.remove_absolute(session.path_join(child).path_join(file)) == OK:
							result.temporary += 1
				if scratch.get_files().is_empty() and scratch.get_directories().is_empty():
					DirAccess.remove_absolute(session.path_join(child))
			# remove_absolute only removes empty directories; unfamiliar content stays.
			if files.get_files().is_empty() and files.get_directories().is_empty():
				DirAccess.remove_absolute(session)
	return result

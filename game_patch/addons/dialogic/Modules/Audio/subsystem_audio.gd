extends DialogicSubsystem

















signal audio_started(info: Dictionary)


const AUDIO_CHANNEL_META: = &"dialogic_audio_channel"



var audio_node: = Node.new()

var one_shot_audio_node: = Node.new()

var current_audio_channels: Dictionary = {}





func clear_game_state(_clear_flag: = DialogicGameHandler.ClearFlags.FULL_CLEAR) -> void :
	stop_all_channels()
	stop_all_one_shot_sounds()



func load_game_state(load_flag: = LoadFlags.FULL_LOAD) -> void :
	if load_flag == LoadFlags.ONLY_DNODES:
		return


	_convert_state_info()

	var info: Dictionary = dialogic.current_state_info.get("audio", {})

	for channel_name in info.keys():
		if info[channel_name].path.is_empty():
			update_audio(channel_name)
		else:
			update_audio(channel_name, info[channel_name].path, info[channel_name].settings_overrides)



func pause() -> void :
	for child in audio_node.get_children():
		child.stream_paused = true
	for child in one_shot_audio_node.get_children():
		child.stream_paused = true



func resume() -> void :
	for child in audio_node.get_children():
		child.stream_paused = false
	for child in one_shot_audio_node.get_children():
		child.stream_paused = false


func _on_dialogic_timeline_ended() -> void :
	if not dialogic.Styles.get_layout_node():
		clear_game_state()







func _ready() -> void :
	dialogic.timeline_ended.connect(_on_dialogic_timeline_ended)

	audio_node.name = "Audio"
	add_child(audio_node)
	one_shot_audio_node.name = "OneShotAudios"
	add_child(one_shot_audio_node)





func update_audio(channel_name: = "", path: = "", settings_overrides: = {}) -> void :
	path = str(path).strip_edges()
	if path.to_lower() == "stop":
		path = ""




	var prev_audio_node: AudioStreamPlayer = _get_tracked_channel_player(channel_name)
	var replacement_should_stay_paused: = (
		(dialogic != null and dialogic.paused)
		or (prev_audio_node != null and prev_audio_node.stream_paused)
	)
	if replacement_should_stay_paused and not channel_name.is_empty():
		_retire_untracked_channel_players(channel_name, prev_audio_node)

	if prev_audio_node == null and path.is_empty():
		_erase_audio_channel_state(channel_name)
		return



	var audio_settings: Dictionary = DialogicUtil.get_audio_channel_defaults().get(channel_name, {})
	audio_settings.merge(
		{"volume": 0, "audio_bus": "", "fade_length": 0.0, "loop": true, "sync_channel": ""}
	)
	audio_settings.merge(settings_overrides, true)
	if str(audio_settings.get("audio_bus", "")).strip_edges().is_empty():
		audio_settings["audio_bus"] = _get_default_audio_bus(channel_name)




	if prev_audio_node != null:
		current_audio_channels.erase(channel_name)
		prev_audio_node.name += "_Prev"
		if replacement_should_stay_paused or not prev_audio_node.is_playing():
			prev_audio_node.stop()
			prev_audio_node.queue_free()
		elif audio_settings.fade_length > 0.0:
			var fade_out_tween: Tween = prev_audio_node.create_tween()
			fade_out_tween.tween_method(
				interpolate_volume_linearly.bind(prev_audio_node), 
				db_to_linear(prev_audio_node.volume_db), 
				0.0, 
				audio_settings.fade_length)
			fade_out_tween.tween_callback(prev_audio_node.queue_free)

		else:
			prev_audio_node.queue_free()


	if not dialogic.current_state_info.has("audio"):
		dialogic.current_state_info["audio"] = {}

	if not path:
		_erase_audio_channel_state(channel_name)
		return

	dialogic.current_state_info["audio"][channel_name] = {"path": path, "settings_overrides": settings_overrides}
	audio_started.emit(dialogic.current_state_info["audio"][channel_name])

	var new_player: = AudioStreamPlayer.new()
	if channel_name:
		new_player.name = channel_name.validate_node_name()
		new_player.set_meta(AUDIO_CHANNEL_META, channel_name)
		audio_node.add_child(new_player)
	else:
		new_player.name = "OneShotSFX"
		one_shot_audio_node.add_child(new_player)


	var resolved: = path
	var cp: = Engine.get_singleton("ContentPaths") if Engine.has_singleton("ContentPaths") else null
	if cp == null:
		cp = dialogic.get_node_or_null("/root/ContentPaths")
	if cp and cp.has_method("resolve"):
		resolved = cp.resolve(path)
	var file = load(resolved) if resolved.begins_with("res://") else AssetLoader.load_audio(resolved)
	if file == null:
		printerr("[Dialogic] Audio file \"%s\" failed to load." % resolved)
		new_player.queue_free()
		_erase_audio_channel_state(channel_name)
		return

	new_player.stream = file






	if audio_settings.fade_length > 0.0 and not replacement_should_stay_paused:
		new_player.volume_db = linear_to_db(0.0)
		var fade_in_tween: = new_player.create_tween()
		fade_in_tween.tween_method(
			interpolate_volume_linearly.bind(new_player), 
			0.0, 
			db_to_linear(audio_settings.volume), 
			audio_settings.fade_length)

	else:
		new_player.volume_db = audio_settings.volume


	new_player.bus = audio_settings.audio_bus


	if "loop" in new_player.stream:
		new_player.stream.loop = audio_settings.loop
	elif "loop_mode" in new_player.stream:
		if audio_settings.loop:
			new_player.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			new_player.stream.loop_begin = 0
			new_player.stream.loop_end = new_player.stream.mix_rate * new_player.stream.get_length()
		else:
			new_player.stream.loop_mode = AudioStreamWAV.LOOP_DISABLED


	if audio_settings.sync_channel and is_channel_playing(audio_settings.sync_channel):
		var play_position: float = current_audio_channels[audio_settings.sync_channel].get_playback_position()
		new_player.play(play_position)


		if new_player.stream is AudioStreamWAV and new_player.stream.format == AudioStreamWAV.FORMAT_IMA_ADPCM:
			printerr("[Dialogic] WAV files using Ima-ADPCM compression cannot be synced. Reimport the file using a different compression mode.")
			dialogic.print_debug_moment()
	else:
		new_player.play()
	if replacement_should_stay_paused:


		new_player.stream_paused = true

	new_player.finished.connect(_on_audio_finished.bind(new_player, channel_name, path))

	if channel_name:
		current_audio_channels[channel_name] = new_player


func _get_tracked_channel_player(channel_name: String) -> AudioStreamPlayer:
	var tracked_player: Variant = current_audio_channels.get(channel_name)
	if tracked_player is AudioStreamPlayer and is_instance_valid(tracked_player):
		return tracked_player as AudioStreamPlayer
	current_audio_channels.erase(channel_name)
	return null


func _retire_untracked_channel_players(channel_name: String, tracked_player: AudioStreamPlayer) -> void :
	for child in audio_node.get_children():
		if child == tracked_player or not (child is AudioStreamPlayer):
			continue
		if str(child.get_meta(AUDIO_CHANNEL_META, "")) != channel_name:
			continue
		(child as AudioStreamPlayer).stop()
		child.queue_free()


func _erase_audio_channel_state(channel_name: String) -> void :
	current_audio_channels.erase(channel_name)
	if dialogic != null and dialogic.current_state_info.has("audio"):
		dialogic.current_state_info["audio"].erase(channel_name)


func _get_default_audio_bus(channel_name: String) -> String:
	var normalized: = channel_name.to_lower().strip_edges()
	if normalized.is_empty():
		return "SFX"
	for music_marker in ["music", "bgm", "theme", "ambient", "ambience"]:
		if music_marker in normalized:
			return "Music"
	return "SFX"



func is_channel_playing(channel_name: String) -> bool:
	return (current_audio_channels.has(channel_name)
		and is_instance_valid(current_audio_channels[channel_name])
		and current_audio_channels[channel_name].is_playing())



func stop_all_channels(fade: = 0.0) -> void :
	for channel_name in current_audio_channels.keys():
		var node = current_audio_channels.get(channel_name)

		if node and is_instance_valid(node):
			node.stop()
		update_audio(channel_name, "", {"fade_length": fade})



func stop_all_one_shot_sounds() -> void :
	for i in one_shot_audio_node.get_children():
		i.queue_free()




func interpolate_volume_linearly(value: float, node: Object) -> void :
	if node == null or not is_instance_valid(node):
		return

	var player: = node as AudioStreamPlayer
	if player == null:
		return

	player.volume_db = linear_to_db(value)




func is_channel_playing_file(file_path: String, channel_name: String) -> bool:
	return (is_channel_playing(channel_name)
		and current_audio_channels[channel_name].stream.resource_path == file_path)



func is_any_channel_playing() -> bool:
	for channel in current_audio_channels:
		if is_channel_playing(channel):
			return true
	return false


func _on_audio_finished(player: AudioStreamPlayer, channel_name: String, path: String) -> void :
	if current_audio_channels.has(channel_name) and current_audio_channels[channel_name] == player:
		current_audio_channels.erase(channel_name)
	player.queue_free()
	if dialogic.current_state_info.get("audio", {}).get(channel_name, {}).get("path", "") == path:
		dialogic.current_state_info["audio"].erase(channel_name)






func _convert_state_info() -> void :
	var info: Dictionary = dialogic.current_state_info.get("music", {})
	if info.is_empty():
		return

	var new_info: = {}
	if info.has("path"):

		new_info["music"] = {
			"path": info.path, 
			"settings_overrides": {
				"volume": info.volume, 
				"audio_bus": info.audio_bus, 
				"loop": info.loop}
				}

	else:

		for channel_id in info.keys():
			if info[channel_id].is_empty():
				continue

			var channel_name = "music"
			if channel_id > 0:
				channel_name += str(channel_id + 1)
			new_info[channel_name] = {
				"path": info[channel_id].path, 
				"settings_overrides": {
					"volume": info[channel_id].volume, 
					"audio_bus": info[channel_id].audio_bus, 
					"loop": info[channel_id].loop, 
					}
				}

	dialogic.current_state_info["audio"] = new_info
	dialogic.current_state_info.erase("music")

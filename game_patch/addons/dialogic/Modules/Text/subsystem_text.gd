extends DialogicSubsystem














@warning_ignore("unused_signal")
signal about_to_show_text(info: Dictionary)



@warning_ignore("unused_signal")
signal text_started(info: Dictionary)


signal text_finished(info: Dictionary)

signal speaker_updated(character: DialogicCharacter)

signal textbox_visibility_changed(visible: bool)





signal animation_textbox_show

signal animation_textbox_hide

signal animation_textbox_new_text


@warning_ignore("unused_signal")
signal meta_hover_started(meta: Variant)

@warning_ignore("unused_signal")
signal meta_hover_ended(meta: Variant)

@warning_ignore("unused_signal")
signal meta_clicked(meta: Variant)





var character_colors: = {}
var color_regex: = RegEx.new()
var text_already_read: = false

var text_effects: = {}
var parsed_text_effect_info: Array[Dictionary] = []
var text_effects_regex: = RegEx.new()
enum ParserModes{ALL = -1, TEXT_ONLY = 0, CHOICES_ONLY = 1}
enum TextTypes{DIALOG_TEXT, CHOICE_TEXT}
var text_modifiers: = []



var _speed_multiplier: = 1.0

var _pure_letter_speed: = 0.1
var _letter_speed_absolute: = false

var _voice_synced_text: = false

var _autopauses: = {}

var parse_stack: Array[Dictionary] = []





func clear_game_state(_clear_flag: = DialogicGameHandler.ClearFlags.FULL_CLEAR) -> void :
	_textbox_visibility_generation += 1
	dialogic.current_state_info.erase("text_sub_idx")
	update_dialog_text("", true)
	update_name_label(null)
	dialogic.current_state_info["speaker"] = ""
	dialogic.current_state_info["text"] = ""

	set_text_reveal_skippable(ProjectSettings.get_setting("dialogic/text/initial_text_reveal_skippable", true))


	for text_node in get_tree().get_nodes_in_group("dialogic_dialog_text"):
		if text_node.start_hidden:
			text_node.textbox_root.hide()


func load_game_state(_load_flag: = LoadFlags.FULL_LOAD) -> void :
	update_textbox(dialogic.current_state_info.get("text", ""), true)
	update_dialog_text(dialogic.current_state_info.get("text", ""), true)
	var character: DialogicCharacter = get_current_speaker()

	if character:
		update_name_label(character)


func post_install() -> void :
	dialogic.Settings.connect_to_change("text_speed", _update_user_speed)

	collect_text_effects()
	collect_text_modifiers()









func parse_text(text: String, type: int = TextTypes.DIALOG_TEXT) -> String:
	if parse_stack.is_empty():
		load_parse_stack()

	for i in parse_stack:
		if i.type != ParserModes.ALL and type != -1 and i.type != type:
			continue
		text = i.method.call(text)

	return text




func load_parse_stack() -> void :
	parse_stack.clear()

	if dialogic.has_subsystem("VAR"):
		parse_stack.append(
			{
				"method": dialogic.VAR.parse_variables, 
				"type": ParserModes.ALL, 
				"order": 30, 
			})

	parse_stack.append(
		{
			"method": parse_text_effects, 
			"type": ParserModes.TEXT_ONLY, 
			"order": 50, 
		})
	for i in text_modifiers:
		parse_stack.append(i)
	parse_stack.append(
		{
			"method": color_character_names, 
			"type": ParserModes.TEXT_ONLY, 
			"order": 90, 
		})
	parse_stack.append(
		{
			"method": dialogic.Glossary.parse_glossary, 
			"type": ParserModes.TEXT_ONLY, 
			"order": 95, 
		})

	parse_stack.sort_custom( func(a, b): return a["order"] < b["order"])





func update_textbox(text: String, instant: = false) -> void :
	if text.is_empty():
		await hide_textbox(instant)
	else:
		await show_textbox(instant)

		if !dialogic.current_state_info["text"].is_empty():
			animation_textbox_new_text.emit()

			if dialogic.Animations.is_animating():
				await dialogic.Animations.finished





func update_dialog_text(text: String, instant: = false, additional: = false) -> String:
	update_text_speed()

	if !instant: dialogic.current_state = dialogic.States.REVEALING_TEXT

	if additional:
		dialogic.current_state_info["text"] += text
	else:
		dialogic.current_state_info["text"] = text

	for text_node in get_tree().get_nodes_in_group("dialogic_dialog_text"):
		connect_meta_signals(text_node)

		if text_node.enabled and (text_node == text_node.textbox_root or text_node.textbox_root.is_visible_in_tree()):

			if instant:
				text_node.text = text

			else:
				var current_character: = get_current_speaker()

				if current_character:
					var character_prefix: String = current_character.custom_info.get(DialogicCharacterPrefixSuffixSection.PREFIX_CUSTOM_KEY, DialogicCharacterPrefixSuffixSection.DEFAULT_PREFIX)
					var character_suffix: String = current_character.custom_info.get(DialogicCharacterPrefixSuffixSection.SUFFIX_CUSTOM_KEY, DialogicCharacterPrefixSuffixSection.DEFAULT_SUFFIX)
					text = character_prefix + text + character_suffix

				text_node.reveal_text(text, additional)

				if !text_node.finished_revealing_text.is_connected(_on_dialog_text_finished):
					text_node.finished_revealing_text.connect(_on_dialog_text_finished)

			dialogic.current_state_info["text_parsed"] = (text_node as RichTextLabel).get_parsed_text()


	update_text_speed(-1, false, 1)

	dialogic.Inputs.auto_advance.enabled_until_next_event = false
	dialogic.Inputs.auto_advance.override_delay_for_current_event = -1
	dialogic.Inputs.manual_advance.disabled_until_next_event = false

	set_text_reveal_skippable(true, true)

	return text


func _on_dialog_text_finished() -> void :
	text_finished.emit({"text": dialogic.current_state_info["text"], "character": dialogic.current_state_info["speaker"]})




func update_name_label(character: DialogicCharacter):
	var character_id: = character.get_identifier() if character else ""
	var current_character_id: String = dialogic.current_state_info.get("speaker", "")

	if character_id != current_character_id:
		speaker_updated.emit(character)
		dialogic.current_state_info["speaker"] = character_id

	var name_label_text: = get_character_name_parsed(character)

	for name_label in get_tree().get_nodes_in_group("dialogic_name_label"):
		name_label.text = name_label_text
		if character:
			if !"use_character_color" in name_label or name_label.use_character_color:
				name_label.self_modulate = character.color
		else:
			name_label.self_modulate = Color(1, 1, 1, 1)


func update_typing_sound_mood_from_character(character: DialogicCharacter, mood: String) -> void :
	if character.custom_info.get("sound_moods", {}).is_empty():
		update_typing_sound_mood()
	elif mood in character.custom_info.get("sound_moods", {}):
		update_typing_sound_mood(character.custom_info.get("sound_moods", {})[mood])
	else:
		var default_mood: String = character.custom_info.get("sound_mood_default", "")
		update_typing_sound_mood(character.custom_info.get("sound_moods", {}).get(default_mood, {}))



func update_typing_sound_mood(mood: Dictionary = {}) -> void :
	for typing_sound in get_tree().get_nodes_in_group("dialogic_type_sounds"):
		typing_sound.load_overwrite(mood)



var _textbox_visibility_generation := 0

func show_textbox(instant: = false) -> void :
	_textbox_visibility_generation += 1
	var visibility_generation := _textbox_visibility_generation
	var emitted: = instant
	for text_node in get_tree().get_nodes_in_group("dialogic_dialog_text"):
		if not text_node.enabled:
			continue
		if not text_node.textbox_root.visible and not emitted:
			animation_textbox_show.emit()
			text_node.textbox_root.show()
			if dialogic.Animations.is_animating():
				await dialogic.Animations.finished
			if visibility_generation != _textbox_visibility_generation:
				return
			textbox_visibility_changed.emit(true)
			emitted = true
		else:
			text_node.textbox_root.show()



func hide_textbox(instant: = false) -> void :
	_textbox_visibility_generation += 1
	var visibility_generation := _textbox_visibility_generation
	dialogic.current_state_info["text"] = ""
	var emitted: = instant
	for name_label in get_tree().get_nodes_in_group("dialogic_name_label"):
		name_label.text = ""
	if !emitted and !get_tree().get_nodes_in_group("dialogic_dialog_text").is_empty() and get_tree().get_nodes_in_group("dialogic_dialog_text")[0].textbox_root.visible:
		animation_textbox_hide.emit()
		if dialogic.Animations.is_animating():
			await dialogic.Animations.finished
	# A previous ending must never hide the input/textbox opened by a newer scene.
	if visibility_generation != _textbox_visibility_generation:
		return
	for text_node in get_tree().get_nodes_in_group("dialogic_dialog_text"):
		if text_node.textbox_root.visible and !emitted:
			textbox_visibility_changed.emit(false)
			emitted = true
		text_node.textbox_root.hide()


func is_textbox_visible() -> bool:
	return get_tree().get_nodes_in_group("dialogic_dialog_text").any( func(x): return x.textbox_root.visible)


func show_next_indicators(question: = false, autoadvance: = false) -> void :
	for next_indicator in get_tree().get_nodes_in_group("dialogic_next_indicator"):
		if next_indicator.enabled:
			if (question and "show_on_questions" in next_indicator and next_indicator.show_on_questions) or \
			(autoadvance and "show_on_autoadvance" in next_indicator and next_indicator.show_on_autoadvance) or ( !question and !autoadvance):
				next_indicator.show()
		else:
			next_indicator.hide()


func hide_next_indicators(_fake_arg: Variant = null) -> void :
	for next_indicator in get_tree().get_nodes_in_group("dialogic_next_indicator"):
		next_indicator.hide()








func set_text_voice_synced(enabled: bool = true) -> void :
	_voice_synced_text = enabled
	update_text_speed()



func is_text_voice_synced() -> bool:
	return _voice_synced_text















func update_text_speed(letter_speed: float = -1, 
		absolute: = false, 
		speed_multiplier: = _speed_multiplier, 
		user_speed: float = dialogic.Settings.get_setting("text_speed", 1)) -> void :

	if letter_speed == -1:
		letter_speed = ProjectSettings.get_setting("dialogic/text/letter_speed", 0.01)

	_pure_letter_speed = letter_speed
	_letter_speed_absolute = absolute
	_speed_multiplier = speed_multiplier

	for text_node in get_tree().get_nodes_in_group("dialogic_dialog_text"):
		if absolute:
			text_node.set_speed(letter_speed)
		else:
			text_node.set_speed(letter_speed * _speed_multiplier * user_speed)


func set_text_reveal_skippable(skippable: = true, temp: = false) -> void :
	if !dialogic.current_state_info.has("text_reveal_skippable"):
		dialogic.current_state_info["text_reveal_skippable"] = {"enabled": false, "temp_enabled": false}

	if temp:
		dialogic.current_state_info["text_reveal_skippable"]["temp_enabled"] = skippable
	else:
		dialogic.current_state_info["text_reveal_skippable"]["enabled"] = skippable


func is_text_reveal_skippable() -> bool:
	return dialogic.current_state_info["text_reveal_skippable"]["enabled"] and dialogic.current_state_info["text_reveal_skippable"].get("temp_enabled", true)


func skip_text_reveal() -> void :
	for text_node in get_tree().get_nodes_in_group("dialogic_dialog_text"):
		if text_node.is_visible_in_tree():
			text_node.finish_text()
	if dialogic.has_subsystem("Voice"):
		dialogic.Voice.stop_audio()







func collect_text_effects() -> void :
	var text_effect_names: = ""
	text_effects.clear()
	for indexer in DialogicUtil.get_indexers(true):
		for effect in indexer._get_text_effects():
			text_effects[effect.command] = {}
			if effect.has("subsystem") and effect.has("method"):
				text_effects[effect.command]["callable"] = Callable(dialogic.get_subsystem(effect.subsystem), effect.method)
			elif effect.has("node_path") and effect.has("method"):
				text_effects[effect.command]["callable"] = Callable(get_node(effect.node_path), effect.method)
			else:
				continue
			text_effect_names += effect.command + "|"
	text_effects_regex.compile("(?<!\\\\)\\[\\s*(?<command>" + text_effect_names.trim_suffix("|") + ")\\s*(=\\s*(?<value>.+?)\\s*)?\\]")




func parse_text_effects(text: String) -> String:
	parsed_text_effect_info.clear()
	var rtl: RichTextLabel = null
	if get_tree().get_first_node_in_group("dialogic_dialog_text"):
		rtl = get_tree().get_first_node_in_group("dialogic_dialog_text").duplicate()
	else:
		rtl = RichTextLabel.new()
		rtl.bbcode_enabled = true
	var position_correction: = 0
	var bbcode_correction: = 0
	for effect_match in text_effects_regex.search_all(text):
		rtl.text = text.substr(0, effect_match.get_start() - position_correction)
		bbcode_correction = effect_match.get_start() - position_correction - len(rtl.get_parsed_text())

		parsed_text_effect_info.append({"index": effect_match.get_start() - position_correction - bbcode_correction, "execution_info": text_effects[effect_match.get_string("command")], "value": effect_match.get_string("value").strip_edges()})

		text = text.substr(0, effect_match.get_start() - position_correction) + text.substr(effect_match.get_start() - position_correction + len(effect_match.get_string()))

		position_correction += len(effect_match.get_string())
	text = text.replace("\\[", "[")
	rtl.queue_free()
	return text


func execute_effects(current_index: int, text_node: Control, skipping: = false) -> void :

	while true:
		if parsed_text_effect_info.is_empty():
			return
		if current_index != -1 and current_index < parsed_text_effect_info[0]["index"]:
			return
		var effect: Dictionary = parsed_text_effect_info.pop_front()
		var callable: Callable = effect["execution_info"]["callable"]
		if is_instance_valid(text_node):
			await callable.call(text_node, skipping, effect["value"])


func collect_text_modifiers() -> void :
	text_modifiers.clear()
	for indexer in DialogicUtil.get_indexers(true):
		for modifier in indexer._get_text_modifiers():
			if modifier.has("subsystem") and modifier.has("method"):
				text_modifiers.append({"method": Callable(dialogic.get_subsystem(modifier.subsystem), modifier.method)})
			elif modifier.has("node_path") and modifier.has("method"):
				text_modifiers.append({"method": Callable(get_node(modifier.node_path), modifier.method)})
			text_modifiers[-1]["type"] = modifier.get("mode", ParserModes.TEXT_ONLY)
			text_modifiers[-1]["order"] = modifier.get("order", 40)








func _ready() -> void :
	dialogic.event_handled.connect(hide_next_indicators)

	_autopauses = {}
	var autopause_data: Dictionary = ProjectSettings.get_setting("dialogic/text/autopauses", {})
	for i in autopause_data.keys():
		_autopauses[RegEx.create_from_string("(?<!(\\[|\\{))[" + i + "](?!([^{}\\[\\]]*[\\]\\}]|$))")] = autopause_data[i]






func get_character_name_parsed(character: DialogicCharacter) -> String:
	if character:
		var translated_display_name: = character.get_display_name_translated()
		if dialogic.has_subsystem("VAR"):
			return dialogic.VAR.parse_variables(translated_display_name)
		else:
			return translated_display_name
	return ""




func get_current_speaker() -> DialogicCharacter:
	var speaker_id: String = dialogic.current_state_info.get("speaker", "")

	if speaker_id.is_empty():
		return null

	return DialogicResourceUtil.get_character_resource(speaker_id)


func _update_user_speed(_user_speed: float) -> void :
	update_text_speed(_pure_letter_speed, _letter_speed_absolute)


func connect_meta_signals(text_node: Node) -> void :
	if not text_node.meta_clicked.is_connected(emit_meta_signal):
		text_node.meta_clicked.connect(emit_meta_signal.bind("meta_clicked"))

	if not text_node.meta_hover_started.is_connected(emit_meta_signal):
		text_node.meta_hover_started.connect(emit_meta_signal.bind("meta_hover_started"))

	if not text_node.meta_hover_ended.is_connected(emit_meta_signal):
		text_node.meta_hover_ended.connect(emit_meta_signal.bind("meta_hover_ended"))


func emit_meta_signal(meta: Variant, sig: String) -> void :
	emit_signal(sig, meta)






func color_character_names(text: String) -> String:
	if not ProjectSettings.get_setting("dialogic/text/autocolor_names", false):
		return text

	collect_character_names()

	var counter: = 0
	for result in color_regex.search_all(text):
		text = text.insert(result.get_start("name") + ((9 + 8 + 8) * counter), "[color=#" + character_colors[result.get_string("name")].to_html() + "]")
		text = text.insert(result.get_end("name") + 9 + 8 + ((9 + 8 + 8) * counter), "[/color]")
		counter += 1

	return text


func collect_character_names() -> void :

	if not ProjectSettings.get_setting("dialogic/text/autocolor_names", false):
		return

	character_colors = {}

	for dch_identifier in DialogicResourceUtil.get_character_directory():
		var character: = (DialogicResourceUtil.get_character_resource(dch_identifier) as DialogicCharacter)

		if character.display_name:
			if "{" in character.display_name and "}" in character.display_name:
				character_colors[dialogic.VAR.parse_variables(character.display_name)] = character.color
			else:
				character_colors[character.display_name] = character.color

		for nickname in character.get_nicknames_translated():
			nickname = nickname.strip_edges()
			if nickname:
				if "{" in nickname and "}" in nickname:
					character_colors[dialogic.VAR.parse_variables(nickname)] = character.color
				else:
					character_colors[nickname] = character.color

	if dialogic.has_subsystem("Glossary"):
		dialogic.Glossary.color_overrides.merge(character_colors, true)

	var sorted_keys: = character_colors.keys()
	sorted_keys.sort_custom(sort_by_length)

	var character_names: = ""
	for key in sorted_keys:
		character_names += "\\Q" + key + "\\E|"

	character_names = character_names.trim_suffix("|")
	color_regex.compile("(?<=\\W|^)(?<name>" + character_names + ")(?=\\W|$)")


func sort_by_length(a: String, b: String) -> bool:
	if a.length() > b.length():
		return true
	return false






func effect_pause(_text_node: Control, skipped: bool, argument: String) -> void :
	if skipped:
		return


	if dialogic.Inputs.auto_skip.enabled:
		return

	var text_speed: float = dialogic.Settings.get_setting("text_speed", 1)

	if argument:
		if argument.ends_with("!"):
			await get_tree().create_timer(float(argument.trim_suffix("!"))).timeout

		elif _speed_multiplier != 0 and text_speed != 0:
			await get_tree().create_timer(float(argument) * _speed_multiplier * text_speed).timeout

	elif _speed_multiplier != 0 and text_speed != 0:
		await get_tree().create_timer(0.5 * _speed_multiplier * text_speed).timeout


func effect_speed(_text_node: Control, skipped: bool, argument: String) -> void :
	if skipped:
		return
	if argument:
		update_text_speed(-1, false, float(argument))
	else:
		update_text_speed(-1, false, 1)


func effect_lspeed(_text_node: Control, skipped: bool, argument: String) -> void :
	if skipped:
		return
	if argument:
		if argument.ends_with("!"):
			update_text_speed(float(argument.trim_suffix("!")), true)
		else:
			update_text_speed(float(argument), false)
	else:
		update_text_speed()


func effect_signal(_text_node: Control, _skipped: bool, argument: String) -> void :
	dialogic.text_signal.emit(argument)


func effect_mood(_text_node: Control, _skipped: bool, argument: String) -> void :
	if argument.is_empty(): return
	if get_current_speaker():
		update_typing_sound_mood(
			get_current_speaker().custom_info.get("sound_moods", {}).get(argument, {}))


var modifier_select_regex: = RegEx.create_from_string("(?<!\\\\)\\<[^\\>]+(\\/[^\\>]*)\\>")
var modifier_select_split_regex: = RegEx.create_from_string("(\\[[^\\]]*\\]|[^\\/]|\\/\\/)+")
func modifier_random_selection(text: String) -> String:
	for replace_mod_match: RegExMatch in modifier_select_regex.search_all(text):
		var string: String = replace_mod_match.get_string().trim_prefix("<").trim_suffix(">")
		var options: = []
		for split: RegExMatch in modifier_select_split_regex.search_all(string):
			options.append(split.get_string())
		var item: String = options.pick_random()
		text = text.replace(replace_mod_match.get_string(), item.strip_edges())
	return text


func modifier_break(text: String) -> String:
	return text.replace("[br]", "\n")


func modifier_autopauses(text: String) -> String:
	var absolute: bool = ProjectSettings.get_setting("dialogic/text/absolute_autopauses", false)
	for i in _autopauses.keys():
		var offset: = 0
		for result in i.search_all(text):
			if absolute:
				text = text.insert(result.get_end() + offset, "[pause=" + str(_autopauses[i]) + "!]")
				offset += len("[pause=" + str(_autopauses[i]) + "!]")
			else:
				text = text.insert(result.get_end() + offset, "[pause=" + str(_autopauses[i]) + "]")
				offset += len("[pause=" + str(_autopauses[i]) + "]")
	return text

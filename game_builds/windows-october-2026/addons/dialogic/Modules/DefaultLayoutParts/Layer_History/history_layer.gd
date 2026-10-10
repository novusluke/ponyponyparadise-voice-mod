@tool
extends DialogicLayoutLayer




@export_group("Look")
@export_subgroup("Font")
@export var font_use_global_size: bool = true
@export var font_custom_size: int = 15
@export var font_use_global_fonts: bool = true
@export_file("*.ttf", "*.tres") var font_custom_normal: String = ""
@export_file("*.ttf", "*.tres") var font_custom_bold: String = ""
@export_file("*.ttf", "*.tres") var font_custom_italics: String = ""

@export_subgroup("Buttons")
@export var show_open_button: bool = true
@export var show_close_button: bool = true

@export_group("Settings")
@export_subgroup("Events")
@export var show_all_choices: bool = true
@export var show_join_and_leave: bool = true

@export_subgroup("Behaviour")
@export var scroll_to_bottom: bool = true
@export var show_name_colors: bool = true
@export var name_delimeter: String = ": "

var scroll_to_bottom_flag: bool = false

@export_group("Private")
@export var HistoryItem: PackedScene = null

var history_item_theme: Theme = null
const CALENDAR_POPUP_SCRIPT: = preload("res://scripts/ui/calendar_popup.gd")
const HISTORY_RENDER_BATCH_SIZE: = 25
@onready var menu_button: Button = $MenuButton
@onready var menu_panel: PanelContainer = $MenuPanel
@onready var menu_save_button: Button = $MenuPanel / MenuMargin / MenuVBox / MenuSaveButton
@onready var menu_load_button: Button = $MenuPanel / MenuMargin / MenuVBox / MenuLoadButton
@onready var menu_context_button: Button = $MenuPanel / MenuMargin / MenuVBox / MenuContextButton
@onready var menu_calendar_button: Button = $MenuPanel / MenuMargin / MenuVBox / MenuCalendarButton
@onready var menu_free_travel_button: Button = $MenuPanel / MenuMargin / MenuVBox / MenuFreeTravelButton
@onready var menu_journal_button: Button = $MenuPanel / MenuMargin / MenuVBox / MenuJournalButton
@onready var menu_character_browser_button: Button = $MenuPanel / MenuMargin / MenuVBox / MenuCharacterBrowserButton
@onready var menu_scenario_customs_button: Button = $MenuPanel / MenuMargin / MenuVBox / MenuScenarioCustomsButton
@onready var menu_music_mix_button: Button = $MenuPanel / MenuMargin / MenuVBox / MenuMusicMixButton
@onready var menu_prompt_editor_button: Button = $MenuPanel / MenuMargin / MenuVBox / MenuPromptEditorButton
@onready var menu_lorebook_button: Button = $MenuPanel / MenuMargin / MenuVBox / MenuLorebookButton
@onready var menu_persona_button: Button = $MenuPanel / MenuMargin / MenuVBox / MenuPersonaButton
@onready var menu_api_button: Button = $MenuPanel / MenuMargin / MenuVBox / MenuAPIButton
@onready var menu_ui_settings_button: Button = $MenuPanel / MenuMargin / MenuVBox / MenuUISettingsButton
@onready var menu_main_menu_button: Button = $MenuPanel / MenuMargin / MenuVBox / MenuMainMenuButton
@onready var menu_close_button: Button = $MenuPanel / MenuMargin / MenuVBox / MenuCloseButton

var _menu_paused: = false
var _menu_toggled_from_button_down: = false
var _menu_button_down_toggle_token: = 0
var _calendar_popup_layer: CanvasLayer = null
var _calendar_popup: Control = null
var _history_render_generation: = 0

func get_show_history_button() -> Button:
	return $ShowHistory


func get_hide_history_button() -> Button:
	return $HideHistory


func get_history_box() -> ScrollContainer:
	return %HistoryBox


func get_history_log() -> VBoxContainer:
	return %HistoryLog


func _ready() -> void :
	if Engine.is_editor_hint():
		return
	UISettingsManager.register_dialogue_control(get_show_history_button(), "history")
	UISettingsManager.register_dialogue_control(menu_button, "menu")
	DialogicUtil.autoload().History.open_requested.connect(_on_show_history_pressed)
	DialogicUtil.autoload().History.close_requested.connect(_on_hide_history_pressed)
	menu_button.pressed.connect(_on_menu_button_pressed)
	menu_button.button_down.connect(_on_menu_button_down)
	menu_save_button.pressed.connect(_on_menu_save_pressed)
	menu_load_button.pressed.connect(_on_menu_load_pressed)
	menu_context_button.pressed.connect(_on_menu_context_pressed)
	menu_calendar_button.pressed.connect(_on_menu_calendar_pressed)
	menu_free_travel_button.pressed.connect(_on_menu_free_travel_pressed)
	menu_journal_button.pressed.connect(_on_menu_journal_pressed)
	menu_character_browser_button.pressed.connect(_on_menu_character_browser_pressed)
	menu_scenario_customs_button.pressed.connect(_on_menu_scenario_customs_pressed)
	menu_music_mix_button.pressed.connect(_on_menu_music_mix_pressed)
	menu_prompt_editor_button.pressed.connect(_on_menu_prompt_editor_pressed)
	menu_lorebook_button.pressed.connect(_on_menu_lorebook_pressed)
	menu_persona_button.pressed.connect(_on_menu_persona_pressed)
	menu_api_button.pressed.connect(_on_menu_api_pressed)
	menu_ui_settings_button.pressed.connect(_on_menu_ui_settings_pressed)
	menu_main_menu_button.pressed.connect(_on_menu_main_menu_pressed)
	menu_close_button.pressed.connect(_on_menu_close_pressed)



	if OS.has_feature("mobile"):
		_enlarge_top_right_buttons_for_mobile()


func _enlarge_top_right_buttons_for_mobile() -> void :
	for btn: Button in [menu_button, get_show_history_button()]:
		if btn == null:
			continue
		btn.custom_minimum_size = Vector2(96, 56)
		btn.add_theme_font_size_override("font_size", 28)
		btn.offset_left = -105.0
		btn.offset_right = -9.0
		btn.offset_top = 7.0
		btn.offset_bottom = 63.0


func _apply_export_overrides() -> void :
	var history_subsystem: Node = DialogicUtil.autoload().get(&"History")
	if history_subsystem != null:
		UISettingsManager.set_dialogue_control_available(get_show_history_button(), show_open_button and history_subsystem.get(&"simple_history_enabled"))
	else:
		set(&"visible", false)

	history_item_theme = Theme.new()

	if font_use_global_size:
		history_item_theme.default_font_size = get_global_setting(&"font_size", font_custom_size)
	else:
		history_item_theme.default_font_size = font_custom_size

	if font_use_global_fonts and ResourceLoader.exists(get_global_setting(&"font", "") as String):
		history_item_theme.default_font = load(get_global_setting(&"font", "") as String) as Font
	elif ResourceLoader.exists(font_custom_normal):
		history_item_theme.default_font = load(font_custom_normal)

	if ResourceLoader.exists(font_custom_bold):
		history_item_theme.set_font(&"RichtTextLabel", &"bold_font", load(font_custom_bold) as Font)
	if ResourceLoader.exists(font_custom_italics):
		history_item_theme.set_font(&"RichtTextLabel", &"italics_font", load(font_custom_italics) as Font)


func _process(_delta: float) -> void :
	if Engine.is_editor_hint():
		return
	if scroll_to_bottom_flag and get_history_box().visible and get_history_log().get_child_count():
		await get_tree().process_frame
		get_history_box().ensure_control_visible(get_history_log().get_children()[-1] as Control)
		scroll_to_bottom_flag = false


func _on_show_history_pressed() -> void :
	DialogicUtil.autoload().paused = true
	Dialogic.paused = true
	_close_menu(true)
	show_history()


func show_history() -> void :
	_history_render_generation += 1
	var render_generation: = _history_render_generation
	for child: Node in get_history_log().get_children():
		child.queue_free()

	UISettingsManager.set_dialogue_control_available(get_show_history_button(), false)
	get_hide_history_button().visible = show_close_button
	get_history_box().show()
	var history_subsystem: Node = DialogicUtil.autoload().get(&"History")
	if history_subsystem == null or not history_subsystem.has_method(&"get_simple_history"):
		return

	var raw_history_entries: Variant = history_subsystem.call(&"get_simple_history")
	if not raw_history_entries is Array:
		return

	var rendered_count: = 0
	for info: Dictionary in raw_history_entries:
		if render_generation != _history_render_generation or not get_history_box().visible:
			return
		var history_item: Node = HistoryItem.instantiate()
		history_item.set(&"theme", history_item_theme)
		match info.event_type:
			"Text":
				if info.has("character") and info["character"]:
					if show_name_colors:
						history_item.call(&"load_info", info["text"], info["character"] + name_delimeter, info["character_color"])
					else:
						history_item.call(&"load_info", info["text"], info["character"] + name_delimeter)
				else:
					history_item.call(&"load_info", info["text"])
			"Character":
				if !show_join_and_leave:
					history_item.queue_free()
					continue
				history_item.call(&"load_info", "[i]" + info["text"])
			"Choice":
				var choices_text: String = ""
				if show_all_choices:
					for i: String in info["all_choices"]:
						if i.ends_with("#disabled"):
							choices_text += "-  [i](" + i.trim_suffix("#disabled") + ")[/i]\n"
						elif i == info["text"]:
							choices_text += "-> [b]" + i + "[/b]\n"
						else:
							choices_text += "-> " + i + "\n"
				else:
					choices_text += "- [b]" + info["text"] + "[/b]\n"
				history_item.call(&"load_info", choices_text)

		get_history_log().add_child(history_item)
		rendered_count += 1
		if rendered_count % HISTORY_RENDER_BATCH_SIZE == 0:
			await get_tree().process_frame

	if scroll_to_bottom:
		scroll_to_bottom_flag = true


func _on_hide_history_pressed() -> void :
	_history_render_generation += 1
	if not _should_keep_dialogic_paused():
		DialogicUtil.autoload().paused = false
		Dialogic.paused = false
	get_history_box().hide()
	get_hide_history_button().hide()
	var history_subsystem: Node = DialogicUtil.autoload().get(&"History")
	UISettingsManager.set_dialogue_control_available(get_show_history_button(), show_open_button and history_subsystem.get(&"simple_history_enabled"))


func _on_menu_button_pressed() -> void :
	if _menu_toggled_from_button_down:
		return
	_toggle_menu_from_button()


func _toggle_menu_from_button() -> void :
	if menu_panel.visible:
		_close_menu()
	else:
		_open_menu()
		_consume_dialogic_input()


func _on_menu_save_pressed() -> void :
	_close_menu()
	var main_scene: = _get_main_scene()
	if main_scene and main_scene.has_method("open_save_menu"):
		main_scene.open_save_menu()
		return

	var save_menu: = _get_group_node("save_load_menu")
	if save_menu and save_menu.has_method("open_save_menu"):
		Dialogic.Save.take_thumbnail()
		save_menu.open_save_menu()


func _on_menu_load_pressed() -> void :
	_close_menu()
	var main_scene: = _get_main_scene()
	if main_scene and main_scene.has_method("open_load_menu"):
		main_scene.open_load_menu()
		return

	var save_menu: = _get_group_node("save_load_menu")
	if save_menu and save_menu.has_method("open_load_menu"):
		save_menu.open_load_menu()




func _on_menu_context_pressed() -> void :
	_close_menu()
	get_tree().call_group("story_panel_host", "open_story_panel")


func _has_story_panel_host() -> bool:
	return not get_tree().get_nodes_in_group("story_panel_host").is_empty()


func _on_menu_calendar_pressed() -> void :
	_close_menu(true)
	_show_calendar_popup()


func _get_free_travel_button_text() -> String:
	var enabled: bool = UISettingsManager != null and UISettingsManager.get_free_travel_enabled()
	return "Free Travel: On" if enabled else "Free Travel: Off"


func _on_menu_free_travel_pressed() -> void :
	if UISettingsManager == null:
		return
	UISettingsManager.set_free_travel_enabled( not UISettingsManager.get_free_travel_enabled())
	UISettingsManager.save_config()
	menu_free_travel_button.text = _get_free_travel_button_text()


func _on_menu_journal_pressed() -> void :
	_close_menu()
	var main_scene: = _get_main_scene()
	if main_scene and main_scene.has_method("open_friendship_journal"):
		main_scene.open_friendship_journal()


func _on_menu_scenario_customs_pressed() -> void :
	_close_menu()
	var main_scene: = _get_main_scene()
	if main_scene and main_scene.has_method("open_scenario_customs_menu"):
		main_scene.open_scenario_customs_menu()


func _on_menu_character_browser_pressed() -> void :
	_close_menu()
	var main_scene: = _get_main_scene()
	if main_scene and main_scene.has_method("open_character_browser_menu"):
		main_scene.open_character_browser_menu()


func _on_menu_music_mix_pressed() -> void :
	_close_menu()
	var main_scene: = _get_main_scene()
	if main_scene and main_scene.has_method("open_music_mix_menu"):
		main_scene.open_music_mix_menu()


func _on_menu_prompt_editor_pressed() -> void :
	_close_menu()
	var main_scene: = _get_main_scene()
	if main_scene and main_scene.has_method("open_prompt_editor_menu"):
		main_scene.open_prompt_editor_menu()


func _on_menu_lorebook_pressed() -> void :
	_close_menu()
	var main_scene: = _get_main_scene()
	if main_scene and main_scene.has_method("open_lorebook_editor_menu"):
		main_scene.open_lorebook_editor_menu()


func _on_menu_persona_pressed() -> void :
	_close_menu()
	var main_scene: = _get_main_scene()
	if main_scene and main_scene.has_method("open_persona_menu"):
		main_scene.open_persona_menu()


func _on_menu_api_pressed() -> void :
	_close_menu()
	var main_scene: = _get_main_scene()
	if main_scene and main_scene.has_method("open_api_settings_menu"):
		main_scene.open_api_settings_menu()
		return

	var api_menu: = _get_group_node("api_config_menu")
	if api_menu and api_menu.has_method("open"):
		api_menu.open()


func _on_menu_ui_settings_pressed() -> void :
	_close_menu()
	var main_scene: = _get_main_scene()
	if main_scene and main_scene.has_method("open_ui_settings_menu"):
		main_scene.open_ui_settings_menu()


func _on_menu_main_menu_pressed() -> void :
	_close_menu()
	var main_scene: = _get_main_scene()
	if main_scene and main_scene.has_method("return_to_main_menu"):
		main_scene.return_to_main_menu()
		return

	if not Engine.is_editor_hint():
		preload("res://scripts/ui/return_to_menu_confirmation.gd").request(self, func() -> void :
			Dialogic.end_timeline(true)
			Dialogic.paused = false
			if DialogicUtil.autoload(): DialogicUtil.autoload().paused = false
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		)


func _on_menu_close_pressed() -> void :
	_close_menu()


func _open_menu() -> void :
	if get_history_box().visible:
		_on_hide_history_pressed()
	menu_context_button.visible = _has_story_panel_host()
	menu_free_travel_button.text = _get_free_travel_button_text()

	menu_free_travel_button.visible = GameState != null and GameState.current_mode == GameState.Mode.SANDBOX
	menu_panel.show()
	_set_menu_paused(true)

	_consume_dialogic_input()


func _close_menu(keep_paused: bool = false) -> void :
	menu_panel.hide()
	if keep_paused:
		_menu_paused = false
		return
	_set_menu_paused(false)


func _on_menu_button_down() -> void :


	_consume_dialogic_input()
	_menu_toggled_from_button_down = true
	_menu_button_down_toggle_token += 1
	var token: = _menu_button_down_toggle_token
	_toggle_menu_from_button()
	_clear_menu_button_down_toggle_after_release(token)


func _clear_menu_button_down_toggle_after_release(token: int) -> void :
	while Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		await get_tree().process_frame
	await get_tree().process_frame
	if token == _menu_button_down_toggle_token:
		_menu_toggled_from_button_down = false


func _consume_dialogic_input() -> void :
	if DialogicUtil.autoload():
		var inputs: Node = DialogicUtil.autoload().get("Inputs") as Node
		if inputs:
			inputs.action_was_consumed = true
			if inputs.has_method("block_input"):
				inputs.block_input(0.2)


func _unhandled_input(event: InputEvent) -> void :
	if event is InputEventMouseButton and event.pressed:
		var mouse_pos: = get_viewport().get_mouse_position()
		if menu_panel.visible:
			var menu_rect: = menu_panel.get_global_rect()
			var button_rect: = menu_button.get_global_rect()
			if not menu_rect.has_point(mouse_pos) and not button_rect.has_point(mouse_pos):
				_close_menu()
				get_viewport().set_input_as_handled()
				return


func _ensure_calendar_popup() -> void :
	if _calendar_popup != null and is_instance_valid(_calendar_popup):
		return
	var host: Node = _get_main_scene()
	if host == null:
		host = get_tree().root
	if _calendar_popup_layer == null or not is_instance_valid(_calendar_popup_layer):
		_calendar_popup_layer = CanvasLayer.new()
		_calendar_popup_layer.name = "DialogicCalendarLayer"
		_calendar_popup_layer.layer = 100
		host.add_child(_calendar_popup_layer)
	_calendar_popup = CALENDAR_POPUP_SCRIPT.new()
	_calendar_popup.name = "DialogicCalendarPopup"
	_calendar_popup_layer.add_child(_calendar_popup)
	if _calendar_popup.has_signal("closed"):
		_calendar_popup.closed.connect(_on_calendar_popup_closed)


func _show_calendar_popup() -> void :
	_ensure_calendar_popup()
	if _calendar_popup == null:
		return
	_set_menu_paused(true)
	_consume_dialogic_input()
	if _calendar_popup.has_method("open_view"):
		_calendar_popup.open_view(false)


func _on_calendar_popup_closed() -> void :
	_set_menu_paused(false)


func _set_menu_paused(should_pause: bool) -> void :
	if Engine.is_editor_hint():
		return
	if should_pause:
		DialogicUtil.autoload().paused = true
		Dialogic.paused = true
		_menu_paused = true
		return

	if _menu_paused and not _should_keep_dialogic_paused():
		DialogicUtil.autoload().paused = false
		Dialogic.paused = false
	_menu_paused = false


func _should_keep_dialogic_paused() -> bool:
	if get_history_box().visible:
		return true
	if _calendar_popup != null and is_instance_valid(_calendar_popup) and _calendar_popup.visible:
		return true
	return _is_blocking_overlay_visible()


func _is_blocking_overlay_visible() -> bool:
	var blockers = get_tree().get_nodes_in_group("ui_blocking_overlay")
	for node in blockers:
		if _node_is_visible(node):
			return true
	return false


func _node_is_visible(node: Node) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	if node.has_method("is_visible_in_tree"):
		return node.is_visible_in_tree()
	if node.has_method("is_visible"):
		return node.is_visible()
	if node.has_method("get"):
		return bool(node.get("visible"))
	return false


func _get_group_node(group_name: String) -> Node:
	var nodes = get_tree().get_nodes_in_group(group_name)
	if nodes.is_empty():
		return null
	return nodes[0]


func _get_main_scene() -> Node:
	var scene: = get_tree().current_scene
	if scene == null:
		return null
	return scene

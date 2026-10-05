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
const ContextEntryScene: = preload("res://scenes/history_entry.tscn")
const CALENDAR_POPUP_SCRIPT: = preload("res://scripts/ui/calendar_popup.gd")
const CONTEXT_PANEL_TARGET_SIZE: = Vector2(1160, 800)
const CONTEXT_PANEL_MIN_SIZE: = Vector2(760, 460)
const CONTEXT_PANEL_VIEWPORT_MARGIN: = Vector2(24, 24)
const EDIT_DIALOG_TARGET_SIZE: = Vector2(600, 400)
const EDIT_DIALOG_MIN_SIZE: = Vector2(420, 280)
const CONTEXT_DEFAULT_PAGE_SIZE: = 100
const CONTEXT_PAGE_SIZE_OPTIONS: = [50, 100, 200]
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
@onready var context_panel: PanelContainer = $ContextPanel
@onready var context_margin: MarginContainer = $ContextPanel / MainVBox / ContextMargin
@onready var context_token_label: Label = $ContextPanel / MainVBox / ContextMargin / ContextVBox / ContextTitle
@onready var context_tabs: TabContainer = $ContextPanel / MainVBox / ContextMargin / ContextVBox / ContextTabs
@onready var context_text: RichTextLabel = $ContextPanel / MainVBox / ContextMargin / ContextVBox / ContextTabs / Text / TextScroll / ContextText
@onready var context_visual_list: VBoxContainer = $ContextPanel / MainVBox / ContextMargin / ContextVBox / ContextTabs / Visual / VisualVBox / VisualScroll / VisualList
@onready var context_close_button: Button = $ContextPanel / MainVBox / ContextMargin / ContextVBox / ContextCloseButton
@onready var context_close_x: Button = $ContextPanel / MainVBox / Header / HeaderHBox / CloseX


@onready var edit_btn: Button = $ContextPanel / MainVBox / ContextMargin / ContextVBox / ContextTabs / Visual / VisualVBox / Toolbar / EditBtn
@onready var delete_btn: Button = $ContextPanel / MainVBox / ContextMargin / ContextVBox / ContextTabs / Visual / VisualVBox / Toolbar / DeleteBtn
@onready var move_up_btn: Button = $ContextPanel / MainVBox / ContextMargin / ContextVBox / ContextTabs / Visual / VisualVBox / Toolbar / MoveUpBtn
@onready var move_down_btn: Button = $ContextPanel / MainVBox / ContextMargin / ContextVBox / ContextTabs / Visual / VisualVBox / Toolbar / MoveDownBtn
@onready var add_btn: Button = $ContextPanel / MainVBox / ContextMargin / ContextVBox / ContextTabs / Visual / VisualVBox / Toolbar / AddBtn


@onready var edit_dialog: PanelContainer = $ContextPanel / EditDialog
@onready var edit_title: Label = $ContextPanel / EditDialog / EditMargin / EditVBox / EditTitle
@onready var character_dropdown: OptionButton = $ContextPanel / EditDialog / EditMargin / EditVBox / CharacterRow / CharacterDropdown
@onready var text_edit: TextEdit = $ContextPanel / EditDialog / EditMargin / EditVBox / TextEdit
@onready var save_edit_btn: Button = $ContextPanel / EditDialog / EditMargin / EditVBox / EditButtons / SaveEditBtn
@onready var cancel_edit_btn: Button = $ContextPanel / EditDialog / EditMargin / EditVBox / EditButtons / CancelEditBtn


var _selected_entry_index: int = -1
var _editing_index: int = -1
var _context_entries: Array = []
var _context_total_entries: = 0
var _context_ai_session_split_index: = -1
var _context_visual_item_map: Dictionary = {}
var _context_visual_dirty: = true
var _context_character_color_cache: Dictionary = {}
var _context_page_index: = -1
var _context_page_size: = CONTEXT_DEFAULT_PAGE_SIZE
var _context_pagination_bar: HBoxContainer = null
var _context_page_buttons: Array[Button] = []
var _context_page_size_buttons: Dictionary = {}
var _context_range_label: Label = null
var _context_first_page_btn: Button = null
var _context_prev_page_btn: Button = null
var _context_next_page_btn: Button = null
var _context_last_page_btn: Button = null

var _menu_paused: = false
var _menu_toggled_from_button_down: = false
var _menu_button_down_toggle_token: = 0
var _context_forced_visible_ancestors: Array[Node] = []
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
	context_close_button.pressed.connect(_on_context_close_pressed)
	context_close_x.pressed.connect(_on_context_close_pressed)
	context_tabs.tab_changed.connect(_on_context_tab_changed)
	context_text.bbcode_enabled = true
	context_token_label.add_theme_font_size_override("font_size", 13)
	context_token_label.add_theme_color_override("font_color", Color(0.76, 0.72, 0.86, 1.0))
	_create_context_pagination_bar()


	edit_btn.pressed.connect(_on_edit_pressed)
	delete_btn.pressed.connect(_on_delete_pressed)
	move_up_btn.pressed.connect(_on_move_up_pressed)
	move_down_btn.pressed.connect(_on_move_down_pressed)
	add_btn.pressed.connect(_on_add_pressed)


	save_edit_btn.pressed.connect(_on_save_edit_pressed)
	cancel_edit_btn.pressed.connect(_on_cancel_edit_pressed)


	_populate_character_dropdown()
	get_viewport().size_changed.connect(_layout_context_panels_for_viewport)
	_layout_context_panels_for_viewport()



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


func _layout_context_panels_for_viewport() -> void :
	if context_panel == null:
		return

	var viewport_size: = get_viewport().get_visible_rect().size
	var panel_width: = minf(CONTEXT_PANEL_TARGET_SIZE.x, maxf(CONTEXT_PANEL_MIN_SIZE.x, viewport_size.x - CONTEXT_PANEL_VIEWPORT_MARGIN.x * 2.0))
	var panel_height: = minf(CONTEXT_PANEL_TARGET_SIZE.y, maxf(CONTEXT_PANEL_MIN_SIZE.y, viewport_size.y - CONTEXT_PANEL_VIEWPORT_MARGIN.y * 2.0))
	var compact: = panel_width < 980.0 or panel_height < 720.0

	context_panel.offset_left = - panel_width * 0.5
	context_panel.offset_top = - panel_height * 0.5
	context_panel.offset_right = panel_width * 0.5
	context_panel.offset_bottom = panel_height * 0.5

	var horizontal_margin: = 20 if not compact else 14
	var vertical_margin: = 20 if not compact else 14
	context_margin.add_theme_constant_override("margin_left", horizontal_margin)
	context_margin.add_theme_constant_override("margin_right", horizontal_margin)
	context_margin.add_theme_constant_override("margin_top", vertical_margin)
	context_margin.add_theme_constant_override("margin_bottom", vertical_margin)
	context_tabs.add_theme_font_size_override("font_size", 14 if not compact else 12)
	context_text.add_theme_font_size_override("normal_font_size", 14 if not compact else 13)
	context_close_x.custom_minimum_size = Vector2(36, 36) if not compact else Vector2(32, 32)
	context_close_x.add_theme_font_size_override("font_size", 18 if not compact else 16)

	var edit_width: = minf(EDIT_DIALOG_TARGET_SIZE.x, maxf(EDIT_DIALOG_MIN_SIZE.x, panel_width - 80.0))
	var edit_height: = minf(EDIT_DIALOG_TARGET_SIZE.y, maxf(EDIT_DIALOG_MIN_SIZE.y, panel_height - 120.0))
	edit_dialog.offset_left = - edit_width * 0.5
	edit_dialog.offset_top = - edit_height * 0.5
	edit_dialog.offset_right = edit_width * 0.5
	edit_dialog.offset_bottom = edit_height * 0.5
	text_edit.custom_minimum_size = Vector2(0, clampf(edit_height * 0.4, 110.0, 160.0))



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
	_open_context_panel()


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


func _on_context_close_pressed() -> void :
	_close_context_panel()


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
	if context_panel.visible:
		_close_context_panel()
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



func open_context() -> void :
	process_mode = Node.PROCESS_MODE_ALWAYS
	_force_show_ancestors()
	_open_context_panel()


func _open_context_panel() -> void :
	if get_history_box().visible:
		_on_hide_history_pressed()
	context_tabs.current_tab = 0
	_context_page_index = -1
	_refresh_context_text()
	context_panel.show()
	_set_menu_paused(true)
	_consume_dialogic_input()


func _close_context_panel() -> void :
	context_panel.hide()
	_clear_context_visual_list()
	context_text.text = ""
	_restore_ancestors()
	process_mode = Node.PROCESS_MODE_INHERIT
	_set_menu_paused(false)


func _force_show_ancestors() -> void :
	_context_forced_visible_ancestors.clear()
	var node: Node = context_panel.get_parent()
	while node:
		if node is CanvasLayer and not node.visible:
			node.visible = true
			_context_forced_visible_ancestors.append(node)
		elif node is CanvasItem and not node.visible:
			node.show()
			_context_forced_visible_ancestors.append(node)
		node = node.get_parent()


func _restore_ancestors() -> void :
	for node in _context_forced_visible_ancestors:
		if is_instance_valid(node) and node.is_inside_tree():
			if node is CanvasLayer:
				node.visible = false
			elif node is CanvasItem:
				node.hide()
	_context_forced_visible_ancestors.clear()


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
		if context_panel.visible:
			var context_rect: = context_panel.get_global_rect()
			if not context_rect.has_point(mouse_pos):
				_close_context_panel()
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


func _refresh_context_text() -> void :
	var lines: Array[String] = []
	_load_context_page_entries()
	_normalize_context_page_index()
	_selected_entry_index = -1
	_context_visual_dirty = true
	_context_visual_item_map.clear()
	_update_toolbar_state()
	_update_context_pagination_bar()
	_update_context_token_label()

	var page_start: = _get_context_page_start()
	var story_lines: = _build_context_text_lines(_context_entries, page_start)
	if story_lines.is_empty():
		lines.append("[color=#666677][i]No dialogue history yet...[/i][/color]")
	else:
		lines.append_array(story_lines)

	context_text.text = "\n\n".join(lines)
	if _is_visual_context_tab_active():
		_rebuild_visual_list()
	else:
		_clear_context_visual_list()


func _on_context_tab_changed(_tab: int) -> void :
	if _is_visual_context_tab_active() and _context_visual_dirty:
		_rebuild_visual_list()


func _is_visual_context_tab_active() -> bool:
	if context_tabs == null:
		return false
	var current: = context_tabs.get_current_tab_control()
	return current != null and current.name == "Visual"


func _load_context_page_entries() -> void :
	var manager: = _get_story_summary_manager()
	if manager != null and manager.has_method("get_context_entries_for_ui_page"):
		var result: Dictionary = manager.call(
			"get_context_entries_for_ui_page", 
			_get_context_page_start(), 
			_context_page_size
		)
		_context_total_entries = maxi(0, int(result.get("total_count", _context_entries.size())))
		_context_ai_session_split_index = int(result.get("ai_session_split_index", -1))
		_normalize_context_page_index()
		var normalized_start: = _get_context_page_start()
		if normalized_start != int(result.get("offset", -1)):
			result = manager.call(
				"get_context_entries_for_ui_page", 
				normalized_start, 
				_context_page_size
			)
			_context_total_entries = maxi(0, int(result.get("total_count", _context_total_entries)))
			_context_ai_session_split_index = int(result.get("ai_session_split_index", _context_ai_session_split_index))
		_context_entries = (result.get("entries", []) as Array).duplicate(false)
		return

	var entries: = _get_context_source_entries()
	_context_total_entries = entries.size()
	_normalize_context_page_index()
	_context_entries = entries.slice(_get_context_page_start(), mini(_get_context_page_start() + _context_page_size, entries.size()))


func _create_context_pagination_bar() -> void :
	if _context_pagination_bar != null:
		return

	_context_pagination_bar = HBoxContainer.new()
	_context_pagination_bar.name = "ContextPaginationBar"
	_context_pagination_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_context_pagination_bar.add_theme_constant_override("separation", 8)

	_context_first_page_btn = _create_context_page_button("<<")
	_context_prev_page_btn = _create_context_page_button("<")
	_context_range_label = Label.new()
	_context_range_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_context_range_label.custom_minimum_size = Vector2(170, 0)
	_context_range_label.add_theme_font_size_override("font_size", 12)
	_context_range_label.add_theme_color_override("font_color", Color(0.76, 0.72, 0.86, 1.0))
	_context_next_page_btn = _create_context_page_button(">")
	_context_last_page_btn = _create_context_page_button(">>")

	_context_pagination_bar.add_child(_context_first_page_btn)
	_context_pagination_bar.add_child(_context_prev_page_btn)
	for child in _create_context_page_number_controls():
		_context_pagination_bar.add_child(child)
	_context_pagination_bar.add_child(_context_next_page_btn)
	_context_pagination_bar.add_child(_context_last_page_btn)
	_context_pagination_bar.add_child(_context_range_label)
	_add_context_page_size_controls()

	_context_first_page_btn.pressed.connect( func(): _set_context_page(0))
	_context_prev_page_btn.pressed.connect( func(): _set_context_page(_context_page_index - 1))
	_context_next_page_btn.pressed.connect( func(): _set_context_page(_context_page_index + 1))
	_context_last_page_btn.pressed.connect( func(): _set_context_page(_get_context_page_count() - 1))

	var context_vbox: = context_tabs.get_parent()
	context_vbox.add_child(_context_pagination_bar)
	context_vbox.move_child(_context_pagination_bar, context_close_button.get_index())


func _create_context_page_button(label: String) -> Button:
	var button: = Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(42, 28)
	button.add_theme_font_size_override("font_size", 12)
	return button


func _create_context_page_number_controls() -> Array:
	var controls: Array = []
	_context_page_buttons.clear()
	for i in range(7):
		var button: = _create_context_page_button("")
		button.custom_minimum_size = Vector2(38, 28)
		button.pressed.connect(_on_context_page_number_pressed.bind(button))
		_context_page_buttons.append(button)
		controls.append(button)
	return controls


func _add_context_page_size_controls() -> void :
	var separator: = VSeparator.new()
	_context_pagination_bar.add_child(separator)
	for option in CONTEXT_PAGE_SIZE_OPTIONS:
		var option_value: = int(option)
		var button: = _create_context_page_button(str(option_value))
		button.custom_minimum_size = Vector2(44, 28)
		button.tooltip_text = "Show %d lines per page" % option_value
		button.pressed.connect(_on_context_page_size_pressed.bind(option_value))
		_context_page_size_buttons[option_value] = button
		_context_pagination_bar.add_child(button)


func _normalize_context_page_index() -> void :
	var page_count: = _get_context_page_count()
	if _context_page_index < 0:
		_context_page_index = page_count - 1
	else:
		_context_page_index = clampi(_context_page_index, 0, page_count - 1)


func _get_context_page_count() -> int:
	if _context_total_entries <= 0:
		return 1
	return maxi(1, int(ceil(float(_context_total_entries) / float(_context_page_size))))


func _get_context_page_start() -> int:
	if _context_total_entries <= 0:
		return 0
	if _context_page_index < 0:
		return maxi(0, _context_total_entries - _context_page_size)
	var clamped_page: = clampi(_context_page_index, 0, _get_context_page_count() - 1)
	if clamped_page >= _get_context_page_count() - 1:
		return maxi(0, _context_total_entries - _context_page_size)
	return clamped_page * _context_page_size


func _get_context_page_end() -> int:
	return mini(_get_context_page_start() + _context_page_size, _context_total_entries)


func _get_context_page_entries() -> Array:
	return _context_entries


func _get_context_page_local_index(global_index: int) -> int:
	var local_index: = global_index - _get_context_page_start()
	if local_index < 0 or local_index >= _context_entries.size():
		return -1
	return local_index


func _get_context_entry_at_global_index(global_index: int) -> Dictionary:
	var local_index: = _get_context_page_local_index(global_index)
	if local_index >= 0:
		return (_context_entries[local_index] as Dictionary).duplicate(true)
	var manager: = _get_story_summary_manager()
	if manager != null and manager.has_method("get_context_entry_for_ui_index"):
		var entry: Variant = manager.call("get_context_entry_for_ui_index", global_index)
		if entry is Dictionary:
			return (entry as Dictionary).duplicate(true)
	return {}


func _has_selected_context_entry() -> bool:
	return not _get_context_entry_at_global_index(_selected_entry_index).is_empty()


func _get_selected_context_entry() -> Dictionary:
	return _get_context_entry_at_global_index(_selected_entry_index)


func _set_context_page(page_index: int) -> void :
	_context_page_index = clampi(page_index, 0, _get_context_page_count() - 1)
	_load_context_page_entries()
	_selected_entry_index = -1
	_update_toolbar_state()
	_sync_to_text_tab()
	_context_visual_dirty = true
	if _is_visual_context_tab_active():
		_rebuild_visual_list()
	else:
		_clear_context_visual_list()
	_update_context_pagination_bar()


func _on_context_page_number_pressed(button: Button) -> void :
	var page_index: = int(button.get_meta("page_index", -1))
	if page_index >= 0:
		_set_context_page(page_index)


func _on_context_page_size_pressed(page_size: int) -> void :
	var old_start: = _get_context_page_start()
	var was_latest: = _context_page_index >= _get_context_page_count() - 1
	_context_page_size = page_size
	if not CONTEXT_PAGE_SIZE_OPTIONS.has(_context_page_size):
		_context_page_size = CONTEXT_DEFAULT_PAGE_SIZE
	if was_latest:
		_context_page_index = _get_context_page_count() - 1
	else:
		_context_page_index = clampi(int(floor(float(old_start) / float(_context_page_size))), 0, _get_context_page_count() - 1)
	_load_context_page_entries()
	_selected_entry_index = -1
	_update_toolbar_state()
	_sync_to_text_tab()
	_context_visual_dirty = true
	if _is_visual_context_tab_active():
		_rebuild_visual_list()
	else:
		_clear_context_visual_list()
	_update_context_pagination_bar()


func _update_context_pagination_bar() -> void :
	if _context_pagination_bar == null:
		return
	var page_count: = _get_context_page_count()
	var has_multiple_pages: = page_count > 1
	_context_pagination_bar.visible = has_multiple_pages or _context_total_entries > CONTEXT_PAGE_SIZE_OPTIONS[0]
	_update_context_page_number_buttons()
	_update_context_page_size_buttons()
	_update_context_range_label()
	if not has_multiple_pages:
		_context_first_page_btn.disabled = true
		_context_prev_page_btn.disabled = true
		_context_next_page_btn.disabled = true
		_context_last_page_btn.disabled = true
		return
	_context_first_page_btn.disabled = _context_page_index <= 0
	_context_prev_page_btn.disabled = _context_page_index <= 0
	_context_next_page_btn.disabled = _context_page_index >= page_count - 1
	_context_last_page_btn.disabled = _context_page_index >= page_count - 1


func _update_context_page_number_buttons() -> void :
	var page_count: = _get_context_page_count()
	var pages: = _get_context_visible_page_slots(page_count)
	for i in range(_context_page_buttons.size()):
		var button: = _context_page_buttons[i]
		if i >= pages.size():
			button.hide()
			button.set_meta("page_index", -1)
			continue
		var slot: Variant = pages[i]
		button.show()
		if slot is String:
			button.text = str(slot)
			button.disabled = true
			button.set_meta("page_index", -1)
			continue
		var page_index: = int(slot)
		button.text = str(page_index + 1)
		button.disabled = page_index == _context_page_index
		button.set_meta("page_index", page_index)


func _get_context_visible_page_slots(page_count: int) -> Array:
	if page_count <= 7:
		var all_pages: Array = []
		for page in range(page_count):
			all_pages.append(page)
		return all_pages

	var current: = clampi(_context_page_index, 0, page_count - 1)
	if current <= 3:
		return [0, 1, 2, 3, 4, "...", page_count - 1]
	if current >= page_count - 4:
		return [0, "...", page_count - 5, page_count - 4, page_count - 3, page_count - 2, page_count - 1]
	return [0, "...", current - 1, current, current + 1, "...", page_count - 1]


func _update_context_page_size_buttons() -> void :
	for raw_option in _context_page_size_buttons.keys():
		var option: = int(raw_option)
		var button: Button = _context_page_size_buttons[option]
		button.disabled = option == _context_page_size


func _update_context_range_label() -> void :
	if _context_range_label == null:
		return
	if _context_total_entries <= 0:
		_context_range_label.text = "0 lines"
		return
	_context_range_label.text = "%d-%d of %d" % [
		_get_context_page_start() + 1, 
		_get_context_page_end(), 
		_context_total_entries, 
	]


func _get_context_page_start_for_page(page_index: int) -> int:
	if _context_total_entries <= 0:
		return 0
	var page_count: = _get_context_page_count()
	var clamped_page: = clampi(page_index, 0, page_count - 1)
	if clamped_page >= page_count - 1:
		return maxi(0, _context_total_entries - _context_page_size)
	return clamped_page * _context_page_size


func _get_context_page_end_for_page(page_index: int) -> int:
	return mini(_get_context_page_start_for_page(page_index) + _context_page_size, _context_total_entries)


func _get_context_page_index_for_global_index(global_index: int) -> int:
	if _context_total_entries <= 0:
		return 0
	var page_count: = _get_context_page_count()
	var latest_page_start: = _get_context_page_start_for_page(page_count - 1)
	if global_index >= latest_page_start:
		return page_count - 1
	return clampi(int(floor(float(global_index) / float(_context_page_size))), 0, page_count - 1)


func _format_story_context_lines(entries: Array) -> Array[String]:
	var result: Array[String] = []
	for entry in entries:
		var character_name: String = entry.get("character_name", "")
		var text: String = entry.get("text", "")
		if text.is_empty():
			continue
		var line_text: = ""
		if character_name.is_empty():

			line_text = "[color=#8888aa][i]%s[/i][/color]" % text
		else:

			var tag: = CharacterPortraitService.get_character_tag(character_name)
			var color: = _get_character_color_hex(entry.get("character_id", ""))
			line_text = "[color=%s][b]%s:[/b][/color] %s" % [color, tag, text]
		var rpg_line: = _format_rpg_check_context_line(entry)
		if not rpg_line.is_empty():
			line_text += "\n" + rpg_line
		result.append(line_text)
	return result




func _format_rpg_check_context_line(entry: Dictionary) -> String:
	var rpg_check_variant: Variant = entry.get("rpg_check", {})
	if not (rpg_check_variant is Dictionary):
		return ""
	var check: = rpg_check_variant as Dictionary
	if check.is_empty():
		return ""
	var tier: = str(check.get("tier", ""))
	var colors: Array = DiceResultPanel.TIER_COLORS.get(tier, [DiceResultPanel.DEFAULT_FILL, DiceResultPanel.DEFAULT_ACCENT])
	var accent: Color = colors[1]
	var color_hex: = "#" + accent.lerp(Color.WHITE, 0.15).to_html(false)
	var modifier: = int(check.get("modifier", 0))
	var modifier_text: = ("+%d" % modifier) if modifier >= 0 else str(modifier)
	return "[color=%s][i]%s — %s %d (%s) • Roll %d %s = %d vs DC %d[/i][/color]" % [
		color_hex, 
		str(check.get("tier_label", "Result")), 
		str(check.get("stat_label", "?")), 
		int(check.get("stat_value", 10)), 
		modifier_text, 
		int(check.get("roll", 0)), 
		modifier_text, 
		int(check.get("total", 0)), 
		int(check.get("dc", 0)), 
	]


func _get_character_color_hex(character_id: String) -> String:
	if character_id.is_empty():
		return "#9b4ba9"
	if _context_character_color_cache.has(character_id):
		return str(_context_character_color_cache[character_id])

	var character: DialogicCharacter = null
	if character_id.begins_with("res://"):
		character = load(character_id) as DialogicCharacter
	else:
		character = DialogicResourceUtil.get_character_resource(character_id)

	if character and character.color:
		var color_hex: = "#" + character.color.to_html(false)
		_context_character_color_cache[character_id] = color_hex
		return color_hex
	_context_character_color_cache[character_id] = "#9b4ba9"
	return "#9b4ba9"


func _collect_story_context_entries() -> Array:
	var entries: Array = []
	var history: = _get_visible_story_history()
	var ai_session_history_start: = _get_ai_session_history_start_raw_index(history.size())
	var pre_ai_entry_count: = 0
	_context_ai_session_split_index = -1

	if not history.is_empty():
		for i in range(history.size()):
			var entry = history[i]
			var text: String = entry.get("text", "")
			var event_type: String = entry.get("event_type", "")
			var character: String = entry.get("character", "")

			if text.is_empty():
				continue
			if text.ends_with(" left") or text.ends_with(" joined"):
				continue
			if event_type != "Text":
				continue

			var character_id: = ""
			if not character.is_empty() and character != "null":
				var tag: = CharacterPortraitService.get_character_tag(character)
				var dialogic_char: = CharacterPortraitService.find_dialogic_character(tag)
				if dialogic_char:
					character_id = dialogic_char.resource_path
				else:
					character_id = CharacterPortraitService.get_dialogic_identifier(tag)

			var fallback_entry: = {
				"text": text, 
				"character_name": "" if character == "null" else character, 
				"character_id": character_id, 
				"context_source": "history_live"
			}
			var raw_rpg_check: Variant = entry.get("rpg_check", {})
			if raw_rpg_check is Dictionary and not (raw_rpg_check as Dictionary).is_empty():
				fallback_entry["rpg_check"] = (raw_rpg_check as Dictionary).duplicate(true)
			entries.append(fallback_entry)
			if ai_session_history_start >= 0 and i < ai_session_history_start:
				pre_ai_entry_count += 1

	var summary_entries: = _collect_summary_context_entries()
	if entries.is_empty():
		entries = summary_entries
	elif _has_external_import_summary():
		var merged_entries: = summary_entries.duplicate(true)
		merged_entries.append_array(entries)
		entries = merged_entries

	if ai_session_history_start >= 0:
		var summary_prefix_size: = summary_entries.size() if _has_external_import_summary() else 0
		_context_ai_session_split_index = clampi(summary_prefix_size + pre_ai_entry_count, 0, entries.size())

	return entries


func _get_visible_story_history() -> Array:
	var history: Array = []
	var history_subsystem: Node = DialogicUtil.autoload().get(&"History")
	if history_subsystem != null and history_subsystem.has_method(&"get_simple_history"):
		var raw_history: Variant = history_subsystem.call(&"get_simple_history")
		if raw_history is Array:
			history = raw_history

	if history.is_empty() and Dialogic.has_subsystem("History"):
		var fallback_history: Variant = Dialogic.History.get_simple_history()
		if fallback_history is Array:
			history = fallback_history

	if RollbackManager != null and RollbackManager.is_in_rollback_mode():
		var ai_data: = RollbackManager.get_current_ai_data()
		if not ai_data.is_empty():
			var visible_history_size: = RollbackManager.get_visible_dialogic_history_size(ai_data)
			if visible_history_size >= 0 and visible_history_size < history.size():
				history = history.slice(0, visible_history_size)

	return history


func _has_external_import_summary() -> bool:
	if StorySummaryManager == null or not StorySummaryManager.has_method("has_external_import_context"):
		return false
	return bool(StorySummaryManager.has_external_import_context())


func _collect_summary_context_entries() -> Array:
	var entries: Array = []
	if StorySummaryManager == null:
		return entries

	var context_text: = ""
	var context_source: = "summary_fallback"
	if _has_external_import_summary():
		var imported: = StorySummaryManager.get_external_import_context()
		context_text = _normalize_external_import_text(str(imported.get("raw_summary_text", "")))
		var parsed_entries: = _parse_external_import_context_entries(context_text)
		if not parsed_entries.is_empty():
			return parsed_entries
		context_source = "summary_import"
	elif StorySummaryManager.has_active_summary():
		context_text = StorySummaryManager.build_active_context().strip_edges()
	else:
		return entries
	if context_text.is_empty():
		return entries

	for block in context_text.split("\n\n", false):
		var cleaned_block: = str(block).strip_edges()
		if cleaned_block.is_empty():
			continue
		entries.append({
			"text": cleaned_block, 
			"character_name": "", 
			"character_id": "", 
			"context_source": context_source
		})

	return entries


func _get_ai_session_history_start_raw_index(history_size: int) -> int:
	if history_size <= 0:
		return -1
	if RollbackManager == null or not AIStateCoordinator.is_active():
		return -1
	var session_start: = RollbackManager.get_active_ai_session_dialogic_history_start()
	if session_start < 0:
		return -1
	return clampi(session_start, 0, history_size)


func _normalize_external_import_text(raw_text: String) -> String:
	var lines: Array[String] = []
	for raw_line in raw_text.split("\n", false):
		lines.append(str(raw_line))

	if not lines.is_empty():
		var first_line: = lines[0].strip_edges()
		if first_line.begins_with("Imported from ") and first_line.find("Treat the following as story history") != -1:
			lines.remove_at(0)
			while not lines.is_empty() and lines[0].strip_edges().is_empty():
				lines.remove_at(0)

	if not lines.is_empty() and lines[0].strip_edges() == "[IMPORTED TRANSCRIPT]":
		lines.remove_at(0)

	return "\n".join(lines).strip_edges()


func _parse_external_import_context_entries(raw_text: String) -> Array:
	var parsed_entries: Array = []
	if raw_text.strip_edges().is_empty():
		return parsed_entries

	for raw_line in raw_text.split("\n", false):
		var line: = str(raw_line).strip_edges()
		if line.is_empty():
			continue
		if _is_external_import_command_line(line):
			continue
		var parsed_entry: = _parse_external_import_line(line)
		if parsed_entry.is_empty():
			return []
		parsed_entries.append(parsed_entry)

	return parsed_entries


func _is_external_import_command_line(line: String) -> bool:
	var normalized: = line.strip_edges()
	if not normalized.begins_with("["):
		return false
	var closing_index: = normalized.find("]")
	if closing_index == -1:
		return false
	return true


func _parse_external_import_line(line: String) -> Dictionary:
	var speaker_token: = ""
	var text: = ""

	var first_quote: = line.find("\"")
	var last_quote: = line.rfind("\"")
	if first_quote > 0 and last_quote > first_quote:
		speaker_token = line.substr(0, first_quote).strip_edges().trim_suffix(":")
		text = line.substr(first_quote + 1, last_quote - first_quote - 1).replace("\\\"", "\"")
	elif ": " in line:
		var split_index: = line.find(": ")
		speaker_token = line.substr(0, split_index).strip_edges()
		text = line.substr(split_index + 2).strip_edges()
	else:
		return {}

	return _build_import_context_entry(speaker_token, text)


func _build_import_context_entry(speaker_token: String, text: String) -> Dictionary:
	var normalized_text: = text.strip_edges()
	if normalized_text.is_empty():
		return {}

	var normalized_speaker: = speaker_token.strip_edges()
	if normalized_speaker.is_empty() or normalized_speaker.to_lower() == "narrator":
		return {
			"text": normalized_text, 
			"character_name": "", 
			"character_id": "", 
			"context_source": "summary_import"
		}

	var tag: = normalized_speaker
	var dialogic_char: = CharacterPortraitService.find_dialogic_character(tag)
	if dialogic_char == null:
		tag = CharacterPortraitService.get_character_tag(normalized_speaker, "full")
		dialogic_char = CharacterPortraitService.find_dialogic_character(tag)

	var character_name: = normalized_speaker
	var character_id: = CharacterPortraitService.get_dialogic_identifier(tag)
	if dialogic_char:
		if not dialogic_char.display_name.strip_edges().is_empty():
			character_name = dialogic_char.display_name.strip_edges()
		if not dialogic_char.resource_path.is_empty():
			character_id = dialogic_char.resource_path

	return {
		"text": normalized_text, 
		"character_name": character_name, 
		"character_id": character_id, 
		"context_source": "summary_import"
	}


func _populate_context_visual(entries: Array) -> void :

	_context_total_entries = entries.size()
	_normalize_context_page_index()
	var page_start: = _get_context_page_start()
	_context_entries = entries.slice(page_start, mini(page_start + _context_page_size, entries.size()))
	_selected_entry_index = -1
	_context_visual_item_map.clear()
	_update_toolbar_state()
	_update_context_pagination_bar()

	for child in context_visual_list.get_children():
		child.queue_free()

	if entries.is_empty():
		var placeholder: = Label.new()
		placeholder.text = "(empty - click '+ Add' to create an entry)"
		placeholder.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 1.0))
		context_visual_list.add_child(placeholder)
		return

	_populate_context_visual_sections(_get_context_page_entries(), page_start)


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


func _get_story_summary_manager() -> Node:
	if StorySummaryManager == null:
		return null
	return StorySummaryManager






const BASE_AVAILABLE_CHARACTERS: = [
	{"name": "Narrator", "display": "(Narrator)", "id": ""}, 
	{"name": "Twilight Sparkle", "display": "Twilight Sparkle", "id": "res://dialogic/characters/twilight.dch"}, 
	{"name": "Spike", "display": "Spike", "id": "res://dialogic/characters/spike.dch"}, 
	{"name": "Applejack", "display": "Applejack", "id": "res://dialogic/characters/applejack.dch"}, 
	{"name": "Rainbow Dash", "display": "Rainbow Dash", "id": "res://dialogic/characters/rainbow_dash.dch"}, 
	{"name": "Rarity", "display": "Rarity", "id": "res://dialogic/characters/rarity.dch"}, 
	{"name": "Fluttershy", "display": "Fluttershy", "id": "res://dialogic/characters/fluttershy.dch"}, 
	{"name": "Pinkie Pie", "display": "Pinkie Pie", "id": "res://dialogic/characters/pinkie_pie.dch"}, 
	{"name": "Trixie", "display": "Trixie", "id": "res://dialogic/characters/trixie.dch"}, 
	{"name": "Zecora", "display": "Zecora", "id": "res://dialogic/characters/zecora.dch"}, 
]


func _populate_character_dropdown() -> void :
	character_dropdown.clear()
	for char_data in _get_available_characters():
		character_dropdown.add_item(char_data["display"])


func _on_entry_clicked(index: int) -> void :

	_set_context_entry_selected(_selected_entry_index, false)


	_selected_entry_index = index
	_set_context_entry_selected(_selected_entry_index, true)
	var voice_entry := _get_selected_context_entry()
	var raw_index := int(voice_entry.get("raw_history_index", -1))
	var voice_controller: Node = preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree())
	if raw_index >= 0 and raw_index < Dialogic.History.simple_history_content.size():
		voice_controller.replay_history(Dialogic.History.simple_history_content[raw_index], "narrator", "", true)
	elif not voice_entry.is_empty():
		var tag := CharacterPortraitService.get_character_tag(str(voice_entry.get("character_name", "narrator")), "full")
		voice_controller.replay_history(voice_entry, tag if not tag.is_empty() else "narrator", str(voice_entry.get("text", "")), true)

	_update_toolbar_state()


func _update_toolbar_state() -> void :
	var selected_entry: = _get_selected_context_entry()
	var has_selection: = not selected_entry.is_empty()
	var selected_ai_affects: = bool(selected_entry.get("ai_affects", false))
	var can_edit: = has_selection
	var can_delete: = has_selection and selected_ai_affects
	var can_add: = true
	var can_move_up: = false
	var can_move_down: = false
	if has_selection:
		can_add = selected_ai_affects
	if has_selection and selected_ai_affects:
		if _selected_entry_index > 0:
			if _selected_entry_index > 1:
				var up_after_entry: = _get_context_entry_at_global_index(_selected_entry_index - 2)
				can_move_up = bool(up_after_entry.get("ai_affects", false))
			else:
				var first_entry: = _get_context_entry_at_global_index(0)
				can_move_up = bool(first_entry.get("ai_affects", false))
		if _selected_entry_index < _context_total_entries - 1:
			var down_after_entry: = _get_context_entry_at_global_index(_selected_entry_index + 1)
			can_move_down = bool(down_after_entry.get("ai_affects", false))
	edit_btn.disabled = not can_edit
	delete_btn.disabled = not can_delete
	move_up_btn.disabled = not can_move_up
	move_down_btn.disabled = not can_move_down
	add_btn.disabled = not can_add
	delete_btn.tooltip_text = "" if can_delete else "Only entries still sent raw to the AI can be deleted."
	move_up_btn.tooltip_text = "" if can_move_up else "Entries can only move within AI-affecting context."
	move_down_btn.tooltip_text = "" if can_move_down else "Entries can only move within AI-affecting context."
	add_btn.tooltip_text = "" if can_add else "New entries can only be added into AI-affecting context."


func _on_edit_pressed() -> void :
	var entry: = _get_selected_context_entry()
	if entry.is_empty():
		return
	_editing_index = _selected_entry_index
	_open_edit_dialog(entry.get("character_name", ""), entry.get("text", ""))


func _on_delete_pressed() -> void :
	var entry: = _get_selected_context_entry()
	if entry.is_empty():
		return
	var manager: = _get_story_summary_manager()
	if manager == null or not manager.has_method("apply_delete"):
		return

	var entry_id: = str(entry.get("entry_id", "")).strip_edges()
	var result: Variant = manager.call("apply_delete", entry_id)
	if result is Dictionary and not bool((result as Dictionary).get("ok", false)):
		return

	var next_index: = _selected_entry_index
	_refresh_context_text()
	if _context_total_entries <= 0:
		_selected_entry_index = -1
	else:
		_selected_entry_index = mini(next_index, _context_total_entries - 1)
		_set_context_entry_selected(_selected_entry_index, true)
	_update_toolbar_state()


func _on_move_up_pressed() -> void :
	var entry: = _get_selected_context_entry()
	if _selected_entry_index <= 0 or entry.is_empty():
		return
	var manager: = _get_story_summary_manager()
	if manager == null or not manager.has_method("apply_move_after"):
		return

	var entry_id: = str(entry.get("entry_id", "")).strip_edges()
	var after_id: = ""
	if _selected_entry_index > 1:
		after_id = str(_get_context_entry_at_global_index(_selected_entry_index - 2).get("entry_id", "")).strip_edges()
	var result: Variant = manager.call("apply_move_after", entry_id, after_id)
	if result is Dictionary and not bool((result as Dictionary).get("ok", false)):
		return

	_refresh_context_text()
	_select_context_entry_by_id(entry_id)
	_update_toolbar_state()


func _on_move_down_pressed() -> void :
	var entry: = _get_selected_context_entry()
	if _selected_entry_index < 0 or _selected_entry_index >= _context_total_entries - 1 or entry.is_empty():
		return
	var manager: = _get_story_summary_manager()
	if manager == null or not manager.has_method("apply_move_after"):
		return

	var entry_id: = str(entry.get("entry_id", "")).strip_edges()
	var after_id: = str(_get_context_entry_at_global_index(_selected_entry_index + 1).get("entry_id", "")).strip_edges()
	var result: Variant = manager.call("apply_move_after", entry_id, after_id)
	if result is Dictionary and not bool((result as Dictionary).get("ok", false)):
		return

	_refresh_context_text()
	_select_context_entry_by_id(entry_id)
	_update_toolbar_state()


func _on_add_pressed() -> void :
	var manager: = _get_story_summary_manager()
	if manager == null or not manager.has_method("can_insert_after"):
		return

	_editing_index = -1
	var selected_entry: = _get_selected_context_entry()
	if not selected_entry.is_empty():
		var selected_id: = str(selected_entry.get("entry_id", "")).strip_edges()
		if bool(manager.call("can_insert_after", selected_id)):
			_editing_index = -2 - _selected_entry_index
	_open_edit_dialog("", "")






func _open_edit_dialog(character_name: String, text: String) -> void :
	edit_title.text = "Add Entry" if _editing_index < 0 else "Edit Entry"


	_populate_character_dropdown()
	var char_index: = 0
	var available_characters: = _get_available_characters()
	for i in range(available_characters.size()):
		if available_characters[i]["name"] == character_name:
			char_index = i
			break
	character_dropdown.select(char_index)
	character_dropdown.disabled = _editing_index >= 0


	text_edit.text = text

	edit_dialog.show()


func _on_save_edit_pressed() -> void :
	if text_edit.text.strip_edges().is_empty():
		return

	var manager: = _get_story_summary_manager()
	if manager == null:
		edit_dialog.hide()
		return

	var result: Variant = null
	var target_entry_id: = ""
	var existing_entry: = _get_context_entry_at_global_index(_editing_index)
	if _editing_index >= 0 and not existing_entry.is_empty():
		if not manager.has_method("apply_text_edit"):
			edit_dialog.hide()
			return
		target_entry_id = str(existing_entry.get("entry_id", "")).strip_edges()
		result = manager.call("apply_text_edit", target_entry_id, text_edit.text)
	else:
		if not manager.has_method("apply_insert_after"):
			edit_dialog.hide()
			return
		var char_index: = character_dropdown.selected
		var available_characters: = _get_available_characters()
		if char_index < 0 or char_index >= available_characters.size():
			return
		var char_data: Dictionary = available_characters[char_index]
		var after_id: = ""
		if _editing_index <= -2:
			var insert_after_index: = -2 - _editing_index
			var insert_after_entry: = _get_context_entry_at_global_index(insert_after_index)
			if not insert_after_entry.is_empty():
				after_id = str(insert_after_entry.get("entry_id", "")).strip_edges()
		var new_entry: = {
			"character_name": "" if str(char_data.get("name", "")).strip_edges() == "Narrator" else str(char_data.get("name", "")).strip_edges(), 
			"character_id": str(char_data.get("id", "")).strip_edges(), 
			"text": text_edit.text, 
		}
		result = manager.call("apply_insert_after", after_id, new_entry)
		if result is Dictionary:
			target_entry_id = str((result as Dictionary).get("entry_id", "")).strip_edges()

	if result is Dictionary and not bool((result as Dictionary).get("ok", false)):
		return
	edit_dialog.hide()
	_refresh_context_text()
	if not target_entry_id.is_empty():
		_select_context_entry_by_id(target_entry_id)
	elif _context_total_entries <= 0:
		_selected_entry_index = -1
	else:
		_selected_entry_index = mini(maxi(_editing_index, 0), _context_total_entries - 1)
		_set_context_entry_selected(_selected_entry_index, true)
	_update_toolbar_state()


func _on_cancel_edit_pressed() -> void :
	edit_dialog.hide()


func _rebuild_visual_list() -> void :
	_context_visual_dirty = false
	_clear_context_visual_list()

	if _context_entries.is_empty():
		var placeholder: = Label.new()
		placeholder.text = "(empty - click '+ Add' to create an entry)"
		placeholder.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 1.0))
		context_visual_list.add_child(placeholder)
		_update_toolbar_state()
		return

	_populate_context_visual_sections(_get_context_page_entries(), _get_context_page_start())

	_update_toolbar_state()


func _clear_context_visual_list() -> void :
	_context_visual_item_map.clear()
	if context_visual_list == null:
		return
	for child in context_visual_list.get_children():
		child.queue_free()


func _sync_to_text_tab() -> void :
	var lines: Array[String] = []
	_update_context_token_label()
	var story_lines: = _build_context_text_lines(_get_context_page_entries(), _get_context_page_start())
	if story_lines.is_empty():
		lines.append("[color=#666677][i]No dialogue history yet...[/i][/color]")
	else:
		lines.append_array(story_lines)
	context_text.text = "\n\n".join(lines)


func _update_context_token_label() -> void :
	if context_token_label == null:
		return
	if StorySummaryManager == null or not StorySummaryManager.has_method("get_story_token_summary_label"):
		context_token_label.visible = false
		return
	context_token_label.text = StorySummaryManager.get_story_token_summary_label()
	context_token_label.visible = true


func _get_context_source_entries() -> Array:
	var manager: = _get_story_summary_manager()
	if manager != null and manager.has_method("get_context_entries_for_ui"):
		var entries: Array = manager.call("get_context_entries_for_ui")
		_context_ai_session_split_index = -1
		var history_size: = 0
		if Dialogic.has_subsystem("History"):
			history_size = Dialogic.History.get_simple_history().size()
		var ai_session_history_start: = _get_ai_session_history_start_raw_index(history_size)
		if ai_session_history_start >= 0:
			var split_index: = entries.size()
			for i in range(entries.size()):
				var entry: = entries[i] as Dictionary
				var raw_history_index: = int((entry as Dictionary).get("raw_history_index", -1))
				if raw_history_index >= ai_session_history_start:
					split_index = i
					break
			_context_ai_session_split_index = clampi(split_index, 0, entries.size())
		return entries
	return _collect_story_context_entries()


func _build_context_text_lines(entries: Array, start_index: int = 0) -> Array[String]:
	var sections: = _get_context_display_sections(entries, start_index)
	if sections.is_empty():
		return []

	var result: Array[String] = []
	for section in sections:
		var title: = str(section.get("title", "")).strip_edges()
		var section_entries: Array = section.get("entries", [])
		if not title.is_empty():
			result.append("[color=#d7cf9a][b]%s[/b][/color]" % title)
		result.append_array(_format_story_context_lines(section_entries))

	return result


func _get_context_display_sections(entries: Array, start_index: int = 0) -> Array:
	if entries.is_empty():
		return []

	if _context_ai_session_split_index < 0 or _context_ai_session_split_index > entries.size():
		if _context_ai_session_split_index < 0:
			return [{"title": "", "entries": entries, "start_index": start_index}]

	var sections: Array = []
	var prior_entries: Array = []
	var session_entries: Array = []
	var prior_start: = -1
	var session_start: = -1

	for local_index in range(entries.size()):
		var global_index: = start_index + local_index
		if global_index < _context_ai_session_split_index:
			if prior_start < 0:
				prior_start = global_index
			prior_entries.append(entries[local_index])
		else:
			if session_start < 0:
				session_start = global_index
			session_entries.append(entries[local_index])

	if not prior_entries.is_empty():
		sections.append({
			"title": "Prior Story Context", 
			"entries": prior_entries, 
			"start_index": prior_start, 
		})

	if not session_entries.is_empty():
		sections.append({
			"title": "Current AI Session", 
			"entries": session_entries, 
			"start_index": session_start, 
		})

	if sections.is_empty():
		sections.append({"title": "", "entries": entries, "start_index": start_index})
	return sections


func _populate_context_visual_sections(entries: Array, start_index: int = 0) -> void :
	for section in _get_context_display_sections(entries, start_index):
		var title: = str(section.get("title", "")).strip_edges()
		var section_entries: Array = section.get("entries", [])
		var entry_index: = int(section.get("start_index", start_index))
		if not title.is_empty():
			_add_context_section_header(title)

		for entry in section_entries:
			var item = ContextEntryScene.instantiate()
			context_visual_list.add_child(item)
			var character_name: String = entry.get("character_name", "")
			var text: String = entry.get("text", "")
			var character_id: String = entry.get("character_id", "")
			item.setup(entry_index, character_name, text, character_id, {
				"cosmetic_only": bool(entry.get("cosmetic_only", false)), 
				"zone": str(entry.get("zone", "")), 
			})
			var rpg_check_variant: Variant = entry.get("rpg_check", {})
			if rpg_check_variant is Dictionary and not (rpg_check_variant as Dictionary).is_empty()\
			and item.has_method("set_rpg_check"):
				item.set_rpg_check(rpg_check_variant as Dictionary)
			item.entry_clicked.connect(_on_entry_clicked)
			_context_visual_item_map[entry_index] = item
			if entry_index == _selected_entry_index and item.has_method("set_selected"):
				item.set_selected(true)
			entry_index += 1


func _add_context_section_header(title: String) -> void :
	var label: = Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.84, 0.8, 0.6, 1.0))
	context_visual_list.add_child(label)


func _set_context_entry_selected(index: int, selected: bool) -> void :
	if index < 0:
		return
	var item = _context_visual_item_map.get(index, null)
	if item != null and item.has_method("set_selected"):
		item.set_selected(selected)


func _select_context_entry_by_id(entry_id: String) -> bool:
	var normalized_id: = entry_id.strip_edges()
	if normalized_id.is_empty():
		_selected_entry_index = -1
		return false

	var manager: = _get_story_summary_manager()
	if manager != null and manager.has_method("get_context_entry_index_for_ui"):
		var global_index: = int(manager.call("get_context_entry_index_for_ui", normalized_id))
		if global_index >= 0:
			_set_context_entry_selected(_selected_entry_index, false)
			_context_page_index = _get_context_page_index_for_global_index(global_index)
			_load_context_page_entries()
			_selected_entry_index = global_index
			_sync_to_text_tab()
			_context_visual_dirty = true
			if _is_visual_context_tab_active():
				_rebuild_visual_list()
			else:
				_clear_context_visual_list()
			_update_context_pagination_bar()
			_set_context_entry_selected(_selected_entry_index, true)
			return true

	var page_start: = _get_context_page_start()
	for local_index in range(_context_entries.size()):
		var entry: = _context_entries[local_index] as Dictionary
		if str(entry.get("entry_id", "")).strip_edges() != normalized_id:
			continue
		_set_context_entry_selected(_selected_entry_index, false)
		_selected_entry_index = page_start + local_index
		_sync_to_text_tab()
		_context_visual_dirty = true
		if _is_visual_context_tab_active():
			_rebuild_visual_list()
		else:
			_clear_context_visual_list()
		_update_context_pagination_bar()
		_set_context_entry_selected(_selected_entry_index, true)
		return true
	_selected_entry_index = -1
	return false


func _get_available_characters() -> Array:
	var available_characters: Array = [{
		"name": "Narrator", 
		"display": "(Narrator)", 
		"id": "", 
	}]
	var player_display_name: = _get_player_display_name()
	if not player_display_name.is_empty():
		available_characters.append({
			"name": player_display_name, 
			"display": player_display_name, 
			"id": "player"
		})

	var added_loaded_characters: = false
	if CharacterSpriteLoader != null:
		if CharacterSpriteLoader.has_method("is_loaded") and not CharacterSpriteLoader.is_loaded():
			CharacterSpriteLoader.load_all_characters()

		var character_rows: Array[Dictionary] = []
		for raw_tag in CharacterSpriteLoader.get_all_tags():
			var tag: = str(raw_tag).strip_edges()
			if tag.is_empty():
				continue
			var dialogic_char: DialogicCharacter = CharacterSpriteLoader.get_dialogic_character(tag)
			if dialogic_char == null:
				continue
			var display_name: = dialogic_char.display_name.strip_edges()
			if display_name.is_empty():
				display_name = tag.capitalize()
			character_rows.append({
				"name": display_name, 
				"display": display_name, 
				"id": CharacterPortraitService.get_dialogic_identifier(tag), 
				"sort_key": display_name.to_lower(), 
			})
		character_rows.sort_custom( func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("sort_key", "")) < str(b.get("sort_key", ""))
		)
		for row in character_rows:
			row.erase("sort_key")
			available_characters.append(row)
			added_loaded_characters = true

	if not added_loaded_characters:
		for char_data in BASE_AVAILABLE_CHARACTERS:
			if str(char_data.get("name", "")).strip_edges() == "Narrator":
				continue
			available_characters.append((char_data as Dictionary).duplicate(true))
	return available_characters


func _get_player_display_name() -> String:
	var player_char: DialogicCharacter = DialogicResourceUtil.get_character_resource("player")
	if player_char and not player_char.display_name.strip_edges().is_empty():
		return player_char.display_name.strip_edges()
	return "Player"

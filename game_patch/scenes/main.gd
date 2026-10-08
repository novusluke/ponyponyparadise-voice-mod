extends Control



const RollbackHistoryScene = preload("res://scenes/rollback_history.tscn")
const SaveLoadMenuScene = preload("res://scenes/save_load_menu.tscn")
const APIConfigMenuScene = preload("res://scenes/api_config_menu.tscn")
const MusicMixMenuScene = preload("res://scenes/music_mix_menu.tscn")
const ScheduleEditorMenuScene = preload("res://scenes/schedule_editor_menu.tscn")
const CharacterDownloadMenuScene = preload("res://scenes/character_download_menu.tscn")
const LocationDownloadMenuScene = preload("res://scenes/location_download_menu.tscn")
const CharacterBrowserMenuScene = preload("res://scenes/character_browser_menu.tscn")
const PromptEditorMenuScene = preload("res://scenes/prompt_editor_menu.tscn")
const PersonaMenuScene = preload("res://scenes/persona_menu.tscn")
const CustomStartMenuScene = preload("res://scenes/custom_start_menu.tscn")
const RenpyImportMenuScene = preload("res://scenes/renpy_import_menu.tscn")
const UISettingsMenuScene = preload("res://scenes/ui_settings_menu.tscn")
const ScenarioSelectPanelScene = preload("res://scenes/scenario_select_panel.tscn")
const ScenarioAllowlistMenuScene = preload("res://scenes/scenario_allowlist_menu.tscn")
const StorySummaryMenuScene = preload("res://scenes/story_summary_menu.tscn")
const FriendshipJournalMenuScript = preload("res://scenes/friendship_journal_menu.gd")
const LorebookEditorMenuScene = preload("res://scenes/lorebook_editor_menu.tscn")
const LorebookActivityIndicatorScript = preload("res://scripts/ui/lorebook_activity_indicator.gd")

var rollback_history: CanvasLayer = null
var save_load_menu: CanvasLayer = null
var api_config_menu: CanvasLayer = null
var music_mix_menu: CanvasLayer = null
var schedule_editor_menu: CanvasLayer = null
var character_download_menu: CanvasLayer = null
var location_download_menu: CanvasLayer = null
var character_browser_menu: CanvasLayer = null
var prompt_editor_menu: CanvasLayer = null
var persona_menu: CanvasLayer = null
var custom_start_menu: CanvasLayer = null
var renpy_import_menu: CanvasLayer = null
var ui_settings_menu: CanvasLayer = null
var scenario_customs_menu: CanvasLayer = null
var story_summary_menu: CanvasLayer = null
var friendship_journal_menu: CanvasLayer = null
var lorebook_editor_menu: CanvasLayer = null
var music_switcher: MusicSwitcher = null
var lorebook_activity_indicator: CanvasLayer = null
var is_in_game: bool = false
var menu_music_tween: Tween = null
var _custom_start_restore_scenario_id: String = "base"
var _custom_start_preview_active: bool = false
var _renpy_import_restore_scenario_id: String = "base"
var _renpy_import_preview_active: bool = false


const BTN_NORMAL_COLOR: = Color(0.173, 0.29, 0.42, 0.85)
const BTN_HOVER_COLOR: = Color(0.29, 0.42, 0.54, 0.95)
const BTN_PRESSED_COLOR: = Color(0.353, 0.482, 0.604, 1.0)
const BTN_DISABLED_COLOR: = Color(0.102, 0.165, 0.231, 0.6)
const BTN_TEXT_COLOR: = Color(0.91, 0.957, 1.0)
const BTN_TEXT_HOVER: = Color(1.0, 1.0, 1.0)
const BTN_TEXT_DISABLED: = Color(0.533, 0.6, 0.667)
const TITLE_MENU_BASE_SIZE: = Vector2(1920, 1080)
const TITLE_MENU_VIEWPORT_MARGIN: = Vector2(24, 24)
const TITLE_MENU_BASE_BUTTON_SIZE: = Vector2(280, 44)
const TITLE_MENU_BASE_SEPARATION: = 8.0
const TITLE_MENU_SEPARATOR_HEIGHT: = 4.0
const TITLE_MENU_MIN_SCALE_DESKTOP: = 0.66
const TITLE_MENU_MIN_SCALE_MOBILE: = 0.56
const TITLE_MENU_MIN_BUTTON_HEIGHT_DESKTOP: = 32.0
const TITLE_MENU_MIN_BUTTON_HEIGHT_MOBILE: = 28.0
const TITLE_MENU_MIN_BUTTON_WIDTH: = 240.0
const API_CONFIG_DEFAULT_LAYER: = 100


func _ready() -> void :
	preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree())


	_apply_window_icon()


	_setup_background()


	_setup_music()
	$BackgroundMusic.finished.connect(_on_background_music_finished)



	CharacterSpriteLoader.call_deferred("load_all_characters")


	_style_menu_buttons()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()


	$MenuButtons / NewGameButton.pressed.connect(_on_new_game_pressed)
	$MenuButtons / QuickStartButton.pressed.connect(_on_quick_start_pressed)
	$MenuButtons / CustomStartButton.pressed.connect(_on_custom_start_pressed)
	$MenuButtons / RenpyImportButton.pressed.connect(_on_renpy_import_pressed)
	$MenuButtons / SaveLoadButton.pressed.connect(_on_save_load_pressed)
	$MenuButtons / APISettingsButton.pressed.connect(_on_api_settings_pressed)
	$MenuButtons / UISettingsButton.pressed.connect(_on_ui_settings_pressed)
	$MenuButtons / MusicMixButton.pressed.connect(_on_music_mix_pressed)
	$MenuButtons / CommunityCharsButton.pressed.connect(_on_community_chars_pressed)
	$MenuButtons / CharacterBrowserButton.pressed.connect(_on_character_browser_pressed)
	$MenuButtons / PromptEditorButton.pressed.connect(_on_prompt_editor_pressed)
	$MenuButtons / PersonaButton.pressed.connect(_on_persona_pressed)
	$MenuButtons / QuitButton.pressed.connect(_on_quit_pressed)
	$MenuButtons / CommunityLocationsButton.pressed.connect(_on_community_locations_pressed)
	$MenuButtons / LorebookButton.pressed.connect(_on_lorebook_pressed)


	Dialogic.timeline_ended.connect(_on_timeline_ended)


	MapManager.map_opened.connect(_on_map_opened)
	MapManager.map_closed.connect(_on_map_closed)


	music_switcher = MusicSwitcher.new()
	add_child(music_switcher)
	lorebook_activity_indicator = LorebookActivityIndicatorScript.new()
	add_child(lorebook_activity_indicator)

	UISettingsManager.apply_runtime_settings()
	_apply_game_title()
	if not UISettingsManager.settings_changed.is_connected(_on_ui_settings_changed):
		UISettingsManager.settings_changed.connect(_on_ui_settings_changed)

	Dialogic.paused = false
	if DialogicUtil.autoload():
		DialogicUtil.autoload().paused = false



func _ensure_character_sprites_loaded() -> void :
	if not CharacterSpriteLoader.is_loaded():
		CharacterSpriteLoader.load_all_characters()




func _ensure_save_load_menu() -> CanvasLayer:
	if save_load_menu == null:
		save_load_menu = SaveLoadMenuScene.instantiate()
		add_child(save_load_menu)
		save_load_menu.closed.connect(_on_save_load_closed)
		save_load_menu.game_loaded.connect(_on_game_loaded)
	return save_load_menu


func _ensure_api_config_menu() -> CanvasLayer:
	if api_config_menu == null:
		api_config_menu = APIConfigMenuScene.instantiate()
		add_child(api_config_menu)
	return api_config_menu


func _ensure_music_mix_menu() -> CanvasLayer:
	if music_mix_menu == null:
		music_mix_menu = MusicMixMenuScene.instantiate()
		add_child(music_mix_menu)
	return music_mix_menu


func _ensure_schedule_editor_menu() -> CanvasLayer:
	if schedule_editor_menu == null:
		schedule_editor_menu = ScheduleEditorMenuScene.instantiate()
		add_child(schedule_editor_menu)
	return schedule_editor_menu


func _ensure_character_download_menu() -> CanvasLayer:
	if character_download_menu == null:
		_ensure_character_sprites_loaded()
		character_download_menu = CharacterDownloadMenuScene.instantiate()
		add_child(character_download_menu)
	return character_download_menu


func _ensure_location_download_menu() -> CanvasLayer:
	if location_download_menu == null:
		location_download_menu = LocationDownloadMenuScene.instantiate()
		add_child(location_download_menu)
	return location_download_menu


func _ensure_character_browser_menu() -> CanvasLayer:
	if character_browser_menu == null:
		_ensure_character_sprites_loaded()
		character_browser_menu = CharacterBrowserMenuScene.instantiate()
		add_child(character_browser_menu)
	return character_browser_menu


func _ensure_prompt_editor_menu() -> CanvasLayer:
	if prompt_editor_menu == null:
		prompt_editor_menu = PromptEditorMenuScene.instantiate()
		add_child(prompt_editor_menu)
	return prompt_editor_menu


func _ensure_persona_menu() -> CanvasLayer:
	if persona_menu == null:
		persona_menu = PersonaMenuScene.instantiate()
		add_child(persona_menu)
	return persona_menu


func _ensure_story_summary_menu() -> CanvasLayer:
	if story_summary_menu == null:
		story_summary_menu = StorySummaryMenuScene.instantiate()
		add_child(story_summary_menu)
	return story_summary_menu


func _ensure_friendship_journal_menu() -> CanvasLayer:
	if friendship_journal_menu == null:
		friendship_journal_menu = FriendshipJournalMenuScript.new()
		add_child(friendship_journal_menu)
	return friendship_journal_menu


func _ensure_lorebook_editor_menu() -> CanvasLayer:
	if lorebook_editor_menu == null:
		lorebook_editor_menu = LorebookEditorMenuScene.instantiate()
		add_child(lorebook_editor_menu)
	return lorebook_editor_menu


func _ensure_ui_settings_menu() -> CanvasLayer:
	if ui_settings_menu == null:
		ui_settings_menu = UISettingsMenuScene.instantiate()
		add_child(ui_settings_menu)
	return ui_settings_menu


func _ensure_custom_start_menu() -> CanvasLayer:
	if custom_start_menu == null:
		custom_start_menu = CustomStartMenuScene.instantiate()
		add_child(custom_start_menu)
		custom_start_menu.cancelled.connect(_on_custom_start_cancelled)
		custom_start_menu.start_requested.connect(_on_custom_start_requested)
	return custom_start_menu


func _ensure_renpy_import_menu() -> CanvasLayer:
	if renpy_import_menu == null:
		renpy_import_menu = RenpyImportMenuScene.instantiate()
		add_child(renpy_import_menu)
		renpy_import_menu.closed.connect(_on_renpy_import_closed)
		renpy_import_menu.start_requested.connect(_on_renpy_import_requested)
	return renpy_import_menu


func _apply_window_icon() -> void :
	var icon_path: = ContentPaths.get_assets_dir().path_join("ui/main/icon.png")
	if not FileAccess.file_exists(icon_path):
		return
	var image: = Image.load_from_file(icon_path)
	if image != null:
		DisplayServer.set_icon(image)


func _setup_background() -> void :
	if $Background.texture != null:
		return

	var bg_texture: = AssetLoader.load_texture(ContentPaths.get_assets_dir().path_join("ui/main/main.png"))
	if bg_texture:
		$Background.texture = bg_texture


func _setup_music() -> void :
	UISettingsManager.ensure_audio_buses()
	if $BackgroundMusic.bus != StringName(UISettingsManager.AUDIO_MUSIC_BUS_NAME):
		$BackgroundMusic.bus = StringName(UISettingsManager.AUDIO_MUSIC_BUS_NAME)
	if $BackgroundMusic.stream == null:

		var music_stream: = AssetLoader.load_audio(ContentPaths.get_assets_dir().path_join("ui/main/main.mp3"))
		if music_stream:
			$BackgroundMusic.stream = music_stream
	if $BackgroundMusic.stream is AudioStreamMP3:
		($BackgroundMusic.stream as AudioStreamMP3).loop = true
	if $BackgroundMusic.stream:
		$BackgroundMusic.volume_db = -6.0
		if not $BackgroundMusic.playing:
			$BackgroundMusic.play()


func _on_ui_settings_changed() -> void :
	_apply_game_title()


func _apply_game_title() -> void :
	if UISettingsManager == null or not UISettingsManager.has_method("get_game_display_title"):
		return
	var title_label: = get_node_or_null("Title") as Label
	if title_label != null:
		title_label.text = UISettingsManager.get_game_display_title()


func _on_background_music_finished() -> void :
	if not is_in_game and $BackgroundMusic.stream:
		$BackgroundMusic.play()


func _create_button_stylebox(color: Color, corner_radius: int = 6) -> StyleBoxFlat:
	var style: = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0

	style.border_width_top = 1
	style.border_color = Color(1, 1, 1, 0.1)
	return style


func _style_menu_buttons() -> void :
	for child in $MenuButtons.get_children():
		if child is Button:

			child.add_theme_stylebox_override("normal", _create_button_stylebox(BTN_NORMAL_COLOR))
			child.add_theme_stylebox_override("hover", _create_button_stylebox(BTN_HOVER_COLOR))
			child.add_theme_stylebox_override("pressed", _create_button_stylebox(BTN_PRESSED_COLOR))
			child.add_theme_stylebox_override("disabled", _create_button_stylebox(BTN_DISABLED_COLOR))

			child.add_theme_color_override("font_color", BTN_TEXT_COLOR)
			child.add_theme_color_override("font_hover_color", BTN_TEXT_HOVER)
			child.add_theme_color_override("font_pressed_color", BTN_TEXT_HOVER)
			child.add_theme_color_override("font_disabled_color", BTN_TEXT_DISABLED)

			child.add_theme_font_size_override("font_size", 22)
			child.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.25))
			child.add_theme_constant_override("outline_size", 2)
			child.alignment = HORIZONTAL_ALIGNMENT_CENTER


func _apply_responsive_layout() -> void :
	var viewport_size: = get_viewport_rect().size
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		return

	var metrics: = _get_title_menu_layout_metrics(viewport_size)
	var scale_factor: = float(metrics.get("scale", 1.0))



	if OS.has_feature("mobile"):
		var content_scale: float = get_window().content_scale_factor
		if content_scale > 0.0:
			scale_factor = clampf(scale_factor / content_scale, TITLE_MENU_MIN_SCALE_MOBILE, 1.0)
			metrics = _get_title_menu_layout_metrics(viewport_size, scale_factor)
	var min_button_font_size: = 18
	if OS.has_feature("mobile"):
		min_button_font_size = 14

	var title_font_size: = maxi(44, int(round(72.0 * scale_factor)))
	var version_font_size: = maxi(14, int(round(20.0 * scale_factor)))
	$Title.add_theme_font_size_override("font_size", title_font_size)
	$Version.add_theme_font_size_override("font_size", version_font_size)

	var menu_left: float = float(metrics.get("left", 48.0))
	var menu_width: float = float(metrics.get("width", TITLE_MENU_BASE_BUTTON_SIZE.x))
	var menu_height: float = float(metrics.get("height", 400.0))
	$MenuButtons.offset_left = menu_left
	$MenuButtons.offset_right = menu_left + menu_width
	$MenuButtons.offset_top = round( - menu_height * 0.5)
	$MenuButtons.offset_bottom = round(menu_height * 0.5)
	$MenuButtons.add_theme_constant_override("separation", int(metrics.get("separation", TITLE_MENU_BASE_SEPARATION)))

	var button_size: = Vector2(menu_width, float(metrics.get("button_height", TITLE_MENU_BASE_BUTTON_SIZE.y)))
	var button_font_size: = maxi(min_button_font_size, int(round(22.0 * scale_factor)))
	for child in $MenuButtons.get_children():
		if child is Button:
			child.custom_minimum_size = button_size
			child.add_theme_font_size_override("font_size", button_font_size)



			var font_height: float = child.get_theme_font("font").get_height(button_font_size)
			var padding: = maxf(0.0, floor((button_size.y - font_height) * 0.5))
			for state in ["normal", "hover", "pressed", "disabled"]:
				var style: StyleBoxFlat = child.get_theme_stylebox(state)
				style.content_margin_top = padding
				style.content_margin_bottom = padding
		elif child is HSeparator:
			child.add_theme_constant_override("separation", int(metrics["separator_height"]))


	menu_height = $MenuButtons.get_combined_minimum_size().y
	$MenuButtons.offset_top = round( - menu_height * 0.5)
	$MenuButtons.offset_bottom = round(menu_height * 0.5)


func _get_title_menu_layout_metrics(viewport_size: Vector2, forced_scale: float = -1.0) -> Dictionary:
	var child_count: = 0
	var button_count: = 0
	var separator_count: = 0
	if has_node("MenuButtons"):
		for child in $MenuButtons.get_children():
			if child is Control and (child as Control).visible:
				child_count += 1
				if child is Button:
					button_count += 1
				elif child is HSeparator:
					separator_count += 1
	if child_count <= 0:
		child_count = 1
	if button_count <= 0:
		button_count = 1

	var mobile: = OS.has_feature("mobile")
	var min_scale: = TITLE_MENU_MIN_SCALE_MOBILE if mobile else TITLE_MENU_MIN_SCALE_DESKTOP
	var scale_factor: = forced_scale
	if scale_factor <= 0.0:
		scale_factor = clampf(
			minf(viewport_size.x / TITLE_MENU_BASE_SIZE.x, viewport_size.y / TITLE_MENU_BASE_SIZE.y), 
			min_scale, 
			1.0
		)

	var min_button_height: = TITLE_MENU_MIN_BUTTON_HEIGHT_MOBILE if mobile else TITLE_MENU_MIN_BUTTON_HEIGHT_DESKTOP
	var button_height: = maxf(min_button_height, round(TITLE_MENU_BASE_BUTTON_SIZE.y * scale_factor))
	var separation: = maxf(4.0, round(TITLE_MENU_BASE_SEPARATION * scale_factor))
	var separator_height: = maxf(2.0, round(TITLE_MENU_SEPARATOR_HEIGHT * scale_factor))
	var menu_height: = _calculate_title_menu_height(button_count, separator_count, child_count, button_height, separator_height, separation)
	var max_menu_height: = maxf(220.0, viewport_size.y - TITLE_MENU_VIEWPORT_MARGIN.y * 2.0)
	if menu_height > max_menu_height:
		var fixed_height: = separator_count * separator_height + maxi(0, child_count - 1) * separation
		var available_button_height: = maxf(0.0, max_menu_height - fixed_height)
		button_height = maxf(24.0, floor(available_button_height / float(button_count)))
		menu_height = _calculate_title_menu_height(button_count, separator_count, child_count, button_height, separator_height, separation)
		scale_factor = minf(scale_factor, button_height / TITLE_MENU_BASE_BUTTON_SIZE.y)

	var menu_width: = clampf(
		round(TITLE_MENU_BASE_BUTTON_SIZE.x * scale_factor), 
		minf(TITLE_MENU_MIN_BUTTON_WIDTH, maxf(160.0, viewport_size.x - TITLE_MENU_VIEWPORT_MARGIN.x * 2.0)), 
		TITLE_MENU_BASE_BUTTON_SIZE.x
	)
	var menu_left: = maxf(TITLE_MENU_VIEWPORT_MARGIN.x, round(48.0 * scale_factor))
	return {
		"scale": scale_factor, 
		"left": menu_left, 
		"width": menu_width, 
		"height": menu_height, 
		"button_height": button_height, 
		"separation": int(separation), 
		"separator_height": separator_height, 
	}


func _calculate_title_menu_height(
	button_count: int, 
	separator_count: int, 
	child_count: int, 
	button_height: float, 
	separator_height: float, 
	separation: float
) -> float:
	return (
		button_count * button_height
		+ separator_count * separator_height
		+ maxi(0, child_count - 1) * separation
	)


func _has_selectable_scenarios() -> bool:
	return ScenarioManager != null and not ScenarioManager.list_scenarios().is_empty()


func _on_new_game_pressed() -> void :
	if not _has_selectable_scenarios():
		_on_scenario_selected("base")
		return





	var panel: CanvasLayer = ScenarioSelectPanelScene.instantiate()
	panel.confirmed.connect(_on_scenario_selected)
	panel.cancelled.connect(_on_scenario_select_cancelled)
	if panel.has_method("set_context_label"):
		panel.set_context_label("New Game")
	add_child(panel)










func open_scenario_customs_menu() -> void :
	if scenario_customs_menu != null and is_instance_valid(scenario_customs_menu):
		return
	scenario_customs_menu = ScenarioAllowlistMenuScene.instantiate()
	scenario_customs_menu.tree_exited.connect(_on_scenario_customs_menu_closed)
	add_child(scenario_customs_menu)


func _on_scenario_customs_menu_closed() -> void :
	scenario_customs_menu = null


func open_character_browser_menu() -> void :
	var menu: = _ensure_character_browser_menu()
	if menu.visible:
		return
	menu.open()


func _on_scenario_select_cancelled() -> void :

	pass


func _on_scenario_selected(scenario_id: String) -> void :



	_reset_for_fresh_start()
	if ScenarioManager != null:
		ScenarioManager.set_active_scenario(scenario_id)
	_hide_menu()
	_setup_game_ui()

	var start_timeline: = "everfree_intro"
	if ScenarioManager != null:
		start_timeline = ScenarioManager.prepare_active_start_timeline()
	Dialogic.start(start_timeline)
	if ScenarioManager == null or ScenarioManager.should_chain_start_timeline_to_library(start_timeline):
		Dialogic.timeline_ended.connect(_on_everfree_intro_ended, CONNECT_ONE_SHOT)


func _on_everfree_intro_ended() -> void :
	Dialogic.start("library_scene")







func disconnect_intro_chain_hook() -> void :
	if Dialogic.timeline_ended.is_connected(_on_everfree_intro_ended):
		Dialogic.timeline_ended.disconnect(_on_everfree_intro_ended)


func _on_quick_start_pressed() -> void :
	if not APIConfigManager.is_configured():
		open_api_settings_menu()
		return
	if not _has_selectable_scenarios():
		_show_quick_start_confirm("base")
		return
	var panel: CanvasLayer = ScenarioSelectPanelScene.instantiate()
	panel.confirmed.connect(_on_quick_start_scenario_selected)
	panel.cancelled.connect(_on_scenario_select_cancelled)
	if panel.has_method("set_context_label"):
		panel.set_context_label("Quick Start")
	add_child(panel)


func _on_quick_start_scenario_selected(scenario_id: String) -> void :
	_show_quick_start_confirm(scenario_id)


func _show_quick_start_confirm(scenario_id: String = "base") -> void :
	var selected_date: = {
		"year": CalendarManager.DEFAULT_START_YEAR, 
		"month": CalendarManager.DEFAULT_START_MONTH, 
		"day": CalendarManager.DEFAULT_START_DAY, 
	}


	var overlay: = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var fade_tween: = create_tween()
	fade_tween.tween_property(overlay, "color:a", 0.6, 0.2)


	var panel: = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(460, 0)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -230
	panel.offset_right = 230
	panel.offset_top = -145
	panel.offset_bottom = 145
	var panel_style: = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.12, 0.18, 0.95)
	panel_style.border_color = Color(0.25, 0.35, 0.5, 0.6)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(12)
	panel_style.content_margin_left = 28
	panel_style.content_margin_right = 28
	panel_style.content_margin_top = 24
	panel_style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", panel_style)
	overlay.add_child(panel)

	var vbox: = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)


	var title: = Label.new()
	title.text = "Ready to Start?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	vbox.add_child(title)

	var mode_label: = Label.new()
	mode_label.text = "Choose whether to play the opening scene or begin directly on the map."
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_label.add_theme_font_size_override("font_size", 13)
	mode_label.add_theme_color_override("font_color", Color(0.62, 0.7, 0.84))
	vbox.add_child(mode_label)


	var date_label: = Label.new()
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	date_label.add_theme_font_size_override("font_size", 16)
	date_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
	vbox.add_child(date_label)


	var update_date_label: = func() -> void :
		var y: = int(selected_date.get("year", 1002))
		var m: = int(selected_date.get("month", 1))
		var d: = int(selected_date.get("day", 1))
		var weekday_name: = CalendarManager.get_weekday_name(CalendarManager.get_weekday_for_date(y, m, d))
		date_label.text = "%s, %s %d, %d" % [weekday_name, CalendarManager.get_month_name(m), d, y]
	update_date_label.call()


	var btn_row: = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)


	var change_btn: = Button.new()
	change_btn.text = "Change Date"
	change_btn.custom_minimum_size = Vector2(120, 38)
	change_btn.add_theme_font_size_override("font_size", 14)
	_apply_popup_button_style(change_btn, BTN_NORMAL_COLOR, BTN_HOVER_COLOR, BTN_PRESSED_COLOR)
	btn_row.add_child(change_btn)


	var start_btn: = Button.new()
	start_btn.text = "Start with Intro"
	start_btn.custom_minimum_size = Vector2(145, 38)
	start_btn.add_theme_font_size_override("font_size", 14)
	_apply_popup_button_style(start_btn, Color(0.15, 0.35, 0.2, 0.9), Color(0.2, 0.45, 0.28, 0.95), Color(0.25, 0.5, 0.32, 1.0))
	btn_row.add_child(start_btn)


	var skip_intro_btn: = Button.new()
	skip_intro_btn.text = "Skip Intro"
	skip_intro_btn.custom_minimum_size = Vector2(120, 38)
	skip_intro_btn.add_theme_font_size_override("font_size", 14)
	_apply_popup_button_style(skip_intro_btn, Color(0.22, 0.25, 0.36, 0.9), Color(0.3, 0.34, 0.48, 0.95), Color(0.36, 0.4, 0.56, 1.0))
	btn_row.add_child(skip_intro_btn)


	var cancel_btn: = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.flat = true
	cancel_btn.add_theme_font_size_override("font_size", 13)
	cancel_btn.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	cancel_btn.add_theme_color_override("font_hover_color", Color(0.75, 0.8, 0.9))
	vbox.add_child(cancel_btn)


	var calendar_popup: CalendarPopup = null


	change_btn.pressed.connect( func():
		if calendar_popup == null:
			calendar_popup = CalendarPopup.new()
			calendar_popup.date_selected.connect( func(date_dict: Dictionary):
				selected_date.clear()
				selected_date.merge(date_dict)
				update_date_label.call()
			)
			add_child(calendar_popup)
		calendar_popup.open_select_mode(true, selected_date)
	)

	var begin_quick_start: = func(play_intro: bool) -> void :
		CalendarManager.pending_start_date = selected_date.duplicate(true)
		overlay.queue_free()
		if calendar_popup != null:
			calendar_popup.queue_free()
		_reset_for_fresh_start()
		if ScenarioManager != null:
			ScenarioManager.set_active_scenario(scenario_id)

		CalendarManager.set_date(
			int(selected_date.get("year", CalendarManager.DEFAULT_START_YEAR)), 
			int(selected_date.get("month", CalendarManager.DEFAULT_START_MONTH)), 
			int(selected_date.get("day", CalendarManager.DEFAULT_START_DAY)), 
			true
		)
		_hide_menu()
		_setup_game_ui()
		if play_intro:
			var quick_start_timeline: = "quick_start"
			if ScenarioManager != null:
				quick_start_timeline = ScenarioManager.prepare_active_quick_start_timeline()
			Dialogic.start(quick_start_timeline)
			return
		MapManager.complete_quick_start()


	start_btn.pressed.connect( func(): begin_quick_start.call(true))
	skip_intro_btn.pressed.connect( func(): begin_quick_start.call(false))


	var close: = func():
		overlay.queue_free()
		if calendar_popup != null:
			calendar_popup.queue_free()
	cancel_btn.pressed.connect(close)
	overlay.gui_input.connect( func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			var panel_rect: = panel.get_global_rect()
			if not panel_rect.has_point(event.global_position):
				close.call()
	)


func _apply_popup_button_style(btn: Button, normal: Color, hover: Color, pressed: Color) -> void :
	btn.add_theme_stylebox_override("normal", _create_button_stylebox(normal, 8))
	btn.add_theme_stylebox_override("hover", _create_button_stylebox(hover, 8))
	btn.add_theme_stylebox_override("pressed", _create_button_stylebox(pressed, 8))
	btn.add_theme_color_override("font_color", BTN_TEXT_COLOR)
	btn.add_theme_color_override("font_hover_color", BTN_TEXT_HOVER)


func _on_custom_start_pressed() -> void :
	if not APIConfigManager.is_configured():
		open_api_settings_menu()
		return
	if not _has_selectable_scenarios():
		_open_custom_start_for_scenario("base")
		return
	var panel: CanvasLayer = ScenarioSelectPanelScene.instantiate()
	panel.confirmed.connect(_on_custom_start_scenario_selected)
	panel.cancelled.connect(_on_scenario_select_cancelled)
	if panel.has_method("set_context_label"):
		panel.set_context_label("Custom Start")
	add_child(panel)


func _on_custom_start_scenario_selected(scenario_id: String) -> void :
	_open_custom_start_for_scenario(scenario_id)


func _open_custom_start_for_scenario(scenario_id: String) -> void :
	var selected_scenario_id: = _normalize_start_scenario_id(scenario_id)
	_custom_start_restore_scenario_id = ScenarioManager.get_active_scenario_id() if ScenarioManager != null else "base"
	_custom_start_preview_active = true
	_reset_for_fresh_start()
	if ScenarioManager != null:
		ScenarioManager.set_active_scenario(selected_scenario_id)
	_ensure_character_sprites_loaded()
	var menu: = _ensure_custom_start_menu()
	if menu.has_method("open"):
		menu.open(selected_scenario_id)


func _on_custom_start_cancelled() -> void :
	if not _custom_start_preview_active:
		return
	var restore_id: = _custom_start_restore_scenario_id
	_custom_start_preview_active = false
	_custom_start_restore_scenario_id = "base"
	if ScenarioManager != null:
		ScenarioManager.set_active_scenario(_normalize_start_scenario_id(restore_id))


func _on_renpy_import_pressed() -> void :
	if not _has_selectable_scenarios():
		_open_renpy_import_for_scenario("base")
		return
	var panel: CanvasLayer = ScenarioSelectPanelScene.instantiate()
	panel.confirmed.connect(_on_renpy_import_scenario_selected)
	panel.cancelled.connect(_on_scenario_select_cancelled)
	if panel.has_method("set_context_label"):
		panel.set_context_label("Import Log")
	add_child(panel)


func _on_renpy_import_scenario_selected(scenario_id: String) -> void :
	_open_renpy_import_for_scenario(scenario_id)


func _open_renpy_import_for_scenario(scenario_id: String) -> void :
	var selected_scenario_id: = _normalize_start_scenario_id(scenario_id)
	_renpy_import_restore_scenario_id = ScenarioManager.get_active_scenario_id() if ScenarioManager != null else "base"
	_renpy_import_preview_active = true
	_reset_for_fresh_start()
	if ScenarioManager != null:
		ScenarioManager.set_active_scenario(selected_scenario_id)
	_ensure_renpy_import_menu().open(selected_scenario_id)


func _on_renpy_import_closed() -> void :
	if not _renpy_import_preview_active:
		return
	var restore_id: = _renpy_import_restore_scenario_id
	_renpy_import_preview_active = false
	_renpy_import_restore_scenario_id = "base"
	if ScenarioManager != null:
		ScenarioManager.set_active_scenario(_normalize_start_scenario_id(restore_id))


func _on_save_load_pressed() -> void :
	_ensure_save_load_menu().open_load_menu()


func _on_api_settings_pressed() -> void :
	_ensure_api_config_menu().open()


func _on_ui_settings_pressed() -> void :
	open_ui_settings_menu()


func _on_music_mix_pressed() -> void :
	_ensure_music_mix_menu().open()


func _on_community_chars_pressed() -> void :
	_ensure_character_download_menu().open()


func _on_community_locations_pressed() -> void :
	_ensure_location_download_menu().open()


func _on_character_browser_pressed() -> void :
	open_character_browser_menu()


func _on_prompt_editor_pressed() -> void :
	_ensure_prompt_editor_menu().open()


func _on_lorebook_pressed() -> void :
	open_lorebook_editor_menu()


func _on_persona_pressed() -> void :
	open_persona_menu()


func _on_quit_pressed() -> void :
	get_tree().quit()


func _on_game_loaded() -> void :
	_hide_menu()
	if friendship_journal_menu and friendship_journal_menu.visible:
		friendship_journal_menu._close()
	_setup_game_ui()
	if rollback_history and rollback_history.has_method("ensure_navigation_buttons"):
		rollback_history.ensure_navigation_buttons()


func _on_save_load_closed() -> void :
	if not is_in_game:
		_show_menu()


func _setup_game_ui() -> void :
	is_in_game = true


	if rollback_history == null:
		rollback_history = RollbackHistoryScene.instantiate()
		add_child(rollback_history)


func _hide_menu() -> void :
	$Background.hide()
	$MenuButtons.hide()
	$Title.hide()
	$Version.hide()

	_fade_out_menu_music()


func _show_menu() -> void :
	$Background.show()
	$MenuButtons.show()
	$Title.show()
	$Version.show()

	if Dialogic.has_subsystem("Styles") and Dialogic.Styles.has_active_layout_node():
		Dialogic.Styles.get_layout_node().hide()
	_stop_game_audio()
	if menu_music_tween:
		menu_music_tween.kill()
		menu_music_tween = null

	$BackgroundMusic.volume_db = -6.0
	if not $BackgroundMusic.playing:
		$BackgroundMusic.play()


func _fade_out_menu_music() -> void :
	if menu_music_tween:
		menu_music_tween.kill()
	menu_music_tween = create_tween()
	menu_music_tween.tween_property($BackgroundMusic, "volume_db", -40.0, 1.5)
	menu_music_tween.tween_callback($BackgroundMusic.stop)
	menu_music_tween.tween_callback( func(): $BackgroundMusic.volume_db = -6.0)
	menu_music_tween.finished.connect( func(): menu_music_tween = null, CONNECT_ONE_SHOT)


func _stop_game_audio() -> void :
	MapManager.stop_map_music()
	if Dialogic.has_subsystem("Audio"):
		Dialogic.Audio.stop_all_channels(0.0)


func _on_timeline_ended() -> void :
	Log.d("Main", "Timeline ended - is_in_game=%s, map_open=%s, mode=%s" % [is_in_game, MapManager.is_map_open(), GameState.current_mode])

	if not is_in_game:
		Log.d("Main", "Not in game, ignoring timeline end")
		return

	if MapManager.is_map_open():
		Log.d("Main", "Map is open, not showing menu")
		return

	if GameState.current_mode == GameState.Mode.STORY or GameState.current_mode == GameState.Mode.SANDBOX:
		Log.d("Main", "In story/sandbox mode, not showing menu")
		return

	Log.d("Main", "Showing menu after timeline end")
	is_in_game = false
	_show_menu()

	if rollback_history:
		rollback_history.queue_free()
		rollback_history = null


func _on_map_opened() -> void :
	Log.d("Main", "Map opened - hiding menu")
	_hide_menu()
	is_in_game = true


func _on_map_closed() -> void :
	Log.d("Main", "Map closed - keeping menu hidden for location visit")
	_hide_menu()


func _input(event: InputEvent) -> void :
	if not is_in_game:
		return

	if event is InputEventKey and event.pressed and not event.echo:






		if _is_scenario_customs_menu_visible():
			return
		if event.keycode == KEY_F5 and (save_load_menu == null or not save_load_menu.visible):
			_ensure_save_load_menu()
			_open_save_menu_with_thumbnail()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F9 and (save_load_menu == null or not save_load_menu.visible):
			_ensure_save_load_menu().open_load_menu()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F8:



			open_scenario_customs_menu()
			get_viewport().set_input_as_handled()


func _is_scenario_customs_menu_visible() -> bool:
	return scenario_customs_menu != null and is_instance_valid(scenario_customs_menu)


func _open_save_menu_with_thumbnail() -> void :
	Dialogic.Save.take_thumbnail()
	_ensure_save_load_menu().open_save_menu()


func open_save_menu() -> void :
	_open_save_menu_with_thumbnail()


func open_load_menu() -> void :
	_ensure_save_load_menu().open_load_menu()


func open_api_settings_menu(layer_override: int = API_CONFIG_DEFAULT_LAYER) -> void :
	var menu: = _ensure_api_config_menu()
	menu.layer = layer_override
	menu.open()


func open_music_mix_menu() -> void :
	_ensure_music_mix_menu().open()


func open_ui_settings_menu() -> void :
	_ensure_ui_settings_menu().open()


func open_prompt_editor_menu() -> void :
	_ensure_prompt_editor_menu().open()


func open_persona_menu() -> void :
	_ensure_persona_menu().open()


func open_story_summary_menu() -> void :
	_ensure_story_summary_menu().open()


func open_friendship_journal() -> void :
	_ensure_friendship_journal_menu().open()


func open_lorebook_editor_menu(show_active_only: bool = false) -> void :
	_ensure_lorebook_editor_menu().open(show_active_only)


func _on_custom_start_requested(config: Dictionary) -> void :
	if is_in_game or AIStateCoordinator.is_active():
		push_warning("[Main] Ignoring custom start request while a game session is already active")
		return
	if not APIConfigManager.is_configured():
		open_api_settings_menu()
		return
	var scenario_id: = _normalize_start_scenario_id(str(config.get("scenario_id", ScenarioManager.BASE_SCENARIO_ID if ScenarioManager != null else "base")))
	var start_config: = config.duplicate(true)
	start_config["scenario_id"] = scenario_id
	_custom_start_preview_active = false
	_custom_start_restore_scenario_id = "base"


	_reset_for_fresh_start()
	if ScenarioManager != null:
		ScenarioManager.set_active_scenario(scenario_id)
	_hide_menu()
	_setup_game_ui()
	MapManager.start_custom_start(start_config)


func _normalize_start_scenario_id(scenario_id: String) -> String:
	var normalized: = scenario_id.strip_edges()
	if normalized.is_empty() or normalized == "base" or ScenarioManager == null:
		return "base"
	return normalized if ScenarioManager.has_scenario(normalized) else "base"


func _on_renpy_import_requested(config: Dictionary) -> void :
	if is_in_game or AIStateCoordinator.is_active():
		push_warning("[Main] Ignoring external context import request while a game session is already active")
		return
	if not APIConfigManager.is_configured():
		open_api_settings_menu()
		return

	var scenario_id: = _normalize_start_scenario_id(str(config.get("scenario_id", ScenarioManager.BASE_SCENARIO_ID if ScenarioManager != null else "base")))
	var import_config: = config.duplicate(true)
	import_config["scenario_id"] = scenario_id


	var previous_restore_scenario_id: = _renpy_import_restore_scenario_id
	_renpy_import_preview_active = false
	_renpy_import_restore_scenario_id = "base"
	_reset_for_fresh_start()
	if ScenarioManager != null:
		ScenarioManager.set_active_scenario(scenario_id)
	var import_result: = StorySummaryManager.import_external_context_file(
		str(import_config.get("import_path", "")), 
		str(import_config.get("import_source_label", "External story import"))
	)
	if not bool(import_result.get("ok", false)):
		var error_message: = "Import failed: %s" % str(import_result.get("error", "Unknown import error"))
		push_warning("[Main] External context import failed: %s" % error_message)
		_renpy_import_preview_active = true
		_renpy_import_restore_scenario_id = previous_restore_scenario_id
		_ensure_renpy_import_menu().open_with_config(import_config, error_message)
		return

	_hide_menu()
	_setup_game_ui()
	_start_imported_sandbox(import_config)


func open_schedule_editor_menu() -> void :
	_ensure_schedule_editor_menu().open()


func return_to_main_menu() -> void :
	preload("res://scripts/ui/return_to_menu_confirmation.gd").request(self, _return_to_main_menu_confirmed)


func _return_to_main_menu_confirmed() -> void :
	disconnect_intro_chain_hook()
	MapManager.prepare_for_load()
	AIStateCoordinator.reset()
	MapManager.finalize_after_load()

	if MapManager.is_map_open():
		MapManager.close_map()

	_reset_dialogue_session()

	_stop_game_audio()

	Dialogic.paused = false
	if DialogicUtil.autoload():
		DialogicUtil.autoload().paused = false
		var inputs: Node = DialogicUtil.autoload().get("Inputs") as Node
		if inputs:
			inputs.action_was_consumed = false
			if inputs.has_method("stop_timers"):
				inputs.stop_timers()

	if save_load_menu and save_load_menu.visible:
		save_load_menu.hide()

	if api_config_menu and api_config_menu.visible:
		api_config_menu.hide()

	if prompt_editor_menu and prompt_editor_menu.visible:
		prompt_editor_menu.hide()

	if story_summary_menu and story_summary_menu.visible:
		story_summary_menu.hide()

	if persona_menu and persona_menu.visible:
		persona_menu.hide()

	if ui_settings_menu and ui_settings_menu.visible:
		ui_settings_menu.hide()

	if custom_start_menu and custom_start_menu.visible:
		custom_start_menu.hide()

	if renpy_import_menu and renpy_import_menu.visible:
		renpy_import_menu.hide()

	if schedule_editor_menu and schedule_editor_menu.visible:
		schedule_editor_menu.hide()

	for node in get_tree().get_nodes_in_group("ui_blocking_overlay"):
		if node and node.is_inside_tree():
			if node.has_method("hide"):
				node.hide()
			elif node.has_method("set"):
				node.set("visible", false)
	if Dialogic.has_subsystem("Styles") and Dialogic.Styles.has_active_layout_node():
		Dialogic.Styles.get_layout_node().hide()

	RollbackManager.clear_snapshots()
	is_in_game = false
	_show_menu()

	if rollback_history:
		rollback_history.queue_free()
		rollback_history = null

	if music_switcher:
		music_switcher.hide_switcher()
	if lorebook_activity_indicator:
		lorebook_activity_indicator.hide_indicator()


func _reset_dialogue_session() -> void:
	# Title and New Game share the main scene. Retire the old layout immediately
	# so restored AI controls, textbox offsets and ending fades cannot be reused.
	preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree()).cancel_preparation()
	Dialogic.paused = false
	for key in ["_skip_call_event_execution", "_block_call_event"]:
		if Dialogic.has_meta(key):
			Dialogic.remove_meta(key)
	Dialogic.clear()
	var layout: Node = Dialogic.Styles.get_layout_node()
	if is_instance_valid(layout):
		layout.hide()
		if layout.get_parent() != null:
			layout.get_parent().remove_child(layout)
		layout.queue_free()
	if get_tree().has_meta("dialogic_layout_node"):
		get_tree().remove_meta("dialogic_layout_node")
	Dialogic.Inputs.action_was_consumed = false
	Dialogic.Inputs.stop_timers()


func _reset_for_fresh_start() -> void :
	disconnect_intro_chain_hook()
	MapManager.prepare_for_load()
	AIStateCoordinator.reset()
	MapManager.finalize_after_load()
	GameState.reset()
	RollbackManager.clear_snapshots()

	if MapManager.is_map_open():
		MapManager.close_map()

	_reset_dialogue_session()

	if Dialogic.has_subsystem("Audio"):
		Dialogic.Audio.stop_all_channels(0.0)
	if Dialogic.has_subsystem("Text"):
		Dialogic.Text.hide_textbox()
	if Dialogic.has_subsystem("Portraits"):
		Dialogic.Portraits.leave_all_characters("", 0.0, false)
	if Dialogic.has_subsystem("Backgrounds") and Dialogic.Backgrounds.has_background():
		Dialogic.Backgrounds.update_background("", "", 0.0)
	if Dialogic.has_subsystem("History"):
		Dialogic.History.simple_history_content.clear()
	if Dialogic.VAR != null:
		Dialogic.VAR.reset()

	Dialogic.paused = false
	if DialogicUtil.autoload():
		DialogicUtil.autoload().paused = false


func _start_imported_sandbox(config: Dictionary) -> void :
	GameState.enter_sandbox_mode()
	GameState.owns_house = bool(config.get("owns_house", false))
	if bool(config.get("suppress_house_offer", false)):
		GameState.house_offer_shown = true
	GameState.current_time_slot = 0
	GameState.daily_visits = 0
	GameState.current_region = "Ponyville"
	_apply_imported_night_residence_config(config)
	CalendarManager.set_date(
		int(config.get("year", CalendarManager.DEFAULT_START_YEAR)), 
		int(config.get("month", CalendarManager.DEFAULT_START_MONTH)), 
		int(config.get("day", CalendarManager.DEFAULT_START_DAY)), 
		true
	)
	if Dialogic.VAR != null:
		Dialogic.VAR.set_variable("is_human", true)
	_ensure_dialogic_layout_for_imported_sandbox()
	MapManager.clear_pending_visit()
	MapManager.set_current_scene(null, [])
	MapManager.set_current_region("Ponyville")
	MapManager.open_map()
	AutosaveManager.request_autosave("renpy_import")


func _ensure_dialogic_layout_for_imported_sandbox() -> void :
	if not Dialogic.has_subsystem("Styles"):
		return
	if not Dialogic.Styles.has_active_layout_node():
		Dialogic.Styles.load_style()


func _apply_imported_night_residence_config(config: Dictionary) -> void :
	var candidate_ids: Array[String] = []
	if SleepoverSystem != null and SleepoverSystem.has_method("get_all_hosted_residence_candidate_ids"):
		candidate_ids = SleepoverSystem.get_all_hosted_residence_candidate_ids()
	for location_id in candidate_ids:
		GameState.unlock_night_residence(location_id)

	var requested_mode: = str(config.get("night_residence_mode", "")).strip_edges()
	var requested_location_id: = str(config.get("night_residence_location_id", "")).strip_edges()
	var applied: = false
	if not requested_mode.is_empty():
		applied = GameState.set_night_residence(requested_mode, requested_location_id)

	if applied:
		return
	if GameState.owns_house:
		GameState.set_night_residence(GameState.NIGHT_RESIDENCE_MODE_OWN_HOUSE)
	else:
		GameState.set_night_residence(GameState.NIGHT_RESIDENCE_MODE_LIBRARY)

extends CanvasLayer


const TouchScrollGesture: = preload("res://scripts/ui/touch_scroll_gesture.gd")

const PANEL_COLOR: = Color(0.07, 0.11, 0.17, 0.98)
const PANEL_BORDER: = Color(0.31, 0.46, 0.62, 1.0)
const SECTION_COLOR: = Color(0.11, 0.16, 0.23, 0.96)
const SECTION_BORDER: = Color(0.24, 0.35, 0.49, 0.9)
const HEADER_COLOR: = Color(0.14, 0.2, 0.29, 0.98)
const HEADER_HOVER: = Color(0.19, 0.27, 0.38, 1.0)
const TEXT_MAIN: = Color(0.92, 0.96, 1.0)
const TEXT_MUTED: = Color(0.68, 0.77, 0.88)
const TEXT_ACCENT: = Color(1.0, 0.84, 0.44)
const PANEL_TARGET_SIZE: = Vector2(1040, 780)
const PANEL_VIEWPORT_MARGIN: = Vector2(48, 48)

var _input_blocker: Control
var _voice_options: Node
var _dimmer: ColorRect
var _panel: PanelContainer
var _game_title_option: OptionButton
var _language_option: OptionButton
var _story_language_option: OptionButton
var _window_mode_option: OptionButton
var _resolution_option: OptionButton
var _vsync_check: CheckBox
var _foregrounds_enabled_check: CheckBox
var _music_volume_slider: HSlider
var _music_volume_label: Label
var _music_mute_button: Button
var _sfx_volume_slider: HSlider
var _sfx_volume_label: Label
var _sfx_mute_button: Button
var _width_spinbox: SpinBox
var _height_spinbox: SpinBox
var _dialogue_text_size_slider: HSlider
var _dialogue_text_size_label: Label
var _dialogue_reveal_speed_slider: HSlider
var _dialogue_reveal_speed_label: Label
var _typing_sounds_enabled_check: CheckBox
var _typing_sounds_path_edit: LineEdit
var _typing_sounds_volume_slider: HSlider
var _typing_sounds_volume_label: Label
var _storage_path_edit: LineEdit
var _storage_summary_label: Label
var _storage_details_toggle: Button
var _storage_details_box: GridContainer
var _storage_default_label: Label
var _storage_saves_label: Label
var _storage_logs_label: Label
var _storage_exports_label: Label
var _storage_vignettes_label: Label
var _storage_scenarios_label: Label
var _storage_lorebooks_label: Label
var _storage_persona_label: Label
var _storage_file_dialog: FileDialog
var _ai_notify_flash_check: CheckBox
var _ai_notify_sound_check: CheckBox
var _ai_reply_autosave_option: OptionButton
var _qa_pass_time_check: CheckBox
var _qa_guidance_check: CheckBox
var _qa_dice_panel_check: CheckBox
var _menu_scale_slider: HSlider
var _menu_scale_label: Label
var _mobile_scale_slider: HSlider
var _mobile_scale_label: Label
var _desktop_scale_slider: HSlider
var _box_fill_picker: ColorPickerButton
var _box_outline_picker: ColorPickerButton
var _main_button_label_edit: LineEdit
var _main_button_fill_picker: ColorPickerButton
var _main_button_outline_picker: ColorPickerButton
var _main_button_text_picker: ColorPickerButton
var _dice_button_label_edit: LineEdit
var _dice_button_fill_picker: ColorPickerButton
var _dice_button_outline_picker: ColorPickerButton
var _dice_button_text_picker: ColorPickerButton
var _roster_button_label_edit: LineEdit
var _roster_button_fill_picker: ColorPickerButton
var _roster_button_outline_picker: ColorPickerButton
var _roster_button_text_picker: ColorPickerButton
var _location_button_label_edit: LineEdit
var _location_button_fill_picker: ColorPickerButton
var _location_button_outline_picker: ColorPickerButton
var _location_button_text_picker: ColorPickerButton
var _map_menu_fill_picker: ColorPickerButton
var _map_menu_outline_picker: ColorPickerButton
var _map_menu_text_picker: ColorPickerButton
var _map_popup_fill_picker: ColorPickerButton
var _map_popup_outline_picker: ColorPickerButton
var _map_popup_text_picker: ColorPickerButton
var _solo_scale_slider: HSlider
var _solo_scale_label: Label
var _duo_scale_slider: HSlider
var _duo_scale_label: Label
var _trio_scale_slider: HSlider
var _trio_scale_label: Label
var _quartet_scale_slider: HSlider
var _quartet_scale_label: Label
var _quintet_scale_slider: HSlider
var _quintet_scale_label: Label
var _sextet_scale_slider: HSlider
var _sextet_scale_label: Label
var _status_label: Label
var _original_music_volume: float = UISettingsManager.DEFAULT_MUSIC_VOLUME
var _original_sfx_volume: float = UISettingsManager.DEFAULT_SFX_VOLUME
var _original_music_muted: bool = UISettingsManager.DEFAULT_MUSIC_MUTED
var _original_sfx_muted: bool = UISettingsManager.DEFAULT_SFX_MUTED
var _original_window_mode: int = UISettingsManager.DEFAULT_WINDOW_MODE
var _original_resolution: Vector2i = UISettingsManager.DEFAULT_RESOLUTION
var _original_vsync: bool = UISettingsManager.DEFAULT_VSYNC

var _color_section_buttons: Dictionary = {}
var _dialogue_control_fields: Dictionary = {}
var _color_section_bodies: Dictionary = {}

var _color_section_titles: = {
	"box": "Dialogue Box", 
	"ask": "Ask Button", 
	"dice": "Launch Dice", 
	"roster": "Manual Roster", 
	"location": "Manual Location", 
	"map_menu": "Map Menu", 
	"map_popup": "Map Popups", 
}
var _color_section_open: = {
	"box": true, 
	"ask": false, 
	"dice": false, 
	"roster": false, 
	"location": false, 
	"map_menu": false, 
	"map_popup": false, 
}


var _dialogic_pause_guard: DialogicPauseGuard = null


func _ready() -> void :
	hide()
	_build_ui()
	get_viewport().size_changed.connect(_layout_panel_for_viewport)


func open() -> void :
	_voice_options.refresh()
	_original_music_volume = UISettingsManager.get_music_volume()
	_original_sfx_volume = UISettingsManager.get_sfx_volume()
	_original_music_muted = UISettingsManager.is_music_muted()
	_original_sfx_muted = UISettingsManager.is_sfx_muted()
	_original_window_mode = UISettingsManager.get_window_mode()
	_original_resolution = UISettingsManager.get_resolution()
	_original_vsync = UISettingsManager.get_vsync()
	_load_from_config()
	_status_label.text = ""
	_layout_panel_for_viewport()
	show()
	_input_blocker.visible = true
	_dimmer.visible = true
	_panel.visible = true
	_dialogic_pause_guard = DialogicPauseGuard.capture_and_pause()


func _close() -> void :
	hide()
	_input_blocker.visible = false
	_dimmer.visible = false
	_panel.visible = false
	if _dialogic_pause_guard != null:
		_dialogic_pause_guard.restore()
		_dialogic_pause_guard = null


func _build_ui() -> void :
	_input_blocker = Control.new()
	_input_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_input_blocker.add_to_group("ui_blocking_overlay")
	_input_blocker.visible = false
	add_child(_input_blocker)

	_dimmer = ColorRect.new()
	_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dimmer.color = Color(0, 0, 0, 0.72)
	_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_dimmer.add_to_group("ui_blocking_overlay")
	_dimmer.visible = false
	add_child(_dimmer)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.add_to_group("ui_blocking_overlay")
	_panel.offset_left = -520
	_panel.offset_top = -390
	_panel.offset_right = 520
	_panel.offset_bottom = 390
	_panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(_panel)
	_layout_panel_for_viewport()

	var margin: = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_panel.add_child(margin)

	var root: = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var header: = HBoxContainer.new()
	root.add_child(header)

	var title_box: = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 4)
	header.add_child(title_box)

	var title: = Label.new()
	title.text = "UI Settings"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", TEXT_ACCENT)
	title_box.add_child(title)

	var subtitle: = Label.new()
	subtitle.text = "Resize the textbox, tune dialogue text and reveal speed, adjust sounds, and recolor each control."
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", TEXT_MUTED)
	title_box.add_child(subtitle)

	var close_button: = Button.new()
	close_button.text = "X"
	close_button.flat = true
	close_button.add_theme_font_size_override("font_size", 20)
	close_button.add_theme_color_override("font_color", TEXT_MUTED)
	close_button.add_theme_color_override("font_hover_color", Color(1.0, 0.55, 0.55))
	close_button.pressed.connect(_on_cancel_pressed)
	header.add_child(close_button)

	root.add_child(_make_separator())

	var scroll: = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	TouchScrollGesture.install_scroll(scroll, false, true)
	root.add_child(scroll)

	var content: = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	scroll.add_child(content)


	var display_panel: = PanelContainer.new()
	display_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display_panel.add_theme_stylebox_override("panel", _make_section_style())
	content.add_child(display_panel)

	var display_margin: = MarginContainer.new()
	display_margin.add_theme_constant_override("margin_left", 16)
	display_margin.add_theme_constant_override("margin_right", 16)
	display_margin.add_theme_constant_override("margin_top", 14)
	display_margin.add_theme_constant_override("margin_bottom", 14)
	display_panel.add_child(display_margin)

	var display_vbox: = VBoxContainer.new()
	display_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display_vbox.add_theme_constant_override("separation", 10)
	display_margin.add_child(display_vbox)

	var display_title: = Label.new()
	display_title.text = "Display"
	display_title.add_theme_font_size_override("font_size", 20)
	display_title.add_theme_color_override("font_color", TEXT_MAIN)
	display_vbox.add_child(display_title)

	if not OS.has_feature("mobile"):
		var scale_result: = _add_value_slider_row(
			display_vbox, tr("Overall UI scale"), 
			UISettingsManager.MIN_DESKTOP_UI_SCALE, UISettingsManager.MAX_DESKTOP_UI_SCALE, 
			0.05, UISettingsManager.DEFAULT_DESKTOP_UI_SCALE, _format_menu_scale_label, 
			func() -> void :
				_desktop_scale_slider.value = UISettingsManager.DEFAULT_DESKTOP_UI_SCALE
				_mark_field_reset(tr("Overall UI scale"))
		)
		_desktop_scale_slider = scale_result[0]
		var scale_hint: = Label.new()
		scale_hint.text = "Scales the whole interface, including text and buttons. Automatically limited to fit your window. Save to apply."
		scale_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		scale_hint.add_theme_font_size_override("font_size", 13)
		scale_hint.add_theme_color_override("font_color", TEXT_MUTED)
		display_vbox.add_child(scale_hint)


	var title_row: = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	display_vbox.add_child(title_row)
	var game_title_label: = Label.new()
	game_title_label.text = "Game Title"
	game_title_label.custom_minimum_size.x = 140
	game_title_label.add_theme_font_size_override("font_size", 15)
	game_title_label.add_theme_color_override("font_color", TEXT_MAIN)
	title_row.add_child(game_title_label)
	_game_title_option = OptionButton.new()
	_game_title_option.custom_minimum_size.x = 260
	for mode in UISettingsManager.get_game_title_modes():
		var index: = _game_title_option.item_count
		_game_title_option.add_item(str(UISettingsManager.get_game_title_options().get(mode, mode)))
		_game_title_option.set_item_metadata(index, str(mode))
	TouchScrollGesture.configure_option_button(_game_title_option)
	title_row.add_child(_game_title_option)


	if LanguagePacks.has_packs():
		_language_option = _add_language_row(display_vbox, tr("Language"), tr("Automatic (system language)"))
		_story_language_option = _add_language_row(display_vbox, tr("Story language"), tr("Same as the game"))
		var language_hint: = Label.new()
		language_hint.text = "A new language for the game applies when you restart it. Story language, what the AI writes in, applies at once."
		language_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		language_hint.add_theme_font_size_override("font_size", 13)
		language_hint.add_theme_color_override("font_color", TEXT_MUTED)
		display_vbox.add_child(language_hint)


	var mode_row: = HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 12)
	display_vbox.add_child(mode_row)
	var mode_label: = Label.new()
	mode_label.text = "Window Mode"
	mode_label.custom_minimum_size.x = 140
	mode_label.add_theme_font_size_override("font_size", 15)
	mode_label.add_theme_color_override("font_color", TEXT_MAIN)
	mode_row.add_child(mode_label)
	_window_mode_option = OptionButton.new()
	_window_mode_option.add_item("Windowed", UISettingsManager.WINDOW_MODE_WINDOWED)
	_window_mode_option.add_item("Fullscreen", UISettingsManager.WINDOW_MODE_FULLSCREEN)
	_window_mode_option.add_item("Borderless Fullscreen", UISettingsManager.WINDOW_MODE_BORDERLESS)
	_window_mode_option.custom_minimum_size.x = 260
	_window_mode_option.item_selected.connect(_on_window_mode_changed)
	TouchScrollGesture.configure_option_button(_window_mode_option)
	mode_row.add_child(_window_mode_option)


	var res_row: = HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 12)
	display_vbox.add_child(res_row)
	var res_label: = Label.new()
	res_label.text = "Resolution"
	res_label.custom_minimum_size.x = 140
	res_label.add_theme_font_size_override("font_size", 15)
	res_label.add_theme_color_override("font_color", TEXT_MAIN)
	res_row.add_child(res_label)
	_resolution_option = OptionButton.new()
	for i in range(UISettingsManager.RESOLUTION_LIST.size()):
		var res: Vector2i = UISettingsManager.RESOLUTION_LIST[i]
		_resolution_option.add_item(UISettingsManager.get_resolution_label(res), i)
	_resolution_option.custom_minimum_size.x = 260
	TouchScrollGesture.configure_option_button(_resolution_option)
	res_row.add_child(_resolution_option)


	var vsync_row: = HBoxContainer.new()
	vsync_row.add_theme_constant_override("separation", 12)
	display_vbox.add_child(vsync_row)
	var vsync_label: = Label.new()
	vsync_label.text = "VSync"
	vsync_label.custom_minimum_size.x = 140
	vsync_label.add_theme_font_size_override("font_size", 15)
	vsync_label.add_theme_color_override("font_color", TEXT_MAIN)
	vsync_row.add_child(vsync_label)
	_vsync_check = CheckBox.new()
	_vsync_check.text = "Enabled"
	_vsync_check.add_theme_color_override("font_color", TEXT_MUTED)
	vsync_row.add_child(_vsync_check)

	var foregrounds_row: = HBoxContainer.new()
	foregrounds_row.add_theme_constant_override("separation", 12)
	display_vbox.add_child(foregrounds_row)
	var foregrounds_label: = Label.new()
	foregrounds_label.text = "Scene Foregrounds"
	foregrounds_label.custom_minimum_size.x = 140
	foregrounds_label.add_theme_font_size_override("font_size", 15)
	foregrounds_label.add_theme_color_override("font_color", TEXT_MAIN)
	foregrounds_row.add_child(foregrounds_label)
	_foregrounds_enabled_check = CheckBox.new()
	_foregrounds_enabled_check.text = "Enabled"
	_foregrounds_enabled_check.add_theme_color_override("font_color", TEXT_MUTED)
	foregrounds_row.add_child(_foregrounds_enabled_check)

	_voice_options = preload("res://scripts/voice_mod/voice_options.gd").build(content, get_tree(), self)
	_build_storage_section(content)
	_build_autosave_section(content)

	var audio_panel: = PanelContainer.new()
	audio_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	audio_panel.add_theme_stylebox_override("panel", _make_section_style())
	content.add_child(audio_panel)

	var audio_margin: = MarginContainer.new()
	audio_margin.add_theme_constant_override("margin_left", 16)
	audio_margin.add_theme_constant_override("margin_right", 16)
	audio_margin.add_theme_constant_override("margin_top", 14)
	audio_margin.add_theme_constant_override("margin_bottom", 14)
	audio_panel.add_child(audio_margin)

	var audio_vbox: = VBoxContainer.new()
	audio_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	audio_vbox.add_theme_constant_override("separation", 10)
	audio_margin.add_child(audio_vbox)

	var audio_title: = Label.new()
	audio_title.text = "Global Audio"
	audio_title.add_theme_font_size_override("font_size", 20)
	audio_title.add_theme_color_override("font_color", TEXT_MAIN)
	audio_vbox.add_child(audio_title)

	var audio_hint: = Label.new()
	audio_hint.text = "Controls the overall music mix and sound effects across the whole game. Typing sounds still have their own extra volume control below."
	audio_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	audio_hint.add_theme_font_size_override("font_size", 13)
	audio_hint.add_theme_color_override("font_color", TEXT_MUTED)
	audio_vbox.add_child(audio_hint)

	var music_result: = _add_value_slider_row(audio_vbox, tr("Music"), -40.0, 6.0, 1.0, UISettingsManager.DEFAULT_MUSIC_VOLUME, _format_db_label)
	_music_volume_slider = music_result[0]
	_music_volume_label = music_result[1]
	_music_mute_button = _add_audio_mute_button(music_result[2], tr("Toggle music mute."), _on_music_mute_pressed)
	_music_volume_slider.value_changed.connect(_on_music_volume_preview_changed)

	var sfx_result: = _add_value_slider_row(audio_vbox, tr("Sound Effects"), -40.0, 6.0, 1.0, UISettingsManager.DEFAULT_SFX_VOLUME, _format_db_label)
	_sfx_volume_slider = sfx_result[0]
	_sfx_volume_label = sfx_result[1]
	_sfx_mute_button = _add_audio_mute_button(sfx_result[2], tr("Toggle sound-effects mute."), _on_sfx_mute_pressed)
	_sfx_volume_slider.value_changed.connect(_on_sfx_volume_preview_changed)


	var size_panel: = PanelContainer.new()
	size_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_panel.add_theme_stylebox_override("panel", _make_section_style())
	content.add_child(size_panel)

	var size_margin: = MarginContainer.new()
	size_margin.add_theme_constant_override("margin_left", 16)
	size_margin.add_theme_constant_override("margin_right", 16)
	size_margin.add_theme_constant_override("margin_top", 14)
	size_margin.add_theme_constant_override("margin_bottom", 14)
	size_panel.add_child(size_margin)

	var size_vbox: = VBoxContainer.new()
	size_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_vbox.add_theme_constant_override("separation", 10)
	size_margin.add_child(size_vbox)

	var size_title: = Label.new()
	size_title.text = "Dialogue Box Size"
	size_title.add_theme_font_size_override("font_size", 20)
	size_title.add_theme_color_override("font_color", TEXT_MAIN)
	size_vbox.add_child(size_title)

	var size_hint: = Label.new()
	size_hint.text = "Only the textbox changes size. Sidebar controls stay aligned to it."
	size_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	size_hint.add_theme_font_size_override("font_size", 13)
	size_hint.add_theme_color_override("font_color", TEXT_MUTED)
	size_vbox.add_child(size_hint)

	_width_spinbox = _add_spinbox_row(size_vbox, tr("Width"), 420, 1600, 10, tr("Dialogue box width in pixels."), func() -> void :
		_width_spinbox.value = UISettingsManager.DEFAULT_DIALOGUE_BOX_WIDTH
		_mark_field_reset(tr("Dialogue box width"))
	)
	_height_spinbox = _add_spinbox_row(size_vbox, tr("Height"), 120, 520, 10, tr("Dialogue box height in pixels."), func() -> void :
		_height_spinbox.value = UISettingsManager.DEFAULT_DIALOGUE_BOX_HEIGHT
		_mark_field_reset(tr("Dialogue box height"))
	)

	var menu_scale_result: = _add_value_slider_row(
		size_vbox, 
		tr("Menu Size"), 
		UISettingsManager.MIN_MENU_PANEL_SCALE, 
		UISettingsManager.MAX_MENU_PANEL_SCALE, 
		0.05, 
		UISettingsManager.DEFAULT_MENU_PANEL_SCALE, 
		_format_menu_scale_label, 
		func() -> void :
			_menu_scale_slider.value = UISettingsManager.DEFAULT_MENU_PANEL_SCALE
			_mark_field_reset(tr("Menu size"))
	)
	_menu_scale_slider = menu_scale_result[0]
	_menu_scale_label = menu_scale_result[1]


	_menu_scale_slider.value_changed.connect( func(_v: float) -> void : _layout_panel_for_viewport())


	if OS.has_feature("mobile"):
		var mobile_scale_result: = _add_value_slider_row(
			size_vbox, 
			tr("Screen UI Size"), 
			UISettingsManager.MIN_MOBILE_UI_SCALE, 
			UISettingsManager.MAX_MOBILE_UI_SCALE, 
			0.05, 
			UISettingsManager.DEFAULT_MOBILE_UI_SCALE, 
			_format_menu_scale_label, 
			func() -> void :
				_mobile_scale_slider.value = UISettingsManager.DEFAULT_MOBILE_UI_SCALE
				_mark_field_reset(tr("Screen UI size"))
		)
		_mobile_scale_slider = mobile_scale_result[0]
		_mobile_scale_label = mobile_scale_result[1]

	var text_panel: = PanelContainer.new()
	text_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_panel.add_theme_stylebox_override("panel", _make_section_style())
	content.add_child(text_panel)

	var text_margin: = MarginContainer.new()
	text_margin.add_theme_constant_override("margin_left", 16)
	text_margin.add_theme_constant_override("margin_right", 16)
	text_margin.add_theme_constant_override("margin_top", 14)
	text_margin.add_theme_constant_override("margin_bottom", 14)
	text_panel.add_child(text_margin)

	var text_vbox: = VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_theme_constant_override("separation", 10)
	text_margin.add_child(text_vbox)

	var text_title: = Label.new()
	text_title.text = "Dialogue Text"
	text_title.add_theme_font_size_override("font_size", 20)
	text_title.add_theme_color_override("font_color", TEXT_MAIN)
	text_vbox.add_child(text_title)

	var text_hint: = Label.new()
	text_hint.text = "Text size changes the dialogue body and speaker name. Set reveal speed to Instant to fill each line immediately."
	text_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_hint.add_theme_font_size_override("font_size", 13)
	text_hint.add_theme_color_override("font_color", TEXT_MUTED)
	text_vbox.add_child(text_hint)

	var text_size_result: = _add_value_slider_row(
		text_vbox, 
		tr("Text Size"), 
		UISettingsManager.MIN_DIALOGUE_TEXT_SIZE, 
		UISettingsManager.MAX_DIALOGUE_TEXT_SIZE, 
		1.0, 
		UISettingsManager.DEFAULT_DIALOGUE_TEXT_SIZE, 
		_format_dialogue_text_size_label, 
		func() -> void :
			_dialogue_text_size_slider.value = UISettingsManager.DEFAULT_DIALOGUE_TEXT_SIZE
			_mark_field_reset(tr("Dialogue text size"))
	)
	_dialogue_text_size_slider = text_size_result[0]
	_dialogue_text_size_label = text_size_result[1]

	var reveal_speed_result: = _add_value_slider_row(
		text_vbox, 
		tr("Reveal Speed"), 
		UISettingsManager.MIN_DIALOGUE_REVEAL_SPEED, 
		UISettingsManager.MAX_DIALOGUE_REVEAL_SPEED, 
		0.1, 
		UISettingsManager.DEFAULT_DIALOGUE_REVEAL_SPEED, 
		_format_dialogue_speed_label, 
		func() -> void :
			_dialogue_reveal_speed_slider.value = UISettingsManager.DEFAULT_DIALOGUE_REVEAL_SPEED
			_mark_field_reset(tr("Dialogue reveal speed"))
	)
	_dialogue_reveal_speed_slider = reveal_speed_result[0]
	_dialogue_reveal_speed_label = reveal_speed_result[1]

	var sound_panel: = PanelContainer.new()
	sound_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sound_panel.add_theme_stylebox_override("panel", _make_section_style())
	content.add_child(sound_panel)

	var sound_margin: = MarginContainer.new()
	sound_margin.add_theme_constant_override("margin_left", 16)
	sound_margin.add_theme_constant_override("margin_right", 16)
	sound_margin.add_theme_constant_override("margin_top", 14)
	sound_margin.add_theme_constant_override("margin_bottom", 14)
	sound_panel.add_child(sound_margin)

	var sound_vbox: = VBoxContainer.new()
	sound_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sound_vbox.add_theme_constant_override("separation", 10)
	sound_margin.add_child(sound_vbox)

	var sound_title: = Label.new()
	sound_title.text = "Sounds & Conversations"
	sound_title.add_theme_font_size_override("font_size", 20)
	sound_title.add_theme_color_override("font_color", TEXT_MAIN)
	sound_vbox.add_child(sound_title)

	var sound_hint: = Label.new()
	sound_hint.text = "Toggle the per-letter speech blips. Custom folders default to data/sounds/typing and should contain .ogg or .mp3 files."
	sound_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sound_hint.add_theme_font_size_override("font_size", 13)
	sound_hint.add_theme_color_override("font_color", TEXT_MUTED)
	sound_vbox.add_child(sound_hint)

	var sound_toggle_row: = HBoxContainer.new()
	sound_toggle_row.add_theme_constant_override("separation", 12)
	sound_vbox.add_child(sound_toggle_row)

	var sound_toggle_label: = Label.new()
	sound_toggle_label.text = "Typing Sounds"
	sound_toggle_label.custom_minimum_size.x = 140
	sound_toggle_label.add_theme_font_size_override("font_size", 15)
	sound_toggle_label.add_theme_color_override("font_color", TEXT_MAIN)
	sound_toggle_row.add_child(sound_toggle_label)

	_typing_sounds_enabled_check = CheckBox.new()
	_typing_sounds_enabled_check.text = "Enabled"
	_typing_sounds_enabled_check.add_theme_color_override("font_color", TEXT_MUTED)
	sound_toggle_row.add_child(_typing_sounds_enabled_check)

	var sound_path_row: = HBoxContainer.new()
	sound_path_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sound_path_row.add_theme_constant_override("separation", 12)
	sound_vbox.add_child(sound_path_row)

	var sound_path_label: = Label.new()
	sound_path_label.text = "Sound Folder"
	sound_path_label.custom_minimum_size.x = 140
	sound_path_label.add_theme_font_size_override("font_size", 15)
	sound_path_label.add_theme_color_override("font_color", TEXT_MAIN)
	sound_path_row.add_child(sound_path_label)

	_typing_sounds_path_edit = LineEdit.new()
	_typing_sounds_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_typing_sounds_path_edit.custom_minimum_size = Vector2(280, 34)
	_typing_sounds_path_edit.placeholder_text = UISettingsManager.DEFAULT_TYPING_SOUNDS_PATH
	_typing_sounds_path_edit.tooltip_text = "Logical data path, res:// path, user:// path, or absolute folder path."
	sound_path_row.add_child(_typing_sounds_path_edit)

	var open_sound_folder_button: = Button.new()
	open_sound_folder_button.text = "Open Folder"
	open_sound_folder_button.custom_minimum_size = Vector2(130, 34)
	open_sound_folder_button.pressed.connect(_on_open_typing_sounds_folder_pressed)
	sound_path_row.add_child(open_sound_folder_button)

	var volume_result: = _add_value_slider_row(sound_vbox, tr("Volume"), -40.0, 6.0, 1.0, UISettingsManager.DEFAULT_TYPING_SOUNDS_VOLUME, _format_db_label)
	_typing_sounds_volume_slider = volume_result[0]
	_typing_sounds_volume_label = volume_result[1]

	var notify_hint: = Label.new()
	notify_hint.text = "When an AI response or scene finishes generating while the window is in the background, get notified. The sound is data/assets/ui/notify.mp3 (replaceable)."
	notify_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notify_hint.add_theme_font_size_override("font_size", 13)
	notify_hint.add_theme_color_override("font_color", TEXT_MUTED)
	sound_vbox.add_child(notify_hint)

	var notify_row: = HBoxContainer.new()
	notify_row.add_theme_constant_override("separation", 12)
	sound_vbox.add_child(notify_row)

	var notify_label: = Label.new()
	notify_label.text = "AI Done Alert"
	notify_label.custom_minimum_size.x = 140
	notify_label.add_theme_font_size_override("font_size", 15)
	notify_label.add_theme_color_override("font_color", TEXT_MAIN)
	notify_row.add_child(notify_label)

	_ai_notify_flash_check = CheckBox.new()
	_ai_notify_flash_check.text = "Flash window"
	_ai_notify_flash_check.add_theme_color_override("font_color", TEXT_MUTED)
	notify_row.add_child(_ai_notify_flash_check)

	_ai_notify_sound_check = CheckBox.new()
	_ai_notify_sound_check.text = "Play sound"
	_ai_notify_sound_check.add_theme_color_override("font_color", TEXT_MUTED)
	notify_row.add_child(_ai_notify_sound_check)

	var pass_time_row: = HBoxContainer.new()
	pass_time_row.add_theme_constant_override("separation", 12)
	sound_vbox.add_child(pass_time_row)

	var pass_time_label: = Label.new()
	pass_time_label.text = "Conversations"
	pass_time_label.custom_minimum_size.x = 140
	pass_time_label.add_theme_font_size_override("font_size", 15)
	pass_time_label.add_theme_color_override("font_color", TEXT_MAIN)
	pass_time_row.add_child(pass_time_label)

	_qa_pass_time_check = CheckBox.new()
	_qa_pass_time_check.text = "Allow passing time to afternoon"
	_qa_pass_time_check.tooltip_text = "Adds an Afternoon button to morning sandbox chats so a date can continue toward evening (and sleepovers) without returning to the map."
	_qa_pass_time_check.add_theme_color_override("font_color", TEXT_MUTED)
	pass_time_row.add_child(_qa_pass_time_check)

	_qa_guidance_check = CheckBox.new()
	_qa_guidance_check.text = "Show Guidance button"
	_qa_guidance_check.tooltip_text = "Shows a Guidance button in AI conversations for instructions that steer the next response, or every response when kept. While it is hidden, a staged or kept guidance still applies."
	_qa_guidance_check.add_theme_color_override("font_color", TEXT_MUTED)
	pass_time_row.add_child(_qa_guidance_check)

	var conversations_row2: = HBoxContainer.new()
	conversations_row2.add_theme_constant_override("separation", 12)
	sound_vbox.add_child(conversations_row2)

	var conversations_row2_spacer: = Control.new()
	conversations_row2_spacer.custom_minimum_size.x = 140
	conversations_row2.add_child(conversations_row2_spacer)

	_qa_dice_panel_check = CheckBox.new()
	_qa_dice_panel_check.text = "Show dice result details"
	_qa_dice_panel_check.tooltip_text = "After an RPG dice turn, shows a banner with the outcome tier, the roll and stat modifier, and the difficulty the AI chose."
	_qa_dice_panel_check.add_theme_color_override("font_color", TEXT_MUTED)
	conversations_row2.add_child(_qa_dice_panel_check)


	var portrait_panel: = PanelContainer.new()
	portrait_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait_panel.add_theme_stylebox_override("panel", _make_section_style())
	content.add_child(portrait_panel)

	var portrait_margin: = MarginContainer.new()
	portrait_margin.add_theme_constant_override("margin_left", 16)
	portrait_margin.add_theme_constant_override("margin_right", 16)
	portrait_margin.add_theme_constant_override("margin_top", 14)
	portrait_margin.add_theme_constant_override("margin_bottom", 14)
	portrait_panel.add_child(portrait_margin)

	var portrait_vbox: = VBoxContainer.new()
	portrait_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait_vbox.add_theme_constant_override("separation", 10)
	portrait_margin.add_child(portrait_vbox)

	var portrait_title: = Label.new()
	portrait_title.text = "Portrait Sizes"
	portrait_title.add_theme_font_size_override("font_size", 20)
	portrait_title.add_theme_color_override("font_color", TEXT_MAIN)
	portrait_vbox.add_child(portrait_title)

	var portrait_hint: = Label.new()
	portrait_hint.text = "Scale of character sprites during solo, duo, trio, quartet, quintet and sextet conversations. Takes effect on next conversation."
	portrait_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	portrait_hint.add_theme_font_size_override("font_size", 13)
	portrait_hint.add_theme_color_override("font_color", TEXT_MUTED)
	portrait_vbox.add_child(portrait_hint)

	var solo_result: = _add_scale_slider_row(portrait_vbox, tr("Solo"), UISettingsManager.MIN_PORTRAIT_SCALE, UISettingsManager.MAX_PORTRAIT_SCALE, UISettingsManager.DEFAULT_SOLO_SCALE, func() -> void :
		_solo_scale_slider.value = UISettingsManager.DEFAULT_SOLO_SCALE
		_mark_field_reset(tr("Solo portrait scale"))
	)
	_solo_scale_slider = solo_result[0]
	_solo_scale_label = solo_result[1]

	var duo_result: = _add_scale_slider_row(portrait_vbox, tr("Duo"), UISettingsManager.MIN_PORTRAIT_SCALE, UISettingsManager.MAX_PORTRAIT_SCALE, UISettingsManager.DEFAULT_DUO_SCALE, func() -> void :
		_duo_scale_slider.value = UISettingsManager.DEFAULT_DUO_SCALE
		_mark_field_reset(tr("Duo portrait scale"))
	)
	_duo_scale_slider = duo_result[0]
	_duo_scale_label = duo_result[1]

	var trio_result: = _add_scale_slider_row(portrait_vbox, tr("Trio"), UISettingsManager.MIN_PORTRAIT_SCALE, UISettingsManager.MAX_PORTRAIT_SCALE, UISettingsManager.DEFAULT_TRIO_SCALE, func() -> void :
		_trio_scale_slider.value = UISettingsManager.DEFAULT_TRIO_SCALE
		_mark_field_reset(tr("Trio portrait scale"))
	)
	_trio_scale_slider = trio_result[0]
	_trio_scale_label = trio_result[1]

	var quartet_result: = _add_scale_slider_row(portrait_vbox, tr("Quartet"), UISettingsManager.MIN_PORTRAIT_SCALE, UISettingsManager.MAX_PORTRAIT_SCALE, UISettingsManager.DEFAULT_QUARTET_SCALE, func() -> void :
		_quartet_scale_slider.value = UISettingsManager.DEFAULT_QUARTET_SCALE
		_mark_field_reset(tr("Quartet portrait scale"))
	)
	_quartet_scale_slider = quartet_result[0]
	_quartet_scale_label = quartet_result[1]

	var quintet_result: = _add_scale_slider_row(portrait_vbox, tr("Quintet"), UISettingsManager.MIN_PORTRAIT_SCALE, UISettingsManager.MAX_PORTRAIT_SCALE, UISettingsManager.DEFAULT_QUINTET_SCALE, func() -> void :
		_quintet_scale_slider.value = UISettingsManager.DEFAULT_QUINTET_SCALE
		_mark_field_reset(tr("Quintet portrait scale"))
	)
	_quintet_scale_slider = quintet_result[0]
	_quintet_scale_label = quintet_result[1]

	var sextet_result: = _add_scale_slider_row(portrait_vbox, tr("Sextet"), UISettingsManager.MIN_PORTRAIT_SCALE, UISettingsManager.MAX_PORTRAIT_SCALE, UISettingsManager.DEFAULT_SEXTET_SCALE, func() -> void :
		_sextet_scale_slider.value = UISettingsManager.DEFAULT_SEXTET_SCALE
		_mark_field_reset(tr("Sextet portrait scale"))
	)
	_sextet_scale_slider = sextet_result[0]
	_sextet_scale_label = sextet_result[1]

	var colors_panel: = PanelContainer.new()
	colors_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	colors_panel.add_theme_stylebox_override("panel", _make_section_style())
	content.add_child(colors_panel)

	var colors_margin: = MarginContainer.new()
	colors_margin.add_theme_constant_override("margin_left", 16)
	colors_margin.add_theme_constant_override("margin_right", 16)
	colors_margin.add_theme_constant_override("margin_top", 14)
	colors_margin.add_theme_constant_override("margin_bottom", 14)
	colors_panel.add_child(colors_margin)

	var colors_vbox: = VBoxContainer.new()
	colors_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	colors_vbox.add_theme_constant_override("separation", 10)
	colors_margin.add_child(colors_vbox)

	var colors_title: = Label.new()
	colors_title.text = "UI Sections"
	colors_title.add_theme_font_size_override("font_size", 20)
	colors_title.add_theme_color_override("font_color", TEXT_MAIN)
	colors_vbox.add_child(colors_title)

	var colors_hint: = Label.new()
	colors_hint.text = "Open the part you want to tune: colors, button labels, visibility and opacity."
	colors_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	colors_hint.add_theme_font_size_override("font_size", 13)
	colors_hint.add_theme_color_override("font_color", TEXT_MUTED)
	colors_vbox.add_child(colors_hint)

	var box_body: = _add_color_section(colors_vbox, "box", tr("Textbox fill and outline."))
	_box_fill_picker = _add_color_row(box_body, tr("Box Fill"), tr("Main fill color of the dialogue box."), func() -> void :
		_box_fill_picker.color = UISettingsManager.DEFAULT_DIALOGUE_BOX_FILL
		_mark_field_reset(tr("Dialogue box fill"))
	)
	_box_outline_picker = _add_color_row(box_body, tr("Box Outline"), tr("Border and shadow tint used around the dialogue box."), func() -> void :
		_box_outline_picker.color = UISettingsManager.DEFAULT_DIALOGUE_BOX_OUTLINE
		_mark_field_reset(tr("Dialogue box outline"))
	)

	var ask_body: = _add_color_section(colors_vbox, "ask", tr("Used by the Ask button and text-entry text color."))
	_main_button_label_edit = _add_text_row(ask_body, tr("Ask Label"), tr("Visible label shown on the Ask button."), func() -> void :
		_main_button_label_edit.text = UISettingsManager.DEFAULT_MAIN_BUTTON_LABEL
		_mark_field_reset(tr("Ask label"))
	)
	_main_button_fill_picker = _add_color_row(ask_body, tr("Ask Fill"), tr("Main fill color for the Ask button."), func() -> void :
		_main_button_fill_picker.color = UISettingsManager.DEFAULT_MAIN_BUTTON_FILL
		_mark_field_reset(tr("Ask fill"))
	)
	_main_button_outline_picker = _add_color_row(ask_body, tr("Ask Outline"), tr("Border color used for the Ask button."), func() -> void :
		_main_button_outline_picker.color = UISettingsManager.DEFAULT_MAIN_BUTTON_OUTLINE
		_mark_field_reset(tr("Ask outline"))
	)
	_main_button_text_picker = _add_color_row(ask_body, tr("Ask Text"), tr("Text color used for the Ask button and entry text."), func() -> void :
		_main_button_text_picker.color = UISettingsManager.DEFAULT_MAIN_BUTTON_TEXT
		_mark_field_reset(tr("Ask text"))
	)

	var dice_body: = _add_color_section(colors_vbox, "dice", tr("Used by Launch Dice and the roll selector shown in debug mode."))
	_dice_button_label_edit = _add_text_row(dice_body, tr("Dice Label"), tr("Visible label shown on the Launch Dice button."), func() -> void :
		_dice_button_label_edit.text = UISettingsManager.DEFAULT_DICE_BUTTON_LABEL
		_mark_field_reset(tr("Dice label"))
	)
	_dice_button_fill_picker = _add_color_row(dice_body, tr("Dice Fill"), tr("Main fill color for Launch Dice."), func() -> void :
		_dice_button_fill_picker.color = UISettingsManager.DEFAULT_DICE_BUTTON_FILL
		_mark_field_reset(tr("Dice fill"))
	)
	_dice_button_outline_picker = _add_color_row(dice_body, tr("Dice Outline"), tr("Border color used for Launch Dice."), func() -> void :
		_dice_button_outline_picker.color = UISettingsManager.DEFAULT_DICE_BUTTON_OUTLINE
		_mark_field_reset(tr("Dice outline"))
	)
	_dice_button_text_picker = _add_color_row(dice_body, tr("Dice Text"), tr("Text color used for Launch Dice."), func() -> void :
		_dice_button_text_picker.color = UISettingsManager.DEFAULT_DICE_BUTTON_TEXT
		_mark_field_reset(tr("Dice text"))
	)

	var roster_body: = _add_color_section(colors_vbox, "roster", tr("Used by the Roster button and roster popup controls."))
	_roster_button_label_edit = _add_text_row(roster_body, tr("Roster Label"), tr("Visible label shown on the manual roster button."), func() -> void :
		_roster_button_label_edit.text = UISettingsManager.DEFAULT_ROSTER_BUTTON_LABEL
		_mark_field_reset(tr("Roster label"))
	)
	_roster_button_fill_picker = _add_color_row(roster_body, tr("Roster Fill"), tr("Main fill color for manual roster controls."), func() -> void :
		_roster_button_fill_picker.color = UISettingsManager.DEFAULT_ROSTER_BUTTON_FILL
		_mark_field_reset(tr("Roster fill"))
	)
	_roster_button_outline_picker = _add_color_row(roster_body, tr("Roster Outline"), tr("Border color used for manual roster controls."), func() -> void :
		_roster_button_outline_picker.color = UISettingsManager.DEFAULT_ROSTER_BUTTON_OUTLINE
		_mark_field_reset(tr("Roster outline"))
	)
	_roster_button_text_picker = _add_color_row(roster_body, tr("Roster Text"), tr("Text color used for manual roster controls."), func() -> void :
		_roster_button_text_picker.color = UISettingsManager.DEFAULT_ROSTER_BUTTON_TEXT
		_mark_field_reset(tr("Roster text"))
	)

	var location_body: = _add_color_section(colors_vbox, "location", tr("Used by the Location button and location popup controls."))
	_location_button_label_edit = _add_text_row(location_body, tr("Location Label"), tr("Visible label shown on the manual location button."), func() -> void :
		_location_button_label_edit.text = UISettingsManager.DEFAULT_LOCATION_BUTTON_LABEL
		_mark_field_reset(tr("Location label"))
	)
	_location_button_fill_picker = _add_color_row(location_body, tr("Location Fill"), tr("Main fill color for manual location controls."), func() -> void :
		_location_button_fill_picker.color = UISettingsManager.DEFAULT_LOCATION_BUTTON_FILL
		_mark_field_reset(tr("Location fill"))
	)
	_location_button_outline_picker = _add_color_row(location_body, tr("Location Outline"), tr("Border color used for manual location controls."), func() -> void :
		_location_button_outline_picker.color = UISettingsManager.DEFAULT_LOCATION_BUTTON_OUTLINE
		_mark_field_reset(tr("Location outline"))
	)
	_location_button_text_picker = _add_color_row(location_body, tr("Location Text"), tr("Text color used for manual location controls."), func() -> void :
		_location_button_text_picker.color = UISettingsManager.DEFAULT_LOCATION_BUTTON_TEXT
		_mark_field_reset(tr("Location text"))
	)

	var map_menu_body: = _add_color_section(colors_vbox, "map_menu", tr("Used by the right-side Ponyville map menu."))
	_map_menu_fill_picker = _add_color_row(map_menu_body, tr("Menu Fill"), tr("Main fill color used by the Ponyville map menu panel."), func() -> void :
		_map_menu_fill_picker.color = UISettingsManager.DEFAULT_MAP_MENU_FILL
		_mark_field_reset(tr("Map menu fill"))
	)
	_map_menu_outline_picker = _add_color_row(map_menu_body, tr("Menu Outline"), tr("Border and button accent color used by the Ponyville map menu."), func() -> void :
		_map_menu_outline_picker.color = UISettingsManager.DEFAULT_MAP_MENU_OUTLINE
		_mark_field_reset(tr("Map menu outline"))
	)
	_map_menu_text_picker = _add_color_row(map_menu_body, tr("Menu Text"), tr("Text color used by the Ponyville map menu buttons."), func() -> void :
		_map_menu_text_picker.color = UISettingsManager.DEFAULT_MAP_MENU_TEXT
		_mark_field_reset(tr("Map menu text"))
	)

	var map_popup_body: = _add_color_section(colors_vbox, "map_popup", tr("Used by Ponyville map popups like sandbox setup and night residence."))
	_map_popup_fill_picker = _add_color_row(map_popup_body, tr("Popup Fill"), tr("Main fill color used by Ponyville map popups."), func() -> void :
		_map_popup_fill_picker.color = UISettingsManager.DEFAULT_MAP_POPUP_FILL
		_mark_field_reset(tr("Map popup fill"))
	)
	_map_popup_outline_picker = _add_color_row(map_popup_body, tr("Popup Outline"), tr("Border and accent color used by Ponyville map popups."), func() -> void :
		_map_popup_outline_picker.color = UISettingsManager.DEFAULT_MAP_POPUP_OUTLINE
		_mark_field_reset(tr("Map popup outline"))
	)
	_map_popup_text_picker = _add_color_row(map_popup_body, tr("Popup Text"), tr("Text color used by Ponyville map popup controls."), func() -> void :
		_map_popup_text_picker.color = UISettingsManager.DEFAULT_MAP_POPUP_TEXT
		_mark_field_reset(tr("Map popup text"))
	)

	_build_dialogue_control_sections(colors_vbox)

	var status_hint: = Label.new()
	status_hint.text = "Saved changes apply immediately to the current discussion UI and will be used for future scenes too."
	status_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_hint.add_theme_font_size_override("font_size", 13)
	status_hint.add_theme_color_override("font_color", TEXT_MUTED)
	root.add_child(status_hint)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.74, 0.74))
	root.add_child(_status_label)

	var footer: = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 10)
	root.add_child(footer)

	var reset_button: = Button.new()
	reset_button.text = "Reset to Defaults"
	reset_button.custom_minimum_size = Vector2(180, 44)
	reset_button.add_theme_stylebox_override("normal", _make_action_style(Color(0.22, 0.26, 0.34, 0.95)))
	reset_button.add_theme_stylebox_override("hover", _make_action_style(Color(0.3, 0.35, 0.44, 1.0)))
	reset_button.add_theme_color_override("font_color", Color.WHITE)
	reset_button.pressed.connect(_on_reset_pressed)
	footer.add_child(reset_button)

	var cancel_button: = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(150, 44)
	cancel_button.pressed.connect(_on_cancel_pressed)
	footer.add_child(cancel_button)

	var save_button: = Button.new()
	save_button.text = "Save"
	save_button.custom_minimum_size = Vector2(150, 44)
	save_button.add_theme_stylebox_override("normal", _make_action_style(Color(0.53, 0.33, 0.12, 0.98)))
	save_button.add_theme_stylebox_override("hover", _make_action_style(Color(0.64, 0.4, 0.15, 1.0)))
	save_button.add_theme_color_override("font_color", Color.WHITE)
	save_button.pressed.connect(_on_save_pressed)
	footer.add_child(save_button)

	for key in _color_section_titles.keys():
		_refresh_color_section_state(key)


func _build_dialogue_control_sections(parent: VBoxContainer) -> void :
	for control_id in UISettingsManager.DIALOGUE_CONTROL_TITLES:
		var section_key: = "control_" + str(control_id)
		_color_section_titles[section_key] = UISettingsManager.DIALOGUE_CONTROL_TITLES[control_id]
		var body: = _add_color_section(parent, section_key, tr("Hide removes the button. At 0% opacity it stays clickable. Blank labels use the current action's default."))
		var fields: = {}
		var visibility: = CheckBox.new()
		visibility.text = "Show button"
		body.add_child(visibility)
		fields["visible"] = visibility
		if control_id not in ["compact", "menu"]:
			var icon: = CheckBox.new()
			icon.text = "Show icon"
			body.add_child(icon)
			fields["show_icon"] = icon
		var labels: = {"label": tr("Label")}
		if control_id == "interrupt":
			labels = {"label": tr("Interrupt Label"), "stop_label": tr("Stop Label"), "cancel_label": tr("Cancel Label")}
		for key in labels:
			var edit: = _add_text_row(body, labels[key], tr("Leave blank to use the default label."))
			edit.placeholder_text = "Default"
			edit.max_length = 80
			fields[key] = edit
		fields["opacity"] = _add_spinbox_row(body, tr("Opacity (%)"), 0, 100, 1, tr("0% is invisible but still clickable. Uncheck Show button to remove the click target too."))
		_dialogue_control_fields[control_id] = fields
		_add_inline_reset_button(body, tr("Restore this button's default label and appearance."), func() -> void :
			_load_dialogue_control_fields(control_id, {})
			_mark_field_reset(tr(UISettingsManager.DIALOGUE_CONTROL_TITLES[control_id]))
		)


func _load_dialogue_control_fields(control_id: String, options: Dictionary) -> void :
	var fields: Dictionary = _dialogue_control_fields[control_id]
	fields["visible"].button_pressed = bool(options.get("visible", true))
	if fields.has("show_icon"):
		fields["show_icon"].button_pressed = bool(options.get("show_icon", true))
	fields["opacity"].value = float(options.get("opacity", 1.0)) * 100.0
	for key in ["label", "stop_label", "cancel_label"]:
		if fields.has(key):
			fields[key].text = str(options.get(key, ""))


func _build_autosave_section(parent: VBoxContainer) -> void :
	var panel: = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_section_style())
	parent.add_child(panel)
	var margin: = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var body: = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	var title: = Label.new()
	title.text = "Autosaves"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", TEXT_MAIN)
	body.add_child(title)
	var row: = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	var label: = Label.new()
	label.text = "Save an AI reply every"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", TEXT_MUTED)
	row.add_child(label)
	_ai_reply_autosave_option = OptionButton.new()
	for interval in UISettingsManager.AI_REPLY_AUTOSAVE_INTERVALS:
		_ai_reply_autosave_option.add_item(tr("1 reply (default)") if interval == 1 else tr_n("%d reply", "%d replies", interval) % interval, interval)
	row.add_child(_ai_reply_autosave_option)
	_add_inline_reset_button(row, tr("Save every AI reply."), func() -> void :
		_ai_reply_autosave_option.select(0)
		_mark_field_reset(tr("AI reply autosaves"))
	)
	var hint: = Label.new()
	hint.text = "Counts complete AI answers, not dialogue lines. Failed or cancelled requests don't count. The first answer after starting or resuming a chat is always saved."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", TEXT_MUTED)
	body.add_child(hint)
	var slots: = Label.new()
	slots.text = "Keeps the latest 27 saved replies. Checkpoints are saved separately."
	slots.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slots.add_theme_color_override("font_color", TEXT_MUTED)
	body.add_child(slots)


func _build_storage_section(parent: VBoxContainer) -> void :
	var storage_panel: = PanelContainer.new()
	storage_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	storage_panel.add_theme_stylebox_override("panel", _make_section_style())
	parent.add_child(storage_panel)

	var storage_margin: = MarginContainer.new()
	storage_margin.add_theme_constant_override("margin_left", 16)
	storage_margin.add_theme_constant_override("margin_right", 16)
	storage_margin.add_theme_constant_override("margin_top", 14)
	storage_margin.add_theme_constant_override("margin_bottom", 14)
	storage_panel.add_child(storage_margin)

	var storage_vbox: = VBoxContainer.new()
	storage_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	storage_vbox.add_theme_constant_override("separation", 6)
	storage_margin.add_child(storage_vbox)

	var header_row: = HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_theme_constant_override("separation", 8)
	storage_vbox.add_child(header_row)

	var storage_title: = Label.new()
	storage_title.text = "Storage"
	storage_title.add_theme_font_size_override("font_size", 20)
	storage_title.add_theme_color_override("font_color", TEXT_MAIN)
	header_row.add_child(storage_title)

	var header_spacer: = Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header_spacer)

	_storage_details_toggle = Button.new()
	_storage_details_toggle.text = "Details"
	_storage_details_toggle.toggle_mode = true
	_storage_details_toggle.custom_minimum_size = Vector2(82, 30)
	_storage_details_toggle.toggled.connect(_on_storage_details_toggled)
	header_row.add_child(_storage_details_toggle)

	var storage_hint: = Label.new()
	storage_hint.text = "Writes saves, logs, exports, vignettes, scenarios, lorebooks, and persona text files here. Changing the folder copies existing files."
	storage_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	storage_hint.add_theme_font_size_override("font_size", 12)
	storage_hint.add_theme_color_override("font_color", TEXT_MUTED)
	storage_vbox.add_child(storage_hint)

	var path_row: = HBoxContainer.new()
	path_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_row.add_theme_constant_override("separation", 12)
	storage_vbox.add_child(path_row)

	var path_label: = Label.new()
	path_label.text = "Folder"
	path_label.custom_minimum_size.x = 92
	path_label.add_theme_font_size_override("font_size", 15)
	path_label.add_theme_color_override("font_color", TEXT_MAIN)
	path_row.add_child(path_label)

	_storage_path_edit = LineEdit.new()
	_storage_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_storage_path_edit.custom_minimum_size = Vector2(280, 34)
	_storage_path_edit.placeholder_text = ContentPaths.get_default_storage_base_dir() if ContentPaths != null and ContentPaths.has_method("get_default_storage_base_dir") else ProjectSettings.globalize_path("user://")
	_storage_path_edit.tooltip_text = "Absolute folder path. Leave blank or use the default path to use Godot's app data folder."
	_storage_path_edit.text_changed.connect(_on_storage_path_text_changed)
	path_row.add_child(_storage_path_edit)

	var browse_button: = Button.new()
	browse_button.text = "Browse"
	browse_button.custom_minimum_size = Vector2(82, 34)
	browse_button.pressed.connect(_on_browse_storage_folder_pressed)
	path_row.add_child(browse_button)

	var open_button: = Button.new()
	open_button.text = "Open"
	open_button.custom_minimum_size = Vector2(72, 34)
	open_button.pressed.connect(_on_open_storage_folder_pressed)
	path_row.add_child(open_button)

	var default_button: = Button.new()
	default_button.text = "Default"
	default_button.custom_minimum_size = Vector2(84, 34)
	default_button.pressed.connect(_on_use_default_storage_pressed)
	path_row.add_child(default_button)

	_storage_summary_label = Label.new()
	_storage_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_storage_summary_label.add_theme_font_size_override("font_size", 12)
	_storage_summary_label.add_theme_color_override("font_color", TEXT_MUTED)
	storage_vbox.add_child(_storage_summary_label)

	_storage_details_box = GridContainer.new()
	_storage_details_box.columns = 2
	_storage_details_box.visible = false
	_storage_details_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_storage_details_box.add_theme_constant_override("h_separation", 16)
	_storage_details_box.add_theme_constant_override("v_separation", 3)
	storage_vbox.add_child(_storage_details_box)

	_storage_default_label = _add_storage_detail_label(_storage_details_box)
	_storage_saves_label = _add_storage_detail_label(_storage_details_box)
	_storage_logs_label = _add_storage_detail_label(_storage_details_box)
	_storage_exports_label = _add_storage_detail_label(_storage_details_box)
	_storage_vignettes_label = _add_storage_detail_label(_storage_details_box)
	_storage_scenarios_label = _add_storage_detail_label(_storage_details_box)
	_storage_lorebooks_label = _add_storage_detail_label(_storage_details_box)
	_storage_persona_label = _add_storage_detail_label(_storage_details_box)

	_storage_file_dialog = FileDialog.new()
	_storage_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_storage_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_storage_file_dialog.title = "Choose Storage Folder"
	_storage_file_dialog.dir_selected.connect(_on_storage_folder_selected)
	add_child(_storage_file_dialog)


func _add_storage_detail_label(parent: Container) -> Label:
	var label: = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", TEXT_MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _load_from_config() -> void :
	for control_id in _dialogue_control_fields:
		_load_dialogue_control_fields(control_id, UISettingsManager.get_dialogue_control_options(control_id))

	_select_game_title_mode(UISettingsManager.get_game_title_mode())
	_select_language(_language_option, UISettingsManager.get_language())
	_select_language(_story_language_option, UISettingsManager.get_story_language())
	_window_mode_option.select(_window_mode_option.get_item_index(UISettingsManager.get_window_mode()))
	_select_resolution(UISettingsManager.get_resolution())
	_vsync_check.button_pressed = UISettingsManager.get_vsync()
	_foregrounds_enabled_check.button_pressed = UISettingsManager.get_foregrounds_enabled()
	_update_resolution_enabled()
	_load_storage_from_config()
	_music_volume_slider.value = UISettingsManager.get_music_volume()
	_sfx_volume_slider.value = UISettingsManager.get_sfx_volume()
	_refresh_audio_mute_button(_music_mute_button, UISettingsManager.is_music_muted())
	_refresh_audio_mute_button(_sfx_mute_button, UISettingsManager.is_sfx_muted())

	_width_spinbox.value = UISettingsManager.get_dialogue_box_width()
	_height_spinbox.value = UISettingsManager.get_dialogue_box_height()
	_dialogue_text_size_slider.value = UISettingsManager.get_dialogue_text_size()
	_dialogue_reveal_speed_slider.value = UISettingsManager.get_dialogue_reveal_speed()
	_typing_sounds_enabled_check.button_pressed = UISettingsManager.get_typing_sounds_enabled()
	_typing_sounds_path_edit.text = UISettingsManager.get_typing_sounds_path()
	_typing_sounds_volume_slider.value = UISettingsManager.get_typing_sounds_volume()
	_ai_notify_flash_check.button_pressed = UISettingsManager.get_ai_notify_flash_enabled()
	_ai_notify_sound_check.button_pressed = UISettingsManager.get_ai_notify_sound_enabled()
	_ai_reply_autosave_option.select(_ai_reply_autosave_option.get_item_index(UISettingsManager.get_ai_reply_autosave_interval()))
	_qa_pass_time_check.button_pressed = UISettingsManager.get_qa_pass_time_enabled()
	_qa_guidance_check.button_pressed = UISettingsManager.get_qa_guidance_enabled()
	_qa_dice_panel_check.button_pressed = UISettingsManager.get_qa_dice_result_panel_enabled()
	_menu_scale_slider.value = UISettingsManager.get_menu_panel_scale()
	if _desktop_scale_slider != null:
		_desktop_scale_slider.value = UISettingsManager.get_desktop_ui_scale()
	if _mobile_scale_slider != null:
		_mobile_scale_slider.value = UISettingsManager.get_mobile_ui_scale()
	_box_fill_picker.color = UISettingsManager.get_dialogue_box_fill()
	_box_outline_picker.color = UISettingsManager.get_dialogue_box_outline()
	_main_button_label_edit.text = UISettingsManager.get_main_button_label()
	_main_button_fill_picker.color = UISettingsManager.get_main_button_fill()
	_main_button_outline_picker.color = UISettingsManager.get_main_button_outline()
	_main_button_text_picker.color = UISettingsManager.get_main_button_text()
	_dice_button_label_edit.text = UISettingsManager.get_dice_button_label()
	_dice_button_fill_picker.color = UISettingsManager.get_dice_button_fill()
	_dice_button_outline_picker.color = UISettingsManager.get_dice_button_outline()
	_dice_button_text_picker.color = UISettingsManager.get_dice_button_text()
	_roster_button_label_edit.text = UISettingsManager.get_roster_button_label()
	_roster_button_fill_picker.color = UISettingsManager.get_roster_button_fill()
	_roster_button_outline_picker.color = UISettingsManager.get_roster_button_outline()
	_roster_button_text_picker.color = UISettingsManager.get_roster_button_text()
	_location_button_label_edit.text = UISettingsManager.get_location_button_label()
	_location_button_fill_picker.color = UISettingsManager.get_location_button_fill()
	_location_button_outline_picker.color = UISettingsManager.get_location_button_outline()
	_location_button_text_picker.color = UISettingsManager.get_location_button_text()
	_map_menu_fill_picker.color = UISettingsManager.get_map_menu_fill()
	_map_menu_outline_picker.color = UISettingsManager.get_map_menu_outline()
	_map_menu_text_picker.color = UISettingsManager.get_map_menu_text()
	_map_popup_fill_picker.color = UISettingsManager.get_map_popup_fill()
	_map_popup_outline_picker.color = UISettingsManager.get_map_popup_outline()
	_map_popup_text_picker.color = UISettingsManager.get_map_popup_text()

	_solo_scale_slider.value = UISettingsManager.get_solo_scale()
	_duo_scale_slider.value = UISettingsManager.get_duo_scale()
	_trio_scale_slider.value = UISettingsManager.get_trio_scale()
	_quartet_scale_slider.value = UISettingsManager.get_quartet_scale()
	_quintet_scale_slider.value = UISettingsManager.get_quintet_scale()
	_sextet_scale_slider.value = UISettingsManager.get_sextet_scale()


func _load_storage_from_config() -> void :
	if _storage_path_edit == null:
		return
	if ContentPaths != null and ContentPaths.has_method("get_storage_base_dir"):
		_storage_path_edit.text = ContentPaths.get_storage_base_dir()
	else:
		_storage_path_edit.text = ProjectSettings.globalize_path("user://")
	_refresh_storage_preview()


func _refresh_storage_preview() -> void :
	if _storage_path_edit == null or _storage_default_label == null or _storage_summary_label == null:
		return

	var default_base: = ProjectSettings.globalize_path("user://")
	var save_dir: = ProjectSettings.globalize_path("user://dialogic/saves")
	var logs_dir: = ProjectSettings.globalize_path("user://logs")
	var exports_dir: = ProjectSettings.globalize_path("user://exports")
	var vignettes_dir: = ProjectSettings.globalize_path("user://vignettes")
	var scenarios_dir: = ProjectSettings.globalize_path("user://scenarios")
	var lorebooks_dir: = ProjectSettings.globalize_path("user://lorebooks")
	var persona_dir: = ProjectSettings.globalize_path("user://persona")
	if ContentPaths != null:
		if ContentPaths.has_method("get_default_storage_base_dir"):
			default_base = ContentPaths.get_default_storage_base_dir()
		if ContentPaths.has_method("get_save_slots_dir_for_base"):
			save_dir = ContentPaths.get_save_slots_dir_for_base(_storage_path_edit.text)
		if ContentPaths.has_method("get_logs_dir_for_base"):
			logs_dir = ContentPaths.get_logs_dir_for_base(_storage_path_edit.text)
		if ContentPaths.has_method("get_exports_dir_for_base"):
			exports_dir = ContentPaths.get_exports_dir_for_base(_storage_path_edit.text)
		if ContentPaths.has_method("get_vignettes_user_dir_for_base"):
			vignettes_dir = ContentPaths.get_vignettes_user_dir_for_base(_storage_path_edit.text)
		if ContentPaths.has_method("get_scenarios_user_dir_for_base"):
			scenarios_dir = ContentPaths.get_scenarios_user_dir_for_base(_storage_path_edit.text)
		if ContentPaths.has_method("get_lorebooks_user_dir_for_base"):
			lorebooks_dir = ContentPaths.get_lorebooks_user_dir_for_base(_storage_path_edit.text)
		if ContentPaths.has_method("get_persona_dir_for_base"):
			persona_dir = ContentPaths.get_persona_dir_for_base(_storage_path_edit.text)

	_storage_summary_label.text = tr("Default: %s\nSaves: %s\nLogs: %s") % [
		default_base, 
		save_dir if not save_dir.is_empty() else tr("(invalid path)"), 
		logs_dir if not logs_dir.is_empty() else tr("(invalid path)"), 
	]
	_storage_default_label.text = tr("Default: %s") % default_base
	_storage_saves_label.text = tr("Saves: %s") % (save_dir if not save_dir.is_empty() else tr("(invalid path)"))
	_storage_logs_label.text = tr("Logs: %s") % (logs_dir if not logs_dir.is_empty() else tr("(invalid path)"))
	_storage_exports_label.text = tr("Exports: %s") % (exports_dir if not exports_dir.is_empty() else tr("(invalid path)"))
	_storage_vignettes_label.text = tr("Vignettes: %s") % (vignettes_dir if not vignettes_dir.is_empty() else tr("(invalid path)"))
	_storage_scenarios_label.text = tr("User scenarios: %s") % (scenarios_dir if not scenarios_dir.is_empty() else tr("(invalid path)"))
	_storage_lorebooks_label.text = tr("Lorebooks: %s") % (lorebooks_dir if not lorebooks_dir.is_empty() else tr("(invalid path)"))
	_storage_persona_label.text = tr("Persona text files: %s") % (persona_dir if not persona_dir.is_empty() else tr("(invalid path)"))


func _on_storage_details_toggled(pressed: bool) -> void :
	if _storage_details_box != null:
		_storage_details_box.visible = pressed
	if _storage_details_toggle != null:
		_storage_details_toggle.text = tr("Hide") if pressed else tr("Details")


func _on_save_pressed() -> void :
	_voice_options.save()

	var selected_game_title_mode: = UISettingsManager.get_game_title_mode()
	if _game_title_option != null and _game_title_option.selected >= 0:
		selected_game_title_mode = str(_game_title_option.get_item_metadata(_game_title_option.selected))
	var selected_window_mode: = _window_mode_option.get_selected_id()
	var res_idx: = _resolution_option.get_selected_id()
	var selected_resolution: = UISettingsManager.get_resolution()
	if res_idx >= 0 and res_idx < UISettingsManager.RESOLUTION_LIST.size():
		selected_resolution = UISettingsManager.RESOLUTION_LIST[res_idx]
	var selected_vsync: = _vsync_check.button_pressed
	var display_changed: = (
		selected_window_mode != _original_window_mode
		or selected_resolution != _original_resolution
		or selected_vsync != _original_vsync
	)
	var previous_storage_base: = ""
	if ContentPaths != null and ContentPaths.has_method("set_storage_base_dir") and _storage_path_edit != null:
		previous_storage_base = ContentPaths.get_storage_base_dir()
		var storage_error: Error = ContentPaths.set_storage_base_dir(_storage_path_edit.text, true)
		if storage_error != OK:
			_status_label.text = tr("Could not use storage folder: %s") % error_string(storage_error)
			return
		_refresh_storage_preview()
		_reload_storage_backed_content()
	UISettingsManager.set_game_title_mode(selected_game_title_mode)
	UISettingsManager.set_language(_selected_language(_language_option, UISettingsManager.get_language()))
	UISettingsManager.set_story_language(_selected_language(_story_language_option, UISettingsManager.get_story_language()))
	UISettingsManager.set_window_mode(selected_window_mode)
	UISettingsManager.set_resolution(selected_resolution)
	UISettingsManager.set_vsync(selected_vsync)
	UISettingsManager.set_foregrounds_enabled(_foregrounds_enabled_check.button_pressed)
	UISettingsManager.set_music_volume(_music_volume_slider.value)
	UISettingsManager.set_sfx_volume(_sfx_volume_slider.value)

	UISettingsManager.set_dialogue_box_width(int(_width_spinbox.value))
	UISettingsManager.set_dialogue_box_height(int(_height_spinbox.value))
	UISettingsManager.set_dialogue_text_size(int(_dialogue_text_size_slider.value))
	UISettingsManager.set_dialogue_reveal_speed(_dialogue_reveal_speed_slider.value)
	UISettingsManager.set_typing_sounds_enabled(_typing_sounds_enabled_check.button_pressed)
	UISettingsManager.set_typing_sounds_path(_typing_sounds_path_edit.text)
	UISettingsManager.set_typing_sounds_volume(_typing_sounds_volume_slider.value)
	UISettingsManager.set_ai_notify_flash_enabled(_ai_notify_flash_check.button_pressed)
	UISettingsManager.set_ai_notify_sound_enabled(_ai_notify_sound_check.button_pressed)
	UISettingsManager.set_ai_reply_autosave_interval(_ai_reply_autosave_option.get_selected_id())
	UISettingsManager.set_qa_pass_time_enabled(_qa_pass_time_check.button_pressed)
	UISettingsManager.set_qa_guidance_enabled(_qa_guidance_check.button_pressed)
	UISettingsManager.set_qa_dice_result_panel_enabled(_qa_dice_panel_check.button_pressed)
	UISettingsManager.set_menu_panel_scale(_menu_scale_slider.value)
	if _desktop_scale_slider != null:
		UISettingsManager.set_desktop_ui_scale(_desktop_scale_slider.value)
	if _mobile_scale_slider != null:
		UISettingsManager.set_mobile_ui_scale(_mobile_scale_slider.value)
	UISettingsManager.set_dialogue_box_fill(_box_fill_picker.color)
	UISettingsManager.set_dialogue_box_outline(_box_outline_picker.color)
	UISettingsManager.set_main_button_label(_main_button_label_edit.text)
	UISettingsManager.set_main_button_fill(_main_button_fill_picker.color)
	UISettingsManager.set_main_button_outline(_main_button_outline_picker.color)
	UISettingsManager.set_main_button_text(_main_button_text_picker.color)
	UISettingsManager.set_dice_button_label(_dice_button_label_edit.text)
	UISettingsManager.set_dice_button_fill(_dice_button_fill_picker.color)
	UISettingsManager.set_dice_button_outline(_dice_button_outline_picker.color)
	UISettingsManager.set_dice_button_text(_dice_button_text_picker.color)
	UISettingsManager.set_roster_button_label(_roster_button_label_edit.text)
	UISettingsManager.set_roster_button_fill(_roster_button_fill_picker.color)
	UISettingsManager.set_roster_button_outline(_roster_button_outline_picker.color)
	UISettingsManager.set_roster_button_text(_roster_button_text_picker.color)
	UISettingsManager.set_location_button_label(_location_button_label_edit.text)
	UISettingsManager.set_location_button_fill(_location_button_fill_picker.color)
	UISettingsManager.set_location_button_outline(_location_button_outline_picker.color)
	UISettingsManager.set_location_button_text(_location_button_text_picker.color)
	UISettingsManager.set_map_menu_fill(_map_menu_fill_picker.color)
	UISettingsManager.set_map_menu_outline(_map_menu_outline_picker.color)
	UISettingsManager.set_map_menu_text(_map_menu_text_picker.color)
	UISettingsManager.set_map_popup_fill(_map_popup_fill_picker.color)
	UISettingsManager.set_map_popup_outline(_map_popup_outline_picker.color)
	UISettingsManager.set_map_popup_text(_map_popup_text_picker.color)
	UISettingsManager.set_solo_scale(_solo_scale_slider.value)
	UISettingsManager.set_duo_scale(_duo_scale_slider.value)
	UISettingsManager.set_trio_scale(_trio_scale_slider.value)
	UISettingsManager.set_quartet_scale(_quartet_scale_slider.value)
	UISettingsManager.set_quintet_scale(_quintet_scale_slider.value)
	UISettingsManager.set_sextet_scale(_sextet_scale_slider.value)
	for control_id in _dialogue_control_fields:
		var fields: Dictionary = _dialogue_control_fields[control_id]
		var options: = {
			"visible": fields["visible"].button_pressed, 
			"show_icon": fields["show_icon"].button_pressed if fields.has("show_icon") else true, 
			"opacity": fields["opacity"].value / 100.0, 
		}
		for key in ["label", "stop_label", "cancel_label"]:
			if fields.has(key):
				options[key] = fields[key].text
		UISettingsManager.set_dialogue_control_options(control_id, options)
	var err: = UISettingsManager.save_config()
	if err != OK:
		var rollback_error: = OK
		if not previous_storage_base.is_empty() and ContentPaths != null:
			rollback_error = ContentPaths.set_storage_base_dir(previous_storage_base, false)
			_storage_path_edit.text = ContentPaths.get_storage_base_dir()
			_refresh_storage_preview()
			_reload_storage_backed_content()
		_status_label.text = (
			tr("Could not save UI settings; the storage folder was restored.")
			if rollback_error == OK
			else tr("Could not save UI settings or restore the previous storage folder.")
		)
		return
	if display_changed:
		UISettingsManager.apply_display_settings()
	LanguagePacks.apply_story_language()
	_close()


func _on_reset_pressed() -> void :
	_voice_options.reset()
	for control_id in _dialogue_control_fields:
		_load_dialogue_control_fields(control_id, {})
	_select_game_title_mode(UISettingsManager.DEFAULT_GAME_TITLE_MODE)
	_select_language(_language_option, "")
	_select_language(_story_language_option, "")
	_window_mode_option.select(_window_mode_option.get_item_index(UISettingsManager.DEFAULT_WINDOW_MODE))
	_select_resolution(UISettingsManager.DEFAULT_RESOLUTION)
	_vsync_check.button_pressed = UISettingsManager.DEFAULT_VSYNC
	_foregrounds_enabled_check.button_pressed = UISettingsManager.DEFAULT_FOREGROUNDS_ENABLED
	_update_resolution_enabled()
	if _storage_path_edit != null:
		_storage_path_edit.text = ContentPaths.get_default_storage_base_dir() if ContentPaths != null and ContentPaths.has_method("get_default_storage_base_dir") else ProjectSettings.globalize_path("user://")
		_refresh_storage_preview()
	_music_volume_slider.value = UISettingsManager.DEFAULT_MUSIC_VOLUME
	_sfx_volume_slider.value = UISettingsManager.DEFAULT_SFX_VOLUME
	UISettingsManager.set_music_muted(UISettingsManager.DEFAULT_MUSIC_MUTED)
	UISettingsManager.set_sfx_muted(UISettingsManager.DEFAULT_SFX_MUTED)
	_refresh_audio_mute_button(_music_mute_button, UISettingsManager.is_music_muted())
	_refresh_audio_mute_button(_sfx_mute_button, UISettingsManager.is_sfx_muted())
	UISettingsManager.apply_runtime_settings()
	_width_spinbox.value = UISettingsManager.DEFAULT_DIALOGUE_BOX_WIDTH
	_height_spinbox.value = UISettingsManager.DEFAULT_DIALOGUE_BOX_HEIGHT
	_dialogue_text_size_slider.value = UISettingsManager.DEFAULT_DIALOGUE_TEXT_SIZE
	_dialogue_reveal_speed_slider.value = UISettingsManager.DEFAULT_DIALOGUE_REVEAL_SPEED
	_typing_sounds_enabled_check.button_pressed = UISettingsManager.DEFAULT_TYPING_SOUNDS_ENABLED
	_typing_sounds_path_edit.text = UISettingsManager.DEFAULT_TYPING_SOUNDS_PATH
	_typing_sounds_volume_slider.value = UISettingsManager.DEFAULT_TYPING_SOUNDS_VOLUME
	_ai_notify_flash_check.button_pressed = UISettingsManager.DEFAULT_AI_NOTIFY_FLASH_ENABLED
	_ai_notify_sound_check.button_pressed = UISettingsManager.DEFAULT_AI_NOTIFY_SOUND_ENABLED
	_ai_reply_autosave_option.select(_ai_reply_autosave_option.get_item_index(UISettingsManager.DEFAULT_AI_REPLY_AUTOSAVE_INTERVAL))
	_qa_pass_time_check.button_pressed = UISettingsManager.DEFAULT_QA_PASS_TIME_ENABLED
	_qa_guidance_check.button_pressed = UISettingsManager.DEFAULT_QA_GUIDANCE_ENABLED
	_qa_dice_panel_check.button_pressed = UISettingsManager.DEFAULT_QA_DICE_RESULT_PANEL_ENABLED
	_menu_scale_slider.value = UISettingsManager.DEFAULT_MENU_PANEL_SCALE
	if _desktop_scale_slider != null:
		_desktop_scale_slider.value = UISettingsManager.DEFAULT_DESKTOP_UI_SCALE
	if _mobile_scale_slider != null:
		_mobile_scale_slider.value = UISettingsManager.DEFAULT_MOBILE_UI_SCALE
	_box_fill_picker.color = UISettingsManager.DEFAULT_DIALOGUE_BOX_FILL
	_box_outline_picker.color = UISettingsManager.DEFAULT_DIALOGUE_BOX_OUTLINE
	_main_button_label_edit.text = UISettingsManager.DEFAULT_MAIN_BUTTON_LABEL
	_main_button_fill_picker.color = UISettingsManager.DEFAULT_MAIN_BUTTON_FILL
	_main_button_outline_picker.color = UISettingsManager.DEFAULT_MAIN_BUTTON_OUTLINE
	_main_button_text_picker.color = UISettingsManager.DEFAULT_MAIN_BUTTON_TEXT
	_dice_button_label_edit.text = UISettingsManager.DEFAULT_DICE_BUTTON_LABEL
	_dice_button_fill_picker.color = UISettingsManager.DEFAULT_DICE_BUTTON_FILL
	_dice_button_outline_picker.color = UISettingsManager.DEFAULT_DICE_BUTTON_OUTLINE
	_dice_button_text_picker.color = UISettingsManager.DEFAULT_DICE_BUTTON_TEXT
	_roster_button_label_edit.text = UISettingsManager.DEFAULT_ROSTER_BUTTON_LABEL
	_roster_button_fill_picker.color = UISettingsManager.DEFAULT_ROSTER_BUTTON_FILL
	_roster_button_outline_picker.color = UISettingsManager.DEFAULT_ROSTER_BUTTON_OUTLINE
	_roster_button_text_picker.color = UISettingsManager.DEFAULT_ROSTER_BUTTON_TEXT
	_location_button_label_edit.text = UISettingsManager.DEFAULT_LOCATION_BUTTON_LABEL
	_location_button_fill_picker.color = UISettingsManager.DEFAULT_LOCATION_BUTTON_FILL
	_location_button_outline_picker.color = UISettingsManager.DEFAULT_LOCATION_BUTTON_OUTLINE
	_location_button_text_picker.color = UISettingsManager.DEFAULT_LOCATION_BUTTON_TEXT
	_map_menu_fill_picker.color = UISettingsManager.DEFAULT_MAP_MENU_FILL
	_map_menu_outline_picker.color = UISettingsManager.DEFAULT_MAP_MENU_OUTLINE
	_map_menu_text_picker.color = UISettingsManager.DEFAULT_MAP_MENU_TEXT
	_map_popup_fill_picker.color = UISettingsManager.DEFAULT_MAP_POPUP_FILL
	_map_popup_outline_picker.color = UISettingsManager.DEFAULT_MAP_POPUP_OUTLINE
	_map_popup_text_picker.color = UISettingsManager.DEFAULT_MAP_POPUP_TEXT
	_solo_scale_slider.value = UISettingsManager.DEFAULT_SOLO_SCALE
	_duo_scale_slider.value = UISettingsManager.DEFAULT_DUO_SCALE
	_trio_scale_slider.value = UISettingsManager.DEFAULT_TRIO_SCALE
	_quartet_scale_slider.value = UISettingsManager.DEFAULT_QUARTET_SCALE
	_quintet_scale_slider.value = UISettingsManager.DEFAULT_QUINTET_SCALE
	_sextet_scale_slider.value = UISettingsManager.DEFAULT_SEXTET_SCALE
	_status_label.text = "Defaults loaded. Save to apply them."


func _mark_field_reset(field_label: String) -> void :
	_status_label.text = tr("%s reset. Save to apply it.") % field_label


func _on_cancel_pressed() -> void :
	_voice_options.cancel()
	UISettingsManager.set_music_volume(_original_music_volume)
	UISettingsManager.set_sfx_volume(_original_sfx_volume)
	UISettingsManager.set_music_muted(_original_music_muted)
	UISettingsManager.set_sfx_muted(_original_sfx_muted)
	UISettingsManager.apply_runtime_settings()
	_close()


func _on_storage_path_text_changed(_new_text: String) -> void :
	_refresh_storage_preview()


func _on_use_default_storage_pressed() -> void :
	if _storage_path_edit == null:
		return
	_storage_path_edit.text = ContentPaths.get_default_storage_base_dir() if ContentPaths != null and ContentPaths.has_method("get_default_storage_base_dir") else ProjectSettings.globalize_path("user://")
	_refresh_storage_preview()
	_status_label.text = "Default storage folder selected. Save to apply it."


func _on_browse_storage_folder_pressed() -> void :
	if _storage_file_dialog == null:
		return
	var current_dir: = _resolve_storage_edit_path()
	_storage_file_dialog.current_dir = current_dir if not current_dir.is_empty() else ProjectSettings.globalize_path("user://")
	_storage_file_dialog.popup_centered_ratio(0.72)


func _on_storage_folder_selected(path: String) -> void :
	if _storage_path_edit == null:
		return
	_storage_path_edit.text = path
	_refresh_storage_preview()
	_status_label.text = "Storage folder selected. Save to apply it."


func _on_open_storage_folder_pressed() -> void :
	var folder_path: = _resolve_storage_edit_path()
	if folder_path.is_empty():
		_status_label.text = "Storage folder must be an absolute path."
		return
	var dir_error: = DirAccess.make_dir_recursive_absolute(folder_path)
	if dir_error != OK:
		_status_label.text = "Could not prepare storage folder."
		return
	var open_error: = OS.shell_open(folder_path)
	if open_error != OK:
		_status_label.text = "Could not open storage folder."
		return
	_status_label.text = "Opened storage folder."


func _resolve_storage_edit_path() -> String:
	if _storage_path_edit == null:
		return ""
	if ContentPaths != null and ContentPaths.has_method("resolve_storage_base_dir"):
		return ContentPaths.resolve_storage_base_dir(_storage_path_edit.text)
	var raw: = _storage_path_edit.text.strip_edges()
	if raw.is_empty():
		return ProjectSettings.globalize_path("user://")
	if raw.begins_with("user://") or raw.begins_with("res://"):
		raw = ProjectSettings.globalize_path(raw)
	return raw if raw.is_absolute_path() else ""


func _reload_storage_backed_content() -> void :
	if ScenarioManager != null and ScenarioManager.has_method("rediscover"):
		ScenarioManager.rediscover()
	if VignetteLoader != null and VignetteLoader.has_method("reload_vignettes"):
		VignetteLoader.reload_vignettes()
	if LorebookManager != null and LorebookManager.has_method("reload"):
		LorebookManager.reload()


func _on_open_typing_sounds_folder_pressed() -> void :
	var folder_path: = UISettingsManager.ensure_typing_sounds_directory(_typing_sounds_path_edit.text)
	if folder_path.is_empty():
		_status_label.text = "Could not resolve the typing sounds folder."
		return
	OS.shell_open(folder_path)
	_status_label.text = "Opened typing sounds folder."


func _toggle_color_section(key: String) -> void :
	_color_section_open[key] = not bool(_color_section_open.get(key, false))
	_refresh_color_section_state(key)


func _refresh_color_section_state(key: String) -> void :
	var button: Button = _color_section_buttons.get(key, null)
	var body: VBoxContainer = _color_section_bodies.get(key, null)
	var is_open: = bool(_color_section_open.get(key, false))
	if body != null:
		body.visible = is_open
	if button != null:
		button.text = "%s  %s" % ["▼" if is_open else "►", tr(_color_section_titles.get(key, key.capitalize()))]


func _add_color_section(parent: VBoxContainer, key: String, description: String) -> VBoxContainer:
	var section_panel: = PanelContainer.new()
	section_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_panel.add_theme_stylebox_override("panel", _make_foldout_style())
	parent.add_child(section_panel)

	var section_vbox: = VBoxContainer.new()
	section_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_vbox.add_theme_constant_override("separation", 0)
	section_panel.add_child(section_vbox)

	var header_button: = Button.new()
	header_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header_button.focus_mode = Control.FOCUS_NONE
	header_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_button.add_theme_stylebox_override("normal", _make_foldout_header_style(HEADER_COLOR))
	header_button.add_theme_stylebox_override("hover", _make_foldout_header_style(HEADER_HOVER))
	header_button.add_theme_stylebox_override("pressed", _make_foldout_header_style(HEADER_HOVER))
	header_button.add_theme_color_override("font_color", TEXT_MAIN)
	header_button.add_theme_font_size_override("font_size", 16)
	header_button.pressed.connect(_toggle_color_section.bind(key))
	section_vbox.add_child(header_button)

	var body_margin: = MarginContainer.new()
	body_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_margin.add_theme_constant_override("margin_left", 14)
	body_margin.add_theme_constant_override("margin_right", 14)
	body_margin.add_theme_constant_override("margin_top", 12)
	body_margin.add_theme_constant_override("margin_bottom", 14)
	section_vbox.add_child(body_margin)

	var body: = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	body_margin.add_child(body)

	var hint: = Label.new()
	hint.text = description
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", TEXT_MUTED)
	body.add_child(hint)

	_color_section_buttons[key] = header_button
	_color_section_bodies[key] = body
	return body


func _make_panel_style() -> StyleBoxFlat:
	var style: = StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 16
	return style


func _layout_panel_for_viewport() -> void :
	if _panel == null:
		return

	var viewport_size: = get_viewport().get_visible_rect().size
	var target: = _scaled_panel_target()
	var panel_width: = minf(target.x, maxf(640.0, viewport_size.x - PANEL_VIEWPORT_MARGIN.x * 2.0))
	var panel_height: = minf(target.y, maxf(420.0, viewport_size.y - PANEL_VIEWPORT_MARGIN.y * 2.0))

	_panel.offset_left = - panel_width * 0.5
	_panel.offset_top = - panel_height * 0.5
	_panel.offset_right = panel_width * 0.5
	_panel.offset_bottom = panel_height * 0.5




func _scaled_panel_target() -> Vector2:
	var menu_scale: = UISettingsManager.get_menu_panel_scale()
	if _menu_scale_slider != null:
		menu_scale = clampf(_menu_scale_slider.value, UISettingsManager.MIN_MENU_PANEL_SCALE, UISettingsManager.MAX_MENU_PANEL_SCALE)
	return PANEL_TARGET_SIZE * menu_scale


func _format_menu_scale_label(value: float) -> String:
	return "%d%%" % roundi(value * 100.0)


func _make_section_style() -> StyleBoxFlat:
	var style: = StyleBoxFlat.new()
	style.bg_color = SECTION_COLOR
	style.border_color = SECTION_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	return style


func _make_foldout_style() -> StyleBoxFlat:
	var style: = StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.14, 0.21, 0.94)
	style.border_color = Color(0.22, 0.34, 0.48, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	return style


func _make_foldout_header_style(fill_color: Color) -> StyleBoxFlat:
	var style: = StyleBoxFlat.new()
	style.bg_color = fill_color
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _make_action_style(fill_color: Color) -> StyleBoxFlat:
	var style: = StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = fill_color.lerp(Color.WHITE, 0.18)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _make_inline_reset_button(tooltip_text: String, callback: Callable) -> Button:
	var button: = Button.new()
	button.text = "Reset"
	button.tooltip_text = tooltip_text
	button.custom_minimum_size = Vector2(74, 34)
	button.add_theme_stylebox_override("normal", _make_action_style(Color(0.18, 0.23, 0.31, 0.94)))
	button.add_theme_stylebox_override("hover", _make_action_style(Color(0.24, 0.31, 0.42, 1.0)))
	button.add_theme_color_override("font_color", TEXT_MAIN)
	button.pressed.connect(callback)
	return button


func _add_inline_reset_button(parent: BoxContainer, tooltip_text: String, callback: Callable) -> Button:
	var button: = _make_inline_reset_button(tooltip_text, callback)
	parent.add_child(button)
	return button


func _make_separator() -> ColorRect:
	var separator: = ColorRect.new()
	separator.custom_minimum_size = Vector2(0, 1)
	separator.color = Color(1, 1, 1, 0.08)
	return separator


func _add_spinbox_row(parent: VBoxContainer, label_text: String, min_value: float, max_value: float, step: float, tooltip_text: String, reset_callback: Callable = Callable()) -> SpinBox:
	var row: = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var label: = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", TEXT_MAIN)
	row.add_child(label)

	var spinbox: = SpinBox.new()
	spinbox.min_value = min_value
	spinbox.max_value = max_value
	spinbox.step = step
	spinbox.custom_minimum_size = Vector2(150, 0)
	spinbox.tooltip_text = tooltip_text
	row.add_child(spinbox)
	if reset_callback.is_valid():
		_add_inline_reset_button(row, tr("Reset this field to its default value."), reset_callback)
	return spinbox


func _add_scale_slider_row(parent: VBoxContainer, label_text: String, min_val: float, max_val: float, default_val: float, reset_callback: Callable = Callable()) -> Array:
	var row: = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var label: = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 60
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", TEXT_MAIN)
	row.add_child(label)

	var slider: = HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = 0.05
	slider.value = default_val
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(200, 0)
	row.add_child(slider)

	var value_label: = Label.new()
	value_label.text = "%d%%" % int(default_val * 100)
	value_label.custom_minimum_size.x = 50
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 15)
	value_label.add_theme_color_override("font_color", TEXT_ACCENT)
	row.add_child(value_label)
	if reset_callback.is_valid():
		_add_inline_reset_button(row, tr("Reset this field to its default value."), reset_callback)

	slider.value_changed.connect( func(val: float) -> void : value_label.text = "%d%%" % int(val * 100))
	return [slider, value_label]


func _add_value_slider_row(parent: VBoxContainer, label_text: String, min_val: float, max_val: float, step: float, default_val: float, formatter: Callable, reset_callback: Callable = Callable()) -> Array:
	var row: = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var label: = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 140
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", TEXT_MAIN)
	row.add_child(label)

	var slider: = HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step
	slider.value = default_val
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(200, 0)
	row.add_child(slider)

	var value_label: = Label.new()
	value_label.text = formatter.call(default_val)
	value_label.custom_minimum_size.x = 64
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 15)
	value_label.add_theme_color_override("font_color", TEXT_ACCENT)
	row.add_child(value_label)
	if reset_callback.is_valid():
		_add_inline_reset_button(row, tr("Reset this field to its default value."), reset_callback)

	slider.value_changed.connect( func(val: float) -> void : value_label.text = formatter.call(val))
	return [slider, value_label, row]


func _add_audio_mute_button(parent: HBoxContainer, tooltip_text: String, pressed_callback: Callable) -> Button:
	var button: = Button.new()
	button.custom_minimum_size = Vector2(78, 32)
	button.tooltip_text = tooltip_text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(pressed_callback)
	parent.add_child(button)
	return button


func _refresh_audio_mute_button(button: Button, is_muted: bool) -> void :
	if button == null:
		return
	button.text = tr("Unmute") if is_muted else tr("Mute")
	button.tooltip_text = tr("Audio is muted. Click to unmute.") if is_muted else tr("Audio is audible. Click to mute.")


func _add_text_row(parent: VBoxContainer, label_text: String, tooltip_text: String, reset_callback: Callable = Callable()) -> LineEdit:
	var row: = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var label: = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", TEXT_MAIN)
	row.add_child(label)

	var line_edit: = LineEdit.new()
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit.custom_minimum_size = Vector2(190, 34)
	line_edit.placeholder_text = "Button text"
	line_edit.tooltip_text = tooltip_text
	row.add_child(line_edit)
	if reset_callback.is_valid():
		_add_inline_reset_button(row, tr("Reset this field to its default value."), reset_callback)
	return line_edit


func _add_color_row(parent: VBoxContainer, label_text: String, tooltip_text: String, reset_callback: Callable = Callable()) -> ColorPickerButton:
	var row: = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var label: = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", TEXT_MAIN)
	row.add_child(label)

	var picker: = ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(190, 34)
	picker.edit_alpha = true
	picker.tooltip_text = tooltip_text
	row.add_child(picker)
	if reset_callback.is_valid():
		_add_inline_reset_button(row, tr("Reset this field to its default value."), reset_callback)
	return picker


func _format_db_label(value: float) -> String:
	return "%+.0f dB" % value


func _format_dialogue_text_size_label(value: float) -> String:
	return "%d pt" % int(round(value))


func _format_dialogue_speed_label(value: float) -> String:
	if is_zero_approx(value):
		return tr("Instant")
	return "%.1fx" % value



func _add_language_row(parent: VBoxContainer, label_text: String, automatic: String) -> OptionButton:
	var row: = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var label: = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 140
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", TEXT_MAIN)
	row.add_child(label)
	var option: = OptionButton.new()
	option.custom_minimum_size.x = 260
	option.add_item(automatic)
	option.set_item_metadata(0, "")
	option.add_item("English")
	option.set_item_metadata(1, LanguagePacks.ENGLISH)
	for pack: Dictionary in LanguagePacks.get_packs():
		option.add_item(str(pack.name))
		option.set_item_metadata(option.item_count - 1, str(pack.locale))

		option.set_item_auto_translate_mode(option.item_count - 1, Node.AUTO_TRANSLATE_MODE_DISABLED)
	option.set_item_auto_translate_mode(1, Node.AUTO_TRANSLATE_MODE_DISABLED)
	TouchScrollGesture.configure_option_button(option)
	row.add_child(option)
	return option


func _select_language(option: OptionButton, locale: String) -> void :
	if option == null:
		return
	for i in range(option.item_count):
		if str(option.get_item_metadata(i)) == locale:
			option.select(i)
			return
	option.select(0)


func _selected_language(option: OptionButton, fallback: String) -> String:
	if option == null or option.selected < 0:
		return fallback
	return str(option.get_item_metadata(option.selected))


func _select_game_title_mode(target: String) -> void :
	if _game_title_option == null:
		return
	for i in range(_game_title_option.item_count):
		if str(_game_title_option.get_item_metadata(i)) == target:
			_game_title_option.select(i)
			return
	if _game_title_option.item_count > 0:
		_game_title_option.select(0)


func _select_resolution(target: Vector2i) -> void :
	while _resolution_option.item_count > UISettingsManager.RESOLUTION_LIST.size():
		_resolution_option.remove_item(_resolution_option.item_count - 1)
	for i in range(UISettingsManager.RESOLUTION_LIST.size()):
		if UISettingsManager.RESOLUTION_LIST[i] == target:
			_resolution_option.select(i)
			return


	_resolution_option.add_item(tr("%d x %d  (Current)") % [target.x, target.y], UISettingsManager.RESOLUTION_LIST.size())
	_resolution_option.select(_resolution_option.item_count - 1)


func _update_resolution_enabled() -> void :

	var is_windowed: = _window_mode_option.get_selected_id() == UISettingsManager.WINDOW_MODE_WINDOWED
	_resolution_option.disabled = not is_windowed


func _on_window_mode_changed(_index: int) -> void :
	_update_resolution_enabled()


func _on_music_volume_preview_changed(value: float) -> void :
	UISettingsManager.set_music_volume(value)
	UISettingsManager.apply_runtime_settings()


func _on_sfx_volume_preview_changed(value: float) -> void :
	UISettingsManager.set_sfx_volume(value)
	UISettingsManager.apply_runtime_settings()


func _on_music_mute_pressed() -> void :
	UISettingsManager.set_music_muted( not UISettingsManager.is_music_muted())
	_refresh_audio_mute_button(_music_mute_button, UISettingsManager.is_music_muted())
	UISettingsManager.apply_runtime_settings()


func _on_sfx_mute_pressed() -> void :
	UISettingsManager.set_sfx_muted( not UISettingsManager.is_sfx_muted())
	_refresh_audio_mute_button(_sfx_mute_button, UISettingsManager.is_sfx_muted())
	UISettingsManager.apply_runtime_settings()

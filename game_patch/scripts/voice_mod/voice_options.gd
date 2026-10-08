extends VBoxContainer

const MAIN := Color(0.92, 0.96, 1.0)
const MUTED := Color(0.68, 0.77, 0.88)
const ACCENT := Color(1.0, 0.84, 0.44)
var controller: Node
var snapshot: Dictionary
var enabled: Button
var folder: LineEdit
var language: OptionButton
var text_mode: OptionButton
var steps: HSlider
var speed: HSlider
var volume: HSlider
var status_label: Label
var folder_dialog: FileDialog
var _observed_steps := 64

static func build(parent: VBoxContainer, tree: SceneTree, _menu: Node = null) -> Node:
	var panel := PanelContainer.new()
	panel.name = "CharacterVoices"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.16, 0.23, 0.96)
	style.border_color = Color(0.24, 0.35, 0.49, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16 if side in ["left", "right"] else 14)
	panel.add_child(margin)
	var options: Node = load("res://scripts/voice_mod/voice_options.gd").new()
	options.controller = load("res://scripts/voice_mod/voice_controller.gd").ensure(tree)
	options.snapshot = options.controller.settings.duplicate(true)
	margin.add_child(options)
	options.create_controls()
	return options

func text_label(text: String, size: int, color: Color = MAIN) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func hint(text: String, size: int = 13) -> void:
	var label := text_label(text, size, MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)

func row(label_text: String, parent: Container = self) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	var label := text_label(label_text, 15)
	label.custom_minimum_size.x = 140
	box.add_child(label)
	parent.add_child(box)
	return box

func action(parent: Container, text: String, callback: Callable, width: float = 82) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, 34)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func path_edit(parent: Container, value: String, placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(280, 34)
	edit.text = value
	edit.placeholder_text = placeholder
	parent.add_child(edit)
	return edit

func slider(label_text: String, minimum: float, maximum: float, step_size: float, value: float, format: String) -> HSlider:
	var box := row(label_text)
	var control := HSlider.new()
	control.min_value = minimum
	control.max_value = maximum
	control.step = step_size
	control.value = value
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size.x = 200
	box.add_child(control)
	var label := text_label(format % value, 15, ACCENT)
	label.custom_minimum_size.x = 64
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(label)
	control.value_changed.connect(func(val: float): label.text = format % val)
	return control

func create_controls() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	add_child(text_label("Character Voices (OmniVoice) · v" + preload("res://scripts/voice_mod/voice_version.gd").VERSION, 20))
	hint("Speaks AI dialogue lines with voice-cloned reference clips via a local OmniVoice install. The OmniVoice folder must contain a venv with the omnivoice package installed.")
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 12)
	add_child(status_row)
	status_label = text_label("Status: " + str(controller.status), 14, ACCENT)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_row.add_child(status_label)
	action(status_row, "Test Voice", test_voice, 110)
	action(status_row, "Stop", func(): controller.stop_voice(), 80)
	var toggle_row := row("Voices Enabled")
	enabled = Button.new()
	enabled.toggle_mode = true
	enabled.text = "Voices Enabled" if bool(snapshot.enabled) else "Enable Voices"
	preload("res://scripts/voice_mod/voice_preparation.gd").button_style(enabled, bool(snapshot.enabled))
	enabled.button_pressed = bool(snapshot.enabled)
	enabled.add_theme_color_override("font_color", MUTED)
	enabled.toggled.connect(func(value: bool):
		controller.set_option("enabled", value)
		enabled.text = "Voices Enabled" if value else "Enable Voices"
		preload("res://scripts/voice_mod/voice_preparation.gd").button_style(enabled, value)
	)
	toggle_row.add_child(enabled)
	var path_row := row("OmniVoice Folder")
	folder = path_edit(path_row, str(snapshot.omnivoice.get("install_path", "")), "Select OmniVoice, .venv or venv…")
	action(path_row, "Browse", browse_folder)
	var language_row := row("Voice Language")
	language = OptionButton.new()
	language.custom_minimum_size.x = 260
	language.add_item("English")
	language.set_item_metadata(0, "en")
	language.select(0)
	language_row.add_child(language)
	steps = slider("Quality (Steps)", 8, 64, 1, int(snapshot.omnivoice.get("num_step", 64)), "%d")
	_observed_steps = int(snapshot.omnivoice.get("num_step", 64))
	steps.tooltip_text = "Default: 64 steps. Fewer steps reduce generation time and voice quality."
	hint("Fewer steps increase speed but reduce voice quality. Ready-to-play story voices stay at 64 steps.", 12)
	speed = slider("Speed", 0.5, 2.0, 0.05, float(snapshot.omnivoice.get("speed", 1.0)), "%.2fx")
	volume = slider("Voice Volume", -30, 6, 1, float(snapshot.get("volume_db", 0.0)), "%+d dB")
	var text_row := row("Text Display Mode")
	text_mode = OptionButton.new()
	text_mode.add_item("Wait for Audio (Recommended)")
	text_mode.add_item("Show Instantly")
	text_mode.select(0 if str(snapshot.get("text_display_mode", "wait")) == "wait" else 1)
	text_row.add_child(text_mode)
	hint("Wait for Audio prepares every clip in the response before showing its first line. Show Instantly displays text while speech is prepared.", 12)
	var cache_row := row("Voice Cache")
	action(cache_row, "Clean Cache", func(): controller.clean_cache(), 110)
	hint("Cleans generated voices", 12)
	folder_dialog = FileDialog.new()
	folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	folder_dialog.use_native_dialog = true
	folder_dialog.title = "Choose OmniVoice Folder"
	folder_dialog.dir_selected.connect(func(path: String): folder.text = path)
	add_child(folder_dialog)
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	timer.timeout.connect(_refresh_status)
	add_child(timer)

func _refresh_status() -> void:
	status_label.text = "Status: " + str(controller.status)
	var current_steps := int(controller.settings.omnivoice.get("num_step", 64))
	if current_steps != _observed_steps:
		# A popup change is already applied. Preserve a separate unsaved proposal.
		if int(steps.value) == _observed_steps:
			steps.value = current_steps
		snapshot.omnivoice.num_step = current_steps
		_observed_steps = current_steps

func test_voice() -> void:
	save()
	controller.test_voice()

func browse_folder() -> void:
	if DirAccess.dir_exists_absolute(folder.text):
		folder_dialog.current_dir = folder.text
	folder_dialog.popup_centered_ratio(0.72)

func save() -> void:
	var settings: Dictionary = controller.settings.duplicate(true)
	settings.enabled = enabled.button_pressed
	settings.language = str(language.get_item_metadata(language.selected))
	settings.execution_mode = "local"
	settings.volume_db = volume.value
	settings.text_display_mode = "wait" if text_mode.selected == 0 else "instant"
	settings.omnivoice.num_step = int(steps.value)
	settings.omnivoice.speed = speed.value
	var selected := folder.text.strip_edges()
	settings.omnivoice.install_path = selected
	if selected != str(controller.settings.omnivoice.get("install_path", "")):
		settings.python_path = ""
		for base in [selected, selected.path_join(".venv"), selected.path_join("venv"), selected.path_join("env")]:
			for relative in ["Scripts/python.exe", "bin/python"]:
				var python: String = base.path_join(relative)
				if FileAccess.file_exists(python):
					settings.python_path = python
					break
			if not str(settings.python_path).is_empty():
				break
		settings.omnivoice.python_path = settings.python_path
	controller.apply_settings(settings)

func reset() -> void:
	_observed_steps = int(controller.settings.omnivoice.get("num_step", 64))
	enabled.button_pressed = true
	steps.value = 64
	speed.value = 1.0
	volume.value = 0
	language.select(0)
	text_mode.select(0)

func cancel() -> void:
	controller.apply_settings(snapshot)

func refresh() -> void:
	snapshot = controller.settings.duplicate(true)
	_observed_steps = int(snapshot.omnivoice.get("num_step", 64))
	enabled.set_pressed_no_signal(bool(snapshot.enabled))
	enabled.text = "Voices Enabled" if bool(snapshot.enabled) else "Enable Voices"
	preload("res://scripts/voice_mod/voice_preparation.gd").button_style(enabled, bool(snapshot.enabled))
	folder.text = str(snapshot.omnivoice.get("install_path", ""))
	steps.value = int(snapshot.omnivoice.get("num_step", 64))
	speed.value = float(snapshot.omnivoice.get("speed", 1.0))
	volume.value = float(snapshot.volume_db)
	for index in range(language.item_count):
		if str(language.get_item_metadata(index)) == str(snapshot.language):
			language.select(index)
	text_mode.select(0 if str(snapshot.get("text_display_mode", "wait")) == "wait" else 1)

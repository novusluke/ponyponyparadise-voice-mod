extends CanvasLayer
## Local synthesis progress. Only successfully prepared clips count as ready.

var controller: Node
var stack: VBoxContainer
var prompt: PanelContainer
var label: Label
var bar: ProgressBar
var steps: HSlider
var step_label: Label
var apply_button: Button
var started_msec := 0
var dismissed := false

static func button_style(button: Button, active: bool = true) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("287649") if active else Color("293747")
		if state == "hover":
			style.bg_color = style.bg_color.lightened(0.12)
		if state == "disabled":
			style.bg_color = Color("293747")
		style.set_corner_radius_all(6)
		style.set_content_margin_all(8)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color("f0f7ff"))
	button.add_theme_font_size_override("font_size", 14)

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	stack = VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 10)
	add_child(stack)
	prompt = panel(true)
	stack.add_child(prompt)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	prompt.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "Too slow? Reduce steps"
	title.add_theme_font_size_override("font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	step_label = Label.new()
	step_label.add_theme_font_size_override("font_size", 13)
	header.add_child(step_label)
	steps = HSlider.new()
	steps.min_value = 8
	steps.max_value = 64
	steps.step = 1
	steps.custom_minimum_size.y = 18
	column.add_child(steps)
	var warning := Label.new()
	warning.text = "Fewer steps increase speed but reduce voice quality."
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.add_theme_font_size_override("font_size", 12)
	warning.add_theme_color_override("font_color", Color("ffd670"))
	column.add_child(warning)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)
	apply_button = Button.new()
	apply_button.text = "Apply"
	button_style(apply_button)
	buttons.add_child(apply_button)
	apply_button.pressed.connect(func():
		if controller._preparation_rows.is_empty():
			return
		controller.apply_preparation_steps(int(steps.value))
		dismissed = true
		prompt.hide()
	)
	var keep := Button.new()
	keep.text = "Keep current"
	button_style(keep, false)
	buttons.add_child(keep)
	keep.pressed.connect(func(): dismissed = true; prompt.hide())
	steps.value_changed.connect(func(value: float):
		step_label.text = "%d steps" % int(value)
		apply_button.disabled = int(value) >= int(controller.settings.omnivoice.num_step)
	)
	var progress := panel(false)
	stack.add_child(progress)
	var progress_column := VBoxContainer.new()
	progress_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.add_child(progress_column)
	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 14)
	progress_column.add_child(label)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = 8
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("55bc7a")
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
	progress_column.add_child(bar)
	hide()
	prompt.hide()

func panel(interactive: bool) -> PanelContainer:
	var result := PanelContainer.new()
	result.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.11, 0.16, 0.98)
	style.border_color = Color("3f586e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	result.add_theme_stylebox_override("panel", style)
	return result

func begin() -> void:
	started_msec = Time.get_ticks_msec()
	dismissed = false
	prompt.hide()

func update_progress(completed: int, total: int) -> void:
	visible = total > 0 and completed < total
	if not visible:
		prompt.hide()
		return
	var percent := int(100.0 * completed / total)
	label.text = "Preparing response voices… %d%%" % percent
	bar.value = percent
	if not dismissed and not prompt.visible and int(controller.settings.omnivoice.num_step) > 8 and Time.get_ticks_msec() - started_msec >= 30000:
		steps.set_value_no_signal(int(controller.settings.omnivoice.num_step))
		step_label.text = "%d steps" % int(steps.value)
		apply_button.disabled = true
		prompt.show()
	var viewport_size := get_viewport().get_visible_rect().size
	stack.size = Vector2(minf(300.0, viewport_size.x - 32.0), 0.0)
	stack.size.y = stack.get_combined_minimum_size().y
	stack.position = viewport_size - stack.size - Vector2(16, 16)

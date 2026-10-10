extends CanvasLayer


















const StoryRowScript: = preload("res://scenes/story_panel/story_row.gd")
const StoryTokenMeterScript: = preload("res://scenes/story_panel/story_token_meter.gd")
const StoryExportDialogScript: = preload("res://scenes/story_panel/story_export_dialog.gd")
const StorySidePanelScript: = preload("res://scenes/story_panel/story_side_panel.gd")
const ExportScript: = preload("res://scripts/story/story_image_export.gd")
const TouchScrollGesture: = preload("res://scripts/ui/touch_scroll_gesture.gd")
const TouchMetrics: = preload("res://scripts/ui/touch_metrics.gd")

const PANEL_TARGET_SIZE: = Vector2(1180, 860)

const PANEL_LARGE_TARGET_SIZE: = Vector2(1400, 900)
const LARGE_VIEWPORT_W: = 1600.0

const LIST_MIN_W: = 640.0
const SIDE_GAP: = 14


const SCENE_LOOKBACK: = 64
const PINNED_H: = 30.0
const PANEL_MIN_SIZE: = Vector2(560, 420)
const PANEL_VIEWPORT_MARGIN: = Vector2(24, 24)
const ACCENT: = Color(0.608, 0.294, 0.663)
const GOLD: = Color(1.0, 0.84, 0.0)
const TEXT_LIGHT: = Color(0.95, 0.9, 1.0)
const TEXT_DIM: = Color(0.65, 0.6, 0.72)
const TEXT_WARN: = Color(1.0, 0.75, 0.3)
const BG_DARK: = Color(0.06, 0.06, 0.08, 0.98)
const BG_LIST: = Color(0.08, 0.06, 0.1, 1)
const BTN_NORMAL: = Color(0.15, 0.12, 0.2, 1)
const BTN_HOVER: = Color(0.21, 0.17, 0.28, 1)
const BTN_BORDER: = Color(0.3, 0.25, 0.38, 1)
const BTN_PRIMARY: = Color(0.5, 0.25, 0.58, 1)
const BTN_PRIMARY_HOVER: = Color(0.58, 0.32, 0.66, 1)
const BTN_TOGGLED: = Color(0.4, 0.26, 0.52, 1)
const CHIP_BG: = Color(0.12, 0.1, 0.16, 1)
const CHIP_BORDER: = Color(0.27, 0.22, 0.33, 1)
const CHIP_ON_BG: = Color(0.24, 0.16, 0.31, 1)
const CHIP_ON_BORDER: = Color(0.76, 0.5, 0.82, 0.85)
const SMALL_FONT: = 14


const ROW_STYLES: = [
	["plain", "Plain", "Rows: portrait, name and text"], 
	["cards", "Cards", "Each line in a card with a bar in the speaker's color"], 
	["bubbles", "Bubbles", "Chat bubbles: characters on the left, you on the right"], 
	["comic", "Comic", "Speech bubbles pointing at bigger portraits, narration in captions"], 
]

const DEFAULT_ROW_HEIGHT: = 60.0
const OVERSCAN_PX: = 240.0
const MEASURE_PER_FRAME: = 250
const WORK_BUDGET_USEC: = 3000
const SEARCH_BATCH: = 128
const SEARCH_DELAY: = 0.25
const STATUS_SECONDS: = 6.0


const TOKENS_DELAY: = 0.3
const DRAG_SCROLL_EDGE: = 48.0
const DRAG_SCROLL_STEP: = 24.0


const HEADER_IMPORTED: = "Imported story · from another game, sent as it is"

const ZONE_HEADERS: = {
	"locked_omitted": "Too old for the summary · not sent", 
	"locked_summary": "Summarized · the AI gets the summary instead", 
	"editable_tail": "End of the summarized part · still sent word for word", 
	"editable_session": "Since the summary · sent word for word", 
}

const HEADER_AI_SESSION: = "Current AI conversation"

const OUTDATED_NOTE: = "summary outdated: refresh it so the AI gets your changes"

const OUTDATED_STATUS: = "Summary outdated: refresh it so the AI gets this change."


const REWIND_BACK: = "↺ Rewind here"

const REWIND_FORWARD: = "↷ Forward to here"

const REWIND_START: = "↺ Back to the start of this conversation"


const START_BUTTON: = "↺ Conversation start"



const SELECT_SVG: = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"white\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><rect x=\"3.5\" y=\"3.5\" width=\"17\" height=\"17\" rx=\"3\"/><path d=\"M8 12.5l3 3 5.5-6.5\"/></svg>"
const TIME_COLOR: = Color(0.61, 0.7, 1.0)




const SHEET_ACTIONS: = [
	["edit", "✎ Edit text"], 
	["add", "✚ Add a line after"], 
	["up", "▲ Move up"], 
	["down", "▼ Move down"], 
	["hide", "⊘ Hide from the AI"], 
	["revert", "↺ Restore the original"], 
	["delete", "✕ Delete"], 
	["rewind", ""], 
]
const SHEET_KEEPS_OPEN: = ["up", "down", "hide", "revert"]

const SHEET_HIDE: = "⊘ Hide from the AI"

const SHEET_SHOW: = "⊘ Show to the AI again"

const SHEET_NOTES: = {
	"locked_omitted": "too old for the summary: not sent", 
	"locked_summary": "summarized: the AI gets the summary instead", 
	"editable_tail": "summarized, still sent word for word", 
	"editable_session": "sent to the AI word for word", 
}
const TOUCH_VIEWPORT_MARGIN: = Vector2(8, 8)

const SELECT_HINT: = "Click lines to select them. Shift+click selects a range."

const SELECT_HINT_TOUCH: = "Tap lines to select them."
const BTN_DANGER: = Color(0.42, 0.14, 0.2, 1)
const BTN_DANGER_HOVER: = Color(0.52, 0.19, 0.26, 1)


var _input_blocker: Control
var _dimmer: ColorRect
var _panel: PanelContainer
var _panel_margin: MarginContainer
var _search: LineEdit
var _filter_edited: Button
var _filter_added: Button
var _filter_hidden: Button
var _filter_scene: Button


var _stage_of_line: Dictionary = {}
var _scene_titles: Dictionary = {}



var _scene_of: Dictionary = {}

var _scene_range: = Vector2i(-1, -1)


var _pinned: Control
var _pinned_text: = ""
var _count_label: Label
var _style_buttons: Dictionary = {}
var _hint_label: Label
var _changes_label: Label
var _revert_all_button: Button

var _open_undo_depth: = 0
var _body: HBoxContainer
var _list_frame: PanelContainer
var _side: ScrollContainer
var _ai_button: Button


var _side_wide: = false
var _side_open: = false


static var _side_hidden: = true
var _scroll: ScrollContainer
var _content: Control
var _drop_line: ColorRect
var _empty_label: Label
var _composer: PanelContainer
var _composer_label: Label
var _composer_speaker: OptionButton
var _composer_text: TextEdit
var _undo_button: Button
var _redo_button: Button
var _add_end_button: Button
var _refresh_summary_button: Button
var _present_button: Button
var _start_button: Button
var _meter: HBoxContainer
var _status_label: Label
var _search_timer: Timer
var _status_timer: Timer
var _tokens_timer: Timer
var _pause_guard: DialogicPauseGuard = null


var _touch: = TouchScrollGesture.is_touch_platform()
var _sheet: PanelContainer
var _sheet_note: Label
var _sheet_buttons: Dictionary = {}
var _sheet_line_id: = ""


var _selecting: = false
var _picked: Dictionary = {}
var _pick_anchor: = ""
var _select_button: Button
var _footer: HBoxContainer
var _select_bar: VBoxContainer
var _picked_label: Label
var _hide_picked_button: Button
var _delete_picked_button: Button
var _delete_dialog: ConfirmationDialog

var _select_status: = ""
var _export_button: Button
var _export_dialog: Control

var _reveal_id: = ""


var _focus_after_reload: = ""


var _ids: Array[String] = []

var _ui_indices: = PackedInt32Array()
var _heights: = PackedFloat32Array()
var _height_index = preload("res://scripts/story/story_height_index.gd").new()

var _offsets: PackedFloat64Array:
	get:
		var result: = PackedFloat64Array()
		result.resize(_heights.size() + 1)
		for i in _heights.size(): result[i + 1] = result[i] + _heights[i]
		return result
var _all_ids: Array[String] = []
var _order_key: Array = []
var _layout_key: Array = []
var _content_key: Array = []
var _scene_key: Array = []
var _resolved_scene_key: Array = []
var _search_generation: = 0
var _search_pending: = false
var _query_key: Array = []
var _query_indices: = PackedInt32Array()
var _tokens_generation: = 0


var _height_cache: Dictionary = {}
var _pick_height_cache: Dictionary = {}
var _measure_next: = 0
var _row_width: = 0.0
var _rows: Array = []
var _selected_id: = ""
var _editing_id: = ""


var _edit_draft: = ""
var _composer_anchor: = ""
var _speakers: Array = []
var _stick_to_end: = false
var _refreshing: = false


var _pending_scroll: = -1.0

var _summary_outdated: = false
var _refreshing_summary: = false



var _rewind_points: Dictionary = {}

var _cursor_snapshot: = -1

var _cursor_id: = ""
var _cursor_ui_index: = -1


var _future_ui_index: = -1


var _start_snapshot: = -1

var _present_snapshot: = -1


func _ready() -> void :
	layer = 100
	_build_ui()
	TouchScrollGesture.install_scroll(_scroll, false, true)
	TouchScrollGesture.install_scroll(_side, false, true)
	TouchScrollGesture.configure_option_button(_composer_speaker)
	get_viewport().size_changed.connect(_layout_panel_for_viewport)
	RollbackManager.rollback_performed.connect( func(_steps: int) -> void : _on_rollback_changed())
	RollbackManager.snapshot_type_changed.connect( func(_type) -> void : _on_rollback_changed())
	StorySummaryManager.summary_accepted.connect( func(_summary: Dictionary) -> void : _on_summary_done(""))
	StorySummaryManager.generation_failed.connect(_on_summary_done)
	StorySummaryManager.generation_cancelled.connect( func() -> void : _on_summary_done(tr("it was cancelled")))
	_layout_panel_for_viewport()
	set_process(false)
	hide()








func open(place: String = "") -> void :
	_side_open = false
	_layout_panel_for_viewport()
	show()
	_input_blocker.visible = true
	_dimmer.visible = true
	_panel.visible = true
	if _pause_guard == null:
		_pause_guard = DialogicPauseGuard.capture_and_pause()
	_editing_id = ""
	_edit_draft = ""
	_hide_composer()
	_close_sheet()
	_set_selecting(false)

	StoryRowScript.SpeakerStyle.clear()
	_open_undo_depth = StorySummaryManager.get_context_undo_depth()
	_show_status("")

	_refreshing_summary = _refreshing_summary and StorySummaryManager.is_generating()
	_refresh_history_state()
	_update_view_controls()
	_load_scene_titles()
	var focus_id: = _history_focus_id()
	_focus_after_reload = focus_id
	_reload(focus_id.is_empty())
	if not focus_id.is_empty():
		_set_selected(focus_id)
	elif place == "history":
		_set_selected(_ids.back() if not _ids.is_empty() else "")
	set_process(true)


func is_open() -> bool:
	return visible


func _close() -> void :
	_focus_after_reload = ""
	_tokens_generation += 1
	_search_generation += 1
	_search_pending = false
	_search_timer.stop()
	_tokens_timer.stop()
	set_process(false)
	var editing: = _editing_id
	_editing_id = ""
	_edit_draft = ""
	if not editing.is_empty(): _remeasure([editing])
	_hide_composer()
	_close_sheet()
	_export_dialog.close()
	_set_selecting(false)
	hide()
	_input_blocker.visible = false
	_dimmer.visible = false
	_panel.visible = false
	if _pause_guard != null:
		_pause_guard.restore()
		_pause_guard = null





func _build_ui() -> void :
	_input_blocker = Control.new()
	_input_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_input_blocker.add_to_group("ui_blocking_overlay")
	_input_blocker.visible = false
	add_child(_input_blocker)

	_dimmer = ColorRect.new()
	_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dimmer.color = Color(0, 0, 0, 0.78)
	_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_dimmer.visible = false
	add_child(_dimmer)

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var panel_style: = StyleBoxFlat.new()
	panel_style.bg_color = BG_DARK
	panel_style.set_corner_radius_all(14)
	panel_style.border_color = Color(ACCENT, 0.4)
	panel_style.set_border_width_all(2)
	_panel.add_theme_stylebox_override("panel", panel_style)
	_panel.visible = false
	add_child(_panel)

	_panel_margin = MarginContainer.new()
	_panel.add_child(_panel_margin)
	var column: = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_panel_margin.add_child(column)

	_build_header(column)
	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", SIDE_GAP)
	column.add_child(_body)
	_build_list(_body)
	_side = StorySidePanelScript.new()
	_side.refresh_requested.connect(_refresh_summary)
	_body.add_child(_side)
	_build_composer(column)
	_build_sheet(column)
	_build_select_bar(column)
	_build_footer(column)
	_export_dialog = StoryExportDialogScript.new()
	add_child(_export_dialog)

	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = SEARCH_DELAY
	_search_timer.timeout.connect( func() -> void : _reload(false))
	add_child(_search_timer)
	_status_timer = Timer.new()
	_status_timer.one_shot = true
	_status_timer.wait_time = STATUS_SECONDS
	_status_timer.timeout.connect( func() -> void : _show_status(""))
	add_child(_status_timer)
	_tokens_timer = Timer.new()
	_tokens_timer.one_shot = true
	_tokens_timer.wait_time = TOKENS_DELAY
	_tokens_timer.timeout.connect(_refresh_token_meter)
	add_child(_tokens_timer)


func _refresh_token_meter() -> void :
	if not visible: return
	_tokens_generation += 1
	var generation: = _tokens_generation
	var job: = StorySummaryManager.begin_context_token_breakdown()
	while not StorySummaryManager.step_context_token_breakdown(job, WORK_BUDGET_USEC):
		await get_tree().process_frame
		if generation != _tokens_generation or not visible: return
	if job.get("cancelled", false):
		_tokens_timer.start()
		return
	var trigger: = StorySummaryManager.get_auto_summary_trigger_tokens()
	_meter.set_breakdown(job.result, trigger)
	_side.set_breakdown(job.result, trigger)




func _build_header(parent: VBoxContainer) -> void :
	var header: = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	parent.add_child(header)

	var title: = Label.new()
	title.text = "Story"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", GOLD)
	header.add_child(title)

	_search = LineEdit.new()
	_search.placeholder_text = UIFonts.pick("⌕", "⚲") + " " + tr("Search text or speaker (Ctrl+F)")
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_search.custom_minimum_size = TouchMetrics.text_button_min(Vector2(160, 36))
	for state in ["normal", "read_only"]:
		_search.add_theme_stylebox_override(state, _box_style(Color(0.1, 0.08, 0.13), CHIP_BORDER, 9, 12))
	_search.add_theme_stylebox_override("focus", _box_style(Color(0, 0, 0, 0), CHIP_ON_BORDER, 9, 12))
	_search.text_changed.connect( func(_text: String) -> void :
		_search_generation += 1
		_search_timer.start())
	header.add_child(_search)

	_select_button = _make_button("", func() -> void : _set_selecting(_select_button.button_pressed), BTN_NORMAL, BTN_HOVER)
	_select_button.toggle_mode = true
	_select_button.tooltip_text = "Select lines to hide them from the AI, delete them or save them as an image (S)"

	_select_button.icon = _svg_icon(SELECT_SVG, 2.0)
	_select_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_select_button.add_theme_constant_override("icon_max_width", 22)
	_select_button.custom_minimum_size = TouchMetrics.icon_button_min(Vector2(46, 36))
	for state in ["icon_normal_color", "icon_focus_color"]:
		_select_button.add_theme_color_override(state, TEXT_LIGHT)
	for state in ["icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		_select_button.add_theme_color_override(state, Color.WHITE)
	_select_button.add_theme_stylebox_override("pressed", _button_style(BTN_TOGGLED, CHIP_ON_BORDER))
	header.add_child(_select_button)


	_ai_button = _make_button(tr("AI memory"), func() -> void : _set_side_open(_ai_button.button_pressed), BTN_NORMAL, BTN_HOVER)
	_ai_button.toggle_mode = true
	_ai_button.tooltip_text = "Show or hide what the AI remembers of the story: how much it reads, and the summary"
	_ai_button.add_theme_stylebox_override("pressed", _button_style(BTN_TOGGLED, CHIP_ON_BORDER))
	header.add_child(_ai_button)

	var close: = _make_icon_button("✕", _close, tr("Close (Esc)"))
	header.add_child(close)


	var chips: = HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 6)
	parent.add_child(chips)
	_filter_edited = _make_chip(tr("Edited"), tr("Only lines you changed"))
	chips.add_child(_filter_edited)
	_filter_added = _make_chip(tr("Added"), tr("Only lines you added"))
	chips.add_child(_filter_added)
	_filter_hidden = _make_chip(tr("Hidden"), tr("Only lines hidden from the AI"))
	chips.add_child(_filter_hidden)
	_filter_scene = _make_chip(tr("This scene"), "")
	chips.add_child(_filter_scene)
	_hint_label = Label.new()
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hint_label.add_theme_font_size_override("font_size", SMALL_FONT)
	_hint_label.add_theme_color_override("font_color", TEXT_DIM)
	chips.add_child(_hint_label)


	_start_button = _make_time_button(tr(START_BUTTON), _rewind_to_start, tr("Show the story as it was when this conversation began"))
	chips.add_child(_start_button)
	_present_button = _make_time_button(tr("↷ Back to the present"), _back_to_present, tr("Show the newest line again"))
	chips.add_child(_present_button)
	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", SMALL_FONT)
	_count_label.add_theme_color_override("font_color", TEXT_DIM)
	chips.add_child(_count_label)



	StoryRowScript.style = UISettingsManager.get_story_panel_style()
	var styles: = HBoxContainer.new()
	styles.add_theme_constant_override("separation", 4)
	styles.alignment = BoxContainer.ALIGNMENT_END
	styles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	styles.size_flags_stretch_ratio = 0.001
	chips.add_child(styles)
	var style_group: = ButtonGroup.new()
	for choice in ROW_STYLES:
		var value: String = choice[0]
		var button: = _make_chip(tr(choice[1]), tr(choice[2]), func() -> void : _set_row_style(value))
		button.button_group = style_group
		button.button_pressed = value == StoryRowScript.style

		button.custom_minimum_size = Vector2(0.0, TouchMetrics.min_touch_height(28.0))
		styles.add_child(button)
		_style_buttons[value] = button


func _build_list(parent: BoxContainer) -> void :
	var frame: = PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_frame = frame
	var style: = StyleBoxFlat.new()
	style.bg_color = BG_LIST
	style.border_color = Color(0.17, 0.14, 0.22)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	style.content_margin_left = 2
	style.content_margin_right = 2
	frame.add_theme_stylebox_override("panel", style)
	parent.add_child(frame)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.focus_mode = Control.FOCUS_NONE
	frame.add_child(_scroll)
	_content = Control.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_content.set_drag_forwarding(Callable(), _can_drop_on_content, _drop_on_content)
	_content.resized.connect(_on_content_resized)
	_scroll.add_child(_content)
	_pinned = Control.new()
	_pinned.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pinned.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_pinned.custom_minimum_size.y = PINNED_H
	_pinned.visible = false
	_pinned.draw.connect(_draw_pinned)
	frame.add_child(_pinned)
	_scroll.get_v_scroll_bar().value_changed.connect( func(_value: float) -> void : _refresh_rows())
	_scroll.get_v_scroll_bar().changed.connect(_apply_pending_scroll)
	_scroll.gui_input.connect(_on_scroll_input)

	_scroll.resized.connect(_refresh_rows)
	_scroll.get_v_scroll_bar().gui_input.connect(_on_scroll_input)

	_drop_line = ColorRect.new()
	_drop_line.color = GOLD
	_drop_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drop_line.visible = false
	_content.add_child(_drop_line)

	_empty_label = Label.new()
	_empty_label.add_theme_color_override("font_color", TEXT_DIM)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.visible = false
	frame.add_child(_empty_label)


func _build_composer(parent: VBoxContainer) -> void :
	_composer = PanelContainer.new()
	var style: = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.17, 1)
	style.border_color = Color(ACCENT, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_composer.add_theme_stylebox_override("panel", style)
	_composer.visible = false
	parent.add_child(_composer)
	var column: = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_composer.add_child(column)
	var top: = HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	column.add_child(top)
	_composer_label = Label.new()
	_composer_label.add_theme_color_override("font_color", TEXT_DIM)
	_composer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_composer_label.clip_text = true
	top.add_child(_composer_label)
	var speaker_label: = Label.new()
	speaker_label.text = "Speaker:"
	top.add_child(speaker_label)
	_composer_speaker = OptionButton.new()
	_composer_speaker.custom_minimum_size = TouchMetrics.text_button_min(Vector2(200, 32))
	top.add_child(_composer_speaker)
	_composer_text = TextEdit.new()
	_composer_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_composer_text.placeholder_text = "What is said or happens (Enter adds it, Shift+Enter: new line)"
	_composer_text.custom_minimum_size = Vector2(0, 72)
	_composer_text.gui_input.connect(_on_composer_input)
	column.add_child(_composer_text)
	var buttons: = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)
	buttons.add_child(_make_button(tr("Add line"), _commit_composer, BTN_PRIMARY, BTN_PRIMARY_HOVER))
	buttons.add_child(_make_button(tr("Cancel"), _hide_composer, BTN_NORMAL, BTN_HOVER))




func _build_sheet(parent: VBoxContainer) -> void :
	_sheet = PanelContainer.new()
	var style: = StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.1, 0.19, 1)
	style.border_color = Color(ACCENT, 0.7)
	style.border_width_top = 2
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	_sheet.add_theme_stylebox_override("panel", style)
	_sheet.visible = false
	parent.add_child(_sheet)
	var column: = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_sheet.add_child(column)
	_sheet_note = Label.new()
	_sheet_note.add_theme_color_override("font_color", TEXT_DIM)
	_sheet_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_sheet_note)
	var buttons: = HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 8)
	column.add_child(buttons)
	var touch_size: = Vector2(TouchMetrics.MIN_TEXT_BUTTON_WIDTH, TouchMetrics.MIN_TOUCH_SIZE)
	for action in SHEET_ACTIONS:
		var action_name: String = action[0]
		var danger: = action_name == "delete"
		var button: = _make_button(tr(action[1]), func() -> void : _on_sheet_action(action_name), 
			BTN_DANGER if danger else BTN_NORMAL, BTN_DANGER_HOVER if danger else BTN_HOVER)
		button.custom_minimum_size = touch_size
		buttons.add_child(button)
		_sheet_buttons[action_name] = button

	var done: = _make_button(tr("Done"), _close_sheet, BTN_NORMAL, BTN_HOVER)
	done.custom_minimum_size = touch_size
	buttons.add_child(done)





func _build_select_bar(parent: VBoxContainer) -> void :
	_select_bar = VBoxContainer.new()
	_select_bar.add_theme_constant_override("separation", 6)
	_select_bar.visible = false
	parent.add_child(_select_bar)
	var picks: = HBoxContainer.new()
	picks.add_theme_constant_override("separation", 8)
	_select_bar.add_child(picks)
	_picked_label = Label.new()
	_picked_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picked_label.clip_text = true
	picks.add_child(_picked_label)
	var all: = _make_button(tr("Select all shown"), _pick_all_shown, BTN_NORMAL, BTN_HOVER)
	all.tooltip_text = "Every line in the list: after a search or filter, only those (Ctrl+A)"
	picks.add_child(all)
	picks.add_child(_make_button(tr("Clear"), _clear_picks, BTN_NORMAL, BTN_HOVER))

	var actions: = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	_select_bar.add_child(actions)
	_hide_picked_button = _make_button(tr(SHEET_HIDE), _hide_picked, BTN_NORMAL, BTN_HOVER)
	actions.add_child(_hide_picked_button)
	_delete_picked_button = _make_button(tr("✕ Delete"), _delete_picked, BTN_DANGER, BTN_DANGER_HOVER)
	_delete_picked_button.tooltip_text = "Delete the selected lines from the story (Delete). Undo brings them back."
	actions.add_child(_delete_picked_button)
	var gap: = Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(gap)
	_export_button = _make_button(tr("Save as image…"), _open_export, BTN_PRIMARY, BTN_PRIMARY_HOVER)
	actions.add_child(_export_button)
	var done: = _make_button(tr("Done"), func() -> void : _set_selecting(false), BTN_NORMAL, BTN_HOVER)
	done.tooltip_text = "Leave Select mode (Esc)"
	actions.add_child(done)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = tr("Delete lines")
	_delete_dialog.ok_button_text = tr("Delete")
	_delete_dialog.dialog_autowrap = true
	_delete_dialog.min_size = Vector2i(420, 0)
	_delete_dialog.confirmed.connect(_confirm_delete_picked)
	add_child(_delete_dialog)




func _build_footer(parent: VBoxContainer) -> void :
	var footer: = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	parent.add_child(footer)
	_footer = footer
	_undo_button = _make_icon_button("↶", _undo, tr("Undo the last change (Ctrl+Z)"))
	footer.add_child(_undo_button)
	_redo_button = _make_icon_button("↷", _redo, tr("Redo (Ctrl+Shift+Z)"))
	footer.add_child(_redo_button)
	var info: = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 2)
	footer.add_child(info)
	_changes_label = Label.new()
	_changes_label.add_theme_font_size_override("font_size", SMALL_FONT)
	_changes_label.add_theme_color_override("font_color", TEXT_DIM)
	_changes_label.clip_text = true
	info.add_child(_changes_label)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", SMALL_FONT)
	_status_label.add_theme_color_override("font_color", TEXT_WARN)
	_status_label.clip_text = true
	_status_label.visible = false
	info.add_child(_status_label)
	_meter = StoryTokenMeterScript.new()
	info.add_child(_meter)
	_refresh_summary_button = _make_button(tr("↻ Refresh the summary"), _refresh_summary, BTN_PRIMARY, BTN_PRIMARY_HOVER)
	_refresh_summary_button.tooltip_text = "Summarize the whole story again, with your changes. The AI keeps the old summary until then. Uses one AI request."
	_refresh_summary_button.visible = false
	footer.add_child(_refresh_summary_button)
	_add_end_button = _make_button(tr("✚ Add a line"), func() -> void : _show_composer(""), BTN_NORMAL, BTN_HOVER)
	_add_end_button.tooltip_text = "Add a line at the end of the story (✚ on a line adds after it)"
	footer.add_child(_add_end_button)
	_revert_all_button = _make_button(tr("Revert all"), _revert_all, BTN_NORMAL, BTN_HOVER)
	_revert_all_button.tooltip_text = "Take back every change to the story at once. Undo brings them back."
	_revert_all_button.add_theme_color_override("font_color", Color(1.0, 0.66, 0.6))
	footer.add_child(_revert_all_button)
	footer.add_child(_make_button(tr("Done"), _close, BTN_PRIMARY, BTN_PRIMARY_HOVER))


func _layout_panel_for_viewport() -> void :
	if _panel == null:
		return
	var viewport_size: = get_viewport().get_visible_rect().size
	var base: = PANEL_LARGE_TARGET_SIZE if viewport_size.x >= LARGE_VIEWPORT_W else PANEL_TARGET_SIZE
	var target: = UISettingsManager.get_scaled_menu_target(base) if UISettingsManager != null else base
	var margin: = PANEL_VIEWPORT_MARGIN
	if _touch:

		target = viewport_size
		margin = TOUCH_VIEWPORT_MARGIN
	var width: = minf(target.x, maxf(PANEL_MIN_SIZE.x, viewport_size.x - margin.x * 2.0))
	var height: = minf(target.y, maxf(PANEL_MIN_SIZE.y, viewport_size.y - margin.y * 2.0))
	_panel.offset_left = - width * 0.5
	_panel.offset_top = - height * 0.5
	_panel.offset_right = width * 0.5
	_panel.offset_bottom = height * 0.5
	var horizontal: = 22 if width >= 900.0 else 12
	var vertical: = 18 if height >= 640.0 else 10
	_panel_margin.add_theme_constant_override("margin_left", horizontal)
	_panel_margin.add_theme_constant_override("margin_right", horizontal)
	_panel_margin.add_theme_constant_override("margin_top", vertical)
	_panel_margin.add_theme_constant_override("margin_bottom", vertical)
	_side_wide = not _touch and width - horizontal * 2.0 - StorySidePanelScript.WIDTH - SIDE_GAP >= LIST_MIN_W
	_update_side_layout()





func _update_side_layout() -> void :
	if _side == null:
		return
	if _side_wide:
		_side_open = false
	var beside: = _column_beside()
	_ai_button.set_pressed_no_signal(beside or _side_open)
	_side.visible = beside or _side_open
	_side.custom_minimum_size.x = StorySidePanelScript.WIDTH if _side_wide else 0.0
	_side.size_flags_horizontal = Control.SIZE_FILL if _side_wide else Control.SIZE_EXPAND_FILL
	_list_frame.visible = not _side_open

	_meter.visible = not _side.visible
	_update_refresh_button()


func _column_beside() -> bool:
	return _side_wide and not _side_hidden




func _set_side_open(open_now: bool) -> void :
	if _side_wide:
		_side_hidden = not open_now
	else:
		_side_open = open_now
	_update_side_layout()
	_refresh_rows()


func _make_button(text: String, callback: Callable, color: Color, hover: Color) -> Button:
	var button: = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = TouchMetrics.text_button_min(Vector2(0, 36))
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var border: = BTN_BORDER if color == BTN_NORMAL else color.lightened(0.15)
	button.add_theme_stylebox_override("normal", _button_style(color, border))
	button.add_theme_stylebox_override("hover", _button_style(hover, border.lightened(0.1)))
	button.add_theme_stylebox_override("pressed", _button_style(color.darkened(0.15), border))
	button.add_theme_stylebox_override("disabled", _button_style(Color(0.11, 0.09, 0.14, 1), Color(0.2, 0.17, 0.24, 1)))
	button.add_theme_color_override("font_disabled_color", Color(TEXT_DIM, 0.5))
	button.pressed.connect(callback)
	return button



func _make_icon_button(glyph: String, callback: Callable, tooltip: String) -> Button:
	var button: = _make_button(glyph, callback, BTN_NORMAL, BTN_HOVER)
	button.tooltip_text = tooltip
	button.custom_minimum_size = TouchMetrics.icon_button_min(Vector2(38, 36))
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_stylebox_override("normal", _box_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 8, 8))
	button.add_theme_stylebox_override("disabled", _box_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 8, 8))
	return button


static func _svg_icon(svg: String, scale: float) -> Texture2D:
	var image: = Image.new()
	if image.load_svg_from_string(svg, scale) != OK:
		return null
	return ImageTexture.create_from_image(image)



func _make_time_button(text: String, callback: Callable, tooltip: String) -> Button:
	var button: = Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.visible = false
	button.custom_minimum_size = TouchMetrics.text_button_min(Vector2(0, 28))
	button.add_theme_font_size_override("font_size", SMALL_FONT)
	button.add_theme_color_override("font_color", TIME_COLOR)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _box_style(Color(0.1, 0.12, 0.2), Color(TIME_COLOR, 0.45), 14, 12))
	button.add_theme_stylebox_override("hover", _box_style(Color(0.14, 0.17, 0.28), Color(TIME_COLOR, 0.8), 14, 12))
	button.add_theme_stylebox_override("pressed", _box_style(Color(0.1, 0.12, 0.2), TIME_COLOR, 14, 12))
	button.pressed.connect(callback)
	return button




func _make_chip(text: String, tooltip: String, on_press: = Callable()) -> Button:
	var button: = Button.new()
	button.text = text
	button.toggle_mode = true
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = TouchMetrics.text_button_min(Vector2(0, 28))
	button.add_theme_font_size_override("font_size", SMALL_FONT)
	button.add_theme_color_override("font_color", TEXT_DIM)
	button.add_theme_color_override("font_pressed_color", TEXT_LIGHT)
	button.add_theme_color_override("font_hover_pressed_color", TEXT_LIGHT)
	button.add_theme_stylebox_override("normal", _box_style(CHIP_BG, CHIP_BORDER, 14, 12))
	button.add_theme_stylebox_override("hover", _box_style(BTN_HOVER, CHIP_BORDER.lightened(0.1), 14, 12))
	button.add_theme_stylebox_override("pressed", _box_style(CHIP_ON_BG, CHIP_ON_BORDER, 14, 12))
	button.add_theme_stylebox_override("hover_pressed", _box_style(CHIP_ON_BG.lightened(0.05), CHIP_ON_BORDER, 14, 12))
	button.pressed.connect(on_press if on_press.is_valid() else func() -> void : _reload(false))
	return button






func _set_row_style(value: String) -> void :
	if value == StoryRowScript.style:
		return
	var to_end: = _stick_to_end or _is_at_end()
	var anchor: = [] if to_end else _anchor()
	var share: = 0.0
	if not anchor.is_empty():
		share = float(anchor[1]) / maxf(1.0, _heights[_ids.find(str(anchor[0]))])
	StoryRowScript.style = value
	UISettingsManager.set_story_panel_style(value)
	UISettingsManager.save_config()
	_height_cache.clear()
	_pick_height_cache.clear()
	_layout_key = []
	_reload(to_end)
	if anchor.is_empty() or _search_pending:
		return
	_remeasure([anchor[0]])
	var pos: = _ids.find(str(anchor[0]))
	if pos >= 0:
		_rebuild_offsets([anchor[0], share * _heights[pos]])


func _button_style(color: Color, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var style: = _box_style(color, border, 8, 12)
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style



func _box_style(color: Color, border: Color, radius: int, margin_x: int) -> StyleBoxFlat:
	var style: = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin_x
	style.content_margin_right = margin_x
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style


func _is_filtered() -> bool:
	return not _search.text.strip_edges().is_empty() or _filter_edited.button_pressed or _filter_added.button_pressed\
	or _filter_hidden.button_pressed or _filter_scene.button_pressed




func _reload(to_end: bool, changed_ids: Array = []) -> void :
	_search_timer.stop()
	_search_generation += 1
	var generation: = _search_generation
	_search_pending = false
	var anchor: = _anchor()
	var order_key: = StorySummaryManager.get_story_ui_key(false)
	var content_key: = StorySummaryManager.get_story_ui_key()
	if order_key != _order_key:
		_order_key = order_key
		_all_ids = StorySummaryManager.get_context_entry_ids_for_ui()
	_load_scene_titles()
	_refresh_history_state()
	_resolve_scenes(_all_ids)
	_scene_range = _this_scene_range(_all_ids)
	_update_scene_chip(_all_ids)
	var filter_key: = [_search.text, _filter_edited.button_pressed, _filter_added.button_pressed, 
		_filter_hidden.button_pressed, _filter_scene.button_pressed, _scene_range if _filter_scene.button_pressed else Vector2i(-1, -1)]
	_summary_outdated = StorySummaryManager.is_summary_outdated()
	var summary_key: = [StorySummaryManager.use_summary_for_ai_context, StorySummaryManager.get_active_summary().get("id", ""), _summary_outdated]
	var layout_key: = [_order_key, _row_width, _selecting, filter_key, _scene_key, summary_key, _cursor_ui_index]
	for line_id in changed_ids:
		_height_cache.erase(line_id)
		_pick_height_cache.erase(line_id)
	var reuse: = layout_key == _layout_key and (content_key == _content_key or ( not changed_ids.is_empty() and not _is_filtered()))
	_stick_to_end = to_end
	if reuse:
		_content_key = content_key
		_count_label.text = tr("%d of %d") % [_ids.size(), _all_ids.size()] if _is_filtered() else tr("%d lines") % _ids.size()
		_remeasure(changed_ids)
		_rebuild_offsets(anchor)
		_update_footer()
		_update_sheet()
		_refresh_rows.call_deferred()
		_apply_focus_after_reload()
		return
	if content_key != _content_key and changed_ids.is_empty():
		_height_cache.clear()
		_pick_height_cache.clear()
	var indices: = PackedInt32Array()
	if _is_filtered():
		var filters: = {"edited": _filter_edited.button_pressed, "added": _filter_added.button_pressed, "hidden": _filter_hidden.button_pressed}
		var query: = _search.text
		var searching: bool = not query.strip_edges().is_empty() or filters.edited or filters.added or filters.hidden
		var first: = maxi(0, _scene_range.x) if _filter_scene.button_pressed else 0
		var end: = _scene_range.y + 1 if _filter_scene.button_pressed else _all_ids.size()
		var query_key: = [content_key, filter_key]
		if searching and query_key == _query_key:
			indices = _query_indices
		elif searching:
			var slice_start: = Time.get_ticks_usec()
			for offset in range(first, end, SEARCH_BATCH):
				indices.append_array(StorySummaryManager.find_context_entries(query, filters, offset, mini(SEARCH_BATCH, end - offset)))
				if Time.get_ticks_usec() - slice_start >= WORK_BUDGET_USEC and offset + SEARCH_BATCH < end:
					_search_pending = true
					_count_label.text = "Searching…"
					await get_tree().process_frame
					if generation != _search_generation or not visible: return
					if content_key != StorySummaryManager.get_story_ui_key():
						_reload.call_deferred(to_end)
						return
					slice_start = Time.get_ticks_usec()
			_query_key = query_key
			_query_indices = indices
		else:
			indices = PackedInt32Array(range(first, end))
	if generation != _search_generation: return
	_search_pending = false
	layout_key[1] = _row_width
	_layout_key = layout_key
	_content_key = content_key
	_ui_indices = indices
	if _is_filtered():
		_ids = []
		for index in indices: _ids.append(_all_ids[index])
		_count_label.text = tr("%d of %d") % [_ids.size(), _all_ids.size()]
	else:
		_ids = _all_ids
		_count_label.text = tr("%d lines") % _ids.size()
	_heights.resize(_ids.size())
	var cached_heights: = _heights_measured()
	for pos in range(_ids.size()):
		var cached: Variant = cached_heights.get(_ids[pos], null)
		_heights[pos] = float(cached[1]) if cached is Array and is_equal_approx(float(cached[0]), _row_width) else DEFAULT_ROW_HEIGHT
	_height_index.build(_heights)
	_measure_next = 0
	_rebuild_offsets(anchor)
	_update_footer()
	_empty_label.visible = _ids.is_empty()
	_empty_label.text = tr("No line matches.") if _is_filtered() else tr("The story is empty.")
	_update_sheet()
	_refresh_rows.call_deferred()
	_apply_focus_after_reload()


func _apply_focus_after_reload() -> void :
	if _focus_after_reload.is_empty():
		return
	_center_on.call_deferred(_focus_after_reload)
	_focus_after_reload = ""


func _set_height(pos: int, height: float) -> void :
	_height_index.add(pos, height - _heights[pos])
	_heights[pos] = height


func _rebuild_offsets(anchor: Array) -> void :
	var total: float = _height_index.offset(_ids.size())
	_content.custom_minimum_size.y = total


	_scroll.update_minimum_size()
	if _stick_to_end:
		_set_scroll(maxf(0.0, total - _scroll.size.y))
	elif not anchor.is_empty():
		var pos: = _ids.find(str(anchor[0]))
		if pos >= 0:
			_set_scroll(_height_index.offset(pos) + float(anchor[1]))


func _set_scroll(value: float) -> void :
	_pending_scroll = value
	_apply_pending_scroll()
	_refresh_rows()


func _apply_pending_scroll() -> void :
	if _stick_to_end:
		_pending_scroll = maxf(0.0, _content.custom_minimum_size.y - _scroll.size.y)
	if _pending_scroll < 0.0:
		return
	_scroll.scroll_vertical = int(_pending_scroll)
	if absf(float(_scroll.scroll_vertical) - _pending_scroll) <= 1.0 and not _stick_to_end:
		_pending_scroll = -1.0





func _on_scroll_input(event: InputEvent) -> void :
	var scrolls: = event is InputEventPanGesture or event is InputEventScreenDrag
	if event is InputEventMouseButton and event.pressed:
		scrolls = true
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask != 0:
		scrolls = true
	if scrolls:
		_stick_to_end = false
		_pending_scroll = -1.0



func _anchor() -> Array:
	if _ids.is_empty() or _height_index.count != _ids.size():
		return []
	var pos: = _position_at(float(_scroll.scroll_vertical))
	return [_ids[pos], float(_scroll.scroll_vertical) - _height_index.offset(pos)]


func _position_at(y: float) -> int:
	return _height_index.position_at(y)




func _refresh_rows() -> void :
	if _refreshing or not visible or _content == null:
		return
	_refreshing = true
	for _pass in range(3):
		if not _place_rows():
			break
	_refreshing = false
	_update_pinned()


func _place_rows() -> bool:
	var font: = _content.get_theme_default_font()
	var font_size: = _content.get_theme_default_font_size()
	var changed: = false

	var anchor: = _anchor()
	var items: = {}
	var first: = 0
	var last: = -1
	if not _ids.is_empty() and _height_index.count == _ids.size():
		var top: = float(_scroll.scroll_vertical) - OVERSCAN_PX
		var bottom: = float(_scroll.scroll_vertical) + _scroll.size.y + OVERSCAN_PX
		first = _position_at(maxf(0.0, top))
		last = _position_at(bottom)
		items = _entries_for(first, last)


	var wanted: = {}
	for pos in items:
		wanted[str((items[pos]["entry"] as Dictionary).get("entry_id", ""))] = true
	var kept: = {}
	var free_rows: Array = []
	for row: Control in _rows:
		if row.visible and wanted.has(row.line_id) and not kept.has(row.line_id):
			kept[row.line_id] = row
		else:
			free_rows.append(row)
	for pos in range(first, last + 1):
		var item: Dictionary = items.get(pos, {})
		if item.is_empty():
			continue
		var entry: Dictionary = item["entry"]
		var line_id: = str(entry.get("entry_id", ""))
		var editing: = _is_editing_line(line_id)
		var height: = StoryRowScript.measure(entry, item["header"], _row_width, font, font_size, editing, _measure_state(line_id, pos))
		if not is_equal_approx(height, _heights[pos]):
			_set_height(pos, height)
			changed = true
		_heights_measured()[line_id] = [_row_width, height]
		var row: Control = kept.get(line_id, null)
		if row == null:
			row = free_rows.pop_back() if not free_rows.is_empty() else _new_row()
			_release_row(row)
		elif row.is_editing and not editing and line_id == _editing_id:

			_edit_draft = row.get_editor_text()
		row.visible = true
		row.position = Vector2(0, _height_index.offset(pos))
		row.size = Vector2(_row_width, height)
		row.setup(entry, item["header"], line_id == _selected_id, editing, _row_state(entry, pos), _edit_draft)
	for row: Control in free_rows:
		if row.visible:
			_release_row(row)
			row.visible = false
	if changed:
		_rebuild_offsets(anchor)
	return changed


func _new_row() -> Control:
	var row: Control = StoryRowScript.new()
	row.touch_mode = _touch
	row.selected.connect(_on_row_pointer)
	row.edit_requested.connect(_begin_edit)
	row.action_requested.connect(_on_row_action)
	row.edit_committed.connect(_commit_edit)
	row.edit_cancelled.connect( func(_line_id: String) -> void : _end_edit())
	row.drop_handler = _on_row_drop
	_content.add_child(row)
	if TouchScrollGesture.is_touch_platform():

		TouchScrollGesture.install_tap_scroll(row, _scroll, func() -> void : _on_row_pointer(row.line_id), false, true)
	_rows.append(row)
	return row




func _release_row(row: Control) -> void :
	if row.is_editing and not _editing_id.is_empty() and row.line_id == _editing_id:
		_edit_draft = row.get_editor_text()
	row.release()



func _entries_for(first: int, last: int) -> Dictionary:
	var result: = {}
	if _ui_indices.is_empty():
		var start: = maxi(0, first - 1)
		var page: = StorySummaryManager.get_context_entries_for_ui_page(start, last - start + 1)
		var entries: Array = page.get("entries", [])
		var split: = int(page.get("ai_session_split_index", -1))
		for i in range(entries.size()):
			var pos: = start + i
			if pos < first:
				continue
			var previous: Dictionary = entries[i - 1] if i > 0 else {}
			result[pos] = {"entry": entries[i], "header": _header_for(pos, entries[i], previous, split)}
	else:
		for pos in range(first, last + 1):
			result[pos] = {"entry": StorySummaryManager.get_context_entry_for_ui_index(_ui_indices[pos]), "header": ""}
	return result


func _header_for(pos: int, entry: Dictionary, previous: Dictionary, split: int) -> String:
	var parts: = PackedStringArray()
	var imported: = str(entry.get("source", "")) == StorySummaryManager.CONTEXT_SOURCE_IMPORTED_PREHISTORY
	if imported:
		if pos == 0:
			parts.append(tr(HEADER_IMPORTED))
	elif StorySummaryManager.has_active_summary() and StorySummaryManager.use_summary_for_ai_context:
		var zone: = str(entry.get("zone", ""))
		var previous_imported: = str(previous.get("source", "")) == StorySummaryManager.CONTEXT_SOURCE_IMPORTED_PREHISTORY
		if (previous.is_empty() or previous_imported or str(previous.get("zone", "")) != zone) and ZONE_HEADERS.has(zone):
			parts.append(tr(str(ZONE_HEADERS[zone])))
			if _summary_outdated and (zone == "locked_summary" or zone == "editable_tail"):
				parts.append(tr(OUTDATED_NOTE))
	if pos == split and split >= 0:
		parts.append(tr(HEADER_AI_SESSION))
	return " · ".join(parts)


func _permissions(entry: Dictionary) -> Dictionary:


	var story_line: = str(entry.get("source", "")) != StorySummaryManager.CONTEXT_SOURCE_IMPORTED_PREHISTORY
	return {
		"edit": true, 
		"add": story_line, 
		"delete": story_line, 
		"move": story_line and not _is_filtered(), 
		"revert": bool(entry.get("edited", false)) or entry.has("display_text") or bool(entry.get("hidden", false)), 
		"hide": story_line, 
	}




func _row_state(entry: Dictionary, pos: int) -> Dictionary:
	var state: = _permissions(entry)
	var ui_index: = _ui_indices[pos] if not _ui_indices.is_empty() else pos
	state["here"] = _is_here(pos)
	state["scene"] = _scene_header_at(pos)
	state["future"] = _future_ui_index >= 0 and ui_index >= _future_ui_index
	if _selecting:
		state["pick"] = true
		state["picked"] = _picked.has(str(entry.get("entry_id", "")))
	state["rewind"] = _rewind_label(str(entry.get("entry_id", "")))
	return state


func _is_here(pos: int) -> bool:
	var ui_index: = _ui_indices[pos] if not _ui_indices.is_empty() else pos
	return _cursor_ui_index >= 0 and ui_index == _cursor_ui_index





func _measure_state(line_id: String, pos: int) -> Dictionary:
	return {"open": line_id == _selected_id and not _touch and not _selecting, "here": _is_here(pos), "scene": _scene_header_at(pos), 
		"pick": _selecting}


func _heights_measured() -> Dictionary:
	return _pick_height_cache if _selecting else _height_cache







func _load_scene_titles() -> void :
	var key: = [StorySummaryManager.get_story_ui_key(false), StorySummaryManager.get_stage_revision()]
	if key == _scene_key: return
	_scene_key = key
	_stage_of_line = ExportScript.stage_ids_by_line()
	_scene_titles = {}



func _scene_title(line_id: String) -> String:
	var stage_id: = str(_stage_of_line.get(line_id, ""))
	if stage_id.is_empty():
		return ""
	if not _scene_titles.has(stage_id):
		_scene_titles[stage_id] = ExportScript.scene_title(StorySummaryManager.get_stage_record(stage_id))
	return _scene_titles[stage_id]






func _resolve_scenes(all_ids: Array[String]) -> void :
	var key: = [_order_key, _scene_key]
	if key == _resolved_scene_key: return
	_resolved_scene_key = key
	_scene_of = {}
	if _stage_of_line.is_empty():
		return
	var current: = ""
	var untitled: = 0
	for line_id in all_ids:
		var title: = _scene_title(line_id)
		if not title.is_empty():
			current = title
			untitled = 0
		else:
			untitled += 1
			if untitled > SCENE_LOOKBACK:
				current = ""
		if not current.is_empty():
			_scene_of[line_id] = current



func _scene_at(pos: int) -> String:
	return str(_scene_of.get(_ids[pos], "")) if pos >= 0 and pos < _ids.size() else ""




func _scene_header_at(pos: int) -> String:
	var scene: = _scene_at(pos)
	if scene.is_empty() or (pos > 0 and _scene_at(pos - 1) == scene):
		return ""
	return scene





func _this_scene_range(all_ids: Array[String]) -> Vector2i:
	if all_ids.is_empty():
		return Vector2i(-1, -1)
	var at: = _cursor_ui_index if _cursor_ui_index >= 0 and _cursor_ui_index < all_ids.size() else all_ids.size() - 1
	var title: = str(_scene_of.get(all_ids[at], ""))
	if title.is_empty():
		return Vector2i(-1, -1)
	var first: = at
	while first > 0 and str(_scene_of.get(all_ids[first - 1], "")) == title:
		first -= 1
	var last: = at
	while last < all_ids.size() - 1 and str(_scene_of.get(all_ids[last + 1], "")) == title:
		last += 1
	return Vector2i(first, last)


func _update_scene_chip(all_ids: Array[String]) -> void :
	var has_scene: = _scene_range.x >= 0
	_filter_scene.text = tr("This scene · %d") % (_scene_range.y - _scene_range.x + 1) if has_scene else tr("This scene")
	_filter_scene.disabled = not has_scene and not _filter_scene.button_pressed
	var title: = str(_scene_of.get(all_ids[_scene_range.x], "")) if has_scene else ""
	_filter_scene.tooltip_text = (tr("Only the lines of this scene: ") + title) if has_scene\
	else tr("The line on screen has no recorded scene (it was shown before the game recorded scenes)")




func _update_pinned() -> void :
	var show: = false
	var title: = ""
	if not _ids.is_empty() and _height_index.count == _ids.size() and _list_frame.visible:
		var scroll_top: = float(_scroll.scroll_vertical)
		var pos: = _position_at(scroll_top)
		title = _scene_at(pos)
		show = not title.is_empty() and scroll_top > 0.0
		if show and _scene_header_at(pos) == title and _height_index.offset(pos) >= scroll_top - 1.0:
			show = false
		var next: = pos + 1
		while show and next < _ids.size() and _height_index.offset(next) - scroll_top < PINNED_H:
			if not _scene_header_at(next).is_empty():
				show = false
			next += 1
	_pinned.visible = show
	if show and title != _pinned_text:
		_pinned_text = title
		_pinned.queue_redraw()


func _draw_pinned() -> void :
	var font: = _pinned.get_theme_default_font()
	var small: = maxi(8, _pinned.get_theme_default_font_size() - StoryRowScript.SMALL_FONT_DELTA)

	var width: = _pinned.size.x - _scroll.get_v_scroll_bar().size.x - 4.0
	_pinned.draw_rect(Rect2(0, 0, width, PINNED_H), Color(BG_LIST, 0.97))
	_pinned.draw_line(Vector2(0, PINNED_H - 0.5), Vector2(width, PINNED_H - 0.5), Color(0.26, 0.21, 0.32), 1.0)
	var gutter: = StoryRowScript.gutter(_selecting)
	StoryRowScript.draw_scene_title(_pinned, Rect2(gutter, 0, width - gutter - 12.0, PINNED_H - 7.0), 
		_pinned_text, font, small)



func _is_editing_line(line_id: String) -> bool:
	return not _selecting and not _editing_id.is_empty() and line_id == _editing_id


func _on_content_resized() -> void :
	var width: = _content.size.x
	if is_equal_approx(width, _row_width):
		return
	_row_width = width
	if _search_pending: return
	_reload(_stick_to_end or _is_at_end())


func _is_at_end() -> bool:
	return float(_scroll.scroll_vertical) + _scroll.size.y >= _content.custom_minimum_size.y - 4.0




func _process(_delta: float) -> void :
	if not visible or _search_pending or _ids.is_empty() or _row_width <= 0.0:
		return
	if _pending_scroll >= 0.0 or _stick_to_end:
		_apply_pending_scroll()
	if _drop_line.visible and not get_viewport().gui_is_dragging():
		_drop_line.visible = false
	if not _reveal_id.is_empty():
		var reveal: = _reveal_id
		_reveal_id = ""
		_scroll_into_view(reveal)
	if _measure_next >= _ids.size():
		return
	var font: = _content.get_theme_default_font()
	var font_size: = _content.get_theme_default_font_size()
	var deadline: = Time.get_ticks_usec() + WORK_BUDGET_USEC
	var end: = mini(_ids.size(), _measure_next + MEASURE_PER_FRAME)
	var changed: = false
	var anchor: = _anchor() if not _stick_to_end else []
	while _measure_next < end:
		var last: = mini(end - 1, _measure_next + 15)
		var entries: = _entries_for(_measure_next, last)
		for pos in range(_measure_next, last + 1):
			var item: Dictionary = entries.get(pos, {})
			if item.is_empty(): continue
			var line_id: = str((item["entry"] as Dictionary).get("entry_id", ""))
			var height: = StoryRowScript.measure(item["entry"], item["header"], _row_width, font, font_size, _is_editing_line(line_id), _measure_state(line_id, pos))
			_heights_measured()[line_id] = [_row_width, height]
			if not is_equal_approx(height, _heights[pos]):
				_set_height(pos, height)
				changed = true
		_measure_next = last + 1
		if Time.get_ticks_usec() >= deadline: break
	if changed:
		_rebuild_offsets(anchor)
		_refresh_rows()







func _on_row_pointer(line_id: String) -> void :
	if _selecting:
		_pick(line_id, Input.is_key_pressed(KEY_SHIFT))
		return
	if not _touch:
		_select(line_id)
		return
	if _sheet.visible and _sheet_line_id == line_id:
		_close_sheet()
		return
	if _is_editing_line(line_id):
		return
	_select(line_id)

	if not _composer.visible:
		_open_sheet(line_id)


func _open_sheet(line_id: String) -> void :
	_sheet_line_id = line_id
	_sheet.visible = true
	_update_sheet()

	_reveal_id = line_id


func _close_sheet() -> void :
	_sheet_line_id = ""
	if _sheet != null:
		_sheet.visible = false




func _update_sheet() -> void :
	if _sheet == null or not _sheet.visible:
		return
	var entry: = _entry_for(_sheet_line_id) if _ids.has(_sheet_line_id) else {}
	if entry.is_empty():
		_close_sheet()
		return
	var rights: = _permissions(entry)
	var index: = StorySummaryManager.get_context_entry_index_for_ui(_sheet_line_id)
	var rewind: = _rewind_label(_sheet_line_id)
	for action_name in _sheet_buttons:
		var button: Button = _sheet_buttons[action_name]
		match action_name:
			"rewind":
				button.visible = not rewind.is_empty()
				button.text = rewind
			"up", "down":
				button.visible = bool(rights.get("move", false))
				button.disabled = index <= 0 if action_name == "up" else index >= _ids.size() - 1
			"hide":
				button.visible = bool(rights.get("hide", false))
				button.text = SHEET_SHOW if bool(entry.get("hidden", false)) else SHEET_HIDE
			_:
				button.visible = bool(rights.get(action_name, false))
	_sheet_note.text = _sheet_note_text(entry, index >= 0 and index == _cursor_ui_index)




func _sheet_note_text(entry: Dictionary, here: bool) -> String:
	var speaker: = str(entry.get("character_name", "")).strip_edges()
	var parts: = PackedStringArray([speaker if not speaker.is_empty() else tr("Narrator")])
	if str(entry.get("source", "")) == StorySummaryManager.CONTEXT_SOURCE_IMPORTED_PREHISTORY:
		parts.append(tr("imported story: your edits only change what you see"))
	elif bool(entry.get("hidden", false)):
		parts.append(tr("hidden from the AI"))
	elif StorySummaryManager.has_active_summary() and StorySummaryManager.use_summary_for_ai_context:
		parts.append(tr(str(SHEET_NOTES.get(str(entry.get("zone", "")), SHEET_NOTES["editable_session"]))))
	else:
		parts.append(tr(SHEET_NOTES["editable_session"]))
	if here:
		parts.append(tr("on screen now"))
	return " · ".join(parts)


func _on_sheet_action(action: String) -> void :
	var line_id: = _sheet_line_id
	if not SHEET_KEEPS_OPEN.has(action):
		_close_sheet()
	_on_row_action(line_id, action)


func _select(line_id: String) -> void :

	if not _selecting and _editing_id != "" and _editing_id != line_id:
		_end_edit()


	_stick_to_end = false
	_set_selected(line_id)
	_refresh_rows()
	var voice_entry: Dictionary = _entry_for(line_id)
	if not _selecting and not voice_entry.is_empty():
		var raw_index := int(voice_entry.get("raw_history_index", -1))
		var voice_controller: Node = preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree())
		if raw_index >= 0 and raw_index < Dialogic.History.simple_history_content.size():
			var stored_voice: Dictionary = Dialogic.History.simple_history_content[raw_index].duplicate(true)
			stored_voice["text"] = str(voice_entry.get("text", stored_voice.get("text", "")))
			voice_controller.replay_history(stored_voice, "narrator", "", true)
		else:
			var tag := CharacterPortraitService.get_character_tag(str(voice_entry.get("character_name", "narrator")), "full")
			voice_controller.replay_history(voice_entry, tag if not tag.is_empty() else "narrator", str(voice_entry.get("text", "")), true)






func _set_selected(line_id: String) -> void :
	var previous: = _selected_id
	_selected_id = line_id
	if previous != line_id:
		_remeasure([previous, line_id])




func _remeasure(line_ids: Array) -> void :
	if _content == null or _row_width <= 0.0 or _height_index.count != _ids.size():
		return
	var font: = _content.get_theme_default_font()
	var font_size: = _content.get_theme_default_font_size()
	var anchor: = _anchor()
	var changed: = false
	for line_id: String in line_ids:
		var pos: = _ids.find(line_id) if not line_id.is_empty() else -1
		var item: Dictionary = _entries_for(pos, pos).get(pos, {}) if pos >= 0 else {}
		if item.is_empty():
			continue
		var height: = StoryRowScript.measure(item["entry"], item["header"], _row_width, font, font_size, _is_editing_line(line_id), _measure_state(line_id, pos))
		_heights_measured()[line_id] = [_row_width, height]
		if not is_equal_approx(height, _heights[pos]):
			_set_height(pos, height)
			changed = true
	if changed:
		_rebuild_offsets(anchor)


func _begin_edit(line_id: String) -> void :
	if _selecting:
		return
	if line_id != _editing_id:
		var entry: = _entry_for(line_id)
		_edit_draft = str(entry.get("display_text", entry.get("text", "")))
	_editing_id = line_id
	_stick_to_end = false
	_set_selected(line_id)
	_refresh_rows()
	_scroll_into_view(line_id)


func _end_edit() -> void :
	_editing_id = ""
	_edit_draft = ""
	_refresh_rows()


func _commit_edit(line_id: String, text: String) -> void :
	var result: Dictionary = StorySummaryManager.apply_text_edit(line_id, text)
	if not bool(result.get("ok", false)):
		_show_status(str(result.get("error", tr("This line can't be changed."))))
		return
	_editing_id = ""
	_edit_draft = ""
	if bool(result.get("cosmetic_only", false)) and bool(result.get("changed", false)):
		_show_status(tr("Imported lines are sent as they were imported: your edit only changes what you see here."))
	_after_change(line_id)


func _on_row_action(line_id: String, action: String) -> void :
	_set_selected(line_id)
	match action:
		"edit":
			_begin_edit(line_id)
		"add":
			_show_composer(line_id)
		"revert":
			_apply(StorySummaryManager.revert_context_entry(line_id), line_id, tr("Line restored."))
		"up":
			_move_by(line_id, -1)
		"down":
			_move_by(line_id, 1)
		"delete":
			_delete(line_id)
		"hide":
			_toggle_hidden(line_id)
		"rewind":
			_rewind(line_id)


func _delete(line_id: String) -> void :
	var neighbour: = _neighbour_id(line_id)
	var result: Dictionary = StorySummaryManager.apply_delete(line_id)
	if bool(result.get("ok", false)):
		_set_selected(neighbour)
	_apply(result, neighbour, tr("Line deleted. ↶ Undo brings it back."))


func _toggle_hidden(line_id: String) -> void :
	var hide: = not bool(_entry_for(line_id).get("hidden", false))
	_apply(StorySummaryManager.apply_hide(line_id, hide), line_id, 
		tr("Hidden from the AI. The line stays in the story.") if hide else tr("The AI gets this line again."))


func _move_by(line_id: String, step: int) -> void :
	var index: = StorySummaryManager.get_context_entry_index_for_ui(line_id)
	if index < 0:
		return
	var after_id: = ""
	if step < 0:
		if index == 0:
			return
		after_id = "" if index - 2 < 0 else str(StorySummaryManager.get_context_entry_for_ui_index(index - 2).get("entry_id", ""))
	else:
		after_id = str(StorySummaryManager.get_context_entry_for_ui_index(index + 1).get("entry_id", ""))
		if after_id.is_empty():
			return
	_move(line_id, after_id)




func _move(line_id: String, after_id: String) -> void :
	if _selecting:
		return
	if _is_filtered():
		_show_status(tr("Lines can't move while a search or filter is on: clear it first."))
		return
	if not StorySummaryManager.can_move_after(line_id, after_id):
		_show_status(tr("This line can't move there."))
		return
	_apply(StorySummaryManager.apply_move_after(line_id, after_id), line_id, "")


func _apply(result: Dictionary, focus_id: String, message: String) -> void :
	if not bool(result.get("ok", false)):
		_show_status(str(result.get("error", tr("That change isn't possible here."))))
		return
	if not message.is_empty():
		_show_status(message)
	_after_change(focus_id)


func _after_change(focus_id: String) -> void :
	if not focus_id.is_empty():
		_set_selected(focus_id)
	var was_outdated: = _summary_outdated
	_reload(false, [focus_id] if not focus_id.is_empty() else [])
	if _summary_outdated and not was_outdated:
		_show_status(tr(OUTDATED_STATUS))
	if not focus_id.is_empty():
		_scroll_into_view.call_deferred(focus_id)


func _entry_for(line_id: String) -> Dictionary:
	return StorySummaryManager.get_context_entry_for_ui_index(StorySummaryManager.get_context_entry_index_for_ui(line_id))


func _neighbour_id(line_id: String) -> String:
	var pos: = _ids.find(line_id)
	if pos < 0:
		return ""
	if pos + 1 < _ids.size():
		return _ids[pos + 1]
	return _ids[pos - 1] if pos > 0 else ""


func _scroll_into_view(line_id: String) -> void :
	var pos: = _ids.find(line_id)
	if pos < 0 or _height_index.count != _ids.size():
		return
	var top: = _height_index.offset(pos)
	var bottom: = _height_index.offset(pos + 1)
	var view_top: = float(_scroll.scroll_vertical)
	var view_bottom: = view_top + _scroll.size.y
	if top < view_top:
		_set_scroll(top)
	elif bottom > view_bottom:
		_set_scroll(minf(top, bottom - _scroll.size.y))
	else:
		_refresh_rows()



func _revert_all() -> void :
	var result: Dictionary = StorySummaryManager.revert_all_context_edits()
	if not bool(result.get("ok", false)):
		_show_status(str(result.get("error", tr("Nothing to revert."))))
		return
	if not bool(result.get("changed", false)):
		_show_status(tr("Nothing to revert."))
		return
	_editing_id = ""
	_edit_draft = ""
	_after_change("")
	_show_status(tr("Every change taken back. ↶ Undo brings them back."))


func _undo() -> void :
	var result: Dictionary = StorySummaryManager.undo_context_edit()
	if not bool(result.get("ok", false)):
		_show_status(tr("Nothing to undo."))
		return
	_reload(false)


func _redo() -> void :
	var result: Dictionary = StorySummaryManager.redo_context_edit()
	if not bool(result.get("ok", false)):
		_show_status(tr("Nothing to redo."))
		return
	_reload(false)


func _update_footer() -> void :
	_undo_button.disabled = not StorySummaryManager.can_undo_context_edit()
	_redo_button.disabled = not StorySummaryManager.can_redo_context_edit()
	_revert_all_button.disabled = not StorySummaryManager.has_context_changes()
	var changes: = maxi(0, StorySummaryManager.get_context_undo_depth() - _open_undo_depth)

	_changes_label.text = (tr_n("%d change · the AI gets it with its next reply", "%d changes · the AI gets them with its next reply", changes) % changes)\
	if changes > 0 else ""
	var counts: = StorySummaryManager.get_context_edit_counts()
	_filter_edited.text = tr("Edited · %d") % int(counts.get("edited", 0))
	_filter_added.text = tr("Added · %d") % int(counts.get("added", 0))
	_filter_hidden.text = tr("Hidden · %d") % int(counts.get("hidden", 0))
	_update_refresh_button()
	_tokens_timer.start()


func _update_refresh_button() -> void :
	_side.set_summary(_summary_info())
	_refresh_summary_button.visible = (_summary_outdated or _refreshing_summary) and not _side.visible
	_refresh_summary_button.disabled = _refreshing_summary
	_refresh_summary_button.text = tr("↻ Refreshing the summary…") if _refreshing_summary else tr("↻ Refresh the summary")



func _summary_info() -> Dictionary:
	var hidden_lines: = int(StorySummaryManager.get_context_edit_counts().get("hidden", 0))
	if not StorySummaryManager.use_summary_for_ai_context:
		return {"mode": "off", "hidden_lines": hidden_lines}
	if not StorySummaryManager.has_active_summary():
		return {"mode": "none", "hidden_lines": hidden_lines, "auto_tokens": StorySummaryManager.get_auto_summary_trigger_tokens()}
	var summary: = StorySummaryManager.get_active_summary()
	return {
		"mode": "active", 
		"outdated": _summary_outdated, 
		"refreshing": _refreshing_summary, 
		"text": str(summary.get("raw_summary_text", "")), 
		"day": int(summary.get("created_at_day", 0)), 
		"slot": int(summary.get("created_at_slot", -1)), 
	}


func _refresh_summary() -> void :
	var result: Dictionary = StorySummaryManager.refresh_summary()
	if not bool(result.get("ok", false)):
		_show_status(str(result.get("error", tr("The summary couldn't be refreshed."))))
		return
	_refreshing_summary = true
	_update_refresh_button()
	_show_status(tr("Refreshing the summary. The AI gets your changes once it is done."))




func _on_summary_done(error: String) -> void :
	var was_refreshing: = _refreshing_summary
	_refreshing_summary = false
	if not visible:
		return
	if was_refreshing:
		_show_status(tr("The summary couldn't be refreshed: ") + error if not error.is_empty() else tr("Summary refreshed."))
	_reload(false)



func _show_status(message: String) -> void :
	_status_label.text = message
	_status_label.visible = not message.is_empty()
	_changes_label.visible = message.is_empty()
	_status_timer.start()
	if _selecting:
		_select_status = message
		_update_select_bar(true)




func _show_composer(anchor_id: String) -> void :
	if _selecting:
		return
	if not anchor_id.is_empty() and not StorySummaryManager.can_insert_after(anchor_id):
		_show_status(tr("Lines can't be added among the imported story."))
		return
	_close_sheet()
	_composer_anchor = anchor_id
	if anchor_id.is_empty():
		_composer_label.text = "Add a line at the end of the story"
	else:
		var index: = StorySummaryManager.get_context_entry_index_for_ui(anchor_id)
		var text: = str(StorySummaryManager.get_context_entry_for_ui_index(index).get("text", ""))
		_composer_label.text = tr("Add a line after: “%s”") % (text.left(70) + ("…" if text.length() > 70 else ""))
	_fill_speakers()
	_composer_text.text = ""
	_composer.visible = true
	_composer_text.grab_focus.call_deferred()


func _hide_composer() -> void :
	if _composer != null:
		_composer.visible = false


func _commit_composer() -> void :
	var text: = _composer_text.text.strip_edges()
	if text.is_empty():
		_show_status(tr("Write the line first."))
		return
	var speaker: Dictionary = _speakers[_composer_speaker.selected] if _composer_speaker.selected >= 0 and _composer_speaker.selected < _speakers.size() else {}
	var result: Dictionary = StorySummaryManager.apply_insert_after(_composer_anchor, {
		"character_name": str(speaker.get("name", "")), 
		"character_id": str(speaker.get("id", "")), 
		"text": text, 
	})
	if not bool(result.get("ok", false)):
		_show_status(str(result.get("error", tr("The line couldn't be added here."))))
		return
	_hide_composer()
	_after_change(str(result.get("entry_id", "")))


func _on_composer_input(event: InputEvent) -> void :
	if not (event is InputEventKey) or not event.pressed:
		return
	var key: = event as InputEventKey
	if key.keycode == KEY_ESCAPE:
		_composer_text.accept_event()
		_hide_composer()
	elif (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER) and not key.shift_pressed:
		_composer_text.accept_event()
		_commit_composer()




func _fill_speakers() -> void :
	var previous: = str(_speakers[_composer_speaker.selected].get("id", "")) if _composer_speaker.selected >= 0 and _composer_speaker.selected < _speakers.size() else ""
	_speakers = [{"name": "", "display": tr("Narrator"), "id": ""}]
	var player: DialogicCharacter = DialogicResourceUtil.get_character_resource("player")
	var player_name: = player.display_name.strip_edges() if player != null else ""
	_speakers.append({"name": player_name if not player_name.is_empty() else "Player", "display": tr("%s (you)") % (player_name if not player_name.is_empty() else tr("Player")), "id": "player"})
	var rows: Array = []
	for raw_tag in CharacterSpriteLoader.get_all_tags():
		var tag: = str(raw_tag).strip_edges()
		var character: DialogicCharacter = CharacterSpriteLoader.get_dialogic_character(tag) if not tag.is_empty() else null
		if character == null:
			continue
		var display_name: = character.display_name.strip_edges()
		if display_name.is_empty():
			display_name = tag.capitalize()
		rows.append({"name": display_name, "display": display_name, "id": CharacterPortraitService.get_dialogic_identifier(tag)})
	rows.sort_custom( func(a: Dictionary, b: Dictionary) -> bool: return str(a["display"]).to_lower() < str(b["display"]).to_lower())
	_speakers.append_array(rows)
	_composer_speaker.clear()
	var selected: = 0
	for i in range(_speakers.size()):
		_composer_speaker.add_item(str(_speakers[i]["display"]))
		if str(_speakers[i]["id"]) == previous:
			selected = i
	_composer_speaker.select(selected)







func _set_selecting(on: bool) -> void :
	if _select_button == null:
		return
	_select_button.set_pressed_no_signal(on)
	if on == _selecting:
		return
	_selecting = on
	if on:
		_close_sheet()
		_hide_composer()

		if is_inside_tree() and get_viewport().gui_is_dragging():
			get_viewport().gui_cancel_drag()
		_drop_line.visible = false
	else:
		_picked.clear()
		_pick_anchor = ""
	_footer.visible = not on
	_select_bar.visible = on
	_update_select_bar()


	_reload(_stick_to_end or _is_at_end())
	_refresh_rows()
	_pinned.queue_redraw()




func _pick(line_id: String, extend: bool) -> void :
	var from: = _ids.find(_pick_anchor) if extend and not _pick_anchor.is_empty() else -1
	var to: = _ids.find(line_id)
	if from >= 0 and to >= 0:
		for pos in range(mini(from, to), maxi(from, to) + 1):
			_picked[_ids[pos]] = true
	elif _picked.has(line_id):
		_picked.erase(line_id)
	else:
		_picked[line_id] = true
	_pick_anchor = line_id
	_set_selected(line_id)
	_stick_to_end = false
	_update_select_bar()
	_refresh_rows()



func _pick_all_shown() -> void :
	for line_id in _ids:
		_picked[line_id] = true
	_update_select_bar()
	_refresh_rows()


func _clear_picks() -> void :
	_picked.clear()
	_pick_anchor = ""
	_update_select_bar()
	_refresh_rows()




func _update_select_bar(keep_status: = false) -> void :
	if not keep_status:
		_select_status = ""
	var count: = _picked.size()
	_picked_label.text = _select_status if not _select_status.is_empty()\
	else (tr_n("%d line selected", "%d lines selected", count) % count) if count > 0\
	else (SELECT_HINT_TOUCH if _touch else SELECT_HINT)
	_picked_label.add_theme_color_override("font_color", TEXT_LIGHT if count > 0 or not _select_status.is_empty() else TEXT_DIM)
	_export_button.disabled = count == 0


	var counts: Dictionary = StorySummaryManager.get_hide_counts(_picked.keys())
	var lines: = int(counts.get("lines", 0))
	var show_again: = lines > 0 and int(counts.get("hidden", 0)) == lines
	_hide_picked_button.text = tr(SHEET_SHOW) if show_again else tr(SHEET_HIDE)
	_hide_picked_button.tooltip_text = tr("Let the AI read the selected lines again (H)") if show_again\
	else tr("Hide the selected lines from the AI: they stay in the story (H)")
	_hide_picked_button.disabled = lines == 0
	_delete_picked_button.disabled = lines == 0




func _hide_picked() -> void :
	var ids: = _picked.keys()
	var counts: Dictionary = StorySummaryManager.get_hide_counts(ids)
	var lines: = int(counts.get("lines", 0))
	if lines == 0:
		_show_status(tr("Imported lines can't be hidden."))
		return
	var hide: = int(counts.get("hidden", 0)) < lines
	var result: Dictionary = StorySummaryManager.apply_hide_many(ids, hide)
	var changed: = int(result.get("count", 0))
	var message: = (tr_n("%d line hidden from the AI. It stays in the story.", "%d lines hidden from the AI. They stay in the story.", changed) if hide
		else tr_n("The AI gets %d line again.", "The AI gets %d lines again.", changed)) % changed
	_apply(result, "", message)
	_update_select_bar(true)
	_refresh_rows()



func _delete_picked() -> void :
	var lines: = int(StorySummaryManager.get_hide_counts(_picked.keys()).get("lines", 0))
	if lines == 0:
		_show_status(tr("Imported lines can't be deleted."))
		return
	_delete_dialog.dialog_text = (tr_n("Delete %d line from the story?", "Delete %d lines from the story?", lines) % lines)\
	+ "\n" + tr("↶ Undo brings them back.")
	_delete_dialog.popup_centered()




func _confirm_delete_picked() -> void :
	var ids: = _picked.keys()
	if _picked.has(_selected_id):
		_set_selected("")
	var result: Dictionary = StorySummaryManager.apply_delete_many(ids)
	if not bool(result.get("ok", false)):
		_apply(result, "", "")
		return
	_set_selecting(false)
	var count: = int(result.get("count", 0))
	_apply(result, "", tr_n("%d line deleted. ↶ Undo brings it back.", "%d lines deleted. ↶ Undo brings them back.", count) % count)



func _picked_entries() -> Array:
	var entries: Array = []
	if _picked.is_empty():
		return entries
	var all_ids: = StorySummaryManager.get_context_entry_ids_for_ui()
	for index in range(all_ids.size()):
		if _picked.has(all_ids[index]):
			entries.append(StorySummaryManager.get_context_entry_for_ui_index(index))
	return entries


func _open_export() -> void :
	var entries: = _picked_entries()
	if entries.is_empty():
		_show_status(tr("Select the lines to save first."))
		return
	_export_dialog.open(entries)






func _drop_position(y_in_content: float) -> int:
	if _ids.is_empty():
		return 0
	var pos: = _position_at(y_in_content)
	var middle: = (_height_index.offset(pos) + _height_index.offset(pos + 1)) * 0.5
	return pos + 1 if y_in_content > middle else pos


func _drag_target(data: Variant, y_in_content: float) -> Dictionary:
	if _selecting or not (data is Dictionary) or not (data as Dictionary).has("story_line_id") or _is_filtered():
		return {}
	var line_id: = str(data["story_line_id"])
	var insert_at: = _drop_position(y_in_content)
	var after_id: = _ids[insert_at - 1] if insert_at > 0 else ""
	if after_id == line_id or (insert_at < _ids.size() and _ids[insert_at] == line_id):
		return {}
	if not StorySummaryManager.can_move_after(line_id, after_id):
		return {}
	return {"line_id": line_id, "after_id": after_id, "y": _height_index.offset(insert_at)}


func _on_row_drop(row: Control, at_position: Vector2, data: Variant, drop: bool) -> bool:
	return _handle_drop(row.position.y + at_position.y, data, drop)


func _can_drop_on_content(at_position: Vector2, data: Variant) -> bool:
	return _handle_drop(at_position.y, data, false)


func _drop_on_content(at_position: Vector2, data: Variant) -> void :
	_handle_drop(at_position.y, data, true)


func _handle_drop(y_in_content: float, data: Variant, drop: bool) -> bool:
	var target: = _drag_target(data, y_in_content)
	if not drop:
		_autoscroll_while_dragging(y_in_content)
		_drop_line.visible = not target.is_empty()
		if not target.is_empty():
			_drop_line.position = Vector2(0, float(target["y"]) - 1.5)
			_drop_line.size = Vector2(_row_width, 3)
			_content.move_child(_drop_line, -1)
		return not target.is_empty()
	_drop_line.visible = false
	if not target.is_empty():
		_move(str(target["line_id"]), str(target["after_id"]))
	return true


func _autoscroll_while_dragging(y_in_content: float) -> void :
	var y_on_screen: = y_in_content - float(_scroll.scroll_vertical)
	if y_on_screen < DRAG_SCROLL_EDGE:
		_scroll.scroll_vertical = maxi(0, _scroll.scroll_vertical - int(DRAG_SCROLL_STEP))
	elif y_on_screen > _scroll.size.y - DRAG_SCROLL_EDGE:
		_scroll.scroll_vertical += int(DRAG_SCROLL_STEP)






func _update_view_controls() -> void :
	_hint_label.text = tr("Tap a line for its actions") if _touch else tr("Double-click to edit · drag ⋮⋮ to move")
	_update_refresh_button()
	_update_time_buttons()


func _refresh_history_state() -> void :
	var navigation: = RollbackManager.get_history_index()
	_rewind_points = navigation.points
	_cursor_snapshot = RollbackManager.get_current_position() if RollbackManager.is_in_rollback_mode() else -1
	_cursor_id = RollbackManager.get_cursor_line_id()
	_cursor_ui_index = _shown_ui_index(_cursor_id)
	_present_snapshot = navigation.present
	var start: int = navigation.start
	_start_snapshot = start if start >= 0 and _shown_ui_index(RollbackManager.get_snapshot_line_id(start)) < 0 else -1
	_future_ui_index = -1
	if _cursor_snapshot >= 0:
		if _cursor_ui_index >= 0:
			_future_ui_index = _cursor_ui_index + 1
		else:



			_future_ui_index = StorySummaryManager.get_context_ui_index_at_history_position(
				RollbackManager.get_snapshot_history_position(_cursor_snapshot))
	if _present_button != null:
		_update_time_buttons()


func _shown_ui_index(line_id: String) -> int:
	return StorySummaryManager.get_context_entry_index_for_ui(line_id) if not line_id.is_empty() else -1


func _update_time_buttons() -> void :
	_present_button.visible = _cursor_snapshot >= 0
	_start_button.visible = _start_snapshot >= 0 and _start_snapshot != _cursor_snapshot
	_hint_label.visible = not (_present_button.visible or _start_button.visible)




func _history_focus_id() -> String:
	if _cursor_ui_index >= 0:
		return _cursor_id
	if _future_ui_index >= 0:
		return str(StorySummaryManager.get_context_entry_for_ui_index(_future_ui_index).get("entry_id", ""))
	return ""


func _on_rollback_changed() -> void :
	if visible:
		_refresh_history_state()
		_update_sheet()
		_refresh_rows()




func _rewind_label(line_id: String) -> String:
	var index: = int(_rewind_points.get(line_id, -1))
	if index < 0 or index == (_cursor_snapshot if _cursor_snapshot >= 0 else _present_snapshot):
		return ""
	if index < RollbackManager.get_snapshot_count() and RollbackManager.get_snapshot_metadata(index).get("type", -1) == RollbackManager.SnapshotType.AI_CONVERSATION_START:
		return tr(REWIND_START)
	return tr(REWIND_FORWARD) if _cursor_snapshot >= 0 and index > _cursor_snapshot else tr(REWIND_BACK)


func _rewind(line_id: String) -> void :
	_rewind_to_snapshot(int(_rewind_points.get(line_id, -1)))


func _back_to_present() -> void :
	_rewind_to_snapshot(_present_snapshot)


func _rewind_to_start() -> void :
	_rewind_to_snapshot(_start_snapshot)




func _rewind_to_snapshot(index: int) -> void :
	var history: = get_tree().get_first_node_in_group("rollback_history") if is_inside_tree() else null
	if index < 0 or history == null or not history.has_method("rewind_to_snapshot"):
		_show_status(tr("This line can't be rewound to."))
		return
	if not bool(history.call("can_rewind")):
		_show_status(tr("Wait for the reply to finish, then rewind."))
		return
	_close()
	history.call("rewind_to_snapshot", index)



func _center_on(line_id: String) -> void :
	var pos: = _ids.find(line_id)
	if pos < 0 or _height_index.count != _ids.size():
		return
	_stick_to_end = false
	_set_scroll(maxf(0.0, _height_index.offset(pos) - _scroll.size.y * 0.35))





func _unhandled_key_input(event: InputEvent) -> void :
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	var key: = event as InputEventKey
	if _delete_dialog.visible:

		return
	if _export_dialog.visible:

		get_viewport().set_input_as_handled()
		if key.keycode == KEY_ESCAPE:
			_export_dialog.escape()
		return
	if _side_open:


		if key.keycode == KEY_ESCAPE:
			_set_side_open(false)
			get_viewport().set_input_as_handled()
		return
	var handled: = true
	var command: = key.ctrl_pressed or key.meta_pressed

	var can_change: = not _selecting
	if key.keycode == KEY_ESCAPE:
		if _sheet.visible:
			_close_sheet()
		elif _composer.visible:
			_hide_composer()
		elif not _search.text.is_empty():
			_search.text = ""
			_reload(false)
		elif _selecting:
			_set_selecting(false)
		else:
			_close()
	elif command and key.keycode == KEY_F:
		_search.grab_focus()
	elif key.keycode == KEY_S and not command and not key.alt_pressed:
		_set_selecting( not _selecting)
	elif _selecting and command and key.keycode == KEY_A:
		_pick_all_shown()
	elif _selecting and key.keycode == KEY_SPACE and not _selected_id.is_empty():
		_pick(_selected_id, key.shift_pressed)
	elif _selecting and key.keycode == KEY_H and not command and not key.alt_pressed and not _picked.is_empty():
		_hide_picked()
	elif _selecting and key.keycode == KEY_DELETE and not _picked.is_empty():
		_delete_picked()
	elif can_change and command and key.keycode == KEY_Z:
		if key.shift_pressed:
			_redo()
		else:
			_undo()
	elif can_change and command and key.keycode == KEY_Y:
		_redo()
	elif key.keycode == KEY_UP or key.keycode == KEY_DOWN:
		var step: = -1 if key.keycode == KEY_UP else 1
		if key.alt_pressed and can_change and not _selected_id.is_empty():
			_move_by(_selected_id, step)
		else:
			_select_step(step)
	elif can_change and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER) and not _selected_id.is_empty():
		_begin_edit(_selected_id)
	elif can_change and key.keycode == KEY_H and not command and not key.alt_pressed and not _selected_id.is_empty():
		if bool(_permissions(_entry_for(_selected_id)).get("hide", false)):
			_toggle_hidden(_selected_id)
		else:
			_show_status(tr("Imported lines can't be hidden."))
	elif can_change and key.keycode == KEY_DELETE and not _selected_id.is_empty():
		if bool(_permissions(_entry_for(_selected_id)).get("delete", false)):
			_delete(_selected_id)
		else:
			_show_status(tr("Imported lines can't be deleted."))
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _select_step(step: int) -> void :
	if _ids.is_empty():
		return
	var pos: = _ids.find(_selected_id)
	pos = (_ids.size() - 1 if step < 0 else 0) if pos < 0 else clampi(pos + step, 0, _ids.size() - 1)
	_stick_to_end = false
	_set_selected(_ids[pos])
	_scroll_into_view(_selected_id)

@icon("node_dialog_text_icon.svg")
class_name DialogicNode_DialogText
extends RichTextLabel



signal started_revealing_text()
signal continued_revealing_text(new_character: String)
signal finished_revealing_text()
enum Alignment{LEFT, CENTER, RIGHT}

@export var enabled: = true
@export var alignment: = Alignment.LEFT
@export var textbox_root: Node = self

@export var hide_when_empty: = false
@export var start_hidden: = true

var revealing: = false
var base_visible_characters: = 0


const TOUCH_DRAG_SLOP: = 12.0
var _touch_state: Dictionary = {}



var active_speed: float = 0.01

var speed_counter: float = 0

func _set(property: StringName, what: Variant) -> bool:
	if property == "text" and typeof(what) == TYPE_STRING:

		text = what

		if hide_when_empty:
			textbox_root.visible = !what.is_empty()

		return true
	return false


func _ready() -> void :

	add_to_group("dialogic_dialog_text")
	meta_hover_ended.connect(_on_meta_hover_ended)
	meta_hover_started.connect(_on_meta_hover_started)
	meta_clicked.connect(_on_meta_clicked)
	gui_input.connect(on_gui_input)
	bbcode_enabled = true
	selection_enabled = true
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	deselect_on_focus_loss_enabled = false
	if textbox_root == null:
		textbox_root = self

	if start_hidden:
		textbox_root.hide()
	text = ""

	var custom_bbcode_effects: Array = ProjectSettings.get_setting("dialogic/text/custom_bbcode_effects", "").split(",", false)
	for i in custom_bbcode_effects:
		var x: Resource = load(i.strip_edges())
		if x is RichTextEffect:
			custom_effects.append(x)

	_configure_scrollbar()
	if OS.has_feature("android"):
		var gesture: = preload("res://scripts/ui/android_scroll_gesture.gd").new()
		add_child(gesture)
		gesture.setup(self, get_v_scroll_bar(), _request_touch_advance)




func reveal_text(_text: String, keep_previous: = false) -> void :
	if !enabled:
		return
	show()

	custom_fx_reset()

	if !keep_previous:
		text = _text
		base_visible_characters = 0

		if alignment == Alignment.CENTER:
			text = "[center]" + text
		elif alignment == Alignment.RIGHT:
			text = "[right]" + text
		visible_characters = 0

	else:
		base_visible_characters = len(text)
		visible_characters = len(get_parsed_text())
		custom_fx_update()
		text = text + _text



		if DialogicUtil.autoload().Inputs.auto_skip.enabled:
			visible_characters = 1
			return

	revealing = true
	speed_counter = 0
	started_revealing_text.emit()


func set_speed(delay_per_character: float) -> void :
	if DialogicUtil.autoload().Text.is_text_voice_synced() and DialogicUtil.autoload().Voice.is_running():
		var total_characters: = get_total_character_count() as float
		var remaining_time: float = DialogicUtil.autoload().Voice.get_remaining_time()
		var synced_speed: = remaining_time / total_characters
		active_speed = synced_speed

	else:
		active_speed = delay_per_character



func continue_reveal() -> void :
	if visible_characters <= get_total_character_count():
		revealing = false

		var current_index: = visible_characters - base_visible_characters
		await DialogicUtil.autoload().Text.execute_effects(current_index, self, false)

		if visible_characters == -1:
			return

		revealing = true
		visible_characters += 1

		if visible_characters > -1 and visible_characters <= len(get_parsed_text()):
			continued_revealing_text.emit(get_parsed_text()[visible_characters - 1])

		custom_fx_update()
	else:
		finish_text(true)


		DialogicUtil.autoload().Inputs.block_input(ProjectSettings.get_setting("dialogic/text/advance_delay", 0.1))



func finish_text(is_organic: = false) -> void :
	visible_ratio = 1
	custom_fx_update()
	if not is_organic:
		custom_fx_skip()
	DialogicUtil.autoload().Text.execute_effects(-1, self, true)
	revealing = false
	DialogicUtil.autoload().current_state = DialogicGameHandler.States.IDLE

	finished_revealing_text.emit()



func _process(delta: float) -> void :
	if !revealing or DialogicUtil.autoload().paused:
		return

	speed_counter += delta

	while speed_counter > active_speed and revealing and !DialogicUtil.autoload().paused:
		speed_counter -= active_speed
		continue_reveal()



func _on_meta_hover_started(_meta: Variant) -> void :
	DialogicUtil.autoload().Inputs.action_was_consumed = true

func _on_meta_hover_ended(_meta: Variant) -> void :
	DialogicUtil.autoload().Inputs.action_was_consumed = false

func _on_meta_clicked(_meta: Variant) -> void :
	DialogicUtil.autoload().Inputs.action_was_consumed = true



func on_gui_input(event: InputEvent) -> void :
	if event is InputEventMouse:
		return # DialogueInput advances on release; RichTextLabel owns selection.
	if event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed and not event.meta_pressed and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		DialogicUtil.autoload().Inputs.input_was_mouse_input = false
		DialogicUtil.autoload().Inputs.handle_input()
		accept_event()
		return
	if OS.has_feature("android") and (event is InputEventScreenTouch or event is InputEventScreenDrag or (event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION)):

		return
	if _is_event_on_scrollbar(event):
		accept_event()
		return





	if OS.has_feature("mobile") or OS.has_feature("android"):
		if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
			accept_event()
			return
		if event is InputEventScreenTouch:
			var touch: = event as InputEventScreenTouch
			if touch.pressed:
				_touch_state = {"index": touch.index, "start": touch.position, "dragging": false}
			else:
				var was_drag: bool = bool(_touch_state.get("dragging", false))\
				or (_touch_state.has("start") and (_touch_state["start"] as Vector2).distance_to(touch.position) >= TOUCH_DRAG_SLOP)
				_touch_state = {}
				if not was_drag:
					_request_touch_advance()
			accept_event()
			return
		if event is InputEventScreenDrag:
			var drag: = event as InputEventScreenDrag
			if int(_touch_state.get("index", -1)) != drag.index:
				return
			if not bool(_touch_state.get("dragging", false)):
				var start: Vector2 = _touch_state.get("start", drag.position)
				_touch_state["dragging"] = start.distance_to(drag.position) >= TOUCH_DRAG_SLOP
			if bool(_touch_state.get("dragging", false)):
				var scrollbar: = get_v_scroll_bar()
				if scrollbar != null and scrollbar.visible:
					scrollbar.value -= drag.relative.y
			accept_event()
			return
	DialogicUtil.autoload().Inputs.handle_node_gui_input(event)




func _request_touch_advance() -> void :
	DialogicUtil.autoload().Inputs.handle_input()
	var shared: = load("res://scripts/ai/ai_dialogue_shared.gd")
	if shared != null and shared.has_method("request_touch_advance"):
		shared.request_touch_advance()


func _configure_scrollbar() -> void :
	var scrollbar: = get_v_scroll_bar()
	if scrollbar == null:
		return
	scrollbar.mouse_filter = Control.MOUSE_FILTER_STOP

	var min_width: = 48.0 if OS.has_feature("android") else (30.0 if OS.has_feature("mobile") else 18.0)
	scrollbar.custom_minimum_size.x = maxf(scrollbar.custom_minimum_size.x, min_width)


func _is_event_on_scrollbar(event: InputEvent) -> bool:
	if not event is InputEventMouse:
		return false

	var scrollbar: = get_v_scroll_bar()
	if scrollbar == null or not scrollbar.visible:
		return false

	var mouse_event: = event as InputEventMouse
	var local_mouse_pos: = scrollbar.get_local_mouse_position()
	return Rect2(Vector2.ZERO, scrollbar.size).has_point(local_mouse_pos)


func custom_fx_update() -> void :
	for effect in custom_effects:
		if "visible_characters" in effect:
			effect.visible_characters = visible_characters


func custom_fx_reset() -> void :
	for effect in custom_effects:
		if effect.has_method("reset"):
			effect.reset()


func custom_fx_skip() -> void :
	for effect in custom_effects:
		if effect.has_method("skip"):
			effect.skip()

class_name DialogicNode_Input
extends Control





func _ready() -> void :
	add_to_group("dialogic_input")
	gui_input.connect(_on_gui_input)
	if OS.has_feature("android"):
		var gesture: = preload("res://scripts/ui/android_scroll_gesture.gd").new()
		add_child(gesture)
		gesture.setup(self, null, _on_android_tap)


func _input(_event: InputEvent) -> void :
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return

func _on_gui_input(event: InputEvent) -> void :
	if OS.has_feature("android") and (event is InputEventScreenTouch or event is InputEventScreenDrag or (event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION)):
		return
	DialogicUtil.autoload().Inputs.handle_node_gui_input(event)


func _on_android_tap() -> void :
	DialogicUtil.autoload().Inputs.handle_input()
	preload("res://scripts/ai/ai_dialogue_shared.gd").request_touch_advance()

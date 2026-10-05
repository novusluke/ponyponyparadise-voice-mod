extends Node

func _ready() -> void:
	get_tree().scene_changed.connect(_check, CONNECT_ONE_SHOT)

func _check() -> void:
	var controller: Node = get_tree().root.get_node("PonyVoiceMod")
	if controller.player.playing or not controller._current_key.is_empty():
		push_error("Speech continued after leaving the dialogue scene for a menu")
		get_tree().quit(1)
	else:
		print("AUDIO_SCENE_EXIT_OK")
		get_tree().quit(0)

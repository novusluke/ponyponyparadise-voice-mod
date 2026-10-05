extends Node

func _ready() -> void:
	assert(OS.get_user_data_dir().contains("VoiceModQA"))
	_run.call_deferred()

func _run() -> void:
	var controller: Node = preload("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree())
	controller.settings.enabled = true
	controller.test_voice()
	if not controller.player.playing:
		push_error("Scene exit fixture could not play the test clip")
		get_tree().quit(1)
		return
	var monitor := Node.new()
	monitor.set_script(load(get_script().resource_path.get_base_dir().path_join("godot_lifecycle_monitor.gd")))
	get_tree().root.add_child(monitor)
	var destination := Node.new()
	destination.name = "MenuDestination"
	var scene := PackedScene.new()
	scene.pack(destination)
	destination.free()
	get_tree().change_scene_to_packed(scene)

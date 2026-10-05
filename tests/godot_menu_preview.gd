extends Node

func _ready() -> void:
	_preview.call_deferred()

func _preview() -> void:
	get_tree().root.content_scale_size = Vector2i(1017, 755)
	get_tree().root.size = Vector2i(1017, 755)
	var controller: Node = load("res://scripts/voice_mod/voice_controller.gd").ensure(get_tree())
	var capture: Dictionary = controller._captured.duplicate(true)
	var menu: Node = load("res://scenes/ui_settings_menu.gd").new()
	get_tree().root.add_child(menu)
	menu.open()
	menu._voice_options.folder.text = "OmniVoice / .venv"
	menu._voice_options.steps.value = 64
	menu._voice_options.speed.value = 1.0
	menu._voice_options.volume.value = 0
	for _i in range(6):
		await get_tree().process_frame
	var panel: Control = menu._voice_options.get_parent().get_parent()
	var scroll: ScrollContainer = panel.get_parent().get_parent()
	scroll.scroll_vertical = int(panel.position.y)
	for _i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("PONY_MENU_SCREENSHOT"))
	controller._captured = capture
	menu._close()
	get_tree().quit()

extends "res://scenes/story_panel/story_panel.gd"
## Exercise the newer game's real selection handler without unrelated UI.
var fixture: Dictionary = {}
func _ready() -> void:
	pass
func _entry_for(_line_id: String) -> Dictionary:
	return fixture
func _refresh_rows() -> void:
	pass

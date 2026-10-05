extends "res://addons/dialogic/Modules/DefaultLayoutParts/Layer_History/history_layer.gd"
## Exercise the actual history-click handler without constructing unrelated UI.
var fixture: Dictionary = {}
func _ready() -> void:
	pass
func _get_selected_context_entry() -> Dictionary:
	return fixture
func _set_context_entry_selected(_index: int, _selected: bool) -> void:
	pass
func _update_toolbar_state() -> void:
	pass

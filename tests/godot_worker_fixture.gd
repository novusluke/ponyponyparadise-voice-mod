extends "res://scripts/voice_mod/voice_controller.gd"
## Leave the real file queue intact; QA supplies deterministic worker completions.
func _start_worker() -> bool:
	return true

extends "res://scripts/ai/ai_conversation_client.gd"
## The newer game adds a rewrite-guidance argument to its provider interface.
var asked := ""
func ask(_system: String, message: String, _history: Array = [], _timeout: float = -1.0, _trim: bool = false, _system_trim: bool = true, _family: String = "generic", _runtime: String = "", _prefill: String = "", _rewrite: String = "") -> void:
	asked = message
	response_received.emit('twi "A friendly test reply."\nnarrator "A quiet moment follows."')

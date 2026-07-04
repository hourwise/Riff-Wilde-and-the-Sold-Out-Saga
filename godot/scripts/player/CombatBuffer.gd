class_name CombatBuffer
extends Node

signal input_logged(action: StringName)
signal combo_accepted(combo_id: StringName)

@export var combo_window_seconds: float = 1.8

var _actions: Array[StringName] = []
var _times: Array[float] = []
var _patterns: Dictionary = {
	&"intro_combo": [&"strike", &"strike", &"sing"],
	&"crescendo_combo": [&"strike", &"sing", &"strike"],
	&"bridge_combo": [&"sing", &"strike"]
}

func _process(delta: float) -> void:
	_prune_expired(_now_seconds())

func record_input(action: StringName) -> StringName:
	var now: float = _now_seconds()
	_prune_expired(now)

	_actions.append(action)
	_times.append(now)
	input_logged.emit(action)
	print("[CombatBuffer] Input logged: %s | Buffer: %s" % [action, _format_buffer()])

	var matched_combo: StringName = _match_combo()
	if matched_combo != &"":
		print("[CombatBuffer] Combo candidate: %s" % _format_combo_name(matched_combo))
		return matched_combo

	return &""

func accept_combo(combo_id: StringName) -> void:
	_actions.clear()
	_times.clear()
	var progression_manager := get_node_or_null("/root/ProgressionManager")
	if progression_manager and progression_manager.has_method("record_combo_completed"):
		progression_manager.call("record_combo_completed")
	combo_accepted.emit(combo_id)
	print("[CombatBuffer] Combo accepted: %s" % _format_combo_name(combo_id))

func reject_combo(combo_id: StringName) -> void:
	_actions.clear()
	_times.clear()
	print("[CombatBuffer] Combo rejected: %s" % _format_combo_name(combo_id))

func _match_combo() -> StringName:
	var best_combo: StringName = &""
	var best_size: int = 0

	for combo_id: StringName in _patterns.keys():
		var pattern: Array = _patterns[combo_id]
		if pattern.size() > best_size and _ends_with_pattern(pattern):
			best_combo = combo_id
			best_size = pattern.size()

	return best_combo

func _ends_with_pattern(pattern: Array) -> bool:
	if _actions.size() < pattern.size():
		return false

	var offset: int = _actions.size() - pattern.size()
	for index in range(pattern.size()):
		if _actions[offset + index] != pattern[index]:
			return false
	return true

func _prune_expired(now: float) -> void:
	while not _times.is_empty() and now - _times[0] > combo_window_seconds:
		_times.remove_at(0)
		_actions.remove_at(0)

func _now_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _format_combo_name(combo_id: StringName) -> String:
	return String(combo_id).capitalize()

func _format_buffer() -> String:
	var labels: Array[String] = []
	for action in _actions:
		labels.append(String(action).capitalize())
	return " -> ".join(labels)

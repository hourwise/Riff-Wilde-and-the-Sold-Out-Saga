extends Node

@export var save_path: String = "user://save_data.json"

func _ready() -> void:
	print("[SaveService] Initializing...")

func save_progression(data: Dictionary) -> bool:
	var payload: Dictionary = {
		"version": 1,
		"progression": data
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if not file:
		push_error("[SaveService] Failed to open save file for writing: %s" % save_path)
		return false

	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	print("[SaveService] Progression saved: %s" % save_path)
	return true

func load_progression() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		print("[SaveService] No save file found. Starting fresh.")
		return {}

	var file := FileAccess.open(save_path, FileAccess.READ)
	if not file:
		push_error("[SaveService] Failed to open save file for reading: %s" % save_path)
		return {}

	var raw_text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw_text)
	if not parsed is Dictionary:
		push_error("[SaveService] Save file is invalid JSON: %s" % save_path)
		return {}

	var payload := parsed as Dictionary
	var progression: Variant = payload.get("progression", {})
	if not progression is Dictionary:
		push_error("[SaveService] Save file missing progression data: %s" % save_path)
		return {}

	print("[SaveService] Progression loaded: %s" % save_path)
	return progression as Dictionary

func delete_save() -> bool:
	if not FileAccess.file_exists(save_path):
		return true

	var error := DirAccess.remove_absolute(save_path)
	if error != OK:
		push_error("[SaveService] Failed to delete save file: %s (Error code: %d)" % [save_path, error])
		return false
	return true

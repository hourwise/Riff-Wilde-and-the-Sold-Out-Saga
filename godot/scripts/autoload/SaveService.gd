extends Node

@export var save_path: String = "user://save_data.json"
@export var settings_path: String = "user://settings.cfg"

## Player-facing options. Defaults are the values used when no settings file exists
## yet; the pause menu reads and writes them through get_setting/set_setting.
const SETTING_DEFAULTS: Dictionary = {
	"audio/master_volume": 0.9,
	"audio/music_volume": 0.8,
	"audio/sfx_volume": 1.0,
	"camera/mouse_sensitivity": 0.003,
	"camera/gamepad_sensitivity": 2.4,
	"camera/invert_y": false,
}

var _settings: Dictionary = {}

func _ready() -> void:
	load_settings()
	print("[SaveService] Ready.")

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

# ── Settings ─────────────────────────────────────────────────────

func get_setting(key: String) -> Variant:
	return _settings.get(key, SETTING_DEFAULTS.get(key, null))


## Stores a setting in memory. Call save_settings() to persist — this keeps slider
## drags from writing to disk on every frame.
func set_setting(key: String, value: Variant) -> void:
	_settings[key] = value


func load_settings() -> Dictionary:
	_settings = SETTING_DEFAULTS.duplicate()

	var config := ConfigFile.new()
	var error: Error = config.load(settings_path)
	if error != OK:
		if error != ERR_FILE_NOT_FOUND:
			push_warning("[SaveService] Could not read settings (error %d). Using defaults." % error)
		return _settings

	for key: String in SETTING_DEFAULTS.keys():
		var parts: PackedStringArray = key.split("/", true, 1)
		if parts.size() != 2:
			continue
		_settings[key] = config.get_value(parts[0], parts[1], SETTING_DEFAULTS[key])

	return _settings


func save_settings() -> bool:
	var config := ConfigFile.new()

	for key: String in _settings.keys():
		var parts: PackedStringArray = key.split("/", true, 1)
		if parts.size() != 2:
			continue
		config.set_value(parts[0], parts[1], _settings[key])

	var error: Error = config.save(settings_path)
	if error != OK:
		push_error("[SaveService] Failed to write settings: %s (error %d)" % [settings_path, error])
		return false
	return true


func reset_settings() -> void:
	_settings = SETTING_DEFAULTS.duplicate()
	save_settings()


# ── Progression ──────────────────────────────────────────────────

func delete_save() -> bool:
	if not FileAccess.file_exists(save_path):
		return true

	var error := DirAccess.remove_absolute(save_path)
	if error != OK:
		push_error("[SaveService] Failed to delete save file: %s (Error code: %d)" % [save_path, error])
		return false
	return true

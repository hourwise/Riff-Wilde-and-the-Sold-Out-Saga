extends Node
## FirebaseConfig — Autoload singleton for Firebase Realtime Database REST API.
## Reads settings from user://firebase.cfg at startup.
## If the config file is missing, cloud features are silently disabled.

const CONFIG_PATH: String = "user://firebase.cfg"

var _enabled: bool = false
var _project_id: String = ""
var _api_key: String = ""
var _rtdb_url: String = ""

func _ready() -> void:
	print("[FirebaseConfig] Initializing...")
	_load_config()

## Returns true if Firebase is configured and enabled.
func is_enabled() -> bool:
	return _enabled

## Returns the Realtime Database base URL (with trailing slash).
func get_rtdb_url() -> String:
	return _rtdb_url

## Builds a full RTDB REST URL for a given path.
## Example: build_url("users/abc123") -> "https://{db}.firebasedatabase.app/users/abc123.json"
func build_url(rtdb_path: String) -> String:
	if not _enabled:
		return ""
	return "%s%s.json" % [_rtdb_url, rtdb_path]

## Builds a URL with the API key as a query parameter (for RTDB, auth is via ?key=).
func build_authenticated_url(rtdb_path: String) -> String:
	var base := build_url(rtdb_path)
	if base.is_empty():
		return ""
	if _api_key.is_empty():
		return base
	return "%s?key=%s" % [base, _api_key]

func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		print("[FirebaseConfig] No firebase.cfg found at %s. Cloud sync disabled." % CONFIG_PATH)
		_enabled = false
		return

	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		push_warning("[FirebaseConfig] Could not open %s. Cloud sync disabled." % CONFIG_PATH)
		_enabled = false
		return

	var raw: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		push_warning("[FirebaseConfig] Invalid JSON in %s. Cloud sync disabled." % CONFIG_PATH)
		_enabled = false
		return

	var cfg := parsed as Dictionary
	_project_id = str(cfg.get("project_id", ""))
	_api_key = str(cfg.get("api_key", ""))
	_rtdb_url = str(cfg.get("rtdb_url", ""))

	# Ensure rtdb_url ends with a trailing slash for clean path joining.
	if not _rtdb_url.is_empty() and not _rtdb_url.ends_with("/"):
		_rtdb_url += "/"

	if _project_id.is_empty() or _rtdb_url.is_empty():
		push_warning("[FirebaseConfig] Missing project_id or rtdb_url in config. Cloud sync disabled.")
		_enabled = false
		return

	_enabled = true
	print("[FirebaseConfig] Firebase configured. Project: %s. RTDB: %s" % [_project_id, _rtdb_url])

extends Node

func _ready() -> void:
	print("[SceneLoader] Initializing...")

func load_scene(path: String) -> void:
	print("[SceneLoader] Loading scene: ", path)
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		push_error("[SceneLoader] Failed to load scene: %s (Error code: %d)" % [path, error])

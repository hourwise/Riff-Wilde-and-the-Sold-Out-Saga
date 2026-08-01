extends Node
## Host for UI that must exist regardless of which scene is loaded.
##
## Global UI lives here rather than being instanced per level, so pausing works
## identically in the hub, the cemetery and during cinematics. Later phases add
## the dialogue box and objective toasts alongside the pause menu.
##
## This is a container, not a controller — it owns no UI logic. Each child scene
## manages itself and talks to the rest of the game through EventBus.

const PAUSE_MENU_SCENE: String = "res://scenes/ui/PauseMenu.tscn"

var pause_menu: CanvasLayer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pause_menu = _instance_ui(PAUSE_MENU_SCENE)
	print("[UIRoot] Ready.")


func _instance_ui(path: String) -> CanvasLayer:
	if not ResourceLoader.exists(path):
		push_error("[UIRoot] Missing UI scene: %s" % path)
		return null

	var packed := ResourceLoader.load(path) as PackedScene
	if packed == null:
		push_error("[UIRoot] Could not load UI scene: %s" % path)
		return null

	var instance := packed.instantiate() as CanvasLayer
	if instance == null:
		push_error("[UIRoot] UI scene root must be a CanvasLayer: %s" % path)
		return null

	add_child(instance)
	return instance

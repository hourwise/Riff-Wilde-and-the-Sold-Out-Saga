extends Node

# State definition
enum GameState { TAVERN, MISSION, GAME_OVER }
var current_state: GameState = GameState.TAVERN

func _ready() -> void:
	print("[GameManager] Initializing...")
	_setup_inputs()

# Programmatically configures core inputs if they are not already set in project.godot
func _setup_inputs() -> void:
	var inputs: Dictionary = {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"dodge": [KEY_SHIFT],
		"strike": [MOUSE_BUTTON_LEFT],
		"sing": [MOUSE_BUTTON_RIGHT],
		"interact": [KEY_E],
		"restart": [KEY_R],
		"pause": [KEY_ESCAPE]
	}
	
	for action: String in inputs.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for key: int in inputs[action]:
				var event: InputEvent
				if key == MOUSE_BUTTON_LEFT or key == MOUSE_BUTTON_RIGHT:
					var mouse_event := InputEventMouseButton.new()
					mouse_event.button_index = key
					event = mouse_event
				else:
					var key_event := InputEventKey.new()
					key_event.physical_keycode = key
					event = key_event
				InputMap.action_add_event(action, event)
			print("[GameManager] Programmatically configured input action: ", action)

func change_state(new_state: GameState) -> void:
	current_state = new_state
	print("[GameManager] State changed to: ", GameState.keys()[new_state])

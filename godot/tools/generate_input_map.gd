extends SceneTree
## Generates the project's InputMap and writes it into project.godot.
##
## The input map is data, not runtime state: defining it here and persisting it to
## ProjectSettings means actions survive export, can be rebound by the player at
## runtime, and are visible in the editor's Input Map tab. This replaces the earlier
## approach of registering actions from GameManager._ready(), which did neither.
##
## Run once after changing the bindings below:
##   godot --headless --path godot --script res://tools/generate_input_map.gd
##
## Keys use physical_keycode so bindings stay in the same physical position on
## non-QWERTY layouts.

const STICK_DEADZONE: float = 0.2
const BUTTON_DEADZONE: float = 0.5

## InputMap's "matches any device" sentinel (InputMap::ALL_DEVICES in the engine).
const ALL_DEVICES_ID: int = -1

## Action name -> binding list. Each binding is one of:
##   ["key",   <KEY_* constant>]
##   ["mouse", <MOUSE_BUTTON_* constant>]
##   ["pad",   <JOY_BUTTON_* constant>]
##   ["axis",  <JOY_AXIS_* constant>, <-1.0 | 1.0>]
const BINDINGS: Dictionary = {
	# ── Movement ──────────────────────────────────────────────────
	"move_forward": [["key", KEY_W], ["key", KEY_UP], ["axis", JOY_AXIS_LEFT_Y, -1.0]],
	"move_back": [["key", KEY_S], ["key", KEY_DOWN], ["axis", JOY_AXIS_LEFT_Y, 1.0]],
	"move_left": [["key", KEY_A], ["key", KEY_LEFT], ["axis", JOY_AXIS_LEFT_X, -1.0]],
	"move_right": [["key", KEY_D], ["key", KEY_RIGHT], ["axis", JOY_AXIS_LEFT_X, 1.0]],

	# ── Camera (gamepad only; mouse look is handled from motion events) ──
	"camera_left": [["axis", JOY_AXIS_RIGHT_X, -1.0]],
	"camera_right": [["axis", JOY_AXIS_RIGHT_X, 1.0]],
	"camera_up": [["axis", JOY_AXIS_RIGHT_Y, -1.0]],
	"camera_down": [["axis", JOY_AXIS_RIGHT_Y, 1.0]],

	# ── Combat ────────────────────────────────────────────────────
	"strike": [["mouse", MOUSE_BUTTON_LEFT], ["pad", JOY_BUTTON_X]],
	"sing": [["mouse", MOUSE_BUTTON_RIGHT], ["pad", JOY_BUTTON_Y]],
	"dodge": [["key", KEY_SPACE], ["key", KEY_SHIFT], ["pad", JOY_BUTTON_B]],
	"lock_on": [["key", KEY_Q], ["mouse", MOUSE_BUTTON_MIDDLE], ["pad", JOY_BUTTON_RIGHT_STICK]],
	"summon_companion": [["key", KEY_F], ["pad", JOY_BUTTON_LEFT_SHOULDER]],

	# ── World ─────────────────────────────────────────────────────
	"interact": [["key", KEY_E], ["pad", JOY_BUTTON_A]],

	# ── System ────────────────────────────────────────────────────
	"pause": [["key", KEY_ESCAPE], ["pad", JOY_BUTTON_START]],
	"map_toggle": [["key", KEY_M], ["pad", JOY_BUTTON_BACK]],
	"restart": [["key", KEY_R]],
}


func _init() -> void:
	var written: int = 0

	for action: String in BINDINGS.keys():
		var bindings: Array = BINDINGS[action]
		var events: Array[InputEvent] = []
		var uses_stick: bool = false

		for binding: Array in bindings:
			var event: InputEvent = _build_event(binding)
			if event == null:
				push_error("[generate_input_map] Unrecognised binding on '%s': %s" % [action, binding])
				continue
			if event is InputEventJoypadMotion:
				uses_stick = true
			events.append(event)

		var setting: String = "input/%s" % action
		ProjectSettings.set_setting(setting, {
			"deadzone": STICK_DEADZONE if uses_stick else BUTTON_DEADZONE,
			"events": events,
		})
		# Actions are gameplay config, not engine defaults — mark them as such so
		# they are written to project.godot rather than treated as overrides.
		ProjectSettings.set_initial_value(setting, {"deadzone": BUTTON_DEADZONE, "events": []})
		written += 1
		print("[generate_input_map] %-18s %d binding(s)" % [action, events.size()])

	var error: Error = ProjectSettings.save()
	if error != OK:
		push_error("[generate_input_map] Failed to save project settings (error %d)." % error)
		quit(1)
		return

	print("[generate_input_map] Wrote %d actions to project.godot." % written)
	quit(0)


func _build_event(binding: Array) -> InputEvent:
	var event: InputEvent = null

	match String(binding[0]):
		"key":
			var key_event := InputEventKey.new()
			key_event.physical_keycode = int(binding[1])
			event = key_event
		"mouse":
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = int(binding[1])
			event = mouse_event
		"pad":
			var pad_event := InputEventJoypadButton.new()
			pad_event.button_index = int(binding[1])
			event = pad_event
		"axis":
			var axis_event := InputEventJoypadMotion.new()
			axis_event.axis = int(binding[1])
			axis_event.axis_value = float(binding[2])
			event = axis_event

	if event != null:
		# InputMap._find_event() skips any binding whose device does not match the
		# incoming event, so anything other than ALL_DEVICES silently never fires.
		# For joypads this also means "any controller" rather than only player 1.
		event.device = ALL_DEVICES_ID

	return event

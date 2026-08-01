class_name PlayerCameraRig
extends Node3D
## Third-person camera. Supports mouse look and right-stick look, with
## sensitivity, inversion and pitch limits driven by saved settings.
##
## The rig yaws; the spring arm pitches. Pause is deliberately NOT handled here —
## it belongs to PauseMenu, so the camera cannot fight the menu over mouse capture.

@export var pitch_min: float = -60.0
@export var pitch_max: float = 45.0

## Right-stick input below this magnitude is discarded. Matches the InputMap
## deadzone, but applied to the combined vector so diagonals are not clipped.
@export var gamepad_deadzone: float = 0.18

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

var _mouse_sensitivity: float = 0.003
var _gamepad_sensitivity: float = 2.4
var _invert_y: bool = false


func _ready() -> void:
	_apply_settings()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.current = true

	# Sensitivity can change while playing, via the pause menu.
	EventBus.game_suspended_changed.connect(_on_suspended_changed)


func _process(delta: float) -> void:
	_apply_gamepad_look(delta)


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	var motion := event as InputEventMouseMotion
	_apply_look(
		-motion.relative.x * _mouse_sensitivity,
		-motion.relative.y * _mouse_sensitivity
	)


func _apply_gamepad_look(delta: float) -> void:
	if GameManager.is_suspended():
		return

	var look := Vector2(
		Input.get_axis("camera_left", "camera_right"),
		Input.get_axis("camera_up", "camera_down")
	)
	if look.length() < gamepad_deadzone:
		return

	_apply_look(
		-look.x * _gamepad_sensitivity * delta,
		-look.y * _gamepad_sensitivity * delta
	)


func _apply_look(yaw_delta: float, pitch_delta: float) -> void:
	rotate_y(yaw_delta)

	var pitch: float = pitch_delta if not _invert_y else -pitch_delta
	spring_arm.rotation.x = clampf(
		spring_arm.rotation.x + pitch,
		deg_to_rad(pitch_min),
		deg_to_rad(pitch_max)
	)


## Re-reads settings whenever the game resumes, so changes made in the pause menu
## take effect immediately without needing a scene reload.
func _on_suspended_changed(is_suspended: bool) -> void:
	if not is_suspended:
		_apply_settings()


func _apply_settings() -> void:
	_mouse_sensitivity = float(SaveService.get_setting("camera/mouse_sensitivity"))
	_gamepad_sensitivity = float(SaveService.get_setting("camera/gamepad_sensitivity"))
	_invert_y = bool(SaveService.get_setting("camera/invert_y"))

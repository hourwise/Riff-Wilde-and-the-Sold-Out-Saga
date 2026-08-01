class_name PlayerCameraRig
extends Node3D
## Third-person camera: free look, lock-on framing and impact shake.
##
## The rig yaws; the spring arm pitches; shake is applied to the camera itself so
## it never affects where the camera is anchored. Pause is deliberately NOT handled
## here — it belongs to PauseMenu, so the camera cannot fight the menu over mouse
## capture.

@export var pitch_min: float = -60.0
@export var pitch_max: float = 45.0

## Right-stick input below this magnitude is discarded. Applied to the combined
## vector rather than per-axis so diagonals are not clipped.
@export var gamepad_deadzone: float = 0.18

@export_group("Lock-on")
## How quickly the rig swings to face a locked target.
@export var lock_on_turn_speed: float = 7.0
## Pitch the camera settles to while locked, in degrees.
@export var lock_on_pitch_degrees: float = -12.0
## Player look input is still honoured while locked, at this fraction of normal.
@export var lock_on_look_influence: float = 0.35

@export_group("Shake")
## Peak positional offset in metres at full trauma.
@export var shake_max_offset: float = 0.32
## Peak roll in degrees at full trauma.
@export var shake_max_roll_degrees: float = 3.2
## Trauma lost per second. Shorter decay reads as a snap; longer as a rumble.
@export var shake_decay: float = 2.2
## Noise sampling rate. Higher is more jittery, lower is more of a sway.
@export var shake_frequency: float = 22.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

var _mouse_sensitivity: float = 0.003
var _gamepad_sensitivity: float = 2.4
var _invert_y: bool = false

var _lock_target: Node3D = null
var _lock_controller: LockOnController = null

var _trauma: float = 0.0
var _shake_time: float = 0.0
var _shake_noise: FastNoiseLite = null
var _camera_rest_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	_apply_settings()
	_build_shake_noise()
	_camera_rest_position = camera.position

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.current = true

	EventBus.game_suspended_changed.connect(_on_suspended_changed)
	EventBus.lock_on_changed.connect(_on_lock_on_changed)


func _process(delta: float) -> void:
	_apply_gamepad_look(delta)
	_track_lock_target(delta)
	_update_shake(delta)


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	var motion := event as InputEventMouseMotion
	var influence: float = lock_on_look_influence if _lock_target != null else 1.0
	_apply_look(
		-motion.relative.x * _mouse_sensitivity * influence,
		-motion.relative.y * _mouse_sensitivity * influence
	)


## Adds camera shake. Trauma accumulates and is squared on use, so several small
## hits stay subtle while a single heavy one is dramatic.
func add_shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func set_lock_controller(controller: LockOnController) -> void:
	_lock_controller = controller


# ── Look ─────────────────────────────────────────────────────────

func _apply_gamepad_look(delta: float) -> void:
	if GameManager.is_suspended():
		return

	var look := Vector2(
		Input.get_axis("camera_left", "camera_right"),
		Input.get_axis("camera_up", "camera_down")
	)
	if look.length() < gamepad_deadzone:
		return

	var influence: float = lock_on_look_influence if _lock_target != null else 1.0
	_apply_look(
		-look.x * _gamepad_sensitivity * delta * influence,
		-look.y * _gamepad_sensitivity * delta * influence
	)


func _apply_look(yaw_delta: float, pitch_delta: float) -> void:
	rotate_y(yaw_delta)

	var pitch: float = pitch_delta if not _invert_y else -pitch_delta
	spring_arm.rotation.x = clampf(
		spring_arm.rotation.x + pitch,
		deg_to_rad(pitch_min),
		deg_to_rad(pitch_max)
	)


# ── Lock-on framing ──────────────────────────────────────────────

func _track_lock_target(delta: float) -> void:
	if _lock_target == null or not is_instance_valid(_lock_target):
		return

	var target_position: Vector3 = _lock_controller.get_target_position() if _lock_controller != null else _lock_target.global_position
	var to_target: Vector3 = target_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		return

	# atan2(x, z) rather than looking at the point directly: the rig must stay
	# upright, and pitch is owned by the spring arm.
	var desired_yaw: float = atan2(to_target.x, to_target.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, clampf(lock_on_turn_speed * delta, 0.0, 1.0))

	spring_arm.rotation.x = lerp_angle(
		spring_arm.rotation.x,
		deg_to_rad(lock_on_pitch_degrees),
		clampf(lock_on_turn_speed * 0.5 * delta, 0.0, 1.0)
	)


func _on_lock_on_changed(target: Node3D) -> void:
	_lock_target = target


# ── Shake ────────────────────────────────────────────────────────

func _build_shake_noise() -> void:
	_shake_noise = FastNoiseLite.new()
	_shake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_shake_noise.frequency = 1.0


func _update_shake(delta: float) -> void:
	if _trauma <= 0.0:
		if camera.position != _camera_rest_position:
			camera.position = _camera_rest_position
			camera.rotation.z = 0.0
		return

	_trauma = maxf(_trauma - shake_decay * delta, 0.0)
	_shake_time += delta * shake_frequency

	# Squaring makes small trauma nearly invisible and large trauma violent,
	# which reads better than a linear response.
	var intensity: float = _trauma * _trauma

	camera.position = _camera_rest_position + Vector3(
		_shake_noise.get_noise_2d(_shake_time, 0.0) * shake_max_offset * intensity,
		_shake_noise.get_noise_2d(0.0, _shake_time) * shake_max_offset * intensity,
		0.0
	)
	camera.rotation.z = deg_to_rad(
		_shake_noise.get_noise_2d(_shake_time, _shake_time) * shake_max_roll_degrees * intensity
	)


# ── Settings ─────────────────────────────────────────────────────

## Re-reads settings whenever the game resumes, so changes made in the pause menu
## take effect immediately without needing a scene reload.
func _on_suspended_changed(is_suspended: bool) -> void:
	if not is_suspended:
		_apply_settings()


func _apply_settings() -> void:
	_mouse_sensitivity = float(SaveService.get_setting("camera/mouse_sensitivity"))
	_gamepad_sensitivity = float(SaveService.get_setting("camera/gamepad_sensitivity"))
	_invert_y = bool(SaveService.get_setting("camera/invert_y"))

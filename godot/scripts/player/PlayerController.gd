class_name PlayerController
extends CharacterBody3D

@export var speed: float = 6.0
@export var lock_on_speed: float = 4.6
@export var acceleration: float = 12.0
@export var gravity: float = 20.0
@export var turn_speed: float = 10.0

@export_group("Dodge")
@export var dodge_speed: float = 18.0
@export var dodge_duration: float = 0.25
@export var dodge_cooldown: float = 0.55
## Invulnerability is a window inside the dodge, not the whole move. Dodging early
## must be rewarded and dodging late must be punished, otherwise spamming it is
## always correct.
@export var invulnerable_start: float = 0.04
@export var invulnerable_end: float = 0.20

var is_dodging: bool = false
var is_invulnerable: bool = false
var is_dead: bool = false
var dodge_timer: float = 0.0
var dodge_cooldown_timer: float = 0.0
var dodge_direction: Vector3 = Vector3.ZERO

## Previous health, used to derive damage amounts for EventBus.player_damaged.
var _last_health: float = 0.0

@onready var state_machine: PlayerStateMachine = $PlayerStateMachine
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var stats: PlayerStats = $PlayerStats
@onready var combat_buffer: CombatBuffer = $CombatBuffer
@onready var lock_on: LockOnController = $LockOnController
@onready var visual: CharacterVisual = $MeshInstance3D/CharacterVisual

var camera_rig: PlayerCameraRig
var hud_controller: Control = null


func _ready() -> void:
	add_to_group("player")

	_bind_camera_rig()
	_bind_hud()

	lock_on.setup(camera_rig.camera)
	camera_rig.set_lock_controller(lock_on)

	_last_health = stats.health
	stats.health_depleted.connect(_on_health_depleted)
	stats.health_changed.connect(_on_health_changed)

	EventBus.player_spawned.emit(self)


func _physics_process(delta: float) -> void:
	if is_dead:
		_apply_gravity(delta)
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		move_and_slide()
		return

	_apply_gravity(delta)

	if dodge_cooldown_timer > 0.0:
		dodge_cooldown_timer -= delta

	if is_dodging:
		_process_dodge(delta)
		return

	var direction: Vector3 = _get_move_direction()

	if Input.is_action_just_pressed("dodge") and dodge_cooldown_timer <= 0.0:
		start_dodge(direction)
		return

	if direction != Vector3.ZERO:
		var current_speed: float = lock_on_speed if lock_on.has_target() else speed
		var target_velocity: Vector3 = direction * current_speed
		velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
		velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)
		state_machine.change_state(PlayerStateMachine.State.MOVE)
	else:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		if is_on_floor() and state_machine.current_state != PlayerStateMachine.State.STAGGERED:
			state_machine.change_state(PlayerStateMachine.State.IDLE)

	_update_facing(direction, delta)
	_update_locomotion_visual()
	move_and_slide()


func _update_locomotion_visual() -> void:
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	visual.play_locomotion(horizontal_speed / maxf(speed, 0.01))


## Movement direction from the current input.
##
## Free movement is camera-relative. Locked-on movement is TARGET-relative:
## forward approaches the target, back retreats, left/right circle it.
##
## This distinction matters. Locking on swings the camera to face the target, and
## with camera-relative movement that silently redefines "forward" mid-stride —
## holding forward as you lock on would launch you straight at the enemy. Anchoring
## to the target instead keeps the stick meaning the same thing throughout.
func _get_move_direction() -> Vector3:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_dir == Vector2.ZERO or camera_rig == null:
		return Vector3.ZERO

	var forward: Vector3 = _get_reference_forward()
	var right: Vector3 = forward.cross(Vector3.UP).normalized()

	return (right * input_dir.x - forward * input_dir.y).normalized()


## The vector that "forward" input means right now.
func _get_reference_forward() -> Vector3:
	if lock_on.has_target():
		var to_target: Vector3 = lock_on.get_target_position() - global_position
		to_target.y = 0.0
		# Standing on top of the target makes the direction unstable, so fall back
		# to the camera rather than spinning.
		if to_target.length_squared() > 0.04:
			return to_target.normalized()

	var cam_forward: Vector3 = -camera_rig.global_transform.basis.z
	cam_forward.y = 0.0
	return cam_forward.normalized()


## While locked on, Riff faces the target and strafes; otherwise he turns to face
## where he is running.
func _update_facing(direction: Vector3, delta: float) -> void:
	var face_direction: Vector3 = direction

	if lock_on.has_target():
		var to_target: Vector3 = lock_on.get_target_position() - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.01:
			face_direction = to_target.normalized()

	_face_world_direction(face_direction, delta)


## Turns the mesh to face a WORLD-space direction.
##
## mesh.rotation is local to the player body, and a level may place that body at
## any yaw — the Inn rotates it 45 degrees. Assigning a world angle straight to a
## local rotation offsets the character by the body's own yaw, which reads as Riff
## walking and striking off to one side. Convert into body space first.
func _face_world_direction(direction: Vector3, delta: float) -> void:
	if direction == Vector3.ZERO:
		return

	var local_direction: Vector3 = global_transform.basis.orthonormalized().inverse() * direction
	local_direction.y = 0.0
	if local_direction.length_squared() < 0.0001:
		return

	var target_angle: float = atan2(-local_direction.x, -local_direction.z)
	mesh.rotation.y = lerp_angle(mesh.rotation.y, target_angle, turn_speed * delta)


# ── Dodge ────────────────────────────────────────────────────────

func start_dodge(dir: Vector3) -> void:
	if is_dead or is_dodging:
		return

	is_dodging = true
	dodge_timer = 0.0
	dodge_cooldown_timer = dodge_cooldown

	if dir != Vector3.ZERO:
		dodge_direction = dir
	elif lock_on.has_target():
		# Backstep away from the target when locked on with no input, which is
		# what players reach for when a heavy attack is incoming.
		var away: Vector3 = global_position - lock_on.get_target_position()
		away.y = 0.0
		dodge_direction = away.normalized() if away.length_squared() > 0.01 else -mesh.global_transform.basis.z.normalized()
	else:
		dodge_direction = -mesh.global_transform.basis.z.normalized()

	state_machine.change_state(PlayerStateMachine.State.DODGE)
	visual.play_dodge(dodge_duration)
	EventBus.player_dodged.emit()
	AudioManager.play_sfx(&"riff_dodge")


func _process_dodge(delta: float) -> void:
	dodge_timer += delta
	is_invulnerable = dodge_timer >= invulnerable_start and dodge_timer <= invulnerable_end

	if dodge_timer >= dodge_duration:
		is_dodging = false
		is_invulnerable = false
		state_machine.change_state(PlayerStateMachine.State.IDLE)
		return

	# Dodge overrides horizontal control entirely, but gravity still applies so a
	# dodge off a ledge does not float.
	var vertical: float = velocity.y
	velocity = dodge_direction * dodge_speed
	velocity.y = vertical

	# Face the dodge direction unless locked on, where facing the target matters more.
	if not lock_on.has_target():
		_face_world_direction(dodge_direction, delta)
	else:
		_update_facing(Vector3.ZERO, delta)

	move_and_slide()


# ── Lifecycle ────────────────────────────────────────────────────

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if is_dead and event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


func _on_health_changed(value: float, max_value: float) -> void:
	# Emitted here rather than from PlayerStats so the stats node stays a pure
	# data holder with no knowledge of the event bus.
	if value < _last_health:
		EventBus.player_damaged.emit(_last_health - value, value / maxf(max_value, 1.0))
		visual.play_hit()
	_last_health = value


func _on_health_depleted() -> void:
	is_dead = true
	is_dodging = false
	is_invulnerable = false
	velocity = Vector3.ZERO
	lock_on.clear()
	state_machine.change_state(PlayerStateMachine.State.STAGGERED)
	visual.play_death()

	GameManager.change_state(GameManager.GameState.GAME_OVER)
	EventBus.player_died.emit()
	AudioManager.play_sfx(&"riff_death")

	if hud_controller and hud_controller.has_method("show_defeat_prompt"):
		hud_controller.show_defeat_prompt()


# ── Setup ────────────────────────────────────────────────────────

func _bind_camera_rig() -> void:
	camera_rig = get_node_or_null("PlayerCameraRig")
	if camera_rig == null:
		camera_rig = get_node_or_null("../PlayerCameraRig")
	if camera_rig == null:
		var rig_scene: PackedScene = load("res://scenes/player/PlayerCameraRig.tscn")
		camera_rig = rig_scene.instantiate() as PlayerCameraRig
		add_child(camera_rig)


func _bind_hud() -> void:
	var hud_scene: PackedScene = preload("res://scenes/ui/HUD.tscn")
	var hud := hud_scene.instantiate() as CanvasLayer
	add_child(hud)

	hud_controller = hud.get_node("HUDController") as Control
	if hud_controller == null:
		return

	if hud_controller.has_method("setup_stats"):
		hud_controller.setup_stats(stats)
	if hud_controller.has_method("setup_combat_buffer"):
		hud_controller.setup_combat_buffer(combat_buffer)

class_name PlayerController
extends CharacterBody3D

@export var speed: float = 6.0
@export var acceleration: float = 12.0
@export var gravity: float = 20.0

# Dodge parameters
@export var dodge_speed: float = 18.0
@export var dodge_duration: float = 0.25
@export var dodge_cooldown: float = 0.8

var is_dodging: bool = false
var is_invulnerable: bool = false
var is_dead: bool = false
var dodge_timer: float = 0.0
var dodge_cooldown_timer: float = 0.0
var dodge_direction: Vector3 = Vector3.ZERO

@onready var state_machine: PlayerStateMachine = $PlayerStateMachine
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var stats: PlayerStats = $PlayerStats
@onready var combat_buffer: Node = $CombatBuffer

var camera_rig: PlayerCameraRig
var hud_controller: Control = null

func _ready() -> void:
	add_to_group("player")

	# Locate camera rig in children, or instantiate if missing
	camera_rig = get_node_or_null("PlayerCameraRig")
	if not camera_rig:
		camera_rig = get_node_or_null("../PlayerCameraRig")
	if not camera_rig:
		var rig_scene = load("res://scenes/player/PlayerCameraRig.tscn")
		camera_rig = rig_scene.instantiate() as PlayerCameraRig
		add_child(camera_rig)
		
	# Instantiate HUD and connect player stats
	var hud_scene: PackedScene = preload("res://scenes/ui/HUD.tscn")
	var hud: CanvasLayer = hud_scene.instantiate() as CanvasLayer
	add_child(hud)
	hud_controller = hud.get_node("HUDController") as Control
	if hud_controller and hud_controller.has_method("setup_stats"):
		hud_controller.setup_stats(stats)
	if hud_controller and hud_controller.has_method("setup_combat_buffer"):
		hud_controller.setup_combat_buffer(combat_buffer)
	stats.health_depleted.connect(_on_health_depleted)
		
	print("[PlayerController] Ready, camera rig bound, and HUD loaded.")

func _physics_process(delta: float) -> void:
	if is_dead:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
		else:
			velocity.y = 0.0
		move_and_slide()
		return

	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
		
	# Update cooldowns
	if dodge_cooldown_timer > 0.0:
		dodge_cooldown_timer -= delta
		
	# Handle dodging
	if is_dodging:
		dodge_timer -= delta
		if dodge_timer <= 0.0:
			is_dodging = false
			is_invulnerable = false
			state_machine.change_state(PlayerStateMachine.State.IDLE)
		else:
			var vertical_vel = velocity.y
			velocity = dodge_direction * dodge_speed
			velocity.y = vertical_vel
			move_and_slide()
			return

	# Calculate movement inputs
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3.ZERO
	
	if camera_rig:
		# Grab horizontal basis vector from camera direction
		var cam_forward := -camera_rig.global_transform.basis.z
		var cam_right := camera_rig.global_transform.basis.x
		cam_forward.y = 0.0
		cam_right.y = 0.0
		cam_forward = cam_forward.normalized()
		cam_right = cam_right.normalized()
		
		# Combine into move direction vector (negate cam_forward since move_forward corresponds to negative Y input_dir)
		direction = (cam_right * input_dir.x - cam_forward * input_dir.y).normalized()

	# Process Dodge action
	if Input.is_action_just_pressed("dodge") and not is_dodging and dodge_cooldown_timer <= 0.0:
		start_dodge(direction)
		return

	# Process normal movement
	if direction != Vector3.ZERO:
		var target_vel := direction * speed
		velocity.x = move_toward(velocity.x, target_vel.x, acceleration * delta)
		velocity.z = move_toward(velocity.z, target_vel.z, acceleration * delta)
		
		state_machine.change_state(PlayerStateMachine.State.MOVE)
		
		# Rotate the visual mesh to look in direction of movement
		var target_angle := atan2(-direction.x, -direction.z)
		mesh.rotation.y = lerp_angle(mesh.rotation.y, target_angle, 10.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		if is_on_floor() and state_machine.current_state != PlayerStateMachine.State.STAGGERED:
			state_machine.change_state(PlayerStateMachine.State.IDLE)
			
	move_and_slide()

func start_dodge(dir: Vector3) -> void:
	if is_dead:
		return

	is_dodging = true
	is_invulnerable = true
	dodge_timer = dodge_duration
	dodge_cooldown_timer = dodge_cooldown
	
	# Fallback to mesh face direction if idle
	if dir == Vector3.ZERO:
		dodge_direction = -mesh.global_transform.basis.z.normalized()
	else:
		dodge_direction = dir
		
	state_machine.change_state(PlayerStateMachine.State.DODGE)

func _unhandled_input(event: InputEvent) -> void:
	if is_dead and event.is_action_pressed("restart"):
		get_tree().reload_current_scene()

func _on_health_depleted() -> void:
	is_dead = true
	is_dodging = false
	is_invulnerable = false
	velocity = Vector3.ZERO
	state_machine.change_state(PlayerStateMachine.State.STAGGERED)

	GameManager.change_state(GameManager.GameState.GAME_OVER)

	if hud_controller and hud_controller.has_method("show_defeat_prompt"):
		hud_controller.show_defeat_prompt()
	print("[PlayerController] Defeated. Press R to restart.")

class_name TrainingDummy
extends CharacterBody3D

@export var max_health: float = 100.0
var current_health: float = max_health
var is_knocked_down: bool = false
var is_dead: bool = false
var reaction_tween: Tween = null
var movement_tween: Tween = null
var spawn_position: Vector3 = Vector3.ZERO

@export var friction: float = 16.0
@export var gravity: float = 20.0
@export var knockback_resistance: float = 1.0
@export var knockdown_friction_multiplier: float = 2.5
@export var death_reset_delay: float = 1.5

@onready var hurtbox: Hurtbox = $Hurtbox
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var health_label: Label3D = $Label3D

func _ready() -> void:
	spawn_position = global_position
	current_health = max_health
	update_hud()
	hurtbox.damaged.connect(_on_damaged)
	print("[TrainingDummy] Ready. Health: ", current_health)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
		
	# Apply decay to knockback velocity
	var current_friction: float = friction * knockdown_friction_multiplier if is_knocked_down else friction
	velocity.x = move_toward(velocity.x, 0.0, current_friction * delta)
	velocity.z = move_toward(velocity.z, 0.0, current_friction * delta)
	
	move_and_slide()

func _on_damaged(event: DamageEvent) -> void:
	if is_dead:
		return

	current_health = max(0.0, current_health - event.damage_amount)
	print("[TrainingDummy] Damage received: %.1f. HP remaining: %.1f" % [event.damage_amount, current_health])
	update_hud()
	
	# Apply knockback force vector
	var resistance: float = maxf(knockback_resistance, 0.01)
	var kb_vel: Vector3 = event.knockback_direction * (event.knockback_force / resistance)
	velocity.x = kb_vel.x
	velocity.z = kb_vel.z
	
	if event.status_effect == &"bridge_pull":
		_apply_bridge_pull(event)
	elif event.status_effect == &"knockdown":
		_apply_knockdown(event.status_duration)
	else:
		_play_hit_reaction()
	
	if current_health <= 0.0:
		die(maxf(event.status_duration, death_reset_delay))

func update_hud() -> void:
	if health_label:
		health_label.text = "Dummy HP: %d/%d" % [int(current_health), int(max_health)]

func die(reset_delay: float) -> void:
	if is_dead:
		return

	is_dead = true
	print("[TrainingDummy] Dummy defeated! Resetting in %.1fs..." % reset_delay)
	await get_tree().create_timer(reset_delay).timeout
	reset_dummy()

func reset_dummy() -> void:
	current_health = max_health
	is_dead = false
	is_knocked_down = false
	velocity = Vector3.ZERO
	global_position = spawn_position
	if reaction_tween:
		reaction_tween.kill()
	if movement_tween:
		movement_tween.kill()
	mesh.scale = Vector3.ONE
	mesh.rotation = Vector3.ZERO
	mesh.position = Vector3(0.0, 0.8, 0.0)
	update_hud()

func _play_hit_reaction() -> void:
	_reset_reaction_tween()
	mesh.rotation = Vector3.ZERO
	mesh.position = Vector3(0.0, 0.8, 0.0)
	reaction_tween.tween_property(mesh, "scale", Vector3(1.3, 0.7, 1.3), 0.05)
	reaction_tween.tween_property(mesh, "scale", Vector3(0.8, 1.2, 0.8), 0.08)
	reaction_tween.tween_property(mesh, "scale", Vector3.ONE, 0.1)

func _apply_knockdown(duration: float) -> void:
	is_knocked_down = true
	print("[TrainingDummy] Knocked down for %.1fs." % duration)

	_reset_reaction_tween()
	reaction_tween.set_parallel(true)
	reaction_tween.tween_property(mesh, "rotation:x", deg_to_rad(90.0), 0.12)
	reaction_tween.tween_property(mesh, "position:y", 0.4, 0.12)
	reaction_tween.tween_property(mesh, "scale", Vector3(1.15, 0.9, 1.15), 0.12)
	reaction_tween.set_parallel(false)
	reaction_tween.tween_interval(duration)
	reaction_tween.set_parallel(true)
	reaction_tween.tween_property(mesh, "rotation:x", 0.0, 0.2)
	reaction_tween.tween_property(mesh, "position:y", 0.8, 0.2)
	reaction_tween.tween_property(mesh, "scale", Vector3.ONE, 0.2)
	reaction_tween.set_parallel(false)
	reaction_tween.tween_callback(func() -> void:
		is_knocked_down = false
	)

func _apply_bridge_pull(event: DamageEvent) -> void:
	_play_hit_reaction()
	velocity = Vector3.ZERO

	var target_position: Vector3 = global_position
	if event.attacker is PlayerController:
		var player_attacker := event.attacker as PlayerController
		var forward: Vector3 = -player_attacker.mesh.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		target_position = player_attacker.global_position + forward * 1.4
	else:
		target_position = global_position + event.knockback_direction * event.knockback_force * 0.08

	target_position.y = global_position.y
	if movement_tween:
		movement_tween.kill()
	movement_tween = create_tween()
	movement_tween.tween_property(self, "global_position", target_position, maxf(event.status_duration, 0.08))

func _reset_reaction_tween() -> void:
	if reaction_tween:
		reaction_tween.kill()
	reaction_tween = create_tween()

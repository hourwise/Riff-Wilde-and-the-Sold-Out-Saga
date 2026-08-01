class_name ToneDeafAI
extends "res://scripts/enemies/EnemyBase.gd"

enum State { IDLE, CHASE, ATTACK, STAGGER, DEAD }

@export var detection_range: float = 20.0
@export var leash_range: float = 32.0
@export var chase_memory_seconds: float = 4.0
@export var attack_range: float = 1.6
@export var move_speed: float = 3.2
@export var acceleration: float = 10.0
@export var attack_damage: float = 8.0
@export var attack_cooldown: float = 1.0
@export var attack_windup: float = 0.35
@export var hit_stun_duration: float = 0.25
@export var obstacle_avoid_distance: float = 2.0
@export var obstacle_avoid_strength: float = 1.35
@export var obstacle_collision_mask: int = 1
@export var obstacle_feeler_heights: Array[float] = [0.25, 0.8]
@export var separation_radius: float = 1.4
@export var separation_strength: float = 1.1
@export var path_update_interval: float = 0.2

var current_state: State = State.IDLE
var attack_cooldown_timer: float = 0.0
var attack_windup_timer: float = 0.0
var is_winding_up_attack: bool = false
var hit_stun_timer: float = 0.0
var path_update_timer: float = 0.0
var chase_memory_timer: float = 0.0
var last_known_target_position: Vector3 = Vector3.ZERO
var target: PlayerController = null

@onready var navigation_agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D") as NavigationAgent3D

func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	_find_target()
	print("[ToneDeafAI] Ready.")

func _physics_process(delta: float) -> void:
	if is_dead:
		current_state = State.DEAD
		return

	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer -= delta
	if attack_windup_timer > 0.0:
		attack_windup_timer -= delta
		if attack_windup_timer <= 0.0:
			_complete_attack()
	if hit_stun_timer > 0.0:
		hit_stun_timer -= delta
	if path_update_timer > 0.0:
		path_update_timer -= delta
	if chase_memory_timer > 0.0:
		chase_memory_timer -= delta

	if not target or not is_instance_valid(target):
		_find_target()

	if _target_is_defeated():
		_cancel_attack()
		_change_state(State.IDLE)
		_apply_gravity(delta)
		_apply_horizontal_friction(delta)
		move_and_slide()
		return

	if is_knocked_down:
		_change_state(State.STAGGER)
		apply_movement_decay(delta)
		move_and_slide()
		return

	if hit_stun_timer > 0.0:
		is_winding_up_attack = false
		attack_windup_timer = 0.0
		_change_state(State.STAGGER)
		_apply_gravity(delta)
		_apply_horizontal_friction(delta)
		move_and_slide()
		return

	_apply_gravity(delta)
	_update_ai(delta)
	move_and_slide()

func _update_ai(delta: float) -> void:
	if not target:
		_change_state(State.IDLE)
		return

	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	var distance: float = to_target.length()
	var has_current_awareness: bool = distance <= detection_range

	if has_current_awareness:
		last_known_target_position = target.global_position
		chase_memory_timer = chase_memory_seconds
	elif distance > leash_range or chase_memory_timer <= 0.0:
		_change_state(State.IDLE)
		_apply_horizontal_friction(delta)
		return

	var chase_target_position: Vector3 = target.global_position if has_current_awareness else last_known_target_position
	var to_chase_target: Vector3 = chase_target_position - global_position
	to_chase_target.y = 0.0
	var chase_distance: float = to_chase_target.length()

	if has_current_awareness and distance <= attack_range:
		_change_state(State.ATTACK)
		_apply_horizontal_friction(delta)
		_try_start_attack()
		return

	_change_state(State.CHASE)
	if chase_distance <= attack_range * 0.75:
		_apply_horizontal_friction(delta)
		return

	var direction: Vector3 = _get_chase_direction(to_chase_target, chase_target_position)
	var target_velocity: Vector3 = direction * move_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)
	_face_direction(direction, delta)

func _on_damaged(event: DamageEvent) -> void:
	super._on_damaged(event)
	if not is_dead and event.status_effect != &"knockdown":
		hit_stun_timer = hit_stun_duration

func _try_start_attack() -> void:
	if attack_cooldown_timer > 0.0 or is_winding_up_attack or not target or _target_is_defeated():
		return

	is_winding_up_attack = true
	attack_windup_timer = attack_windup
	print("[ToneDeafAI] Attack wind-up started.")

func _complete_attack() -> void:
	is_winding_up_attack = false
	attack_cooldown_timer = attack_cooldown

	if not target or not is_instance_valid(target) or _target_is_defeated():
		return

	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() > attack_range + 0.25:
		print("[ToneDeafAI] Attack missed: target moved out of range.")
		return

	if target.stats.can_take_damage():
		target.stats.take_damage(attack_damage)
		print("[ToneDeafAI] Hit player for %.1f damage." % attack_damage)
	else:
		print("[ToneDeafAI] Attack avoided.")

func _cancel_attack() -> void:
	is_winding_up_attack = false
	attack_windup_timer = 0.0

func _target_is_defeated() -> bool:
	return target and "is_dead" in target and target.is_dead

func _find_target() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty() and players[0] is PlayerController:
		target = players[0] as PlayerController

func _get_chase_direction(to_chase_target: Vector3, chase_target_position: Vector3) -> Vector3:
	var desired_direction: Vector3 = to_chase_target.normalized()

	if navigation_agent:
		if path_update_timer <= 0.0:
			navigation_agent.target_position = chase_target_position
			path_update_timer = path_update_interval

		if not navigation_agent.is_navigation_finished():
			var next_path_position: Vector3 = navigation_agent.get_next_path_position()
			var to_path_point: Vector3 = next_path_position - global_position
			to_path_point.y = 0.0
			if to_path_point.length_squared() > 0.01:
				desired_direction = to_path_point.normalized()

	return _apply_steering(desired_direction)

## direction is world-space; mesh.rotation is local to this body, which a level may
## place at any yaw. Convert first, or the enemy faces off to one side of whatever
## it is chasing.
func _face_direction(direction: Vector3, delta: float) -> void:
	if not mesh or direction == Vector3.ZERO:
		return

	var local_direction: Vector3 = global_transform.basis.orthonormalized().inverse() * direction
	local_direction.y = 0.0
	if local_direction.length_squared() < 0.0001:
		return

	var target_angle: float = atan2(-local_direction.x, -local_direction.z)
	mesh.rotation.y = lerp_angle(mesh.rotation.y, target_angle, 8.0 * delta)

func _apply_steering(desired_direction: Vector3) -> Vector3:
	var steered_direction: Vector3 = desired_direction
	steered_direction += _get_obstacle_avoidance(desired_direction) * obstacle_avoid_strength
	steered_direction += _get_enemy_separation() * separation_strength
	steered_direction.y = 0.0

	if steered_direction.length_squared() <= 0.001:
		return desired_direction
	return steered_direction.normalized()

func _get_obstacle_avoidance(desired_direction: Vector3) -> Vector3:
	if desired_direction == Vector3.ZERO:
		return Vector3.ZERO

	var origin: Vector3 = global_position + Vector3.UP * 0.8
	if not _any_feeler_hits_obstacle(desired_direction):
		return Vector3.ZERO

	var left: Vector3 = Vector3(-desired_direction.z, 0.0, desired_direction.x).normalized()
	var left_probe: Vector3 = (desired_direction + left * 0.85).normalized()
	var right_probe: Vector3 = (desired_direction - left * 0.85).normalized()
	var left_clearance: float = _get_best_clearance(left_probe)
	var right_clearance: float = _get_best_clearance(right_probe)

	return left if left_clearance >= right_clearance else -left

func _get_enemy_separation() -> Vector3:
	var separation: Vector3 = Vector3.ZERO
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == self or not node is Node3D:
			continue

		var other := node as Node3D
		var offset: Vector3 = global_position - other.global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance <= 0.001 or distance > separation_radius:
			continue

		separation += offset.normalized() * (1.0 - distance / separation_radius)

	return separation.normalized() if separation.length_squared() > 0.001 else Vector3.ZERO

func _any_feeler_hits_obstacle(direction: Vector3) -> bool:
	for height in obstacle_feeler_heights:
		var origin: Vector3 = global_position + Vector3.UP * height
		if not _intersect_obstacle_ray(origin, direction, obstacle_avoid_distance).is_empty():
			return true
	return false

func _get_best_clearance(direction: Vector3) -> float:
	var best_clearance: float = obstacle_avoid_distance
	for height in obstacle_feeler_heights:
		var origin: Vector3 = global_position + Vector3.UP * height
		best_clearance = minf(best_clearance, _get_clearance(origin, direction))
	return best_clearance

func _get_clearance(origin: Vector3, direction: Vector3) -> float:
	var hit: Dictionary = _intersect_obstacle_ray(origin, direction, obstacle_avoid_distance)
	if hit.is_empty():
		return obstacle_avoid_distance

	var hit_position: Vector3 = hit["position"]
	return origin.distance_to(hit_position)

func _intersect_obstacle_ray(origin: Vector3, direction: Vector3, distance: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * distance)
	query.exclude = [self]
	query.collision_mask = obstacle_collision_mask
	return get_world_3d().direct_space_state.intersect_ray(query)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

func _apply_horizontal_friction(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	velocity.z = move_toward(velocity.z, 0.0, friction * delta)

func _change_state(new_state: State) -> void:
	if current_state == new_state:
		return

	print("[ToneDeafAI] State changed: %s -> %s" % [State.keys()[current_state], State.keys()[new_state]])
	current_state = new_state

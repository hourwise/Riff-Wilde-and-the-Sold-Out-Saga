class_name EnemySteering
extends Node
## Navigation and local avoidance, shared by the whole enemy roster.
##
## Extracted from the original ToneDeafAI so every enemy paths, avoids geometry
## and spreads out identically. Combines three influences:
##   1. A navigation path toward the goal (global routing).
##   2. Obstacle feelers that steer around what the path does not know about.
##   3. Separation from other enemies, so a group surrounds the player instead of
##      collapsing into a single stack.
##
## Pure query: it returns a direction and never touches the body's velocity.

@export_group("Obstacle avoidance")
@export var obstacle_avoid_distance: float = 2.0
@export var obstacle_avoid_strength: float = 1.35
## Layer 1 is world geometry. Enemies are deliberately excluded — they are handled
## by separation, and treating them as walls makes crowds jitter.
@export_flags_3d_physics var obstacle_collision_mask: int = 1
## Ray heights, so a knee-high gravestone and a chest-high wall are both felt.
@export var obstacle_feeler_heights: Array[float] = [0.25, 0.8]

@export_group("Separation")
@export var separation_radius: float = 1.4
@export var separation_strength: float = 1.1

@export_group("Pathing")
## Seconds between navigation target updates. Repathing every frame is wasteful
## and makes agents twitch.
@export var path_update_interval: float = 0.2

var _body: CharacterBody3D = null
var _agent: NavigationAgent3D = null
var _path_timer: float = 0.0


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if _body == null:
		push_error("[EnemySteering] Must be a child of a CharacterBody3D.")
		return
	_agent = _body.get_node_or_null("NavigationAgent3D") as NavigationAgent3D


func _process(delta: float) -> void:
	if _path_timer > 0.0:
		_path_timer -= delta


## Direction the body should move to reach goal_position, already steered around
## obstacles and away from other enemies. Returns a normalised vector, or ZERO if
## there is nowhere sensible to go.
func get_direction_to(goal_position: Vector3) -> Vector3:
	if _body == null:
		return Vector3.ZERO

	var to_goal: Vector3 = goal_position - _body.global_position
	to_goal.y = 0.0
	if to_goal.length_squared() < 0.0001:
		return Vector3.ZERO

	var desired: Vector3 = to_goal.normalized()

	if _agent != null:
		if _path_timer <= 0.0:
			_agent.target_position = goal_position
			_path_timer = path_update_interval

		if not _agent.is_navigation_finished():
			var next_point: Vector3 = _agent.get_next_path_position() - _body.global_position
			next_point.y = 0.0
			if next_point.length_squared() > 0.01:
				desired = next_point.normalized()

	return _apply_influences(desired)


func _apply_influences(desired: Vector3) -> Vector3:
	var steered: Vector3 = desired
	steered += _get_obstacle_avoidance(desired) * obstacle_avoid_strength
	steered += _get_separation() * separation_strength
	steered.y = 0.0

	# Influences can cancel out exactly; fall back to the raw heading rather than
	# freezing in place.
	if steered.length_squared() <= 0.001:
		return desired
	return steered.normalized()


## Returns a sideways nudge when something blocks the way, choosing whichever side
## has more room.
func _get_obstacle_avoidance(desired: Vector3) -> Vector3:
	if desired == Vector3.ZERO or not _feelers_hit(desired):
		return Vector3.ZERO

	var left: Vector3 = Vector3(-desired.z, 0.0, desired.x).normalized()
	var left_clearance: float = _best_clearance((desired + left * 0.85).normalized())
	var right_clearance: float = _best_clearance((desired - left * 0.85).normalized())

	return left if left_clearance >= right_clearance else -left


func _get_separation() -> Vector3:
	var separation: Vector3 = Vector3.ZERO

	for node in get_tree().get_nodes_in_group("enemies"):
		if node == _body or not (node is Node3D):
			continue

		var offset: Vector3 = _body.global_position - (node as Node3D).global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance <= 0.001 or distance > separation_radius:
			continue

		# Weight by closeness so crowding pushes harder than mere proximity.
		separation += offset.normalized() * (1.0 - distance / separation_radius)

	return separation.normalized() if separation.length_squared() > 0.001 else Vector3.ZERO


func _feelers_hit(direction: Vector3) -> bool:
	for height: float in obstacle_feeler_heights:
		if not _raycast(_body.global_position + Vector3.UP * height, direction).is_empty():
			return true
	return false


func _best_clearance(direction: Vector3) -> float:
	var clearance: float = obstacle_avoid_distance
	for height: float in obstacle_feeler_heights:
		var origin: Vector3 = _body.global_position + Vector3.UP * height
		var hit: Dictionary = _raycast(origin, direction)
		if not hit.is_empty():
			clearance = minf(clearance, origin.distance_to(hit["position"]))
	return clearance


func _raycast(origin: Vector3, direction: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction.normalized() * obstacle_avoid_distance
	)
	query.exclude = [_body.get_rid()]
	query.collision_mask = obstacle_collision_mask
	return _body.get_world_3d().direct_space_state.intersect_ray(query)

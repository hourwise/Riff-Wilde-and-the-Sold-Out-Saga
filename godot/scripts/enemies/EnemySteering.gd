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
## Once a side is picked to go round something, it is held for this long.
##
## Without it, avoidance re-decides every frame. Two clearances that are nearly
## equal — which is the normal case for a headstone in open ground — flip the
## chosen side on tiny differences, and the enemy zigzags on the spot instead of
## travelling. Committing to a side for a moment is also just what going round
## something looks like.
@export var obstacle_commit_seconds: float = 0.55
## Layer 1 is world geometry. Enemies are deliberately excluded — they are handled
## by separation, and treating them as walls makes crowds jitter.
@export_flags_3d_physics var obstacle_collision_mask: int = 1
## Ray heights, so a knee-high gravestone and a chest-high wall are both felt.
@export var obstacle_feeler_heights: Array[float] = [0.25, 0.8]

@export_group("Separation")
@export var separation_radius: float = 1.4
@export var separation_strength: float = 1.1
## Cap on the combined separation push, so being surrounded cannot outvote the
## direction of travel entirely.
@export var separation_limit: float = 1.0

@export_group("Pathing")
## Seconds between navigation target updates. Repathing every frame is wasteful
## and makes agents twitch.
@export var path_update_interval: float = 0.2
## How far the goal must move before the path is recomputed.
##
## Repathing on a timer alone re-decides the route five times a second at a
## target that has barely moved. Each recomputation can pick a different first
## corner, and the enemy turns toward a new one every 200 ms — a slow left-right
## wobble that costs it most of its forward speed. Chasing a player who is
## standing still should not need a new path at all.
@export var repath_distance: float = 0.6

@export_group("Smoothing")
## How fast the steering direction may turn, in degrees per second.
##
## The influences below are recomputed from scratch every frame and can differ
## sharply between one frame and the next. Feeding that straight into velocity is
## what makes a group read as twitching rather than walking; rate-limiting the
## heading costs nothing in responsiveness at these speeds.
@export var turn_rate_degrees: float = 540.0

var _body: CharacterBody3D = null
var _agent: NavigationAgent3D = null
var _path_timer: float = 0.0
var _last_goal: Vector3 = Vector3.INF

## Which way round the current obstacle, and how long that choice still holds.
var _avoid_side: float = 0.0
var _avoid_hold: float = 0.0

## Last direction returned, so the heading can be rate-limited rather than
## snapping to whatever this frame's influences add up to.
var _smoothed: Vector3 = Vector3.ZERO
var _last_delta: float = 0.0


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if _body == null:
		push_error("[EnemySteering] Must be a child of a CharacterBody3D.")
		return
	_agent = _body.get_node_or_null("NavigationAgent3D") as NavigationAgent3D


## Timers tick on the physics clock because that is the clock steering is queried
## on. Ticking them in _process meant the commit window and the turn-rate limit
## were measured against a different frame rate than the one moving the enemy.
func _physics_process(delta: float) -> void:
	_last_delta = delta
	if _path_timer > 0.0:
		_path_timer -= delta
	if _avoid_hold > 0.0:
		_avoid_hold -= delta


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
		var goal_moved: bool = (
			is_inf(_last_goal.x) or goal_position.distance_to(_last_goal) > repath_distance
		)
		if _path_timer <= 0.0 and goal_moved:
			_agent.target_position = goal_position
			_last_goal = goal_position
			_path_timer = path_update_interval

		if not _agent.is_navigation_finished():
			var next_point: Vector3 = _agent.get_next_path_position() - _body.global_position
			next_point.y = 0.0
			# Ignored when the corner is close enough to be standing on. Aiming at
			# a point half a step away swings the heading wildly as it is passed,
			# which is the same wobble arriving by a different route.
			if next_point.length() > 0.35:
				desired = next_point.normalized()

	return _apply_influences(desired)


## Direction to back away from a threat while staying on navigable ground.
##
## Retreating naively — just moving along the away vector — walks the enemy
## backwards off ledges and into walls, because nothing is checking where it is
## going. Projecting the retreat goal onto the navigation map first keeps it on
## the level.
func get_retreat_direction(threat_position: Vector3, distance: float) -> Vector3:
	if _body == null:
		return Vector3.ZERO

	var away: Vector3 = _body.global_position - threat_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = -_body.global_transform.basis.z
		away.y = 0.0

	var goal: Vector3 = snap_to_navigation(_body.global_position + away.normalized() * distance)
	return get_direction_to(goal)


## Nearest point on the navigation map. Returns the input unchanged when no map is
## available, so this is safe in test scenes that have no NavigationRegion.
func snap_to_navigation(point: Vector3) -> Vector3:
	if _agent == null:
		return point

	var map: RID = _agent.get_navigation_map()
	if not map.is_valid():
		return point

	# An empty map answers every closest-point query with the world origin, which
	# would drag retreating enemies to 0,0,0 — straight through the player. Scenes
	# without a baked navigation region must be left alone.
	if NavigationServer3D.map_get_regions(map).is_empty():
		return point

	var closest: Vector3 = NavigationServer3D.map_get_closest_point(map, point)

	# A registered region is not the same as a queryable one: the server adopts
	# regions before their polygons are synced, and answers with the origin in
	# between. Treat an exact origin result for a non-origin query as "not ready"
	# rather than walking the enemy to the middle of the level.
	if closest.is_zero_approx() and not point.is_zero_approx():
		return point

	return closest


func _apply_influences(desired: Vector3) -> Vector3:
	var steered: Vector3 = desired
	steered += _get_obstacle_avoidance(desired) * obstacle_avoid_strength
	steered += _get_separation() * separation_strength
	steered.y = 0.0

	# Influences can cancel out exactly; fall back to the raw heading rather than
	# freezing in place.
	if steered.length_squared() <= 0.001:
		steered = desired

	return _smooth(steered.normalized())


## Rate-limits how fast the heading may swing.
func _smooth(target: Vector3) -> Vector3:
	if _smoothed.length_squared() < 0.001:
		_smoothed = target
		return target

	# Falls back to the body's own physics step, so a caller that queries steering
	# before the first _physics_process still gets a sane limit rather than a
	# near-zero one that pins the heading in place.
	var step: float = _last_delta if _last_delta > 0.0 else get_physics_process_delta_time()
	var limit: float = deg_to_rad(turn_rate_degrees) * maxf(step, 0.0001)
	var angle: float = _smoothed.signed_angle_to(target, Vector3.UP)
	_smoothed = _smoothed.rotated(Vector3.UP, clampf(angle, -limit, limit)).normalized()
	return _smoothed


## A sideways push around whatever is in the way, proportional to how blocked the
## path is and committed to one side for long enough to actually get round.
##
## This used to be all-or-nothing: a full-strength perpendicular the instant a
## feeler touched anything, and nothing at all the instant it cleared. That is a
## loop — steer off, the feeler clears, steer back, the feeler hits — and it is
## why enemies crabbed left and right instead of closing.
func _get_obstacle_avoidance(desired: Vector3) -> Vector3:
	if desired == Vector3.ZERO:
		return Vector3.ZERO

	var ahead: float = _best_clearance(desired)
	if ahead >= obstacle_avoid_distance:
		# Nothing in the way. The committed side is kept until it times out, so
		# clearing the obstacle for a single frame does not restart the decision.
		if _avoid_hold <= 0.0:
			_avoid_side = 0.0
		return Vector3.ZERO

	var left: Vector3 = Vector3(-desired.z, 0.0, desired.x).normalized()

	if _avoid_side == 0.0 or _avoid_hold <= 0.0:
		var left_clearance: float = _best_clearance((desired + left * 0.85).normalized())
		var right_clearance: float = _best_clearance((desired - left * 0.85).normalized())
		_avoid_side = 1.0 if left_clearance >= right_clearance else -1.0
		_avoid_hold = obstacle_commit_seconds

	# Proportional to how close the obstruction is, so a distant wall bends the
	# path and a near one turns it hard.
	var urgency: float = 1.0 - clampf(ahead / maxf(obstacle_avoid_distance, 0.001), 0.0, 1.0)
	return left * _avoid_side * urgency


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

	# Limited rather than normalised. Normalising made one distant neighbour push
	# exactly as hard as being wedged in a crowd, so a pair of enemies walking
	# near each other shoved each other about as violently as a scrum.
	if separation.length() > separation_limit:
		separation = separation.normalized() * separation_limit
	return separation


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

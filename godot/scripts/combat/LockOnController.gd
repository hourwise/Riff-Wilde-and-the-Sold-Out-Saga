class_name LockOnController
extends Node
## Soft lock-on targeting.
##
## Acquires the enemy closest to where the camera is looking, keeps it while it
## stays alive and in range, and lets the player flick between targets. Announces
## changes on EventBus.lock_on_changed so the camera, HUD reticle and player
## facing can react without any of them referencing each other.
##
## Targets are any node in the "enemies" group. An optional "LockOnPoint" child
## marks where to aim; otherwise the node's origin plus a default height is used.

## Maximum distance at which a new target can be acquired.
@export var acquire_range: float = 18.0
## Distance at which an existing lock breaks. Larger than acquire_range so a lock
## does not flicker off the moment the player backs away slightly.
@export var break_range: float = 24.0
## Half-angle from the camera's forward vector within which targets are eligible.
@export var acquire_half_angle_degrees: float = 70.0
## How strongly distance-from-screen-centre is preferred over raw proximity.
@export var aim_weight: float = 2.0
## Seconds before another flick can switch targets.
@export var switch_cooldown: float = 0.28
## Stick or mouse deflection required to switch targets while locked.
@export var switch_threshold: float = 0.65
## Height above a target's origin used when it has no LockOnPoint child.
@export var default_target_height: float = 1.0
## Physics layers that block line of sight. Layer 1 is world geometry.
@export_flags_3d_physics var occlusion_mask: int = 1

var current_target: Node3D = null

var _player: CharacterBody3D = null
var _camera: Camera3D = null
var _switch_timer: float = 0.0
var _mouse_switch_axis: float = 0.0


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	if _player == null:
		push_error("[LockOnController] Must be a child of the player CharacterBody3D.")
		set_process(false)


func setup(camera: Camera3D) -> void:
	_camera = camera


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("lock_on"):
		toggle()
		return

	# Mouse flicks switch targets while locked. Accumulated here and consumed in
	# _process so a single fast flick does not switch several times.
	if current_target != null and event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_mouse_switch_axis += motion.relative.x * 0.01


func _process(delta: float) -> void:
	if _switch_timer > 0.0:
		_switch_timer -= delta

	if current_target == null:
		_mouse_switch_axis = 0.0
		return

	if not _is_valid_target(current_target, break_range):
		clear()
		return

	_handle_switch_input()


func toggle() -> void:
	if current_target != null:
		clear()
		AudioManager.play_ui(&"ui_back")
		return

	var target: Node3D = _find_best_target(Vector2.ZERO)
	if target == null:
		AudioManager.play_ui(&"ui_back")
		return

	_set_target(target)
	AudioManager.play_ui(&"ui_confirm")


func clear() -> void:
	if current_target == null:
		return
	_set_target(null)


func has_target() -> bool:
	return current_target != null


## World-space point to aim at, accounting for the target's LockOnPoint if present.
func get_target_position() -> Vector3:
	if current_target == null:
		return Vector3.ZERO

	var point := current_target.get_node_or_null("LockOnPoint") as Node3D
	if point != null:
		return point.global_position
	return current_target.global_position + Vector3.UP * default_target_height


# ── Target selection ─────────────────────────────────────────────

func _handle_switch_input() -> void:
	if _switch_timer > 0.0:
		_mouse_switch_axis = 0.0
		return

	var stick: float = Input.get_axis("camera_left", "camera_right")
	var deflection: float = stick if absf(stick) > absf(_mouse_switch_axis) else _mouse_switch_axis
	_mouse_switch_axis = 0.0

	if absf(deflection) < switch_threshold:
		return

	# Search to one side of the current target only, so flicking right never
	# selects something on the left.
	var direction := Vector2(signf(deflection), 0.0)
	var next: Node3D = _find_best_target(direction)
	if next == null or next == current_target:
		return

	_switch_timer = switch_cooldown
	_set_target(next)
	AudioManager.play_ui(&"ui_hover")


## Picks the best target. When search_direction is non-zero, only candidates on
## that side of the current target (in screen space) are considered.
func _find_best_target(search_direction: Vector2) -> Node3D:
	if _camera == null or _player == null:
		return null

	var best: Node3D = null
	var best_score: float = INF
	var current_screen_x: float = 0.0
	if current_target != null:
		current_screen_x = _camera.unproject_position(get_target_position()).x

	for node in get_tree().get_nodes_in_group("enemies"):
		var candidate := node as Node3D
		if candidate == null or candidate == current_target:
			continue
		if not _is_valid_target(candidate, acquire_range):
			continue

		var candidate_position: Vector3 = _aim_point(candidate)
		if _camera.is_position_behind(candidate_position):
			continue

		var screen_position: Vector2 = _camera.unproject_position(candidate_position)
		if search_direction.x != 0.0:
			var offset: float = screen_position.x - current_screen_x
			if signf(offset) != search_direction.x or is_zero_approx(offset):
				continue

		var viewport_centre: Vector2 = Vector2(get_viewport().get_visible_rect().size) * 0.5
		var aim_error: float = screen_position.distance_to(viewport_centre) / maxf(viewport_centre.x, 1.0)
		var distance: float = _player.global_position.distance_to(candidate_position)

		# Prefer whatever the player is looking at, then whatever is closest.
		var score: float = aim_error * aim_weight + distance / maxf(acquire_range, 1.0)
		if score < best_score:
			best_score = score
			best = candidate

	return best


func _is_valid_target(target: Node3D, range_limit: float) -> bool:
	if not is_instance_valid(target) or not target.is_inside_tree():
		return false
	if bool(target.get("is_dead")):
		return false
	if _player.global_position.distance_to(_aim_point(target)) > range_limit:
		return false
	return _has_line_of_sight(target)


func _has_line_of_sight(target: Node3D) -> bool:
	var origin: Vector3 = _player.global_position + Vector3.UP * default_target_height
	var query := PhysicsRayQueryParameters3D.create(origin, _aim_point(target))
	query.collision_mask = occlusion_mask
	query.exclude = [_player.get_rid()]
	return get_tree().root.world_3d.direct_space_state.intersect_ray(query).is_empty()


func _aim_point(target: Node3D) -> Vector3:
	var point := target.get_node_or_null("LockOnPoint") as Node3D
	if point != null:
		return point.global_position
	return target.global_position + Vector3.UP * default_target_height


func _set_target(target: Node3D) -> void:
	current_target = target
	EventBus.lock_on_changed.emit(target)

extends SceneTree
## Automated verification for Phase 2 (combat feel).
##
##   godot --headless --path godot --script res://tools/smoke_test_phase2.gd
##
## Focuses on behaviour that fails silently rather than crashing: a lock-on that
## never acquires, an i-frame window that covers the whole dodge, a hitstop that
## forgets to restore time scale, or a chain whose buffer window is unreachable.

const ARENA: String = "res://scenes/levels/PrototypeArena.tscn"
const ENEMY: String = "res://scenes/enemies/ToneDeaf.tscn"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	await process_frame
	change_scene_to_file(ARENA)

	# Let the arena build its navigation and the player bind its camera rig.
	for i in range(12):
		await process_frame

	print("\n=== Phase 2 smoke test ===\n")

	var player: Node3D = _get_player()
	if player == null:
		print("  FAIL  player present in arena")
		print("\nFAILED\n")
		quit(1)
		return

	_test_attack_chain(player)
	_test_dodge_iframes(player)
	await _test_camera_framing(player)
	await _test_hitstop()
	await _test_lock_on(player)
	await _test_locked_movement(player)

	print("\n=== %d/%d checks passed ===" % [_checks - _failures, _checks])
	if _failures > 0:
		print("FAILED\n")
		quit(1)
		return
	print("PASSED\n")
	quit(0)


# ── Tests ────────────────────────────────────────────────────────

func _test_attack_chain(player: Node3D) -> void:
	var strike: Node = player.get_node_or_null("StrikeController")
	if not _check(strike != null, "StrikeController present"):
		return

	var chain: Array = strike.get("chain")
	_check(chain.size() >= 3, "melee chain has at least three steps")

	var previous_damage: float = 0.0
	var escalates: bool = true
	for step in chain:
		# A buffer window at or past the end of the step can never be reached,
		# which silently turns the chain into single hits.
		_check(
			step.buffer_open < step.total_duration(),
			"'%s' buffer window is reachable" % step.display_name
		)
		_check(step.active > 0.0, "'%s' has active frames" % step.display_name)
		_check(step.windup > 0.0, "'%s' has a readable wind-up" % step.display_name)
		if step.damage < previous_damage:
			escalates = false
		previous_damage = step.damage

	_check(escalates, "chain damage escalates toward the finisher")


func _test_dodge_iframes(player: Node3D) -> void:
	var start: float = float(player.get("invulnerable_start"))
	var end: float = float(player.get("invulnerable_end"))
	var duration: float = float(player.get("dodge_duration"))

	_check(start > 0.0, "dodge has vulnerable start-up")
	_check(end < duration, "dodge has vulnerable recovery")
	_check(start < end, "i-frame window is non-empty")
	_check(
		float(player.get("dodge_cooldown")) > 0.0,
		"dodge cannot be spammed without cooldown"
	)


## The game is third person. Anything that writes the camera's transform can
## collapse it onto the player and silently turn the game first person — which is
## exactly what caching the camera's rest position before SpringArm3D had run did.
## Distance is asserted at rest and while shaking, since shake is the code that
## touches the camera transform.
func _test_camera_framing(player: Node3D) -> void:
	var rig: Node3D = player.get_node_or_null("PlayerCameraRig")
	if not _check(rig != null, "camera rig present"):
		return

	var spring_arm := rig.get_node_or_null("SpringArm3D") as SpringArm3D
	var camera: Camera3D = rig.get("camera")
	if not _check(spring_arm != null and camera != null, "spring arm and camera resolve"):
		return

	_check(
		camera.get_parent() != spring_arm,
		"camera is not a direct spring arm child, so shake cannot fight it"
	)

	# The arm may be shortened by geometry, so require a clear majority of it.
	var minimum: float = spring_arm.spring_length * 0.5
	await process_frame
	await process_frame

	var rest_distance: float = camera.global_position.distance_to(player.global_position)
	_check(rest_distance > minimum, "camera sits behind the player at rest (%.2fm)" % rest_distance)

	rig.call("add_shake", 1.0)
	for i in range(3):
		await process_frame

	var shake_distance: float = camera.global_position.distance_to(player.global_position)
	_check(shake_distance > minimum, "camera stays third person while shaking (%.2fm)" % shake_distance)

	# Let the trauma decay so it does not bleed into later checks.
	for i in range(30):
		await process_frame


func _test_hitstop() -> void:
	var game_manager: Node = root.get_node_or_null("GameManager")
	if not _check(game_manager != null, "GameManager present"):
		return

	_check(is_equal_approx(Engine.time_scale, 1.0), "time scale starts normal")

	game_manager.call("apply_hitstop", 0.05, 0.1)
	await process_frame
	_check(Engine.time_scale < 1.0, "hitstop slows time")

	# Real-time wait: a scaled timer would outlast the hitstop it is measuring.
	var timer: SceneTreeTimer = create_timer(0.25, true, false, true)
	await timer.timeout
	_check(is_equal_approx(Engine.time_scale, 1.0), "hitstop restores time scale")


func _test_lock_on(player: Node3D) -> void:
	var lock_on: Node = player.get_node_or_null("LockOnController")
	if not _check(lock_on != null, "LockOnController present"):
		return

	# Place a known enemy in front of the player so acquisition is deterministic
	# rather than depending on where the arena happens to spawn things.
	var enemy_scene := load(ENEMY) as PackedScene
	if not _check(enemy_scene != null, "enemy scene loads"):
		return

	var enemy := enemy_scene.instantiate() as Node3D
	current_scene.add_child(enemy)
	enemy.global_position = player.global_position + Vector3(0.0, 0.0, -6.0)
	await process_frame
	await process_frame

	var announced: Array[Node3D] = []
	var bus: Node = root.get_node("EventBus")
	bus.lock_on_changed.connect(func(target: Node3D) -> void: announced.append(target))

	lock_on.call("toggle")
	await process_frame
	_check(bool(lock_on.call("has_target")), "lock-on acquires a nearby enemy")
	_check(announced.size() == 1 and announced[0] != null, "acquisition announced on EventBus")

	var aim: Vector3 = lock_on.call("get_target_position")
	_check(aim.y > enemy.global_position.y, "aim point sits above the target's feet")

	lock_on.call("toggle")
	await process_frame
	_check(not bool(lock_on.call("has_target")), "lock-on toggles off")
	_check(announced.size() == 2 and announced[1] == null, "release announced on EventBus")

	# A dead target must not stay locked, or the camera keeps framing a corpse.
	lock_on.call("toggle")
	await process_frame
	if bool(lock_on.call("has_target")):
		enemy.set("is_dead", true)
		await process_frame
		await process_frame
		_check(not bool(lock_on.call("has_target")), "lock-on drops a dead target")
	else:
		_check(false, "lock-on re-acquires for the death test")

	enemy.queue_free()


## While locked on, movement must be anchored to the TARGET, not the camera.
## With camera-relative movement, locking on redefines "forward" as the camera
## swings, which launches the player at the enemy. The camera is deliberately
## rotated away here so a camera-relative implementation cannot pass.
func _test_locked_movement(player: Node3D) -> void:
	var lock_on: Node = player.get_node_or_null("LockOnController")
	var rig: Node3D = player.get_node_or_null("PlayerCameraRig")
	if not _check(lock_on != null and rig != null, "lock-on and rig available for movement test"):
		return

	# Run this on a clean platform well above the arena. Measuring displacement in
	# the arena itself is unreliable: its props and its own chasing enemies box the
	# player in, so a correct implementation still registers as not moving.
	var platform := StaticBody3D.new()
	var platform_shape := CollisionShape3D.new()
	var platform_box := BoxShape3D.new()
	platform_box.size = Vector3(120.0, 1.0, 120.0)
	platform_shape.shape = platform_box
	platform.add_child(platform_shape)
	platform.collision_layer = 1
	current_scene.add_child(platform)
	platform.global_position = Vector3(0.0, 200.0, 0.0)

	# The arena's own enemies would compete for the lock; take them out of it.
	for node in get_nodes_in_group("enemies"):
		node.remove_from_group("enemies")
		node.set_physics_process(false)

	var enemy_scene := load(ENEMY) as PackedScene
	var enemy := enemy_scene.instantiate() as Node3D
	current_scene.add_child(enemy)
	enemy.set_physics_process(false)

	player.velocity = Vector3.ZERO
	player.global_position = Vector3(0.0, 201.0, 0.0)
	enemy.global_position = Vector3(0.0, 201.0, -10.0)

	# Let the player settle onto the platform before measuring.
	for i in range(20):
		await physics_frame

	lock_on.call("clear")
	lock_on.call("toggle")
	await physics_frame
	if not _check(lock_on.get("current_target") == enemy, "locked onto the intended target"):
		enemy.queue_free()
		return

	# Point the camera 90 degrees away from the target.
	rig.rotation.y += deg_to_rad(90.0)

	var start_distance: float = player.global_position.distance_to(enemy.global_position)
	await _hold_action("move_forward", 24)
	var approach_distance: float = player.global_position.distance_to(enemy.global_position)

	_check(
		approach_distance < start_distance - 0.5,
		"locked forward approaches the target despite the camera facing elsewhere (%.2fm -> %.2fm)"
			% [start_distance, approach_distance]
	)

	rig.rotation.y += deg_to_rad(90.0)
	var strafe_start: float = player.global_position.distance_to(enemy.global_position)
	await _hold_action("move_right", 24)
	var strafe_distance: float = player.global_position.distance_to(enemy.global_position)

	# Circling keeps roughly constant range; a camera-relative basis would drift
	# in or out as the camera swings.
	_check(
		absf(strafe_distance - strafe_start) < 1.5,
		"locked strafe circles the target at a steady range (%.2fm -> %.2fm)"
			% [strafe_start, strafe_distance]
	)

	lock_on.call("clear")
	enemy.queue_free()
	platform.queue_free()
	await physics_frame


func _hold_action(action: String, frames: int) -> void:
	Input.action_press(action)
	for i in range(frames):
		await physics_frame
	Input.action_release(action)
	await physics_frame


# ── Helpers ──────────────────────────────────────────────────────

func _get_player() -> Node3D:
	var players: Array[Node] = get_nodes_in_group("player")
	return players[0] as Node3D if not players.is_empty() else null


func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if condition:
		print("  ok    %s" % description)
		return true

	_failures += 1
	print("  FAIL  %s" % description)
	return false

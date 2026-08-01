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
	await _test_hitstop()
	await _test_lock_on(player)

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

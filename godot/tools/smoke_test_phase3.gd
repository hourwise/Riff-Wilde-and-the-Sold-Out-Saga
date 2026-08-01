extends SceneTree
## Automated verification for Phase 3 (enemy roster).
##
##   godot --headless --path godot --script res://tools/smoke_test_phase3.gd
##
## Each enemy exists to teach one lesson. These checks assert the mechanic that
## carries that lesson actually works — an interruptible channel that cannot be
## interrupted, or poise that never breaks, would still look fine on screen.

const PLAYER: String = "res://scenes/player/Player.tscn"

const ROSTER: Array[Dictionary] = [
	{"scene": "res://scenes/enemies/ToneDeaf.tscn", "stats": "res://resources/enemies/tone_deaf.tres"},
	{"scene": "res://scenes/enemies/GraveCrawler.tscn", "stats": "res://resources/enemies/grave_crawler.tres"},
	{"scene": "res://scenes/enemies/HollowChoir.tscn", "stats": "res://resources/enemies/hollow_choir.tres"},
	{"scene": "res://scenes/enemies/BoneBellRinger.tscn", "stats": "res://resources/enemies/bone_bell_ringer.tres"},
]

var _failures: int = 0
var _checks: int = 0
var _root: Node3D = null
var _player: Node3D = null


func _initialize() -> void:
	await process_frame
	_build_arena()
	for i in range(15):
		await physics_frame

	print("\n=== Phase 3 smoke test ===\n")

	_test_stats_resources()
	_test_scene_structure()
	await _test_enemy_animations()
	await _test_choir_interrupt()
	await _test_choir_buff()
	await _test_bell_ringer_poise()
	await _test_crawler_leap()

	print("\n=== %d/%d checks passed ===" % [_checks - _failures, _checks])
	if _failures > 0:
		print("FAILED\n")
		quit(1)
		return
	print("PASSED\n")
	quit(0)


## A bare platform with a player on it. Built here rather than loading a level so
## the roster is tested in isolation from level layout.
func _build_arena() -> void:
	_root = Node3D.new()
	root.add_child(_root)
	current_scene = _root

	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.collision_layer = 1
	_root.add_child(floor_body)
	floor_body.global_position = Vector3.ZERO

	_player = (load(PLAYER) as PackedScene).instantiate() as Node3D
	_root.add_child(_player)
	_player.global_position = Vector3(0.0, 1.0, 0.0)


# ── Tests ────────────────────────────────────────────────────────

func _test_stats_resources() -> void:
	for entry: Dictionary in ROSTER:
		var stats := load(String(entry["stats"])) as EnemyStats
		if not _check(stats != null, "stats load: %s" % entry["stats"]):
			continue

		_check(stats.max_health > 0.0, "%s has health" % stats.display_name)
		# Zero wind-up means an unreactable attack, which reads as unfair.
		_check(stats.attack_windup > 0.0, "%s telegraphs its attack" % stats.display_name)
		_check(
			stats.detection_range < stats.leash_range,
			"%s leashes further than it detects" % stats.display_name
		)


func _test_scene_structure() -> void:
	for entry: Dictionary in ROSTER:
		var scene := load(String(entry["scene"])) as PackedScene
		if not _check(scene != null, "scene loads: %s" % entry["scene"]):
			continue

		var enemy := scene.instantiate() as Node3D
		var name: String = enemy.name

		_check(enemy.get_node_or_null("Hurtbox") != null, "%s has a Hurtbox" % name)
		_check(enemy.get_node_or_null("EnemySteering") != null, "%s has steering" % name)
		_check(enemy.get_node_or_null("NavigationAgent3D") != null, "%s has a nav agent" % name)
		# Without a LockOnPoint the reticle sits at the enemy's feet.
		_check(enemy.get_node_or_null("LockOnPoint") != null, "%s has a lock-on anchor" % name)
		_check(enemy.get("stats") != null, "%s has stats assigned" % name)

		enemy.free()


## Rigged enemies must actually be driven by their model's AnimationPlayer, with
## every configured clip present. A renamed or misspelled clip is skipped
## silently, leaving the enemy sliding around in a T-pose.
func _test_enemy_animations() -> void:
	for entry: Dictionary in ROSTER:
		# Spawned well away from the player so nothing reacts during the check.
		var enemy: Node3D = await _spawn(String(entry["scene"]), Vector3(0.0, 0.6, -60.0))
		if enemy == null:
			continue

		var visual := enemy.get_node_or_null("CharacterVisual") as CharacterVisual
		if not _check(visual != null, "%s has a CharacterVisual" % enemy.name):
			enemy.queue_free()
			continue

		if _check(visual.has_animations(), "%s is driven by an AnimationPlayer" % enemy.name):
			var missing: Array[StringName] = visual.get_missing_clips()
			_check(
				missing.is_empty(),
				"%s clip names all resolve%s" % [enemy.name, "" if missing.is_empty() else " (missing: %s)" % str(missing)]
			)

		enemy.queue_free()
		await physics_frame


func _test_choir_interrupt() -> void:
	await _reset_player()
	var choir: Node3D = await _spawn_near_player("res://scenes/enemies/HollowChoir.tscn", Vector3(0.0, 0.0, -6.0))
	if not _check(choir != null, "Hollow Choir spawns"):
		return

	choir.call("_start_channel")
	await physics_frame
	if not _check(bool(choir.get("is_channelling")), "Hollow Choir begins channelling"):
		choir.queue_free()
		return

	_damage(choir, 5.0)
	await physics_frame
	_check(
		not bool(choir.get("is_channelling")),
		"damage interrupts the Hollow Choir's channel"
	)

	choir.queue_free()
	await physics_frame


func _test_choir_buff() -> void:
	await _reset_player()
	var choir: Node3D = await _spawn_near_player("res://scenes/enemies/HollowChoir.tscn", Vector3(0.0, 0.0, -6.0))
	var ally: Node3D = await _spawn_near_player("res://scenes/enemies/ToneDeaf.tscn", Vector3(2.0, 0.0, -6.0))
	if choir == null or ally == null:
		_check(false, "choir and ally spawn for buff test")
		return

	var before: float = float(ally.get("_damage_multiplier"))
	choir.call("_start_channel")
	choir.call("_complete_channel")
	await physics_frame

	_check(
		float(ally.get("_damage_multiplier")) > before,
		"a completed choir song empowers nearby undead"
	)

	choir.queue_free()
	ally.queue_free()
	await physics_frame


func _test_bell_ringer_poise() -> void:
	await _reset_player()
	var ringer: Node3D = await _spawn_near_player("res://scenes/enemies/BoneBellRinger.tscn", Vector3(0.0, 0.0, -6.0))
	if not _check(ringer != null, "Bone Bell Ringer spawns"):
		return

	var poise: float = (ringer.get("stats") as EnemyStats).poise
	_check(poise > 0.0, "Bone Bell Ringer has poise")

	# Chip damage must bounce off, or the heavy is just a slow Tone Deaf.
	_damage(ringer, poise * 0.2)
	await physics_frame
	_check(
		float(ringer.get("hit_stun_timer")) <= 0.0,
		"chip damage does not stagger the Bone Bell Ringer"
	)

	# Committing past the poise threshold must break it.
	_damage(ringer, poise)
	await physics_frame
	_check(
		float(ringer.get("hit_stun_timer")) > 0.0,
		"breaking poise staggers the Bone Bell Ringer"
	)

	ringer.queue_free()
	await physics_frame


func _test_crawler_leap() -> void:
	await _reset_player()

	# Pin the player. It is only a reference point here, and letting it be shoved
	# around by physics changes the very distance the leap depends on.
	_player.set_physics_process(false)
	_player.velocity = Vector3.ZERO
	_player.global_position = Vector3(0.0, 0.6, 0.0)
	await physics_frame

	var crawler: Node3D = await _spawn("res://scenes/enemies/GraveCrawler.tscn", Vector3(0.0, 0.6, -5.0))
	if not _check(crawler != null, "Grave Crawler spawns"):
		_player.set_physics_process(true)
		return

	# Settle so it is grounded and has acquired the player.
	for i in range(5):
		await physics_frame
	_check(crawler.get("target") != null, "Grave Crawler acquires the player")

	# Guard the premise: if the pair is not actually at mid-range, a leap failure
	# below would be the setup's fault, not the crawler's.
	var setup_distance: float = crawler.global_position.distance_to(_player.global_position)
	_check(
		setup_distance > 3.0 and setup_distance < float(crawler.get("leap_range")),
		"crawler starts at mid-range (%.2fm)" % setup_distance
	)

	# Observe the leap happening rather than asking whether it would: the crawler
	# acts the moment it is in range, so by the time a predicate is polled it is
	# already airborne and on cooldown.
	var leapt: bool = false
	for i in range(60):
		await physics_frame
		if bool(crawler.get("_is_leaping")):
			leapt = true
			break
	_check(leapt, "Grave Crawler leaps to close mid-range")

	# Point blank it should swipe, not leap over the player's head.
	crawler.set("_is_leaping", false)
	crawler.set("_leap_cooldown_timer", 0.0)
	crawler.global_position = _player.global_position + Vector3(0.0, 0.0, -1.0)
	await physics_frame
	_check(not bool(crawler.call("_should_leap")), "Grave Crawler does not leap point blank")

	_player.set_physics_process(true)
	crawler.queue_free()
	await physics_frame


# ── Helpers ──────────────────────────────────────────────────────

## Returns the player to the origin and lets it settle. Enemies from earlier
## sub-tests shove it around, so without this each test spawns its enemy at a
## different real distance than intended.
func _reset_player() -> void:
	_player.velocity = Vector3.ZERO
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	for i in range(6):
		await physics_frame


## Spawns relative to the player rather than at a world coordinate, so distances
## are what the test asks for.
func _spawn_near_player(path: String, offset: Vector3) -> Node3D:
	return await _spawn(path, _player.global_position + offset)


func _spawn(path: String, position: Vector3) -> Node3D:
	var scene := load(path) as PackedScene
	if scene == null:
		return null

	var enemy := scene.instantiate() as Node3D
	_root.add_child(enemy)
	enemy.global_position = position
	await physics_frame
	return enemy


func _damage(enemy: Node3D, amount: float) -> void:
	var hurtbox := enemy.get_node_or_null("Hurtbox") as Hurtbox
	if hurtbox == null:
		return
	hurtbox.receive_damage(DamageEvent.new(amount, 0.0, Vector3.FORWARD, _player, &"", 0.0, &"strike", 0.0))


func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if condition:
		print("  ok    %s" % description)
		return true

	_failures += 1
	print("  FAIL  %s" % description)
	return false

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
	{"scene": "res://scenes/enemies/DirgeCantor.tscn", "stats": "res://resources/enemies/dirge_cantor.tres"},
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
	await _test_retreat_direction()
	await _test_fall_recovery()
	await _test_travels_without_zigzagging()
	await _test_cantor_projectile()
	await _test_quaver_drops()

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

		# Toe bones sit in front of the ankle on any humanoid rig, so foot-to-toes
		# says which way the model faces. Asserted here because facing has been
		# wrong repeatedly and was only ever caught by playing the game.
		var forward: Vector3 = _measure_facing(enemy, visual)
		if forward != Vector3.ZERO:
			_check(forward.z < 0.0, "%s faces forward, not backwards" % enemy.name)

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


## The Hollow Choir kites, and a naive retreat walks it backwards off the level.
## Its retreat must be routed through steering, which projects the goal onto the
## navigation map before moving.
func _test_retreat_direction() -> void:
	await _reset_player()
	var choir: Node3D = await _spawn_near_player("res://scenes/enemies/HollowChoir.tscn", Vector3(0.0, 0.0, -3.0))
	if not _check(choir != null, "Hollow Choir spawns for retreat test"):
		return

	var steering := choir.get_node_or_null("EnemySteering") as EnemySteering
	if not _check(steering != null, "Hollow Choir has steering"):
		choir.queue_free()
		return

	var away: Vector3 = steering.get_retreat_direction(_player.global_position, 8.0)
	var expected: Vector3 = choir.global_position - _player.global_position
	expected.y = 0.0

	_check(away != Vector3.ZERO, "retreat produces a direction")
	_check(
		away.normalized().dot(expected.normalized()) > 0.5,
		"retreat heads away from the player"
	)

	choir.queue_free()
	await physics_frame


## A gap in level geometry must not be able to delete an enemy the player still
## needs to defeat, so anything that falls out of the world is returned to the
## last ground it stood on.
func _test_fall_recovery() -> void:
	await _reset_player()
	var enemy: Node3D = await _spawn_near_player("res://scenes/enemies/ToneDeaf.tscn", Vector3(3.0, 0.0, -3.0))
	if not _check(enemy != null, "enemy spawns for fall test"):
		return

	# Let it settle so it records solid ground beneath it.
	for i in range(15):
		await physics_frame

	var recovery_height: float = float(enemy.get("fall_recovery_y"))
	enemy.global_position = Vector3(0.0, recovery_height - 30.0, 0.0)
	enemy.velocity = Vector3.ZERO

	for i in range(10):
		await physics_frame

	_check(
		enemy.global_position.y > recovery_height,
		"an enemy that falls out of the world is recovered (y=%.1f)" % enemy.global_position.y
	)

	enemy.queue_free()
	await physics_frame



## Which way a character actually faces, measured in its CharacterVisual's space
## so the configured yaw correction is included. Godot's forward is -Z.
func _measure_facing(character: Node3D, visual: Node3D) -> Vector3:
	var skeleton: Skeleton3D = _find_node(character, "Skeleton3D") as Skeleton3D
	if skeleton == null:
		return Vector3.ZERO

	var foot_index: int = -1
	var toe_index: int = -1
	for i in range(skeleton.get_bone_count()):
		var bone: String = skeleton.get_bone_name(i).to_lower()
		if toe_index < 0 and bone.contains("toe"):
			toe_index = i
		elif foot_index < 0 and bone.contains("foot") and not bone.contains("toe"):
			foot_index = i

	if foot_index < 0 or toe_index < 0:
		return Vector3.ZERO

	var to_visual: Transform3D = visual.global_transform.affine_inverse() * skeleton.global_transform
	var forward: Vector3 = (to_visual * skeleton.get_bone_global_pose(toe_index)).origin 		- (to_visual * skeleton.get_bone_global_pose(foot_index)).origin
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.0001 else Vector3.ZERO


func _find_node(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found: Node = _find_node(child, type_name)
		if found != null:
			return found
	return null

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


## Enemies must close on the player, not crab.
##
## Measured on a GROUP, because that is where the oscillation actually came from.
## Graveyard scenery carries no collision, so obstacle feelers rarely fire out
## there; what does fire, constantly, is separation between the members of an
## encounter. It was normalised to full strength and then scaled by 1.1, making
## the push away from a neighbour stronger than the pull toward the player. Two
## enemies converging would shove each other apart, re-converge, and shove again
## — visibly sliding left and right while barely advancing.
func _test_travels_without_zigzagging() -> void:
	var group: Array[Node3D] = []
	for i in range(5):
		var enemy := (load("res://scenes/enemies/ToneDeaf.tscn") as PackedScene).instantiate() as Node3D
		_root.add_child(enemy)
		# Deliberately tight: inside each other's separation radius from the start.
		enemy.global_position = Vector3(-1.2 + 0.6 * float(i), 1.0, -15.0 - 0.4 * float(i))
		group.append(enemy)

	for i in range(10):
		await physics_frame

	var watched: Node3D = group[2]
	var start: Vector3 = watched.global_position
	var previous: Vector3 = start
	var travelled: float = 0.0
	var reversals: int = 0
	var last_sideways: float = 0.0

	for i in range(180):
		await physics_frame
		var step: Vector3 = watched.global_position - previous
		step.y = 0.0
		travelled += step.length()

		if step.length() > 0.002:
			# Sideways relative to the line to the player, so ordinary turning
			# does not count as a reversal.
			var to_player: Vector3 = _player.global_position - watched.global_position
			to_player.y = 0.0
			var side: Vector3 = Vector3(-to_player.z, 0.0, to_player.x).normalized()
			var sideways: float = step.dot(side)
			if absf(sideways) > 0.004:
				if last_sideways != 0.0 and signf(sideways) != signf(last_sideways):
					reversals += 1
				last_sideways = sideways

		previous = watched.global_position

	var closed: float = start.distance_to(_player.global_position) - watched.global_position.distance_to(_player.global_position)
	var efficiency: float = closed / maxf(travelled, 0.001)

	_check(closed > 5.0, "an enemy in a group closes on the player (%.1fm)" % closed)
	_check(
		efficiency > 0.6,
		"most of its movement is toward the player (%.0f%% of %.1fm travelled)" % [efficiency * 100.0, travelled]
	)
	_check(
		reversals < 3,
		"it does not crab left and right on the way (%d direction reversals in 3s)" % reversals
	)

	for enemy: Node3D in group:
		enemy.queue_free()
	await physics_frame


## The Dirge Cantor exists so that dodging has a reason to exist.
##
## Every other enemy attacks in melee, which the player can simply walk out of.
## Checked for the three properties that make its note a dodge test rather than an
## unavoidable tax: it is actually fired, it crosses ground slowly enough to be
## read, and an invulnerable player takes nothing from it.
func _test_cantor_projectile() -> void:
	var cantor := (load("res://scenes/enemies/DirgeCantor.tscn") as PackedScene).instantiate() as Node3D
	_root.add_child(cantor)
	cantor.global_position = _player.global_position + Vector3(0.0, 0.0, -11.0)

	# Long enough for the cooldown and a full wind-up.
	var fired: Node = null
	for i in range(320):
		await physics_frame
		fired = _first_projectile()
		if fired != null:
			break

	if not _check(fired != null, "the Cantor fires a note"):
		cantor.queue_free()
		return

	# Slow enough to see coming. A note that arrives faster than a reaction is not
	# something the dodge can answer.
	var speed: float = float(fired.get("speed"))
	_check(speed > 6.0 and speed < 18.0, "the note travels at a readable speed (%.0f m/s)" % speed)

	var start: Vector3 = (fired as Node3D).global_position
	for i in range(10):
		await physics_frame
		if not is_instance_valid(fired):
			break
	if is_instance_valid(fired):
		var moved: float = (fired as Node3D).global_position.distance_to(start)
		_check(moved > 0.5, "the note actually travels (%.1fm in 10 frames)" % moved)

	# It must land on the player when not dodged.
	var stats: Node = _player.get_node_or_null("PlayerStats")
	var before: float = float(stats.get("health"))
	var landed: bool = false
	for i in range(420):
		await physics_frame
		if float(stats.get("health")) < before:
			landed = true
			break
	_check(landed, "a note that is not dodged does damage")

	# And nothing at all through i-frames, which is the whole point. Riff has no
	# Hurtbox node; the dodge window is a flag on the controller that PlayerStats
	# reads, so that is what gets held open here.
	_player.set("is_invulnerable", true)
	var guarded: float = float(stats.get("health"))
	for i in range(420):
		await physics_frame
		_player.set("is_invulnerable", true)
		if float(stats.get("health")) < guarded:
			break
	_check(
		is_equal_approx(float(stats.get("health")), guarded),
		"a dodged note does nothing"
	)
	_player.set("is_invulnerable", false)

	cantor.queue_free()
	for projectile in get_nodes_in_group("enemy_projectiles"):
		projectile.queue_free()
	await physics_frame


func _first_projectile() -> Node:
	var found: Array[Node] = get_nodes_in_group("enemy_projectiles")
	return found[0] if not found.is_empty() else null


## Notes shaken loose by a kill.
##
## These exist because of how the fight actually goes wrong: one enemy is no
## trouble, four at once is, and the only answers were to run or to die. Lowering
## enemy damage would fix that by removing the threat. A drop rewards the opposite
## response — killing something buys the means to keep killing — so a swarm
## becomes survivable by fighting through it.
##
## The parts that can fail quietly are the ones checked: that anything drops at
## all, that walking over it actually pays, and that a drop at full health is not
## simply thrown away.
func _test_quaver_drops() -> void:
	# Loaded by path, not by class name. Naming QuaverDrops here would force it to
	# compile alongside this script — which happens before autoloads register — and
	# its EventBus references would fail to resolve, leaving a script that cannot
	# be instantiated at all.
	var drops: Node = (load("res://scripts/world/QuaverDrops.gd") as GDScript).new()
	drops.set("quaver_scene", load("res://scenes/world/Quaver.tscn"))
	_root.add_child(drops)
	await physics_frame

	var stats: Node = _player.get_node_or_null("PlayerStats")
	if not _check(stats != null, "player stats available for the drop check"):
		return

	# Killed well away from the player, so nothing is collected before it is counted.
	var enemy := (load("res://scenes/enemies/ToneDeaf.tscn") as PackedScene).instantiate() as Node3D
	_root.add_child(enemy)
	enemy.global_position = _player.global_position + Vector3(40.0, 1.0, 0.0)
	for i in range(6):
		await physics_frame

	enemy.call("die")
	await physics_frame
	_check(_quavers().size() >= 1, "an enemy drops a note when it dies (%d)" % _quavers().size())

	# Wounded, then walked over one.
	var max_health: float = float(stats.get("max_health"))
	stats.call("set_health", max_health * 0.4)
	var before: float = float(stats.get("health"))

	var note: Node3D = _quavers()[0] as Node3D
	note.global_position = _player.global_position + Vector3(0.0, 0.7, 0.0)
	for i in range(60):
		await physics_frame
		if not is_instance_valid(note):
			break

	_check(float(stats.get("health")) > before, "walking over one restores health (+%.1f)" % (float(stats.get("health")) - before))
	_check(not is_instance_valid(note), "and the note is spent")

	# At full health the drop pays breath instead of being wasted.
	_clear_quavers()
	stats.call("set_health", max_health)
	stats.call("set_breath", 10.0)
	var breath_before: float = float(stats.get("breath"))

	var second := (load("res://scenes/enemies/ToneDeaf.tscn") as PackedScene).instantiate() as Node3D
	_root.add_child(second)
	second.global_position = _player.global_position + Vector3(40.0, 1.0, 0.0)
	for i in range(6):
		await physics_frame
	second.call("die")
	await physics_frame

	var full_note: Node3D = _quavers()[0] as Node3D if not _quavers().is_empty() else null
	if _check(full_note != null, "a note drops from the second kill"):
		full_note.global_position = _player.global_position + Vector3(0.0, 0.7, 0.0)
		for i in range(60):
			await physics_frame
			if not is_instance_valid(full_note):
				break
		_check(
			float(stats.get("breath")) > breath_before,
			"a note collected at full health pays breath instead (+%.1f)" % (float(stats.get("breath")) - breath_before)
		)
		_check(
			is_equal_approx(float(stats.get("health")), max_health),
			"and does not overheal"
		)

	# Heavier enemies are worth more. The heavies are what turn a fight dangerous,
	# so putting one down should visibly buy the player their footing back.
	_clear_quavers()
	var heavy := (load("res://scenes/enemies/BoneBellRinger.tscn") as PackedScene).instantiate() as Node3D
	_root.add_child(heavy)
	heavy.global_position = _player.global_position + Vector3(40.0, 1.0, 0.0)
	for i in range(6):
		await physics_frame
	heavy.call("die")
	await physics_frame
	_check(_quavers().size() >= 2, "a heavy is worth more than one note (%d)" % _quavers().size())

	_clear_quavers()
	drops.queue_free()
	await physics_frame


func _quavers() -> Array[Node]:
	var alive: Array[Node] = []
	for node in get_nodes_in_group("quavers"):
		if is_instance_valid(node):
			alive.append(node)
	return alive


func _clear_quavers() -> void:
	for node in get_nodes_in_group("quavers"):
		if is_instance_valid(node):
			node.queue_free()

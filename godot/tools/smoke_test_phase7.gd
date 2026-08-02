extends SceneTree
## Automated verification for Phase 7 (The Choirmaster).
##
##   godot --headless --path godot --script res://tools/smoke_test_phase7.gd
##
## The fight's whole shape is the three conducted interludes, and every part of
## that shape fails quietly if it breaks: a boss who stays vulnerable while
## conducting turns the set piece into a damage check, one who never resumes
## soft-locks the demo at its final encounter, and a wave that never clears leaves
## the player hitting an invulnerable target forever.
##
## Class names are deliberately not referenced. Naming a class forces its script
## to compile alongside this one, which happens before autoloads register, and
## every EventBus reference in it would then fail to resolve.

const BOSS: String = "res://scenes/enemies/Choirmaster.tscn"
const PLAYER: String = "res://scenes/player/Player.tscn"
const LEVEL: String = "res://scenes/levels/ChurchGraveyard.tscn"

var _failures: int = 0
var _checks: int = 0
var _bus: Node = null
var _root: Node3D = null
var _player: Node3D = null
var _boss: Node3D = null


func _initialize() -> void:
	await process_frame
	_bus = root.get_node("EventBus")
	_build_arena()
	for i in range(20):
		await physics_frame

	print("\n=== Phase 7 smoke test ===\n")

	_test_boss_built()
	await _test_interlude_structure()
	_test_level_wiring()

	print("\n=== %d/%d checks passed ===" % [_checks - _failures, _checks])
	if _failures > 0:
		print("FAILED\n")
		quit(1)
		return
	print("PASSED\n")
	quit(0)


func _build_arena() -> void:
	_root = Node3D.new()
	root.add_child(_root)
	current_scene = _root

	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(240.0, 1.0, 240.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.collision_layer = 1
	_root.add_child(floor_body)

	_player = (load(PLAYER) as PackedScene).instantiate() as Node3D
	_root.add_child(_player)
	_player.global_position = Vector3(0.0, 1.0, 0.0)

	_boss = (load(BOSS) as PackedScene).instantiate() as Node3D
	_root.add_child(_boss)
	_boss.global_position = Vector3(0.0, 1.0, -10.0)


# ── Tests ────────────────────────────────────────────────────────

func _test_boss_built() -> void:
	if not _check(_boss != null, "the Choirmaster loads"):
		return

	var visual: Node = _boss.get_node_or_null("CharacterVisual")
	if _check(visual != null, "the Choirmaster has a CharacterVisual"):
		var missing: Array = visual.call("get_missing_clips")
		_check(
			missing.is_empty(),
			"his clip names all resolve%s" % ("" if missing.is_empty() else " (missing: %s)" % str(missing))
		)
		# The conducting gesture is the fight's signature pose. Falling back to the
		# procedural squash here would make the set piece read as a bug.
		_check(
			String(visual.get("song_animation")) != "",
			"he has a conducting animation"
		)

	_check(_boss.get_node_or_null("Hurtbox") != null, "he has a hurtbox to make invulnerable")
	_check((_boss.get("low_summons") as Array).size() > 0, "he has rank and file to summon")
	_check((_boss.get("mid_summons") as Array).size() > 0, "he has heavies to summon")
	_check(_boss.get("projectile_scene") != null, "he has something to cast")

	# Bigger than Riff, deliberately.
	var boss_height: float = _height_of(_boss)
	var player_height: float = _height_of(_player)
	_check(
		boss_height > player_height * 1.3,
		"he towers over Riff (%.2fm against %.2fm)" % [boss_height, player_height]
	)


## The three interludes, walked through in order.
func _test_interlude_structure() -> void:
	var interludes: Array = _boss.get_script().get_script_constant_map()["INTERLUDES"]
	_check(interludes.size() == 3, "three interludes are declared")

	var thresholds: Array[float] = []
	for entry: Dictionary in interludes:
		thresholds.append(float(entry["at"]))
	_check(
		thresholds == [0.75, 0.5, 0.25],
		"they sit at three quarters, half and a quarter health (%s)" % str(thresholds)
	)

	# Each wave should be worse than the last, or the fight flattens out.
	var escalates: bool = true
	for index in range(1, interludes.size()):
		var previous: int = int(interludes[index - 1]["low"]) + int(interludes[index - 1]["mid"]) * 2
		var current: int = int(interludes[index]["low"]) + int(interludes[index]["mid"]) * 2
		if current <= previous:
			escalates = false
	_check(escalates, "each wave is heavier than the last")

	var started: Array[int] = []
	var finished: Array[int] = []
	var start_handler := func(number: int, _total: int) -> void: started.append(number)
	var finish_handler := func(completed: int, _total: int) -> void: finished.append(completed)
	_bus.boss_interlude_started.connect(start_handler)
	_bus.boss_interlude_finished.connect(finish_handler)

	var hurtbox: Node = _boss.get_node_or_null("Hurtbox")
	var max_health: float = float(_boss.get("max_health"))

	for index in range(interludes.size()):
		var threshold: float = float(interludes[index]["at"])
		var expected: int = int(interludes[index]["low"]) + int(interludes[index]["mid"])

		# Damaged to just under the threshold rather than set directly, so the
		# transition fires through the real damage path.
		_boss.set("current_health", max_health * threshold + 1.0)
		_damage_boss(2.0)
		await physics_frame

		if not _check(int(_boss.get("bout")) == 1, "interlude %d begins on crossing %.0f%% health" % [index + 1, threshold * 100.0]):
			break

		_check(
			hurtbox != null and bool(hurtbox.get("is_invulnerable")),
			"he cannot be hurt while conducting (interlude %d)" % (index + 1)
		)

		# The wave arrives staggered, so it is waited for. Counted as enemies that
		# have actually risen, not as get_remaining_summons — that figure includes
		# the ones still queued, so it reaches the target immediately and the wait
		# ends before anything has spawned. Clearing "the wave" at that point kills
		# nothing, and the rest rise afterwards into a fight nobody is watching.
		var raised: int = 0
		for frame in range(400):
			await physics_frame
			raised = _living_summons()
			if raised >= expected:
				break
		_check(
			raised >= expected,
			"interlude %d calls up its whole wave (%d of %d)" % [index + 1, raised, expected]
		)

		# He must not resume while the wave is alive, whatever the timer says.
		for frame in range(60):
			await physics_frame
		_check(
			int(_boss.get("bout")) == 1,
			"he keeps conducting while the wave stands (interlude %d)" % (index + 1)
		)

		var health_before: float = float(_boss.get("current_health"))
		_damage_boss(40.0)
		await physics_frame
		_check(
			is_equal_approx(float(_boss.get("current_health")), health_before),
			"hitting him during the interlude does nothing (interlude %d)" % (index + 1)
		)

		_clear_summons()
		var resumed: bool = false
		for frame in range(500):
			await physics_frame
			if int(_boss.get("bout")) == 0:
				resumed = true
				break
		if not _check(resumed, "he resumes once the wave is cleared (interlude %d)" % (index + 1)):
			break

		_check(
			hurtbox != null and not bool(hurtbox.get("is_invulnerable")),
			"and can be hurt again (interlude %d)" % (index + 1)
		)

	_check(started.size() == 3, "all three interludes ran (%d)" % started.size())
	_check(finished.size() == 3, "and all three finished (%d)" % finished.size())

	# Past the last interlude he simply fights, or the demo cannot be won.
	_boss.set("current_health", max_health * 0.1)
	_damage_boss(2.0)
	await physics_frame
	_check(int(_boss.get("bout")) == 0, "below the last threshold he just fights")

	var defeated: Array[StringName] = []
	var defeat_handler := func(id: StringName) -> void: defeated.append(id)
	_bus.boss_defeated.connect(defeat_handler)
	_boss.call("die")
	await physics_frame
	_check(defeated.size() == 1, "his defeat is announced")
	# A half-finished wave outliving him turns the end of the fight into mopping up.
	_check(int(_boss.call("get_remaining_summons")) == 0, "his summons die with him")

	_bus.boss_defeated.disconnect(defeat_handler)
	_bus.boss_interlude_started.disconnect(start_handler)
	_bus.boss_interlude_finished.disconnect(finish_handler)


## The level has to actually bring him on. The bell is the only thing that does.
func _test_level_wiring() -> void:
	var packed := load(LEVEL) as PackedScene
	var state: SceneState = packed.get_state()

	var has_boss: bool = false
	var has_altar: bool = false
	for index in range(state.get_node_property_count(0)):
		var property: String = state.get_node_property_name(0, index)
		if property == "boss_scene":
			has_boss = state.get_node_property_value(0, index) != null
		elif property == "conducting_altar":
			has_altar = String(state.get_node_property_value(0, index)) != ""

	_check(has_boss, "the level knows which boss the bell summons")
	_check(has_altar, "and what he turns to conduct toward")


# ── Helpers ──────────────────────────────────────────────────────

## Damage through the real path, so the threshold check runs where it will in play.
func _damage_boss(amount: float) -> void:
	var hurtbox: Node = _boss.get_node_or_null("Hurtbox")
	if hurtbox == null:
		return
	var event := DamageEvent.new(amount, 0.0, Vector3.FORWARD, _player, &"", 0.0, &"test", 0.0)
	# Called on the boss directly rather than through the hurtbox, so the check
	# for invulnerability is the boss's own and not the hurtbox short-circuiting.
	_boss.call("_on_damaged", event)


## Enemies on the field that are not the boss.
func _living_summons() -> int:
	var count: int = 0
	for node in get_nodes_in_group("enemies"):
		if node != _boss and not bool(node.get("is_dead")):
			count += 1
	return count


func _clear_summons() -> void:
	for node in get_nodes_in_group("enemies"):
		if node == _boss:
			continue
		if node.has_method("die"):
			node.call("die")


func _height_of(character: Node) -> float:
	var skeleton: Skeleton3D = _find(character, "Skeleton3D") as Skeleton3D
	if skeleton == null:
		return 0.0

	var lowest: float = INF
	var highest: float = -INF
	for i in range(skeleton.get_bone_count()):
		var y: float = (skeleton.global_transform * skeleton.get_bone_global_pose(i)).origin.y
		lowest = minf(lowest, y)
		highest = maxf(highest, y)
	return 0.0 if is_inf(lowest) else highest - lowest


func _find(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found: Node = _find(child, type_name)
		if found != null:
			return found
	return null


func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if condition:
		print("  ok    %s" % description)
		return true

	_failures += 1
	print("  FAIL  %s" % description)
	return false

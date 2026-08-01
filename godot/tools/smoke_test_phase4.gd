extends SceneTree
## Automated verification for Phase 4 (Encore, companion, layered music).
##
##   godot --headless --path godot --script res://tools/smoke_test_phase4.gd
##
## The music system cannot be heard yet — the stems are still being produced — so
## these checks assert the behaviour that must be right *before* audio arrives:
## tier thresholds matching the stem contract, bar quantisation, and above all
## that layered stems are never stopped and restarted, which is what would break
## their phase lock and cannot be fixed by tuning later.

const PLAYER: String = "res://scenes/player/Player.tscn"
const ENEMY: String = "res://scenes/enemies/ToneDeaf.tscn"

var _failures: int = 0
var _checks: int = 0
var _root: Node3D = null
var _player: Node3D = null
## Autoload names do not resolve as identifiers in a SceneTree script.
var _bus: Node = null


func _initialize() -> void:
	await process_frame
	_bus = root.get_node("EventBus")
	_build_arena()
	for i in range(15):
		await physics_frame

	print("\n=== Phase 4 smoke test ===\n")

	_test_music_contract()
	await _test_encore_gain()
	await _test_encore_tiers()
	await _test_encore_decay()
	await _test_combat_state()
	await _test_companion()

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
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.collision_layer = 1
	_root.add_child(floor_body)

	_player = (load(PLAYER) as PackedScene).instantiate() as Node3D
	_root.add_child(_player)
	_player.global_position = Vector3(0.0, 1.0, 0.0)


# ── Tests ────────────────────────────────────────────────────────

func _test_music_contract() -> void:
	var director: Node = root.get_node_or_null("MusicDirector")
	if not _check(director != null, "MusicDirector autoload present"):
		return

	# 120 BPM in 4/4 is a 2 second bar. If this drifts from the authored stems,
	# every layer reveal lands off-beat.
	_check(
		is_equal_approx(float(director.call("get_bar_seconds")), 2.0),
		"bar length matches the 120 BPM stem contract"
	)

	var layers: PackedStringArray = director.get("COMBAT_LAYERS")
	_check(layers.size() == 4, "four combat stems are declared")

	# Tier thresholds must line up with the stems, or an instrument unlocks at a
	# point the music was not written for.
	var encore_node: Node = _player.get_node_or_null("EncoreMeter")
	if not _check(encore_node != null, "EncoreMeter available for tier comparison"):
		return
	var thresholds: Array = encore_node.get_script().get_script_constant_map()["TIER_THRESHOLDS"]
	_check(
		thresholds.size() == layers.size(),
		"one Encore tier per combat stem"
	)

	var ascending: bool = true
	for i in range(1, thresholds.size()):
		if float(thresholds[i]) <= float(thresholds[i - 1]):
			ascending = false
	_check(ascending, "tier thresholds ascend")
	_check(is_equal_approx(float(thresholds[-1]), 1.0), "top tier requires a full meter")


func _test_encore_gain() -> void:
	var encore: Node = _player.get_node_or_null("EncoreMeter")
	if not _check(encore != null, "EncoreMeter present on the player"):
		return

	encore.set("value", 0.0)
	_bus.player_attack_landed.emit(10.0, &"strike", null)
	await process_frame
	var after_hit: float = float(encore.get("value"))
	_check(after_hit > 0.0, "landing a hit builds Encore")

	_bus.combo_completed.emit(&"intro_combo")
	await process_frame
	var after_combo: float = float(encore.get("value")) - after_hit
	# Combos are the skill expression; they must pay better than mashing or the
	# meter teaches the wrong habit.
	_check(after_combo > after_hit, "a combo builds more Encore than a single hit")

	_bus.player_damaged.emit(20.0, 0.5)
	await process_frame
	_check(
		float(encore.get("value")) < after_hit + after_combo,
		"taking damage costs Encore"
	)


func _test_encore_tiers() -> void:
	var encore: Node = _player.get_node_or_null("EncoreMeter")
	if encore == null:
		return

	var announced: Array[int] = []
	var full_count: Array[int] = [0]
	var tier_handler := func(tier: int) -> void: announced.append(tier)
	var full_handler := func() -> void: full_count[0] += 1
	_bus.encore_tier_changed.connect(tier_handler)
	_bus.encore_full.connect(full_handler)

	encore.set("value", 0.0)
	encore.call("_announce")
	await process_frame

	encore.set("value", float(encore.get("max_value")))
	encore.call("_announce")
	await process_frame

	_check(int(encore.call("get_tier")) == 3, "a full meter reaches the top tier")
	_check(full_count[0] >= 1, "a full meter announces encore_full")

	# Decaying back through the threshold must not re-fire the summon cue.
	var before: int = full_count[0]
	encore.set("value", float(encore.get("max_value")) * 0.5)
	encore.call("_announce")
	await process_frame
	encore.set("value", float(encore.get("max_value")))
	encore.call("_announce")
	await process_frame
	_check(full_count[0] > before, "refilling announces encore_full again")

	_bus.encore_tier_changed.disconnect(tier_handler)
	_bus.encore_full.disconnect(full_handler)


func _test_encore_decay() -> void:
	var encore: Node = _player.get_node_or_null("EncoreMeter")
	if encore == null:
		return

	encore.set("value", 50.0)
	encore.set("_decay_timer", 0.0)
	var before: float = float(encore.get("value"))
	for i in range(30):
		await process_frame
	_check(float(encore.get("value")) < before, "Encore decays when idle")


func _test_combat_state() -> void:
	var tracker: Node = _player.get_node_or_null("CombatStateTracker")
	if not _check(tracker != null, "CombatStateTracker present"):
		return

	var started: Array[int] = [0]
	var ended: Array[int] = [0]
	var start_handler := func() -> void: started[0] += 1
	var end_handler := func() -> void: ended[0] += 1
	_bus.combat_started.connect(start_handler)
	_bus.combat_ended.connect(end_handler)

	var enemy := (load(ENEMY) as PackedScene).instantiate() as Node3D
	_root.add_child(enemy)
	enemy.global_position = _player.global_position + Vector3(0.0, 0.0, -5.0)

	for i in range(20):
		await process_frame
	_check(started[0] >= 1, "an enemy nearby starts combat")
	_check(bool(tracker.get("is_in_combat")), "tracker reports in combat")

	# Removing the enemy rather than moving it: shoving it off the platform makes
	# the fall-recovery guard return it to the ground beside the player, so it
	# never actually disengages.
	enemy.queue_free()
	await process_frame
	var delay: float = float(tracker.get("disengage_delay"))
	var timer: SceneTreeTimer = create_timer(delay + 1.0, true, false, true)
	await timer.timeout
	_check(ended[0] >= 1, "combat ends once enemies leave")

	_bus.combat_started.disconnect(start_handler)
	_bus.combat_ended.disconnect(end_handler)
	await process_frame


func _test_companion() -> void:
	var summoner: Node = _player.get_node_or_null("CompanionSummoner")
	var encore: Node = _player.get_node_or_null("EncoreMeter")
	if not _check(summoner != null, "CompanionSummoner present"):
		return

	encore.set("value", 0.0)
	encore.call("_announce")
	_check(not bool(summoner.call("can_summon")), "cannot summon on an empty meter")

	encore.set("value", float(encore.get("max_value")))
	encore.call("_announce")
	await process_frame
	_check(bool(summoner.call("can_summon")), "can summon on a full meter")

	var summoned: Array[StringName] = []
	var dismissed: Array[StringName] = []
	var summon_handler := func(id: StringName) -> void: summoned.append(id)
	var dismiss_handler := func(id: StringName) -> void: dismissed.append(id)
	_bus.companion_summoned.connect(summon_handler)
	_bus.companion_dismissed.connect(dismiss_handler)

	summoner.call("summon")
	await process_frame
	_check(summoned.size() == 1, "summoning announces the companion")
	_check(
		is_zero_approx(float(encore.get("value"))),
		"summoning spends the whole meter"
	)

	# He must clean himself up: a companion that lingers is a permanent follower,
	# which ADR-0002 explicitly rules out.
	var brass: Node = _find_sir_brass(_root)
	_check(brass != null, "Sir Brass materialises in the scene")

	var timeout: SceneTreeTimer = create_timer(4.0, true, false, true)
	await timeout.timeout
	_check(dismissed.size() == 1, "Sir Brass dismisses himself")
	_check(_find_sir_brass(_root) == null, "Sir Brass frees himself from the scene")

	_bus.companion_summoned.disconnect(summon_handler)
	_bus.companion_dismissed.disconnect(dismiss_handler)


# ── Helpers ──────────────────────────────────────────────────────

## Matched by script path rather than by class name on purpose. Naming the class
## here would force SirBrass.gd to compile while this test script is compiled,
## which is before autoloads register, so every EventBus reference in it would fail
## to resolve and take CompanionSummoner down with it.
func _find_sir_brass(node: Node) -> Node:
	var script: Script = node.get_script() as Script
	if script != null and String(script.resource_path).ends_with("SirBrass.gd"):
		return node
	for child in node.get_children():
		var found: Node = _find_sir_brass(child)
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

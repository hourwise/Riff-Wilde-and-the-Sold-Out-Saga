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
	await _test_delivered_music()
	await _test_encore_gain()
	await _test_encore_tiers()
	await _test_encore_decay()
	await _test_combat_state()
	await _test_companion()
	await _test_restorative_song()

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

	# Polled rather than slept on. The tracker counts in game frames while a timer
	# counts wall clock, so on a heavy frame the polls fall behind the clock and a
	# fixed wait reports a failure that is really just a slow machine.
	var delay: float = float(tracker.get("disengage_delay"))
	var deadline: SceneTreeTimer = create_timer(delay * 3.0 + 3.0, true, false, true)
	var expired: Array[bool] = [false]
	deadline.timeout.connect(func() -> void: expired[0] = true)
	while ended[0] < 1 and not expired[0]:
		await process_frame

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


## Riff's restorative song: the only way to regain health that costs anything.
##
## Checked for the things that make it a decision rather than a free button — it
## must refuse while enemies are engaged, must actually spend breath and
## resonance, must reach past the passive regeneration ceiling, and must break
## when the player is hit. Any one of those quietly failing turns it into a heal
## button with extra steps.
func _test_restorative_song() -> void:
	var song: Node = _player.get_node_or_null("RestorativeSong")
	if not _check(song != null, "RestorativeSong present on the player"):
		return

	var stats: Node = _player.get_node_or_null("PlayerStats")
	var tracker: Node = _player.get_node_or_null("CombatStateTracker")
	if not _check(stats != null and tracker != null, "stats and combat tracker available"):
		return

	var max_health: float = float(stats.get("max_health"))
	var duration: float = float(song.get("channel_seconds"))

	# Wounded, rested, and out of combat: the situation it exists for.
	stats.call("set_health", max_health * 0.4)
	stats.call("set_breath", float(stats.get("max_breath")))
	stats.call("set_resonance", float(stats.get("max_resonance")))
	tracker.set("is_in_combat", false)
	await process_frame

	_check(bool(song.call("can_sing")), "the song is available in a lull")

	# The song's animation never played. `visual` is an @onready on the controller
	# and a child's _ready runs before its parent's, so reading it when the song
	# was built always gave null — silently, since the call was guarded.
	_check(song.call("_resolve_visual") != null, "the song can reach the character visual")

	# A refusal has to say which of four gates closed. "Nothing happened" on an
	# ability gated this many ways reads as a broken button.
	stats.call("set_breath", 0.0)
	await process_frame
	var reason: String = String(song.call("get_block_reason"))
	_check(reason.contains("breath"), "a refusal names the resource that is short (%s)" % reason)
	stats.call("set_breath", float(stats.get("max_breath")))
	await process_frame

	# Dead men do not sing. get_block_reason returned "no reason" for a dead
	# player, which reads as "yes, go ahead".
	_player.set("is_dead", true)
	await process_frame
	_check(not bool(song.call("can_sing")), "a dead player cannot sing")
	_player.set("is_dead", false)
	await process_frame

	# Refused mid-fight. Healing to full while three skeletons watch is exactly
	# what this must not allow.
	tracker.set("is_in_combat", true)
	await process_frame
	_check(not bool(song.call("can_sing")), "the song is refused while in combat")
	_check(
		String(song.call("get_block_reason")) != "",
		"and says why (%s)" % String(song.call("get_block_reason"))
	)

	tracker.set("is_in_combat", false)
	await process_frame

	var breath_before: float = float(stats.get("breath"))
	var resonance_before: float = float(stats.get("resonance"))
	var health_before: float = float(stats.get("health"))

	var completed: Array[float] = []
	var handler := func(healed: float) -> void: completed.append(healed)
	_bus.restorative_song_completed.connect(handler)

	_check(bool(song.call("try_perform")), "singing starts")
	_check(bool(song.get("is_singing")), "and holds while it is sung")
	_check(float(stats.get("breath")) < breath_before, "it spends breath")
	_check(float(stats.get("resonance")) < resonance_before, "it spends resonance")
	# Not instant: healing has to be committed to, or it is a panic button.
	_check(is_equal_approx(float(stats.get("health")), health_before), "no health arrives before the song ends")

	var deadline: SceneTreeTimer = create_timer(duration * 2.0 + 2.0, true, false, true)
	var expired: Array[bool] = [false]
	deadline.timeout.connect(func() -> void: expired[0] = true)
	while completed.is_empty() and not expired[0]:
		await process_frame

	_check(completed.size() == 1, "the song completes and announces what it healed")
	_check(float(stats.get("health")) > health_before, "health is restored (+%.0f)" % (float(stats.get("health")) - health_before))

	# Past the passive ceiling, which is the point of paying for it.
	var regen: Node = _player.get_node_or_null("HealthRegen")
	if regen != null:
		var ceiling: float = float(regen.get("regen_ceiling_ratio")) * max_health
		stats.call("set_health", ceiling)
		await process_frame
		_check(bool(song.call("can_sing")), "it can still be sung at the regeneration ceiling")

	_bus.restorative_song_completed.disconnect(handler)

	# Interrupted by damage, with part of the cost handed back.
	stats.call("set_health", max_health * 0.4)
	stats.call("set_breath", float(stats.get("max_breath")))
	stats.call("set_resonance", float(stats.get("max_resonance")))
	await process_frame

	song.call("try_perform")
	await process_frame
	var breath_spent: float = float(stats.get("breath"))
	var interrupted: Array[int] = [0]
	var interrupt_handler := func() -> void: interrupted[0] += 1
	_bus.restorative_song_interrupted.connect(interrupt_handler)

	var wounded: float = float(stats.get("health"))
	_bus.player_damaged.emit(10.0, 0.4)
	await process_frame

	_check(interrupted[0] == 1, "taking a hit breaks the song")
	_check(not bool(song.get("is_singing")), "and it stops being sung")
	_check(float(stats.get("breath")) > breath_spent, "part of the breath is handed back")

	for i in range(int(duration * 70.0)):
		await process_frame
	_check(
		is_equal_approx(float(stats.get("health")), wounded),
		"an interrupted song heals nothing"
	)

	_bus.restorative_song_interrupted.disconnect(interrupt_handler)


## The music that actually exists, as opposed to the contract it was specced to.
##
## The delivered tracks are finished arrangements, not the four tempo-locked stems
## the director was built around, so it runs them in single-track mode and
## expresses the Encore as intensity instead. That mode has its own ways to fail
## silently: a track that does not load leaves the level mute, and an Encore that
## changes nothing makes the meter cosmetic.
func _test_delivered_music() -> void:
	var director: Node = root.get_node_or_null("MusicDirector")
	if director == null:
		return

	for track: String in ["explore_graveyard_ambient", "combat_full", "boss_choirmaster_full"]:
		_check(
			String(director.call("_find_stem_path", track)) != "",
			"%s is present" % track
		)

	# Whatever the format, it has to loop. A twelve-minute level backed by an
	# eighty-four second track that plays once is silent for most of the run.
	for track: String in ["explore_graveyard_ambient", "combat_full", "boss_choirmaster_full"]:
		var stream: AudioStream = director.call("_load_stem", track)
		if not _check(stream != null, "%s loads as a stream" % track):
			continue
		var loops: bool = false
		if stream is AudioStreamWAV:
			loops = (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
		elif stream is AudioStreamOggVorbis:
			loops = (stream as AudioStreamOggVorbis).loop
		_check(loops, "%s is set to loop" % track)

	_check(bool(director.get("_combat_is_single")), "combat runs as one arrangement")

	# That a stream loads says nothing about whether anything is audible. The
	# exploration bed was faded up on a player that had never been started —
	# no error, no warning, and the level was silent while every check here passed.
	director.call("play_exploration")
	await process_frame
	var ambient: AudioStreamPlayer = director.get("_ambient_player")
	_check(ambient != null and ambient.playing, "play_exploration actually starts the music")

	# Started is not the same as playing, and this is the check that was missing.
	# A looping AudioStreamWAV whose loop_end is left at zero loops over a
	# zero-length region: it reports itself playing for one frame, advances not one
	# sample, and stops. Stream valid, bus unmuted, volume fading up on schedule,
	# and the level completely silent. Asserted as forward progress through the
	# stream, which is the only thing that means audible.
	var furthest: float = 0.0
	for i in range(30):
		await process_frame
		furthest = maxf(furthest, ambient.get_playback_position())
	_check(
		furthest > 0.02,
		"and the music actually advances through the stream (%.3fs)" % furthest
	)
	_check(ambient.playing, "and is still playing half a second later")

	# Every music stream, not only the one exploration happens to use.
	var stalled: Array[String] = []
	for track: String in ["explore_graveyard_ambient", "combat_full", "boss_choirmaster_full"]:
		var stream: AudioStream = director.call("_load_stem", track)
		var sample := stream as AudioStreamWAV
		if sample == null:
			continue
		if sample.loop_mode != AudioStreamWAV.LOOP_DISABLED and sample.loop_end <= 0:
			stalled.append(track)
	_check(
		stalled.is_empty(),
		"no track loops over a zero-length region%s" % ("" if stalled.is_empty() else " (%s)" % ", ".join(stalled))
	)

	director.call("_on_combat_started")
	await process_frame
	var combat: AudioStreamPlayer = (director.get("_combat_players") as Array)[0]
	_check(combat != null and combat.playing, "entering combat actually starts the combat track")

	director.call("play_boss", 0)
	await process_frame
	var boss: AudioStreamPlayer = (director.get("_boss_players") as Array)[0]
	_check(boss != null and boss.playing, "the boss arrangement actually starts")

	# Leaving a level with enemies still alive.
	#
	# Enemies destroyed with their scene never announce a death, so the global
	# live count kept them forever — and combat music only returns to exploration
	# once that count reaches zero. Five survivors left behind meant the music
	# could never come back down, for the rest of the session, accumulating across
	# every retry.
	director.call("_on_combat_started")
	var standins: Array[Node3D] = []
	for i in range(5):
		var standin := Node3D.new()
		_root.add_child(standin)
		standins.append(standin)
		_bus.enemy_spawned.emit(standin)
	await process_frame
	_check(int(director.call("get_live_enemy_count")) == 5, "live enemies are counted")

	# An enemy that leaves without dying. A patrol despawning when the player walks
	# away does exactly this, and a plain counter never saw it — so the count stayed
	# permanently high and combat music, which only returns to exploration at zero,
	# never stopped again for the rest of the session.
	standins[0].queue_free()
	await process_frame
	_check(
		int(director.call("get_live_enemy_count")) == 4,
		"an enemy that despawns without dying stops being counted (%d left)" % int(director.call("get_live_enemy_count"))
	)

	# The whole point: with everything gone, combat must actually end.
	for index in range(1, standins.size()):
		standins[index].queue_free()
	await process_frame
	_check(int(director.call("get_live_enemy_count")) == 0, "and the count reaches zero")

	var hold: float = float(director.get_script().get_script_constant_map()["COMBAT_HOLD_SECONDS"])
	var waited: SceneTreeTimer = create_timer(hold + 1.5, true, false, true)
	var expired: Array[bool] = [false]
	waited.timeout.connect(func() -> void: expired[0] = true)
	while bool(director.get("_in_combat")) and not expired[0]:
		await process_frame
	_check(
		not bool(director.get("_in_combat")),
		"combat music gives way to exploration once nothing is left alive"
	)

	director.call("_on_combat_started")
	for standin in standins:
		if is_instance_valid(standin):
			_bus.enemy_spawned.emit(standin)
	await process_frame

	director.call("_on_scene_transition", "res://scenes/levels/TavernHub.tscn")
	await process_frame
	_check(int(director.call("get_live_enemy_count")) == 0, "leaving a level forgets the enemies left alive in it")
	_check(not bool(director.get("_in_combat")), "and drops out of combat")
	_check(not bool(director.get("_boss_active")), "and out of the boss fight")

	# The proof that it matters: exploration must be reachable again afterwards.
	director.call("play_exploration")
	await process_frame
	_check(
		(director.get("_ambient_player") as AudioStreamPlayer).playing,
		"exploration music returns after leaving a level mid-fight"
	)

	director.call("stop_all", 0.05)
	await process_frame

	# The Encore has to change how it sounds, or the meter is decoration.
	var bus: int = AudioServer.get_bus_index("MusicCombat")
	if not _check(bus >= 0, "the combat music bus exists"):
		return

	director.call("_apply_intensity", &"MusicCombat", 0)
	await process_frame
	var filter: AudioEffectLowPassFilter = director.call("_intensity_filter", &"MusicCombat")
	if not _check(filter != null, "an intensity filter is installed on it"):
		return

	# Waited out rather than sampled immediately: the change is eased over a
	# crossfade so it swells instead of clicking.
	var settle: SceneTreeTimer = create_timer(2.0, true, false, true)
	await settle.timeout
	var closed: float = filter.cutoff_hz
	var quiet: float = AudioServer.get_bus_volume_db(bus)

	director.call("_apply_intensity", &"MusicCombat", 3)
	var opening: SceneTreeTimer = create_timer(2.0, true, false, true)
	await opening.timeout

	_check(
		filter.cutoff_hz > closed * 2.0,
		"a full Encore opens the arrangement up (%.0f Hz to %.0f Hz)" % [closed, filter.cutoff_hz]
	)
	_check(
		AudioServer.get_bus_volume_db(bus) > quiet,
		"and lifts it (%.1f dB to %.1f dB)" % [quiet, AudioServer.get_bus_volume_db(bus)]
	)

	# The bottom of the range is where every fight starts. It was -7 dB behind a
	# 900 Hz low-pass, so walking into combat made the music quieter and duller
	# than the exploration bed it replaced.
	var floor_db: float = float(director.get_script().get_script_constant_map()["INTENSITY_DB"][0])
	var floor_hz: float = float(director.get_script().get_script_constant_map()["INTENSITY_CUTOFF_HZ"][0])
	_check(floor_db > -4.0, "combat starts at a believable level (%.1f dB)" % floor_db)
	_check(floor_hz > 2000.0, "and is not muffled when it arrives (%.0f Hz)" % floor_hz)

	# Only one filter, however many times intensity is applied. Stacking a new
	# low-pass on every tier change would muffle the music a little more each time
	# until it disappeared.
	var effects: int = AudioServer.get_bus_effect_count(bus)
	director.call("_apply_intensity", &"MusicCombat", 1)
	director.call("_apply_intensity", &"MusicCombat", 2)
	await process_frame
	_check(
		AudioServer.get_bus_effect_count(bus) == effects,
		"repeated tier changes do not stack filters (%d effects)" % AudioServer.get_bus_effect_count(bus)
	)


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

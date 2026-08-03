extends Node
## Global gameplay signal hub. The one place systems are allowed to talk across
## domain boundaries.
##
## Rules:
##   - Producers (combat, player, enemies, world) emit. They never listen for their
##     own domain's events and never look up a consumer.
##   - Consumers (music, quests, HUD, minimap, save) listen. They never reach back
##     into the producer.
##   - This script holds NO state and NO logic. If you are tempted to add a variable
##     here, it belongs in a director instead.
##
## Anything that is a direct service call — "play this sound", "load this scene" —
## does not belong here. Call AudioManager or SceneLoader directly.

# ── Game flow ────────────────────────────────────────────────────
## Values are GameManager.GameState members, typed as int because signal parameter
## annotations cannot reference an autoload's enum at parse time.
signal game_state_changed(previous: int, current: int)
signal game_suspended_changed(is_suspended: bool)
signal scene_transition_started(target_path: String)
signal scene_transition_finished(target_path: String)

# ── Player ───────────────────────────────────────────────────────
signal player_spawned(player: Node3D)
signal player_damaged(amount: float, health_ratio: float)
signal player_healed(amount: float, health_ratio: float)
signal player_died()
signal player_dodged()

# ── Combat ───────────────────────────────────────────────────────
signal player_attack_landed(damage: float, damage_type: StringName, target: Node3D)
signal combo_completed(combo_id: StringName)
signal combo_dropped()
signal lock_on_changed(target: Node3D)

# ── Enemies ──────────────────────────────────────────────────────
signal enemy_spawned(enemy: Node3D)
signal enemy_died(enemy: Node3D)
signal enemy_staggered(enemy: Node3D)
signal enemy_channel_interrupted(enemy: Node3D)

## Emitted when the player enters or leaves active combat. Drives the music
## crossfade, so it is deliberately hysteretic — combat does not "end" the instant
## the last enemy dies.
signal combat_started()
signal combat_ended()

# ── Encore & companion ───────────────────────────────────────────
signal encore_changed(value: float, max_value: float)
signal encore_tier_changed(tier: int)
signal encore_full()

## Riff's restorative song: the third way to regain health, and the only one that
## costs anything. Announced so the HUD, the music and the audio can respond
## without any of them knowing where the song lives.
## The Choirmaster's fight, announced in beats rather than as a health number, so
## the HUD, the music and the camera can all respond to the same structure.
signal boss_interlude_started(number: int, total: int)
signal boss_interlude_finished(completed: int, total: int)
signal boss_summon_raised(interlude: int)
signal boss_defeated(boss_id: StringName)

## A note shaken loose by a kill and walked over. Announced so the HUD can show
## what it paid without the pickup knowing the HUD exists.
signal quaver_collected(healed: float, breath: float)

signal restorative_song_started(duration: float)
signal restorative_song_completed(healed: float)
signal restorative_song_interrupted()
signal companion_summoned(companion_id: StringName)
signal companion_attack_landed(companion_id: StringName)
signal companion_dismissed(companion_id: StringName)

# ── Quests & world ───────────────────────────────────────────────
signal objective_added(objective_id: StringName, text: String)
signal objective_completed(objective_id: StringName)
signal quest_completed(quest_id: StringName)
signal altar_cleansed(altar_id: StringName, cleansed_count: int, total_count: int)
signal all_altars_cleansed()
signal church_bell_rang()
signal region_discovered(region_id: StringName, display_name: String)
signal lore_collected(lore_id: StringName)

# ── Cinematics & dialogue ────────────────────────────────────────
signal cinematic_started(cinematic_id: StringName)
signal cinematic_finished(cinematic_id: StringName)
signal dialogue_started(speaker_id: StringName)
signal dialogue_finished(speaker_id: StringName)


func _ready() -> void:
	# Must keep delivering signals while the tree is paused so cinematics, dialogue
	# and the pause menu can still communicate.
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("[EventBus] Ready.")

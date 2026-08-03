class_name RestorativeSong
extends Node
## Riff sings himself back together between fights.
##
## The other two ways to regain health are both passive: HealthRegen ticks back up
## out of combat, and cleansing an altar returns a lump. Neither is a decision.
## This one is — it spends the same breath and resonance that the Sing blast wants,
## so healing costs you the attack you were saving, and it can only be done when
## nothing is hunting you.
##
## It deliberately reaches past HealthRegen's ceiling. Regen alone stops at
## three-quarters health, so the last quarter is only ever bought with resources,
## and arriving at a boss topped up means having spent something to get there.
##
## Channelled rather than instant, and interrupted by damage or by a fight
## starting, so it cannot be used as a panic button the moment a straggler wanders
## off. Standing still and singing while a patrol closes is the player's mistake to
## make.

## Fraction of maximum health restored by a complete song.
@export_range(0.05, 1.0, 0.05) var heal_ratio: float = 0.3

@export var breath_cost: float = 45.0
@export var resonance_cost: float = 30.0

## How long Riff must stand and sing. Long enough to be a commitment, short enough
## that a lull between encounters is time to use it.
@export var channel_seconds: float = 1.8

## Refunded share of the costs when the song is cut short, so being jumped
## mid-verse is a setback rather than a punishment.
@export_range(0.0, 1.0, 0.05) var interrupt_refund: float = 0.5

var is_singing: bool = false

var _player: Node = null
var _stats: PlayerStats = null
var _tracker: Node = null
var _visual: Node = null
var _elapsed: float = 0.0


func _ready() -> void:
	_player = get_parent()
	_stats = _player.get_node_or_null("PlayerStats") as PlayerStats
	_tracker = _player.get_node_or_null("CombatStateTracker")
	# Resolved lazily, not here. `visual` is an @onready on PlayerController, and a
	# child's _ready runs before its parent's — so read now it is always null, and
	# the song played no animation at all.
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.combat_started.connect(_on_combat_started)
	set_process(false)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= channel_seconds:
		_finish()


## Why the song cannot be sung right now, or an empty string if it can.
##
## Returned as a reason rather than a bool so the HUD can say which of the four
## things is missing. "Nothing happened" is the worst possible feedback for an
## ability with this many preconditions.
func get_block_reason() -> String:
	if _stats == null:
		return "no stats"
	if is_singing:
		return "already singing"
	if bool(_player.get("is_dead")):
		return "dead"
	if _tracker != null and bool(_tracker.get("is_in_combat")):
		return "Not while they can hear you"
	if _stats.health >= _stats.max_health:
		return "Already whole"
	# Stated with the numbers. This ability is gated four ways, and a refusal that
	# only says "not enough" leaves the player guessing which of four things to go
	# and do — or, worse, concluding the button is broken.
	if _stats.breath < breath_cost:
		return "Not enough breath  %d / %d" % [int(_stats.breath), int(breath_cost)]
	if _stats.resonance < resonance_cost:
		return "Not enough resonance  %d / %d" % [int(_stats.resonance), int(resonance_cost)]
	return ""


func can_sing() -> bool:
	return get_block_reason() == "" and not is_singing and not bool(_player.get("is_dead"))


## Starts the song if it can be started. Returns whether it took the input, so the
## caller knows not to fire the Sing blast as well.
func try_perform() -> bool:
	if is_singing or _stats == null or bool(_player.get("is_dead")):
		return false

	# Out of combat, the blast has nothing to hit. Taking the input here even when
	# the song cannot be afforded is what makes the refusal legible — otherwise the
	# player spends their breath on a blast aimed at nobody and wonders why they
	# did not heal.
	if _tracker != null and bool(_tracker.get("is_in_combat")):
		return false

	var reason: String = get_block_reason()
	if reason != "":
		_announce(reason)
		AudioManager.play_ui(&"ui_back")
		return true

	_stats.use_breath(breath_cost)
	_stats.set_resonance(_stats.resonance - resonance_cost)

	is_singing = true
	_elapsed = 0.0
	set_process(true)

	var visual: Node = _resolve_visual()
	if visual != null and visual.has_method("play_song"):
		visual.call("play_song")
	AudioManager.play_sfx(&"riff_song_restore")
	EventBus.restorative_song_started.emit(channel_seconds)
	return true


## Cuts the song short and hands back part of what it cost.
func interrupt() -> void:
	if not is_singing:
		return

	is_singing = false
	set_process(false)

	if _stats != null and interrupt_refund > 0.0:
		_stats.set_breath(_stats.breath + breath_cost * interrupt_refund)
		_stats.set_resonance(_stats.resonance + resonance_cost * interrupt_refund)

	AudioManager.play_ui(&"ui_back")
	EventBus.restorative_song_interrupted.emit()
	_announce("The song breaks")


func _finish() -> void:
	is_singing = false
	set_process(false)

	var healed: float = 0.0
	if _stats != null:
		healed = _stats.heal(_stats.max_health * heal_ratio)

	EventBus.restorative_song_completed.emit(healed)
	_announce("Restored  +%d" % int(round(healed)))


func _on_player_damaged(_amount: float, _health_ratio: float) -> void:
	interrupt()


func _on_combat_started() -> void:
	interrupt()


func _resolve_visual() -> Node:
	if _visual == null or not is_instance_valid(_visual):
		_visual = _player.get("visual")
	return _visual


func _announce(message: String) -> void:
	if message == "":
		return
	var hud: Node = _player.get("hud_controller")
	if hud != null and hud.has_method("show_temporary_center_message"):
		hud.call("show_temporary_center_message", message, 2.4)

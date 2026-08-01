class_name HealthRegen
extends Node
## Riff's recovery. Two sources, deliberately different in character.
##
## The demo is a single unbroken run with no shops and no potions, so without
## recovery a bad first encounter poisons the remaining ten minutes. But healing
## that is too available removes all weight from taking a hit.
##
## So:
##   1. A slow out-of-combat trickle, capped below full. It undoes the cost of
##      exploring badly, never the cost of fighting badly.
##   2. A large burst for cleansing a Funeral Altar. Restoring the graveyard
##      restores Riff — it ties recovery to the objective rather than to waiting,
##      and turns each altar into a natural checkpoint.
##
## A pure EventBus consumer: it never asks the world whether combat is happening.

@export_group("Out of combat")
@export var regen_per_second: float = 3.5
## Seconds after leaving combat, or after being hit, before the trickle starts.
@export var regen_delay: float = 4.0
## Ceiling for passive regeneration, as a fraction of max health. Below 1.0 on
## purpose: waiting should never fully undo a mauling.
@export_range(0.0, 1.0, 0.05) var regen_ceiling_ratio: float = 0.75

@export_group("Altar restoration")
## Health restored per altar cleansed, as a fraction of max.
@export_range(0.0, 1.0, 0.05) var altar_heal_ratio: float = 0.5

var _stats: PlayerStats = null
var _player: Node3D = null
var _in_combat: bool = false
var _delay_timer: float = 0.0


func _ready() -> void:
	_player = get_parent() as Node3D
	_stats = get_parent().get_node_or_null("PlayerStats") as PlayerStats

	EventBus.combat_started.connect(_on_combat_started)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.altar_cleansed.connect(_on_altar_cleansed)


func _process(delta: float) -> void:
	if _stats == null or _stats.is_depleted:
		return

	if _delay_timer > 0.0:
		_delay_timer -= delta
		return

	if _in_combat:
		return

	var ceiling: float = _stats.max_health * regen_ceiling_ratio
	if _stats.health >= ceiling:
		return

	# Clamped to the ceiling so the trickle cannot overshoot it in a single frame.
	var restored: float = minf(regen_per_second * delta, ceiling - _stats.health)
	_stats.heal(restored)


func _on_combat_started() -> void:
	_in_combat = true


func _on_combat_ended() -> void:
	_in_combat = false
	_delay_timer = regen_delay


## Being hit restarts the wait, so standing in a fight does not tick health back.
func _on_player_damaged(_amount: float, _health_ratio: float) -> void:
	_delay_timer = regen_delay


func _on_altar_cleansed(_altar_id: StringName, _cleansed: int, _total: int) -> void:
	if _stats == null:
		return

	var restored: float = _stats.heal(_stats.max_health * altar_heal_ratio)
	if restored <= 0.0:
		return

	AudioManager.play_sfx(&"altar_cleanse")
	_announce("Restored  +%d health" % int(round(restored)))


func _announce(message: String) -> void:
	if _player == null:
		return

	var hud: Node = _player.get("hud_controller")
	if hud != null and hud.has_method("show_temporary_center_message"):
		hud.call("show_temporary_center_message", message, 2.2)

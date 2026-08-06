class_name CombatStateTracker
extends Node
## Decides when the player is "in combat" and announces it on EventBus.
##
## Music, and later the quest tracker, key off this. It lives on the player rather
## than in a director because it is a gameplay observation, and it is deliberately
## hysteretic: combat starts readily and ends reluctantly, so the soundtrack does
## not flap every time an enemy steps behind a crypt.

## An enemy this close and alive counts as engaged.
@export var engage_radius: float = 16.0
## Combat only ends once everything is beyond this. Wider than engage_radius so a
## fight does not end and restart while circling one enemy.
@export var disengage_radius: float = 24.0
## Seconds with nothing engaged before combat is declared over.
@export var disengage_delay: float = 3.0
## How often the check runs. Every frame is wasteful for something this coarse.
@export var poll_interval: float = 0.25

var is_in_combat: bool = false

var _player: Node3D = null
var _poll_timer: float = 0.0
var _clear_timer: float = 0.0


func _ready() -> void:
	_player = get_parent() as Node3D
	EventBus.player_died.connect(_on_player_died)


func _process(delta: float) -> void:
	_poll_timer -= delta
	if _poll_timer > 0.0:
		return
	_poll_timer = poll_interval

	var engaged: bool = _has_engaged_enemy()

	if engaged:
		_clear_timer = 0.0
		if not is_in_combat:
			is_in_combat = true
			EventBus.combat_started.emit()
		return

	if not is_in_combat:
		return

	_clear_timer += poll_interval
	if _clear_timer >= disengage_delay:
		is_in_combat = false
		_clear_timer = 0.0
		EventBus.combat_ended.emit()


func _has_engaged_enemy() -> bool:
	if _player == null:
		return false

	# Uses the wider radius once already fighting, which is what stops the state
	# oscillating at the boundary.
	var radius: float = disengage_radius if is_in_combat else engage_radius
	var radius_squared: float = radius * radius

	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or bool(enemy.get("is_dead")):
			continue
		if _player.global_position.distance_squared_to(enemy.global_position) > radius_squared:
			continue

		# Near is not the same as fighting. Encounters spawn when the player comes
		# within about twenty-five metres and then wait to be fought, so in a level
		# this dense there is nearly always something standing inside the radius —
		# and combat never ended. Kill the two that pulled you, stand still for a
		# minute, and the fight music plays on because a group you have not met yet
		# is idling twenty metres away.
		if enemy.has_method("is_engaged"):
			if bool(enemy.call("is_engaged")):
				return true
			continue

		# Anything without an opinion is assumed to be fighting, so a future enemy
		# type cannot silently end combat by not answering.
		return true

	return false


func _on_player_died() -> void:
	if not is_in_combat:
		return
	is_in_combat = false
	_clear_timer = 0.0
	EventBus.combat_ended.emit()

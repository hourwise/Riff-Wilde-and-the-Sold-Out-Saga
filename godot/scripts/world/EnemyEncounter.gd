class_name EnemyEncounter
extends Node3D
## A group of enemies guarding something, spawned when the player gets close and
## reported as cleared when they are all dead.
##
## Enemies are spawned rather than left sitting in the level so the cemetery does
## not run several dozen AI agents from the moment it loads, and so a group is
## fresh if the player leaves and returns without clearing it.

signal cleared

## Which enemy, and how many. Order is preserved, so a group reads as authored:
## put the heavy first and it stands at the back.
@export var spawns: Array[PackedScene] = []
## Spawn points. If fewer than spawns, positions are reused with an offset.
@export var spawn_points: Array[NodePath] = []
## Distance at which the group wakes. Wide enough that the fight is visible
## before it starts, so the player is never ambushed by something off screen.
@export var activation_radius: float = 26.0
## Seconds between each enemy appearing, so a group arrives rather than blinks in.
@export var spawn_stagger: float = 0.18

var is_active: bool = false
var is_cleared: bool = false

var _remaining: int = 0
var _player: Node3D = null


func _ready() -> void:
	add_to_group("encounters")
	EventBus.player_spawned.connect(_on_player_spawned)
	_find_player()

	# Nothing to guard: report cleared immediately so a level author can leave an
	# encounter empty without deadlocking whatever is waiting on it.
	if spawns.is_empty():
		is_cleared = true
		call_deferred("_announce_cleared")


func _process(_delta: float) -> void:
	if is_active or is_cleared or _player == null:
		return
	if global_position.distance_to(_player.global_position) <= activation_radius:
		activate()


func activate() -> void:
	if is_active or is_cleared:
		return

	is_active = true
	set_process(false)
	_spawn_group()


## Forces the encounter cleared without a fight. Used when restoring a save.
func mark_cleared() -> void:
	if is_cleared:
		return
	is_cleared = true
	is_active = true
	set_process(false)
	_announce_cleared()


func _spawn_group() -> void:
	for index in range(spawns.size()):
		var scene: PackedScene = spawns[index]
		if scene == null:
			continue

		var enemy := scene.instantiate() as Node3D
		if enemy == null:
			continue

		# Parented to the level rather than to the encounter: an enemy that chases
		# the player across the graveyard should not be transformed by the marker
		# it spawned from.
		var host: Node = get_parent()
		host.add_child(enemy)
		enemy.global_position = _resolve_spawn_position(index)

		_remaining += 1
		if enemy.has_signal("died"):
			enemy.died.connect(_on_enemy_died)

		if spawn_stagger > 0.0:
			await get_tree().create_timer(spawn_stagger).timeout

	# Every spawn failed to instantiate.
	if _remaining <= 0 and not is_cleared:
		is_cleared = true
		_announce_cleared()


func _resolve_spawn_position(index: int) -> Vector3:
	if spawn_points.is_empty():
		# Ring them around the marker so they do not stack.
		var angle: float = TAU * float(index) / maxf(float(spawns.size()), 1.0)
		return global_position + Vector3(cos(angle), 0.0, sin(angle)) * 2.5

	var point := get_node_or_null(spawn_points[index % spawn_points.size()]) as Node3D
	if point == null:
		return global_position

	# Reused points get nudged apart so two enemies never share a spot exactly.
	var reuse: int = index / spawn_points.size()
	if reuse == 0:
		return point.global_position

	var offset_angle: float = TAU * float(index) / maxf(float(spawns.size()), 1.0)
	return point.global_position + Vector3(cos(offset_angle), 0.0, sin(offset_angle)) * 1.8


func _on_enemy_died(_enemy: Node) -> void:
	_remaining = maxi(0, _remaining - 1)
	if _remaining > 0 or is_cleared:
		return

	is_cleared = true
	_announce_cleared()


func _announce_cleared() -> void:
	cleared.emit()


func _on_player_spawned(player: Node3D) -> void:
	_player = player


func _find_player() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0] as Node3D

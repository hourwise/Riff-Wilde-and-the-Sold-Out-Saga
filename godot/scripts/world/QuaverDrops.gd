class_name QuaverDrops
extends Node
## Shakes a note or two loose whenever something dies.
##
## A listener rather than something the enemies call. EnemyBase already announces
## its own death on the EventBus, so the roster needs to know nothing about loot,
## and a level that wants no drops simply leaves this node out.
##
## Bigger things drop more. That is not a reward curve so much as a pacing one:
## the heavies are what turn a fight from awkward into dangerous, and the moment
## one goes down should visibly buy the player their footing back.

## What falls. Left as an export so a level could drop something else entirely.
@export var quaver_scene: PackedScene = null

## Enemies with at least this much maximum health drop an extra note per step.
## Tuned against the roster: the rank and file sit well under it, the heavies and
## the Choirmaster do not.
@export var extra_drop_per_health: float = 55.0

## Nothing drops more than this, so the boss does not carpet the courtyard.
@export var maximum_drops: int = 6

## Spread of the little scatter each drop lands in.
@export var scatter_radius: float = 1.1

## Where the notes are parented. Left empty to use this node's own parent, which
## is normally the level — a drop must outlive the corpse it came from.
@export var container_path: NodePath

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	EventBus.enemy_died.connect(_on_enemy_died)

	if quaver_scene == null:
		push_warning("[QuaverDrops] No quaver scene assigned; nothing will drop.")


func _on_enemy_died(enemy: Node3D) -> void:
	if quaver_scene == null or enemy == null or not is_instance_valid(enemy):
		return

	var host: Node = get_node_or_null(container_path)
	if host == null:
		host = get_parent()
	if host == null:
		return

	# Read before the corpse is freed. An enemy queued for deletion is still valid
	# this frame, but its position is the only thing worth taking from it.
	var at: Vector3 = enemy.global_position

	for index in range(_drop_count(enemy)):
		var note := quaver_scene.instantiate() as Node3D
		if note == null:
			continue

		host.add_child(note)
		var angle: float = _rng.randf_range(0.0, TAU)
		var spread: float = 0.0 if index == 0 else _rng.randf_range(0.4, scatter_radius)
		note.global_position = at + Vector3(
			cos(angle) * spread,
			0.8,
			sin(angle) * spread
		)


func _drop_count(enemy: Node3D) -> int:
	var health: float = float(enemy.get("max_health"))
	if health <= 0.0:
		return 1
	return clampi(1 + int(health / extra_drop_per_health), 1, maximum_drops)

class_name RovingPatrol
extends Node3D
## A small group of enemies that walks a route through the cemetery until it
## notices the player.
##
## The difference between this and EnemyEncounter is who decides when the fight
## starts. An encounter is a set piece: it guards a place, wakes when the player
## arrives, and is what the altars are gated on. A patrol is weather — it crosses
## the level on its own business, and meeting one is the player's doing as much as
## the level's. Clearing one is never required, so nothing waits on it.
##
## Patrols spawn on approach for the same reason encounters do: a hundred idle AI
## agents pathing around an empty graveyard costs the same as a hundred fighting
## ones, and nobody is there to see it.

## Which enemies walk this route.
@export var spawns: Array[PackedScene] = []
## The route, as child Marker3D nodes. Walked in order and then looped, so the
## last point should sit near the first.
@export var route: Array[NodePath] = []
## Distance from the player at which the patrol spawns. Wider than an encounter's:
## a patrol should already be walking when it comes into view, not appear.
@export var activation_radius: float = 44.0
## Distance beyond which a spawned patrol is taken away again, so a level full of
## patrols does not slowly become a level full of enemies.
@export var despawn_radius: float = 90.0
## Fraction of normal move speed while patrolling.
@export var patrol_speed_ratio: float = 0.45
## Spacing between members, so a patrol walks as a file rather than a stack.
@export var spacing: float = 2.4

var is_active: bool = false

var _player: Node3D = null
var _members: Array[Node3D] = []
var _points: PackedVector3Array = PackedVector3Array()


func _ready() -> void:
	add_to_group("patrols")
	EventBus.player_spawned.connect(_on_player_spawned)
	_find_player()
	_collect_route()

	if spawns.is_empty() or _points.size() < 2:
		# A patrol with no route is a stationary group that no altar is gated on,
		# which is just a bug that is hard to see. Say so rather than standing there.
		push_warning("[RovingPatrol] %s has %d spawns and %d route points; disabled." % [
			name, spawns.size(), _points.size()
		])
		set_process(false)


func _process(_delta: float) -> void:
	if _player == null:
		return

	var distance: float = global_position.distance_to(_player.global_position)

	if not is_active:
		if distance <= activation_radius:
			_spawn()
		return

	_forget_dead_members()

	# Measured from the patrol's own marker rather than from its members: chasing
	# the player is exactly when a patrol is furthest from home, and despawning it
	# mid-fight would delete enemies the player is already swinging at.
	if _members.is_empty():
		return
	if distance > despawn_radius and _nearest_member_distance() > despawn_radius:
		_despawn()


## Where the patrol currently is, for anything that wants to draw or count it.
func get_members() -> Array[Node3D]:
	_forget_dead_members()
	return _members.duplicate()


func _collect_route() -> void:
	var points: PackedVector3Array = PackedVector3Array()
	for path: NodePath in route:
		var marker := get_node_or_null(path) as Node3D
		if marker != null:
			points.append(marker.global_position)
	_points = points


func _spawn() -> void:
	is_active = true

	var host: Node = get_parent()
	for index in range(spawns.size()):
		var scene: PackedScene = spawns[index]
		if scene == null:
			continue

		var enemy := scene.instantiate() as Node3D
		if enemy == null:
			continue

		# Parented to the level, not to this marker: an enemy that chases the
		# player across the cemetery must not be dragged around by the route it
		# started on.
		host.add_child(enemy)
		enemy.global_position = _points[0] + Vector3(
			cos(TAU * float(index) / float(spawns.size())) * spacing,
			0.5,
			sin(TAU * float(index) / float(spawns.size())) * spacing
		)

		if enemy.has_method("set"):
			enemy.set("patrol_points", _points)
			enemy.set("patrol_speed_ratio", patrol_speed_ratio)
			# Staggered start indices, so the file strings out along the route
			# instead of every member walking to the same point at once.
			enemy.set("_patrol_index", index % _points.size())

		_members.append(enemy)


func _despawn() -> void:
	for member: Node3D in _members:
		if is_instance_valid(member):
			member.queue_free()
	_members.clear()
	is_active = false


func _forget_dead_members() -> void:
	var alive: Array[Node3D] = []
	for member: Node3D in _members:
		if is_instance_valid(member):
			alive.append(member)
	_members = alive


func _nearest_member_distance() -> float:
	var nearest: float = INF
	for member: Node3D in _members:
		nearest = minf(nearest, member.global_position.distance_to(_player.global_position))
	return nearest


func _on_player_spawned(_player_node: Node) -> void:
	_find_player()


func _find_player() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	_player = players[0] as Node3D if not players.is_empty() else null

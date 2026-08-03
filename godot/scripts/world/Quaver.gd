class_name Quaver
extends Area3D
## A note shaken loose when something dies. Walk over it and it tops Riff up.
##
## This exists because of how the fight actually goes wrong. One enemy at a time
## is no trouble; four at once is, and the only answers available were to run away
## or to die. Lowering enemy damage would fix the symptom by removing the threat,
## which throws away the thing that makes a group frightening in the first place.
##
## A drop rewards the opposite response. Killing something buys the resources to
## keep killing, so a swarm becomes survivable by fighting *through* it rather than
## backing out — and a player who is losing can still turn a fight around by
## picking off the weakest thing in it.
##
## Deliberately not a health potion. It pays into health, and once health is full
## the rest goes to breath, so it is never wasted and it feeds the Sing blast and
## the restorative song when Riff is already healthy.

## Share of maximum health restored. Small on purpose: the point is that killing
## six of them matters, not that any one of them rescues you.
## Tuned down from 4% after play: at that rate a whole encounter's drops more
## than covered the damage it dealt, so health never fell during a fight and the
## fights stopped having stakes. The point is to let a fight continue, not to pay
## for it.
@export_range(0.005, 0.2, 0.005) var health_ratio: float = 0.025

## Breath granted by the part of the drop that health could not take. Applied at
## full value when health is already full.
@export var breath_value: float = 7.0

## How high above the ground it floats once it has settled.
@export var hover_height: float = 0.3

## How close before it comes to you.
##
## Was 5.5, which together with a third-of-a-second hold meant a note dropped by
## an enemy dying in melee range was collected 0.42 seconds after it appeared —
## most of that spent held still. It was never invisible; there was simply nothing
## to see. Now it has to be approached.
@export var attract_radius: float = 4.0
@export var attract_speed: float = 9.0
## Distance at which it is collected.
@export var collect_radius: float = 1.1

## Seconds before it fades. Long enough to finish the fight it dropped in, short
## enough that the floor does not become a larder to graze on later.
@export var lifetime: float = 14.0
@export var fade_seconds: float = 2.0

## Held where it dropped before it will come to anyone.
##
## This is the number that decides whether the drop exists as an object in the
## world or merely as a health tick. Long enough to be noticed in peripheral
## vision during a fight, and to still be there when the fight ends.
@export var settle_seconds: float = 1.6

var _player: Node3D = null
var _age: float = 0.0
var _collected: bool = false
var _rise: float = 0.0
var _mesh: Node3D = null
var _light: OmniLight3D = null
var _grounded: bool = false


func _ready() -> void:
	add_to_group("quavers")
	_mesh = get_node_or_null("Mesh") as Node3D
	_light = get_node_or_null("Glow") as OmniLight3D
	_find_player()
	EventBus.player_spawned.connect(_on_player_spawned)


func _physics_process(delta: float) -> void:
	if _collected:
		return

	if not _grounded:
		_settle_onto_ground()

	_age += delta
	if _age >= lifetime:
		_expire()
		return

	_bob(delta)

	if _player == null or _age < settle_seconds:
		return

	var to_player: Vector3 = _player.global_position + Vector3.UP * 0.7 - global_position
	var distance: float = to_player.length()

	if distance <= collect_radius:
		_collect()
		return

	if distance <= attract_radius:
		# Accelerates as it closes, so it snaps in rather than drifting alongside
		# the player for several seconds.
		var eagerness: float = 1.0 - (distance / attract_radius)
		global_position += to_player.normalized() * attract_speed * (0.35 + eagerness) * delta


## Drops the note onto whatever is beneath it.
##
## Done on the first physics frame rather than in _ready, because whoever spawned
## it sets its position after adding it to the tree — in _ready it would sample the
## ground under the world origin.
##
## It matters on a hilly level: notes scatter around the kill, and a metre sideways
## on a bank is most of a metre of height. Without this they hang in the air on one
## side of a slope and sit buried in it on the other.
func _settle_onto_ground() -> void:
	_grounded = true

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 3.0,
		global_position - Vector3.UP * 6.0
	)
	query.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return

	global_position.y = float((hit["position"] as Vector3).y) + hover_height


func _bob(delta: float) -> void:
	_rise += delta
	if _mesh != null:
		_mesh.rotate_y(delta * 2.6)
		# Pops up on spawn before settling into its bob. Movement is what the eye
		# catches in a busy fight; a note that simply appears and hovers is missed
		# even when it is bright.
		var pop: float = 0.0
		if _rise < 0.45:
			pop = sin(_rise / 0.45 * PI) * 0.5
		_mesh.position.y = pop + 0.15 * sin(_rise * 3.0)

	# Fades out rather than vanishing, so a drop that times out reads as spent
	# instead of as having been picked up by something invisible.
	var remaining: float = lifetime - _age
	if remaining < fade_seconds and _light != null:
		_light.light_energy = lerpf(0.0, 1.8, remaining / fade_seconds)


func _collect() -> void:
	if _collected:
		return
	_collected = true

	var healed: float = 0.0
	var breath: float = 0.0

	if _player != null:
		var stats: Node = _player.get("stats")
		if stats != null:
			var before: float = float(stats.get("health"))
			var wanted: float = float(stats.get("max_health")) * health_ratio
			stats.call("heal", wanted)
			healed = float(stats.get("health")) - before

			# Whatever health could not take is paid in breath, scaled by how much
			# of the drop went unused. A drop is never wasted, and at full health
			# it becomes fuel for the Sing blast and the restorative song instead.
			var unused: float = 1.0 if wanted <= 0.0 else clampf(1.0 - healed / wanted, 0.0, 1.0)
			if unused > 0.01:
				breath = breath_value * unused
				stats.call("set_breath", float(stats.get("breath")) + breath)

	EventBus.quaver_collected.emit(healed, breath)
	AudioManager.play_sfx(&"quaver_collect")
	queue_free()


func _expire() -> void:
	_collected = true
	queue_free()


func _on_player_spawned(_player_node: Node) -> void:
	_find_player()


func _find_player() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	_player = players[0] as Node3D if not players.is_empty() else null

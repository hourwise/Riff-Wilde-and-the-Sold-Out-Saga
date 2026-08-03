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
@export_range(0.005, 0.2, 0.005) var health_ratio: float = 0.04

## Breath granted by the part of the drop that health could not take. Applied at
## full value when health is already full.
@export var breath_value: float = 9.0

## How close before it comes to you. Generous, because stopping mid-fight to walk
## over a specific tile is the opposite of what this is for.
@export var attract_radius: float = 5.5
@export var attract_speed: float = 9.0
## Distance at which it is collected.
@export var collect_radius: float = 1.1

## Seconds before it fades. Long enough to finish the fight it dropped in, short
## enough that the floor does not become a larder to graze on later.
@export var lifetime: float = 14.0
@export var fade_seconds: float = 2.0

## Held still briefly so it is seen where the kill happened, rather than flying to
## the player from a corpse they were not looking at.
@export var settle_seconds: float = 0.35

var _player: Node3D = null
var _age: float = 0.0
var _collected: bool = false
var _rise: float = 0.0
var _mesh: Node3D = null
var _light: OmniLight3D = null


func _ready() -> void:
	add_to_group("quavers")
	_mesh = get_node_or_null("Mesh") as Node3D
	_light = get_node_or_null("Glow") as OmniLight3D
	_find_player()
	EventBus.player_spawned.connect(_on_player_spawned)


func _physics_process(delta: float) -> void:
	if _collected:
		return

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


func _bob(delta: float) -> void:
	_rise += delta
	if _mesh != null:
		_mesh.rotate_y(delta * 2.6)
		_mesh.position.y = 0.15 * sin(_rise * 3.0)

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

extends Node3D
## The Church Graveyard. The demo's mission level.
##
## Owns level flow only: build the world, bake navigation over it, place the
## player, and hand off to the systems that already exist. Altar counting lives in
## AltarNetwork, the gate in ChurchBell, music in MusicDirector — this script
## coordinates, it does not implement.

## Where the boss appears once the bell has rung.
@export var boss_spawn: Vector3 = Vector3(0.0, 0.0, -126.0)
@export var player_spawn: Vector3 = Vector3(0.0, 1.0, 40.0)
@export var return_scene: String = "res://scenes/levels/TavernHub.tscn"
@export var boss_scene: PackedScene = null
## What the Choirmaster turns to face during his conducted interludes.
@export var conducting_altar: NodePath

@onready var graveyard_builder: GraveyardBuilder = $NavigationRegion3D/GraveyardBuilder
@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D
@onready var altar_network: AltarNetwork = $AltarNetwork
## The church is parented under the navigation region so its collision is picked
## up when the mesh is baked, which is why the bell sits this deep.
@onready var church: ChurchBuilder = $NavigationRegion3D/Church
@onready var church_bell: ChurchBell = $NavigationRegion3D/Church/ChurchBell

var _navigation_ready: bool = false


func _ready() -> void:
	GameManager.change_state(GameManager.GameState.MISSION)

	_settle_onto_terrain()
	_place_player()
	_hang_bell()
	_bake_navigation()

	EventBus.altar_cleansed.connect(_on_altar_cleansed)
	church_bell.toll_finished.connect(_on_bell_finished)

	MusicDirector.play_exploration()


## Drops everything authored at ground level onto the ground.
##
## The cemetery used to be flat, so altars, encounter markers, patrol routes and
## the church were all placed at y=0 and that was the ground. It is not any more.
## Rather than write a height into every one of them by hand — which would have to
## be redone the moment a hill moves — each is asked where the terrain is beneath
## it and settled there. Their authored y is kept as an offset, so anything
## deliberately raised stays raised.
func _settle_onto_terrain() -> void:
	if graveyard_builder == null:
		return

	var settled: int = 0
	for node in _nodes_to_settle():
		var here := Vector2(node.global_position.x, node.global_position.z)
		node.global_position.y += graveyard_builder.height_at(here)
		settled += 1

	# The church is built by its own script around its origin, so moving the
	# origin carries the whole building, tower and all.
	if church != null:
		var at := Vector2(church.global_position.x, church.global_position.z)
		church.global_position.y += graveyard_builder.height_at(at)

	print("[ChurchGraveyard] Settled %d markers onto the terrain." % settled)


## Everything placed in the scene that belongs on the ground. Patrol route points
## are included: a route at a fixed height sends enemies walking into a hillside
## or through the air above a hollow.
func _nodes_to_settle() -> Array[Node3D]:
	var found: Array[Node3D] = []

	for group: StringName in [&"funeral_altars", &"encounters", &"patrols"]:
		for node in get_tree().get_nodes_in_group(group):
			var spatial := node as Node3D
			if spatial == null:
				continue
			found.append(spatial)
			for child in spatial.get_children():
				var marker := child as Marker3D
				if marker != null:
					found.append(marker)

	# The great altar is scenery rather than a tracked altar, so it is in none of
	# the groups above and would otherwise be left buried in the hillside.
	var great_altar := get_node_or_null("GreatAltar") as Node3D
	if great_altar != null:
		found.append(great_altar)

	var spawn_points: Node = get_node_or_null("SpawnPoints")
	if spawn_points != null:
		for child in spawn_points.get_children():
			var marker := child as Node3D
			if marker != null:
				found.append(marker)

	return found


## Puts the bell where the tower actually ends up, rather than at a hard-coded
## height that silently drifts whenever the church's proportions are tuned.
func _hang_bell() -> void:
	if church == null or church_bell == null:
		return
	church_bell.position = church.bell_position


## Navigation is baked at runtime because the cemetery's geometry is generated at
## runtime — there is nothing to bake in the editor. Baked on a thread so the
## fade-in is not held up by it.
func _bake_navigation() -> void:
	if navigation_region.navigation_mesh == null:
		push_error("[ChurchGraveyard] NavigationRegion3D has no navigation mesh assigned.")
		return

	navigation_region.bake_finished.connect(_on_navigation_baked, CONNECT_ONE_SHOT)
	navigation_region.bake_navigation_mesh(true)


func _on_navigation_baked() -> void:
	_navigation_ready = true

	# An empty bake is silent: it reports success and leaves every enemy unable to
	# path, so the polygon count is worth stating out loud.
	var polygons: int = navigation_region.navigation_mesh.get_polygon_count()
	if polygons <= 0:
		push_error("[ChurchGraveyard] Navigation baked with no polygons — enemies cannot path.")
	else:
		print("[ChurchGraveyard] Navigation baked: %d polygons." % polygons)


func is_navigation_ready() -> bool:
	return _navigation_ready


func _place_player() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return

	var player := players[0] as Node3D
	# A spawn point requested by whatever loaded this scene wins, so the Inn can
	# send the player to a specific entrance later.
	var requested: StringName = SceneLoader.consume_spawn_point()
	if requested != &"":
		var marker := get_node_or_null("SpawnPoints/%s" % requested) as Node3D
		if marker != null:
			player.global_position = marker.global_position
			return

	player.global_position = Vector3(
		player_spawn.x,
		graveyard_builder.height_at(Vector2(player_spawn.x, player_spawn.z)) + player_spawn.y,
		player_spawn.z
	)


func _on_altar_cleansed(_altar_id: StringName, cleansed: int, total: int) -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return

	var hud: Node = players[0].get("hud_controller")
	if hud != null and hud.has_method("show_temporary_center_message"):
		hud.call("show_temporary_center_message", "Altar restored  %d / %d" % [cleansed, total], 2.6)


## The bell has tolled and the choir has answered.
func _on_bell_finished() -> void:
	_summon_choirmaster()


## Brings the Choirmaster into the courtyard.
##
## Spawned on the bell rather than placed in the scene so he is not stood in the
## arena for the twelve minutes before he matters — idling, pathable, and
## shootable through a fence by a player who wandered in early.
func _summon_choirmaster() -> void:
	if boss_scene == null:
		push_warning("[ChurchGraveyard] No boss scene assigned; the bell leads nowhere.")
		return

	var boss := boss_scene.instantiate() as Node3D
	if boss == null:
		return

	navigation_region.add_child(boss)
	boss.global_position = Vector3(
		boss_spawn.x,
		graveyard_builder.height_at(Vector2(boss_spawn.x, boss_spawn.z)) + 0.5,
		boss_spawn.z
	)

	# Pointed at the great altar so his interludes read as addressing the choir
	# rather than staring into the middle distance.
	var altar: Node3D = get_node_or_null(conducting_altar) as Node3D
	if altar != null:
		boss.set("altar_path", boss.get_path_to(altar))

	# The music changes with him, not with the bell: the toll is the cue, but the
	# arrangement belongs to the fight that follows it.
	MusicDirector.play_boss(0)

	print("[ChurchGraveyard] The Choirmaster takes the stand at %s." % str(boss.global_position))

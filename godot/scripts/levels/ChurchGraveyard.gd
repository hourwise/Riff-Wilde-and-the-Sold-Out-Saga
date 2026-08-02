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

@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D
@onready var altar_network: AltarNetwork = $AltarNetwork
## The church is parented under the navigation region so its collision is picked
## up when the mesh is baked, which is why the bell sits this deep.
@onready var church: ChurchBuilder = $NavigationRegion3D/Church
@onready var church_bell: ChurchBell = $NavigationRegion3D/Church/ChurchBell

var _navigation_ready: bool = false


func _ready() -> void:
	GameManager.change_state(GameManager.GameState.MISSION)

	_place_player()
	_hang_bell()
	_bake_navigation()

	EventBus.altar_cleansed.connect(_on_altar_cleansed)
	church_bell.toll_finished.connect(_on_bell_finished)

	MusicDirector.play_exploration()


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

	player.global_position = player_spawn


func _on_altar_cleansed(_altar_id: StringName, cleansed: int, total: int) -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return

	var hud: Node = players[0].get("hud_controller")
	if hud != null and hud.has_method("show_temporary_center_message"):
		hud.call("show_temporary_center_message", "Altar restored  %d / %d" % [cleansed, total], 2.6)


## The bell has tolled and the choir has answered. Phase 7 spawns the Choirmaster
## here; until then the level reports itself complete so the loop can be walked
## end to end.
func _on_bell_finished() -> void:
	print("[ChurchGraveyard] Bell finished. Boss cue at %s." % str(boss_spawn))

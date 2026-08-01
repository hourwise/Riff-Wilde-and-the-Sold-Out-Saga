extends Node3D

@export var nav_min: Vector2 = Vector2(-23.0, -23.0)
@export var nav_max: Vector2 = Vector2(23.0, 23.0)
@export var nav_cell_size: float = 2.0
@export var return_scene_path: String = "res://scenes/levels/TavernHub.tscn"

var blocked_rects: Array[Rect2] = [
	Rect2(Vector2(-13.5, -13.5), Vector2(7.0, 7.0)),
	Rect2(Vector2(5.5, 5.5), Vector2(9.0, 9.0))
]

var enemies_remaining: int = 0
var encounter_complete: bool = false
var scouting_complete: bool = false
var area_complete: bool = false

@onready var scouting_marker: Node = get_node_or_null("ScoutingMarker")
@onready var extraction_point: Node = get_node_or_null("ExtractionPoint")

func _ready() -> void:
	_create_runtime_navigation()
	_setup_area_objectives()
	call_deferred("_setup_encounter_tracking")

func _setup_area_objectives() -> void:
	if scouting_marker and scouting_marker.has_signal("scouted"):
		scouting_marker.scouted.connect(_on_area_scouted)

	if extraction_point:
		if extraction_point.has_method("set_active"):
			extraction_point.call("set_active", false)
		if extraction_point.has_signal("player_entered"):
			extraction_point.player_entered.connect(_on_extraction_entered)
		if extraction_point.has_signal("player_exited"):
			extraction_point.player_exited.connect(_on_extraction_exited)
		if extraction_point.has_signal("extraction_requested"):
			extraction_point.extraction_requested.connect(_extract_to_hub)

func _setup_encounter_tracking() -> void:
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemies")
	enemies_remaining = enemies.size()
	print("[PrototypeArena] Encounter started. Enemies remaining: %d" % enemies_remaining)

	for enemy in enemies:
		if enemy.has_signal("died"):
			enemy.died.connect(_on_enemy_died)

	if enemies_remaining <= 0:
		_complete_encounter()

func _on_enemy_died(enemy: Node) -> void:
	if encounter_complete:
		return

	enemies_remaining = max(0, enemies_remaining - 1)
	print("[PrototypeArena] Enemy defeated. Enemies remaining: %d" % enemies_remaining)

	if enemies_remaining <= 0:
		_complete_encounter()

func _complete_encounter() -> void:
	if encounter_complete:
		return

	encounter_complete = true
	print("[PrototypeArena] Encounter cleared. Area remains active.")

	var player := get_tree().get_first_node_in_group("player")
	if player and "hud_controller" in player and player.hud_controller and player.hud_controller.has_method("show_temporary_center_message"):
		player.hud_controller.show_temporary_center_message("Encounter cleared")

	_check_area_completion()

func _on_area_scouted() -> void:
	scouting_complete = true
	var progression_manager := get_node_or_null("/root/ProgressionManager")
	if progression_manager and progression_manager.has_method("record_scouting_completed"):
		progression_manager.call("record_scouting_completed")
	print("[PrototypeArena] Scouting objective complete.")

	var player := get_tree().get_first_node_in_group("player")
	if player and "hud_controller" in player and player.hud_controller and player.hud_controller.has_method("show_temporary_center_message"):
		player.hud_controller.show_temporary_center_message("Area scouted")

	_check_area_completion()

func _check_area_completion() -> void:
	if area_complete:
		return
	if not encounter_complete or not scouting_complete:
		return

	area_complete = true
	print("[PrototypeArena] Area complete. Extraction available.")
	if extraction_point and extraction_point.has_method("set_active"):
		extraction_point.call("set_active", true)

	var player := get_tree().get_first_node_in_group("player")
	if player and "hud_controller" in player and player.hud_controller and player.hud_controller.has_method("show_center_message"):
		player.hud_controller.show_center_message("Area Complete - Find the exit")

func _on_extraction_entered() -> void:
	if not area_complete:
		return

	var player := get_tree().get_first_node_in_group("player")
	if player and "hud_controller" in player and player.hud_controller and player.hud_controller.has_method("show_center_message"):
		player.hud_controller.show_center_message("Press E to return to Tavern")

func _on_extraction_exited() -> void:
	if not area_complete:
		return

	var player := get_tree().get_first_node_in_group("player")
	if player and "hud_controller" in player and player.hud_controller and player.hud_controller.has_method("show_center_message"):
		player.hud_controller.show_center_message("Area Complete - Find the exit")

func _extract_to_hub() -> void:
	if not area_complete:
		return

	print("[PrototypeArena] Extracting to Tavern Hub.")
	var progression_manager := get_node_or_null("/root/ProgressionManager")
	if progression_manager and progression_manager.has_method("complete_mission"):
		progression_manager.call("complete_mission")
	GameManager.change_state(GameManager.GameState.INN_HUB)
	SceneLoader.load_scene(return_scene_path)

func _create_runtime_navigation() -> void:
	var navigation_region := NavigationRegion3D.new()
	navigation_region.name = "RuntimeNavigationRegion"
	navigation_region.navigation_mesh = _build_navigation_mesh()
	add_child(navigation_region)
	print("[PrototypeArena] Runtime navigation mesh generated.")

func _build_navigation_mesh() -> NavigationMesh:
	var navigation_mesh := NavigationMesh.new()
	var columns: int = int(floor((nav_max.x - nav_min.x) / nav_cell_size))
	var rows: int = int(floor((nav_max.y - nav_min.y) / nav_cell_size))
	var vertices := PackedVector3Array()

	for z_index in range(rows + 1):
		for x_index in range(columns + 1):
			vertices.append(Vector3(
				nav_min.x + float(x_index) * nav_cell_size,
				0.05,
				nav_min.y + float(z_index) * nav_cell_size
			))

	navigation_mesh.vertices = vertices

	for z_index in range(rows):
		for x_index in range(columns):
			var center := Vector2(
				nav_min.x + (float(x_index) + 0.5) * nav_cell_size,
				nav_min.y + (float(z_index) + 0.5) * nav_cell_size
			)
			if _is_blocked(center):
				continue

			var top_left: int = z_index * (columns + 1) + x_index
			var top_right: int = top_left + 1
			var bottom_left: int = (z_index + 1) * (columns + 1) + x_index
			var bottom_right: int = bottom_left + 1
			navigation_mesh.add_polygon(PackedInt32Array([top_left, top_right, bottom_right, bottom_left]))

	_add_ramp_bridge(navigation_mesh)
	return navigation_mesh

func _is_blocked(point: Vector2) -> bool:
	for rect in blocked_rects:
		if rect.has_point(point):
			return true
	return false

func _add_ramp_bridge(navigation_mesh: NavigationMesh) -> void:
	var start_index: int = navigation_mesh.vertices.size()
	var vertices: PackedVector3Array = navigation_mesh.vertices

	vertices.append(Vector3(5.5, 0.05, -0.5))
	vertices.append(Vector3(14.5, 0.05, -0.5))
	vertices.append(Vector3(14.5, 0.05, 4.5))
	vertices.append(Vector3(5.5, 0.05, 4.5))
	navigation_mesh.vertices = vertices
	navigation_mesh.add_polygon(PackedInt32Array([start_index, start_index + 1, start_index + 2, start_index + 3]))

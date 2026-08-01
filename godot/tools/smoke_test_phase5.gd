extends SceneTree
## Automated verification for Phase 5 (Church Graveyard).
##
##   godot --headless --path godot --script res://tools/smoke_test_phase5.gd
##
## The level is generated, so the checks that matter are about whether it came out
## playable: navigation that actually covers the ground, altars gated behind their
## guards, clearings left clear, and the bell gate firing exactly once.
##
## Class names are deliberately not referenced here. Naming a class forces its
## script to compile alongside this one, which happens before autoloads register,
## and every EventBus reference in it would then fail to resolve.

const LEVEL: String = "res://scenes/levels/ChurchGraveyard.tscn"

var _failures: int = 0
var _checks: int = 0
var _bus: Node = null
var _level: Node = null


func _initialize() -> void:
	await process_frame
	_bus = root.get_node("EventBus")

	change_scene_to_file(LEVEL)
	for i in range(30):
		await process_frame

	_level = current_scene

	# Navigation is baked on a worker thread, so it is not ready simply because a
	# few frames have passed. Waiting a fixed number of frames made an empty mesh
	# look like a broken bake when it was only an unfinished one.
	var waited: int = 0
	while not bool(_level.call("is_navigation_ready")) and waited < 600:
		waited += 1
		await process_frame

	# Baking the mesh and the navigation server adopting it are separate steps: the
	# server syncs maps during the physics frame. Querying in between returns the
	# world origin for every point, which reads exactly like a broken level.
	# Registration is not readiness: the server adopts a region before its polygons
	# are queryable, and answers with the world origin in the meantime. Wait until
	# a probe well away from the origin actually resolves nearby.
	var region := _level.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	var probe := Vector3(0.0, 0.0, 22.0)
	var synced: int = 0
	while region != null and synced < 240:
		var map: RID = region.get_navigation_map()
		if map.is_valid() and not NavigationServer3D.map_get_regions(map).is_empty():
			if NavigationServer3D.map_get_closest_point(map, probe).distance_to(probe) < 3.0:
				break
		synced += 1
		await physics_frame

	print("\n=== Phase 5 smoke test ===\n")
	_check(bool(_level.call("is_navigation_ready")), "navigation finished baking (%d frames)" % waited)
	_check(synced < 180, "navigation map adopted the baked region (%d frames)" % synced)

	_test_world_built()
	_test_navigation()
	_test_clearings()
	await _test_altar_gate()

	print("\n=== %d/%d checks passed ===" % [_checks - _failures, _checks])
	if _failures > 0:
		print("FAILED\n")
		quit(1)
		return
	print("PASSED\n")
	quit(0)


# ── Tests ────────────────────────────────────────────────────────

func _test_world_built() -> void:
	var builder: Node = _level.get_node_or_null("NavigationRegion3D/GraveyardBuilder")
	if _check(builder != null, "graveyard builder present"):
		var scenery: Node = builder.get_node_or_null("Scenery")
		var count: int = scenery.get_child_count() if scenery != null else 0
		_check(count > 300, "graveyard is dressed (%d pieces)" % count)

	var church: Node = _level.get_node_or_null("NavigationRegion3D/Church")
	if _check(church != null, "church present"):
		var pieces: Node = church.get_node_or_null("Pieces")
		_check(pieces != null and pieces.get_child_count() > 50, "church is assembled")

		# The tower is the level's landmark, so the bell must actually be up it.
		var bell: Node3D = church.get_node_or_null("ChurchBell") as Node3D
		if _check(bell != null, "church bell present"):
			_check(bell.position.y > 6.0, "bell hangs in the belfry (y=%.1f)" % bell.position.y)

	_check(_level.get_node_or_null("AltarNetwork") != null, "altar network present")
	_check(not get_nodes_in_group("player").is_empty(), "player is in the level")


## A navigation mesh with no polygons bakes without error and silently leaves
## every enemy unable to path, so the polygon count has to be asserted.
func _test_navigation() -> void:
	var region := _level.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if not _check(region != null, "navigation region present"):
		return

	var mesh: NavigationMesh = region.navigation_mesh
	if not _check(mesh != null, "navigation mesh assigned"):
		return

	_check(mesh.get_polygon_count() > 0, "navigation baked %d polygons" % mesh.get_polygon_count())
	_check(mesh.vertices.size() > 0, "navigation mesh has vertices")

	# Navigable ground must reach the far end of the level, or the boss arena is
	# unreachable and the demo cannot be finished.
	var map: RID = region.get_navigation_map()
	if not map.is_valid():
		_check(false, "navigation map valid")
		return

	for probe: Dictionary in [
		{"at": Vector3(0.0, 0.0, 22.0), "what": "the gate"},
		{"at": Vector3(6.0, 0.0, -8.0), "what": "the graveyard"},
		{"at": Vector3(28.0, 0.0, -32.0), "what": "the crypts"},
		{"at": Vector3(-30.0, 0.0, -32.0), "what": "the mausoleum"},
		{"at": Vector3(0.0, 0.0, -58.0), "what": "the church courtyard"},
	]:
		var target: Vector3 = probe["at"]
		var closest: Vector3 = NavigationServer3D.map_get_closest_point(map, target)
		_check(
			closest.distance_to(target) < 3.0,
			"%s is navigable (%.1fm from the nearest navmesh point)" % [probe["what"], closest.distance_to(target)]
		)


## Procedural scenery that wanders into an altar plaza or across a path makes the
## level unplayable, so the clearings are verified to be empty.
func _test_clearings() -> void:
	var builder: Node = _level.get_node_or_null("NavigationRegion3D/GraveyardBuilder")
	var scenery: Node = builder.get_node_or_null("Scenery") if builder != null else null
	if not _check(scenery != null, "scenery available for clearance check"):
		return

	var clearings: Array = builder.get_script().get_script_constant_map()["CLEARINGS"]
	var intrusions: int = 0

	for child in scenery.get_children():
		var node := child as Node3D
		if node == null:
			continue
		# Roads are meant to be inside clearings; everything else is not.
		if String(node.name).begins_with("road"):
			continue

		var point := Vector2(node.position.x, node.position.z)
		for clearing: Dictionary in clearings:
			if point.distance_to(clearing["at"]) < float(clearing["radius"]) * 0.8:
				intrusions += 1
				break

	_check(intrusions == 0, "no scenery blocks the plazas or spawn (%d intrusions)" % intrusions)


## The whole progression gate, walked end to end: an altar is locked until its
## guards die, cleansing counts, and the last one rings the bell exactly once.
func _test_altar_gate() -> void:
	var network: Node = _level.get_node_or_null("AltarNetwork")
	if not _check(network != null, "altar network available"):
		return

	_check(int(network.call("get_total")) == 4, "four altars are tracked")

	var altars: Array[Node] = get_nodes_in_group("funeral_altars")
	if not _check(altars.size() == 4, "four altars in the level"):
		return

	# State 0 is CORRUPTED: guarded, and not cleansable.
	var locked: int = 0
	for altar in altars:
		if int(altar.get("state")) == 0:
			locked += 1
	_check(locked == 4, "every altar starts guarded")

	var first: Node = altars[0]
	first.call("cleanse")
	await process_frame
	_check(not bool(first.call("is_cleansed")), "a guarded altar refuses to be cleansed")

	var bell_rang: Array[int] = [0]
	var all_done: Array[int] = [0]
	var bell_handler := func() -> void: bell_rang[0] += 1
	var done_handler := func() -> void: all_done[0] += 1
	_bus.church_bell_rang.connect(bell_handler)
	_bus.all_altars_cleansed.connect(done_handler)

	# Clear each encounter, then cleanse the altar it was guarding.
	for altar in altars:
		var encounter := altar.get_node_or_null(altar.get("encounter_path")) as Node
		if encounter != null:
			encounter.call("mark_cleared")
		await process_frame
		_check(int(altar.get("state")) == 1, "%s unlocks once its guards are cleared" % altar.name)

		altar.call("cleanse")
		await process_frame
		_check(bool(altar.call("is_cleansed")), "%s cleanses" % altar.name)

	_check(bool(network.call("is_complete")), "network reports all altars cleansed")
	_check(all_done[0] == 1, "all_altars_cleansed fires exactly once")
	_check(bell_rang[0] == 1, "the bell rings exactly once")

	_bus.church_bell_rang.disconnect(bell_handler)
	_bus.all_altars_cleansed.disconnect(done_handler)


# ── Helpers ──────────────────────────────────────────────────────

func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if condition:
		print("  ok    %s" % description)
		return true

	_failures += 1
	print("  FAIL  %s" % description)
	return false

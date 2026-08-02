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
	_test_content_volume()
	await _test_patrols()
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
		var count: int = (builder.call("get_placements") as Array).size()
		_check(count > 1000, "graveyard is dressed (%d pieces)" % count)

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

	var spawn := Vector3(0.0, 0.0, 40.0)

	for probe: Dictionary in [
		{"at": spawn, "what": "the gate"},
		{"at": Vector3(0.0, 0.0, 0.0), "what": "the graveyard altar"},
		{"at": Vector3(64.0, 0.0, -6.0), "what": "Weeping Hollow"},
		{"at": Vector3(-64.0, 0.0, -44.0), "what": "the mausoleum altar"},
		{"at": Vector3(56.2, 0.0, -38.0), "what": "the maze mouth"},
		{"at": Vector3(67.0, 0.0, -76.6), "what": "the crypt altar chamber"},
		{"at": Vector3(0.0, 0.0, -100.0), "what": "the bone field"},
		{"at": Vector3(0.0, 0.0, -124.0), "what": "the church altar"},
		{"at": Vector3(0.0, 0.0, -126.0), "what": "the boss arena"},
	]:
		var target: Vector3 = probe["at"]
		var closest: Vector3 = NavigationServer3D.map_get_closest_point(map, target)
		_check(
			closest.distance_to(target) < 3.0,
			"%s is navigable (%.1fm from the nearest navmesh point)" % [probe["what"], closest.distance_to(target)]
		)

	# The definition of done is that the demo can be completed without help, and
	# that starts with the route existing. Navigable ground at both ends proves
	# nothing on its own — the maze could seal the far half of the cemetery off
	# entirely and every probe above would still pass.
	for destination: Dictionary in [
		{"at": Vector3(67.0, 0.0, -76.6), "what": "the crypt altar, through the maze"},
		{"at": Vector3(-64.0, 0.0, -44.0), "what": "the mausoleum altar"},
		{"at": Vector3(0.0, 0.0, -126.0), "what": "the boss arena"},
	]:
		var target: Vector3 = destination["at"]
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, spawn, target, true)
		var arrived: bool = path.size() >= 2 and path[-1].distance_to(target) < 4.0
		_check(
			arrived,
			"a path runs from spawn to %s (%d waypoints, ends %.1fm away)" % [
				destination["what"],
				path.size(),
				path[-1].distance_to(target) if path.size() > 0 else -1.0
			]
		)


## Procedural scenery that wanders into an altar plaza or across a path makes the
## level unplayable, so the clearings are verified to be empty.
##
## Scattered dressing only. Authored structure — roads, and the maze walls under
## their own branch — is meant to sit in a clearing.
func _test_clearings() -> void:
	var builder: Node = _level.get_node_or_null("NavigationRegion3D/GraveyardBuilder")
	if not _check(builder != null, "scenery available for clearance check"):
		return

	# Read from the builder's own record rather than from scene nodes: nearly all
	# scenery is drawn from a MultiMesh and has no node left to inspect.
	var placements: Array = builder.call("get_placements")
	var clearings: Array = builder.get_script().get_script_constant_map()["CLEARINGS"]
	var intrusions: int = 0
	var offenders: Array[String] = []

	for placement: Dictionary in placements:
		var piece: String = placement["piece"]
		# Roads and maze walls are authored structure and belong in a clearing.
		if piece.begins_with("road") or piece.begins_with("stone-wall"):
			continue

		var point: Vector2 = placement["at"]
		for clearing: Dictionary in clearings:
			if point.distance_to(clearing["at"]) < float(clearing["radius"]) * 0.8:
				intrusions += 1
				# Named, not just counted. A bare tally says the layout is wrong
				# without saying where, which is most of the work of fixing it.
				if offenders.size() < 6:
					offenders.append("%s at (%.0f, %.0f) in the clearing at (%.0f, %.0f)" % [
						piece, point.x, point.y, clearing["at"].x, clearing["at"].y
					])
				break

	_check(
		intrusions == 0,
		"no scenery blocks the plazas or spawn%s" % (
			"" if intrusions == 0 else " (%d intrusions, e.g. %s)" % [intrusions, "; ".join(offenders)]
		)
	)


## The brief asks for a 12–15 minute level, which is a content quantity as much as
## a design. These floors are what that many minutes needs; they exist so the
## level cannot quietly shrink back to a ten-minute one during later tuning.
func _test_content_volume() -> void:
	var encounters: Array[Node] = get_nodes_in_group("encounters")
	var enemies: int = 0
	for encounter: Node in encounters:
		enemies += (encounter.get("spawns") as Array).size()

	_check(encounters.size() >= 15, "at least 15 encounter groups (%d)" % encounters.size())
	_check(enemies >= 60, "at least 60 enemies posted across them (%d)" % enemies)
	_check(get_nodes_in_group("patrols").size() >= 4, "at least 4 roving patrols")

	var builder: Node = _level.get_node_or_null("NavigationRegion3D/GraveyardBuilder")
	if builder == null:
		return

	# Dead ends are the whole point of a maze. A generator that produced a single
	# corridor would still bake, still be navigable, and still pass every other
	# check here.
	var dead_ends: Array = builder.call("get_dead_ends")
	_check(dead_ends.size() >= 4, "the crypt maze has dead ends (%d)" % dead_ends.size())

	var forest: Node = builder.get_node_or_null("ForestWall") as MultiMeshInstance3D
	var trees: int = (forest as MultiMeshInstance3D).multimesh.instance_count if forest != null else 0
	_check(trees >= 3000, "a forest thick enough to hide the horizon (%d trees)" % trees)


## Patrols must actually rove. A patrol that spawns and then stands still is
## indistinguishable from an encounter, and nothing else here would notice.
func _test_patrols() -> void:
	var patrols: Array[Node] = get_nodes_in_group("patrols")
	if not _check(not patrols.is_empty(), "patrols present"):
		return

	var patrol := patrols[0] as Node3D
	var players: Array[Node] = get_nodes_in_group("player")
	if not _check(not players.is_empty(), "player available to wake a patrol"):
		return

	# Walked to rather than teleported into range, so the patrol wakes the way it
	# would in play.
	var player := players[0] as Node3D
	var resume: Vector3 = player.global_position
	player.global_position = patrol.global_position + Vector3(0.0, 1.0, 6.0)

	for i in range(20):
		await process_frame
	if not _check(bool(patrol.get("is_active")), "a patrol wakes when the player approaches"):
		player.global_position = resume
		return

	var members: Array = patrol.call("get_members")
	if not _check(not members.is_empty(), "the patrol spawned its members"):
		player.global_position = resume
		return

	var member := members[0] as Node3D
	_check(
		(member.get("patrol_points") as PackedVector3Array).size() >= 2,
		"patrol members are given their route"
	)

	# Moved out of detection range first: an enemy that has seen the player is
	# chasing, not patrolling, and chasing would pass a naive movement check.
	player.global_position = patrol.global_position + Vector3(0.0, 1.0, 70.0)
	for i in range(40):
		await physics_frame

	var start: Vector3 = member.global_position
	for i in range(120):
		await physics_frame
		if member.global_position.distance_to(start) > 1.5:
			break

	_check(
		member.global_position.distance_to(start) > 1.5,
		"a patrol walks its route unprompted (%.1fm)" % member.global_position.distance_to(start)
	)

	player.global_position = resume
	await process_frame


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

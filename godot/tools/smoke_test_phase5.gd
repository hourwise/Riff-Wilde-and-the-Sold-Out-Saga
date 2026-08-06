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
	await _test_terrain_is_solid()
	await _test_banks_stop_the_player()
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

	# Probes are authored as ground positions, but the ground is generated and no
	# longer at y=0. map_get_closest_point measures in three dimensions, so a probe
	# left at zero over ground four metres up reports four metres off the navmesh
	# while standing directly above it.
	var builder: Node = _level.get_node_or_null("NavigationRegion3D/GraveyardBuilder")
	var spawn: Vector3 = _on_ground(builder, Vector3(0.0, 0.0, 40.0))

	for probe: Dictionary in [
		{"at": Vector3(0.0, 0.0, 40.0), "what": "the gate"},
		{"at": Vector3(0.0, 0.0, 0.0), "what": "the graveyard altar"},
		{"at": Vector3(64.0, 0.0, -6.0), "what": "Weeping Hollow"},
		{"at": Vector3(-64.0, 0.0, -44.0), "what": "the mausoleum altar"},
		{"at": Vector3(56.2, 0.0, -38.0), "what": "the maze mouth"},
		{"at": Vector3(67.0, 0.0, -76.6), "what": "the crypt altar chamber"},
		{"at": Vector3(0.0, 0.0, -100.0), "what": "the bone field"},
		{"at": Vector3(0.0, 0.0, -124.0), "what": "the church altar"},
		{"at": Vector3(0.0, 0.0, -126.0), "what": "the boss arena"},
	]:
		var target: Vector3 = _on_ground(builder, probe["at"])
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
		var target: Vector3 = _on_ground(builder, destination["at"])
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

	_test_terrain_gates_access(map, builder)


## The ground must actually stop things.
##
## The terrain is generated, and its collision is a separate object from its mesh:
## a heightfield shape built from the same samples. Nothing connects them except
## the code that builds both, so they can disagree silently — the hills render,
## the navigation bakes over them, every other check passes, and the player walks
## straight through a hillside.
##
## Raycast rather than dropped, because a dropped body that finds no floor just
## falls forever and the test would have to guess how long to wait.
func _test_terrain_is_solid() -> void:
	var builder: Node = _level.get_node_or_null("NavigationRegion3D/GraveyardBuilder")
	if builder == null or not builder.has_method("height_at"):
		return

	var space: PhysicsDirectSpaceState3D = (_level as Node3D).get_world_3d().direct_space_state
	var worst: float = 0.0
	var missed: Array[String] = []

	for probe: Dictionary in [
		{"at": Vector2(0.0, 40.0), "what": "the gate"},
		{"at": Vector2(0.0, 0.0), "what": "the graveyard altar"},
		{"at": Vector2(44.5, -20.0), "what": "the Weeping Hollow bank"},
		{"at": Vector2(-52.0, -68.0), "what": "the mausoleum slope"},
		{"at": Vector2(64.0, -6.0), "what": "the hollow floor"},
		{"at": Vector2(0.0, -113.0), "what": "the church causeway"},
		{"at": Vector2(56.2, -65.8), "what": "the maze plateau"},
	]:
		var here: Vector2 = probe["at"]
		var expected: float = float(builder.call("height_at", here))

		var from := Vector3(here.x, expected + 40.0, here.y)
		var to := Vector3(here.x, expected - 40.0, here.y)
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		var hit: Dictionary = space.intersect_ray(query)

		if hit.is_empty():
			missed.append(String(probe["what"]))
			continue

		var difference: float = absf(float((hit["position"] as Vector3).y) - expected)
		worst = maxf(worst, difference)

	_check(
		missed.is_empty(),
		"the ground is solid everywhere%s" % ("" if missed.is_empty() else " (fell through at: %s)" % ", ".join(missed))
	)
	# The collision heightfield and the visible mesh are built from the same
	# samples, so they should agree to well within a step height. Drifting apart
	# is how a character ends up hovering or wading.
	_check(
		worst < 0.35,
		"collision matches the visible ground (worst mismatch %.2fm)" % worst
	)


## The banks must stop the player too, not only the enemies.
##
## Navigation refuses anything over 38 degrees, so the ridges already gate where
## enemies can go. The player is a CharacterBody3D and obeys its own slope limit,
## which is inherited from Godot unless stated — and Godot's default of 45 degrees
## sits between navigation's 38 and the banks' 48-to-58. That gap let the player
## scramble up ground nothing could follow them onto, and made "that way is
## closed" a rule the level could not rely on.
func _test_banks_stop_the_player() -> void:
	var players: Array[Node] = get_nodes_in_group("player")
	if players.is_empty():
		return

	var builder: Node = _level.get_node_or_null("NavigationRegion3D/GraveyardBuilder")
	if builder == null:
		return

	var player := players[0] as CharacterBody3D
	var resume: Vector3 = player.global_position

	# At the foot of the Weeping Hollow bank, facing straight up it.
	var foot := Vector2(52.0, -18.0)
	var uphill := Vector3(-1.0, 0.0, 0.0)
	player.global_position = Vector3(
		foot.x, float(builder.call("height_at", foot)) + 0.5, foot.y
	)
	for i in range(10):
		await physics_frame

	var start: float = player.global_position.y

	# Driven directly rather than through input, so the test measures the body's
	# response to the slope and not the state machine's response to a key.
	for i in range(120):
		player.velocity.x = uphill.x * 6.0
		player.velocity.z = uphill.z * 6.0
		player.move_and_slide()
		await physics_frame

	var climbed: float = player.global_position.y - start
	_check(
		climbed < 1.5,
		"the player cannot walk up a bank (climbed %.2fm in two seconds)" % climbed
	)

	player.global_position = resume
	await physics_frame


## The terrain has to do more than look uneven: some ground must be genuinely
## impassable, or "you can cross that ridge but not this one" is not a rule the
## player can learn.
##
## Measured as a detour rather than by probing a slope directly. A ridge that
## reads as steep but is still walkable would pass any check on its geometry; the
## question that matters is whether reaching the far side actually requires the
## road. Weeping Hollow sits behind an authored bank with one way in, so the
## walked route there should be far longer than the straight line.
func _test_terrain_gates_access(map: RID, builder: Node) -> void:
	# Started well off the road, so the straight line crosses the bank somewhere
	# other than where the road cuts through it. Measuring from a point already on
	# the road would compare the road against itself.
	var from: Vector3 = _on_ground(builder, Vector3(30.0, 0.0, -22.0))
	var to: Vector3 = _on_ground(builder, Vector3(64.0, 0.0, -6.0))

	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, from, to, true)
	if not _check(path.size() >= 2, "a route into Weeping Hollow exists at all"):
		return

	var walked: float = 0.0
	for index in range(path.size() - 1):
		walked += path[index].distance_to(path[index + 1])

	var direct: float = from.distance_to(to)
	_check(
		path[-1].distance_to(to) < 4.0,
		"the route into Weeping Hollow arrives (%.1fm short)" % path[-1].distance_to(to)
	)
	_check(
		walked > direct * 1.25,
		"the ridge forces a detour rather than a straight walk in (%.0fm walked vs %.0fm direct)" % [walked, direct]
	)

	# And the bank's flank is off the navigation mesh, so nothing walks up it.
	# Probed on the slope, not the crest: the top of a hill is legitimately flat,
	# so a crest sample proves nothing either way.
	var crest := Vector3(48.8, 0.0, -18.0)
	var on_crest: Vector3 = _on_ground(builder, crest)
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(map, on_crest)
	_check(
		closest.distance_to(on_crest) > 1.5,
		"the top of the bank is not walkable (%.1fm to the nearest navigable point)" % closest.distance_to(on_crest)
	)


## Raises an authored ground position onto the generated terrain.
func _on_ground(builder: Node, point: Vector3) -> Vector3:
	if builder == null or not builder.has_method("height_at"):
		return point
	return Vector3(point.x, float(builder.call("height_at", Vector2(point.x, point.z))), point.z)


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
		# Ground cover does too: grass and loose stones across an altar plaza are
		# what stop it looking like unfinished ground, and neither blocks anything.
		if piece.begins_with("road") or piece.begins_with("stone-wall"):
			continue
		if piece.begins_with("forest/") or piece.begins_with("halloween/"):
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

	var placements: Array = builder.call("get_placements")

	# Ground cover has to be ground-sized. It was sized by multiplier on the
	# assumption that the forest pack matched the graveyard kit's scale; it does
	# not, and grass came out nearly three metres tall — taller than the trees it
	# grows under.
	#
	# Measured from the builder's own record, not by reading the MultiMesh back.
	# Headless uses the dummy rendering server, where instance transforms are
	# written into a no-op and read back as identity: every piece reports as
	# unscaled at the world origin, which looks exactly like this bug and is not.
	var tallest: float = 0.0
	var tallest_piece: String = ""
	var cover: int = 0
	for placement: Dictionary in placements:
		var piece: String = placement["piece"]
		if not (piece.begins_with("forest/") or piece.begins_with("halloween/")):
			continue
		cover += 1
		var height: float = float(placement.get("height", 0.0))
		if height > tallest:
			tallest = height
			tallest_piece = piece

	_check(cover > 2000, "the ground is covered (%d pieces)" % cover)
	# Riff is 1.25 m. Undergrowth may reach his knee; nothing here should reach his
	# waist, and certainly not tower over him.
	_check(
		tallest > 0.0 and tallest < 0.8,
		"ground cover is ground-sized (tallest %.2fm, %s)" % [tallest, tallest_piece]
	)

	# Anything too small to read as a shadow should not be casting one. Bias is a
	# fixed distance regardless of how small the caster is, so on ankle-high cover
	# it pushes the shadow clear of its own base and the two visibly separate.
	#
	# Checked on the scene nodes rather than through the renderer: cast_shadow is a
	# property, not something that has to be drawn to be read.
	var batched: Node = builder.get_node_or_null("BatchedScenery")
	if batched != null:
		var shadowed_small: Array[String] = []
		var floor_height: float = float(builder.get_script().get_script_constant_map()["SHADOW_HEIGHT_FLOOR"])
		var tallest_by_batch: Dictionary = {}
		for placement: Dictionary in placements:
			var piece: String = placement["piece"]
			var height: float = float(placement.get("height", 0.0))
			if height > float(tallest_by_batch.get(piece, 0.0)):
				tallest_by_batch[piece] = height

		for child in batched.get_children():
			var instance := child as MultiMeshInstance3D
			if instance == null or not String(instance.name).begins_with("cover_"):
				continue
			if instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				continue
			# Still casting: every piece in it must clear the floor.
			for piece: String in tallest_by_batch.keys():
				if String(instance.name).contains(piece.replace("/", "_")):
					if float(tallest_by_batch[piece]) < floor_height:
						shadowed_small.append("%s (%.2fm)" % [piece, tallest_by_batch[piece]])

		_check(
			shadowed_small.is_empty(),
			"cover too small to read casts no shadow%s" % (
				"" if shadowed_small.is_empty() else " (%s)" % "; ".join(shadowed_small)
			)
		)

	# The apron under the forest must stay under the whole level.
	#
	# It sat 1.2 m below the height at the centre of the map, which was fine when
	# the ground was flat. With hills from -4.5 m to +8.3 m it surfaced through
	# every hollow as an enormous dark sheet with gravestones and trees standing in
	# it — it read as a flood, and things clipped through it because it is scenery
	# with no collision.
	var apron := builder.get_node_or_null("ForestFloor") as Node3D
	var terrain: Node = builder.call("get_terrain")
	if apron != null and terrain != null and terrain.has_method("get_lowest"):
		var lowest: float = float(terrain.call("get_lowest"))
		_check(
			apron.global_position.y < lowest,
			"the forest apron stays below the lowest ground (%.1fm against %.1fm)" % [
				apron.global_position.y, lowest
			]
		)

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

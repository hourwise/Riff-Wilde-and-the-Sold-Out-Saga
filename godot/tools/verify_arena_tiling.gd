extends SceneTree
## Verifies the arena's generated scenery actually tiles without gaps.
##
##   godot --headless --path godot --script res://tools/verify_arena_tiling.gd
##
## Loads the arena, measures the real spacing between adjacent generated floor
## pieces, and compares it to the pieces' own footprint. Reading tile size from
## the mesh rather than trusting the exported constant is the point: the two
## disagreeing is exactly the bug this catches.

const ARENA: String = "res://scenes/levels/PrototypeArena.tscn"


func _initialize() -> void:
	await process_frame
	change_scene_to_file(ARENA)
	for i in range(10):
		await process_frame

	var environment: Node = _find_environment(current_scene)
	if environment == null:
		print("FAIL: no EnvironmentBuilder node found")
		quit(1)
		return

	var floors: Array[Node3D] = []
	var walls: Array[Node3D] = []
	for child in environment.get_children():
		if not (child is Node3D):
			continue
		if String(child.name).begins_with("Floor"):
			floors.append(child as Node3D)
		elif String(child.name).begins_with("Wall"):
			walls.append(child as Node3D)

	print("\n=== Arena tiling ===")
	print("floor pieces: %d   wall pieces: %d" % [floors.size(), walls.size()])

	var failures: int = 0
	failures += _report("floor", floors, environment.get("floor_tile_size"))
	failures += _report("wall", walls, environment.get("wall_segment_size"))

	print("")
	if failures > 0:
		print("FAILED\n")
		quit(1)
		return
	print("PASSED\n")
	quit(0)


## Compares configured spacing against the piece's measured footprint, and against
## the smallest real gap between neighbours.
func _report(label: String, pieces: Array[Node3D], configured_spacing: Variant) -> int:
	if pieces.size() < 2:
		print("  %s: too few pieces to measure" % label)
		return 1

	var footprint: float = _footprint_width(pieces[0])
	var spacing: float = float(configured_spacing)

	print("  %s: footprint=%.2f  configured spacing=%.2f" % [label, footprint, spacing])

	var failures: int = 0
	if absf(spacing - footprint) > 0.05:
		print("    FAIL  spacing does not match the piece footprint — gap of %.2f per tile" % (spacing - footprint))
		failures += 1
	else:
		print("    ok    spacing matches the piece footprint")

	# Nearest-neighbour distance along the ground, as actually placed.
	var nearest: float = INF
	var sample: int = mini(pieces.size(), 60)
	for i in range(sample):
		for j in range(i + 1, sample):
			var a: Vector3 = pieces[i].global_position
			var b: Vector3 = pieces[j].global_position
			if absf(a.y - b.y) > 0.1:
				continue
			nearest = minf(nearest, Vector2(a.x - b.x, a.z - b.z).length())

	if is_inf(nearest):
		print("    (no coplanar neighbours sampled)")
		return failures

	print("    nearest neighbour distance: %.2f" % nearest)
	if nearest > footprint + 0.05:
		print("    FAIL  neighbours are %.2f apart but only %.2f wide" % [nearest, footprint])
		failures += 1
	else:
		print("    ok    neighbours touch")

	return failures


func _footprint_width(piece: Node3D) -> float:
	var bounds: AABB = AABB()
	var first: bool = true
	for node in _find_all(piece, "MeshInstance3D"):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var world_box: AABB = mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		bounds = world_box if first else bounds.merge(world_box)
		first = false
	return maxf(bounds.size.x, bounds.size.z)


func _find_environment(node: Node) -> Node:
	if node.get_script() != null and String(node.get_script().resource_path).ends_with("EnvironmentBuilder.gd"):
		return node
	for child in node.get_children():
		var found: Node = _find_environment(child)
		if found != null:
			return found
	return null


func _find_all(node: Node, type_name: String) -> Array:
	var found: Array = []
	if node.is_class(type_name):
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_all(child, type_name))
	return found

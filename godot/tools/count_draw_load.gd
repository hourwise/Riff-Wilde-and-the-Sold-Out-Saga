extends SceneTree
## Counts what the graveyard actually asks the GPU to draw.
##
##   godot --headless --path godot --script res://tools/count_draw_load.gd
##
## Target hardware for this project is an onboard GPU, where surface count is the
## thing that decides whether the level runs. Counted rather than estimated,
## because "it is only scenery" is how a level ends up at four thousand surfaces.

const LEVEL: String = "res://scenes/levels/ChurchGraveyard.tscn"


func _initialize() -> void:
	await process_frame
	change_scene_to_file(LEVEL)
	for i in range(60):
		await process_frame

	var meshes: int = 0
	var surfaces: int = 0
	var triangles: int = 0
	var multimesh_instances: int = 0
	var lights: int = 0
	var per_piece: Dictionary = {}

	for node in _walk(current_scene):
		if node is OmniLight3D or node is SpotLight3D:
			lights += 1
			continue

		var multimesh_node := node as MultiMeshInstance3D
		if multimesh_node != null and multimesh_node.multimesh != null:
			multimesh_instances += multimesh_node.multimesh.instance_count
			surfaces += multimesh_node.multimesh.mesh.get_surface_count() if multimesh_node.multimesh.mesh != null else 0
			continue

		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue

		meshes += 1
		surfaces += mesh_node.mesh.get_surface_count()
		for surface in range(mesh_node.mesh.get_surface_count()):
			var arrays: Array = mesh_node.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += indices.size() / 3 if not indices.is_empty() else 0

		var owner_name: String = String(mesh_node.get_parent().name)
		per_piece[owner_name] = int(per_piece.get(owner_name, 0)) + 1

	print("\n=== Draw load ===\n")
	print("  mesh instances       %d" % meshes)
	print("  surfaces (≈ draws)   %d" % surfaces)
	print("  triangles            %d" % triangles)
	print("  multimesh instances  %d" % multimesh_instances)
	print("  realtime lights      %d" % lights)

	var ranked: Array = per_piece.keys()
	ranked.sort_custom(func(a, b): return int(per_piece[a]) > int(per_piece[b]))
	print("\n  heaviest piece types:")
	for name: String in ranked.slice(0, 10):
		print("    %-28s %d" % [name, int(per_piece[name])])

	quit(0)


func _walk(node: Node) -> Array[Node]:
	var found: Array[Node] = [node]
	for child in node.get_children():
		found.append_array(_walk(child))
	return found

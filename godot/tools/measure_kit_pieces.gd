extends SceneTree
## Reports the footprint of static kit pieces, in kit units.
##
##   godot --headless --path godot --script res://tools/measure_kit_pieces.gd -- <piece> [...]
##
## Tiling geometry has to butt up exactly. Guessing a piece is "probably 2 units"
## is what left visible gaps between every tile in the prototype arena, twice. So
## walls and roads are measured before anything is laid out with them.

const KIT: String = "res://assets/environment/graveyard-kit"


func _initialize() -> void:
	var pieces: PackedStringArray = OS.get_cmdline_user_args()
	print("\n%-28s %8s %8s %8s" % ["piece", "x", "y", "z"])
	for piece: String in pieces:
		await _measure(piece)
	quit(0)


func _measure(piece: String) -> void:
	# Pack-qualified names, matching GraveyardBuilder: "forest/Grass_1_A_Color1".
	var path: String = "%s/%s.glb" % [KIT, piece]
	if piece.contains("/"):
		var pack: String = piece.substr(0, piece.find("/"))
		var name: String = piece.substr(piece.find("/") + 1)
		var directories: Dictionary = {
			"forest": "res://assets/kaykit/forest/Assets/gltf",
			"halloween": "res://assets/kaykit/halloween/Assets/gltf",
		}
		if directories.has(pack):
			path = "%s/%s.gltf" % [directories[pack], name]

	var packed := ResourceLoader.load(path) as PackedScene
	if packed == null:
		print("%-28s  not found" % piece)
		return

	var instance: Node3D = packed.instantiate()
	root.add_child(instance)
	await process_frame

	var bounds := AABB()
	var first: bool = true
	for visual: VisualInstance3D in _visuals(instance):
		var box: AABB = visual.global_transform * visual.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false

	if first:
		print("%-28s  no geometry" % piece)
	else:
		print("%-28s %8.3f %8.3f %8.3f" % [piece, bounds.size.x, bounds.size.y, bounds.size.z])

	instance.queue_free()
	await process_frame


func _visuals(node: Node) -> Array[VisualInstance3D]:
	var found: Array[VisualInstance3D] = []
	if node is VisualInstance3D:
		found.append(node as VisualInstance3D)
	for child in node.get_children():
		found.append_array(_visuals(child))
	return found

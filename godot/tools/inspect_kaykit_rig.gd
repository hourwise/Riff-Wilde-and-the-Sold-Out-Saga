extends SceneTree
## Checks whether a KayKit animation library can drive a KayKit character.
##
##   godot --headless --path godot --script res://tools/inspect_kaykit_rig.gd
##
## These packs ship the mesh and its animations as separate files that share a
## rig. Merging them only works if the animation's track paths resolve against
## the character's node structure, so both are printed side by side before any
## merging code is written.

const CHARACTER: String = "res://assets/kaykit/skeletons/characters/gltf/Skeleton_Warrior.glb"
const LIBRARY: String = "res://assets/kaykit/animations/Animations/gltf/Rig_Medium/Rig_Medium_General.glb"


func _initialize() -> void:
	await process_frame

	print("\n=== Character: %s" % CHARACTER.get_file())
	var character: Node = _instantiate(CHARACTER)
	if character != null:
		_describe(character, 1)
		var skeleton: Skeleton3D = _find(character, "Skeleton3D") as Skeleton3D
		if skeleton != null:
			print("  Skeleton3D path from root: %s" % character.get_path_to(skeleton))
			print("  bones: %d, first: %s" % [
				skeleton.get_bone_count(),
				", ".join(_bone_names(skeleton, 6)),
			])
		print("  AnimationPlayer present: %s" % str(_find(character, "AnimationPlayer") != null))

	print("\n=== Library: %s" % LIBRARY.get_file())
	var library: Node = _instantiate(LIBRARY)
	if library != null:
		_describe(library, 1)
		var player: AnimationPlayer = _find(library, "AnimationPlayer") as AnimationPlayer
		if player != null:
			print("  root_node: %s" % str(player.root_node))
			var clips: PackedStringArray = player.get_animation_list()
			print("  clips: %d" % clips.size())
			if clips.size() > 0:
				var anim: Animation = player.get_animation(clips[0])
				print("  sample clip '%s' tracks:" % clips[0])
				for i in range(mini(5, anim.get_track_count())):
					print("     %s" % str(anim.track_get_path(i)))
		var lib_skeleton: Skeleton3D = _find(library, "Skeleton3D") as Skeleton3D
		if lib_skeleton != null:
			print("  Skeleton3D path from root: %s" % library.get_path_to(lib_skeleton))
			print("  bones: %d, first: %s" % [
				lib_skeleton.get_bone_count(),
				", ".join(_bone_names(lib_skeleton, 6)),
			])

	print("")
	quit(0)


func _instantiate(path: String) -> Node:
	if not ResourceLoader.exists(path):
		print("  MISSING: %s" % path)
		return null
	var scene := ResourceLoader.load(path) as PackedScene
	if scene == null:
		print("  NOT A SCENE: %s" % path)
		return null
	var node: Node = scene.instantiate()
	root.add_child(node)
	return node


func _bone_names(skeleton: Skeleton3D, count: int) -> PackedStringArray:
	var names: PackedStringArray = []
	for i in range(mini(count, skeleton.get_bone_count())):
		names.append(skeleton.get_bone_name(i))
	return names


func _describe(node: Node, depth: int) -> void:
	print("%s%s [%s]" % ["  ".repeat(depth), node.name, node.get_class()])
	if depth >= 3:
		return
	for child in node.get_children():
		_describe(child, depth + 1)


func _find(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found: Node = _find(child, type_name)
		if found != null:
			return found
	return null

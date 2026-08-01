extends SceneTree
## Prints the node structure, skeleton and animation content of imported models.
##
##   godot --headless --path godot --script res://tools/inspect_model.gd -- <res://path> [...]
##
## Used to decide how a placeholder rig can be driven before committing to an
## AnimationTree layout.

func _initialize() -> void:
	var paths: PackedStringArray = OS.get_cmdline_user_args()
	if paths.is_empty():
		print("Usage: --script res://tools/inspect_model.gd -- <res://model.fbx> [...]")
		quit(1)
		return

	for path: String in paths:
		_inspect(path)

	quit(0)


func _inspect(path: String) -> void:
	print("\n════ %s" % path)

	if not ResourceLoader.exists(path):
		print("  MISSING")
		return

	var packed := ResourceLoader.load(path) as PackedScene
	if packed == null:
		print("  not a PackedScene")
		return

	var root: Node = packed.instantiate()
	_describe(root, 1)

	for player: AnimationPlayer in _find_all(root, "AnimationPlayer"):
		var names: PackedStringArray = player.get_animation_list()
		print("  AnimationPlayer '%s': %d animation(s)" % [player.name, names.size()])
		for anim_name: String in names:
			var anim: Animation = player.get_animation(anim_name)
			print("    - %-28s %6.2fs  %d track(s)  loop=%s" % [
				anim_name, anim.length, anim.get_track_count(), anim.loop_mode != Animation.LOOP_NONE
			])

	for skeleton: Skeleton3D in _find_all(root, "Skeleton3D"):
		print("  Skeleton3D '%s': %d bones" % [skeleton.name, skeleton.get_bone_count()])
		var sample: PackedStringArray = []
		for i in range(mini(12, skeleton.get_bone_count())):
			sample.append(skeleton.get_bone_name(i))
		print("    bones: %s%s" % [", ".join(sample), " ..." if skeleton.get_bone_count() > 12 else ""])

	root.free()


func _describe(node: Node, depth: int) -> void:
	print("%s%s [%s]" % ["  ".repeat(depth), node.name, node.get_class()])
	if depth >= 3:
		return
	for child in node.get_children():
		_describe(child, depth + 1)


func _find_all(node: Node, type_name: String) -> Array:
	var found: Array = []
	if node.is_class(type_name):
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_all(child, type_name))
	return found

extends SceneTree
## Measures a rigged model's real in-game size.
##
##   godot --headless --path godot --script res://tools/measure_model.gd -- <res://model> [...]
##
## Bind-pose AABBs and bone rests are unreliable on these packs — the rest pose is
## flattened and the real transforms live in the animation tracks. So the model is
## added to the tree, posed by its idle animation, and then measured.

func _initialize() -> void:
	var paths: PackedStringArray = OS.get_cmdline_user_args()
	for path: String in paths:
		await _measure(path)
	quit(0)


func _measure(path: String) -> void:
	print("\n════ %s" % path)

	var packed := ResourceLoader.load(path) as PackedScene
	if packed == null:
		print("  could not load")
		return

	var instance: Node3D = packed.instantiate()
	root.add_child(instance)
	await process_frame

	var player: AnimationPlayer = _find(instance, "AnimationPlayer") as AnimationPlayer
	var skeleton: Skeleton3D = _find(instance, "Skeleton3D") as Skeleton3D

	if player != null:
		# Idle if present, otherwise whatever comes first.
		var chosen: String = ""
		for name: String in player.get_animation_list():
			if name.to_lower().contains("idle"):
				chosen = name
				break
		if chosen == "" and player.get_animation_list().size() > 0:
			chosen = player.get_animation_list()[0]
		if chosen != "":
			player.play(chosen)
			player.seek(0.1, true)
			await process_frame
			await process_frame

	if skeleton != null:
		var low: Vector3 = Vector3.INF
		var high: Vector3 = -Vector3.INF
		for i in range(skeleton.get_bone_count()):
			var point: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(i)).origin
			low = Vector3(minf(low.x, point.x), minf(low.y, point.y), minf(low.z, point.z))
			high = Vector3(maxf(high.x, point.x), maxf(high.y, point.y), maxf(high.z, point.z))

		var size: Vector3 = high - low
		print("  posed bone extent: size=%s  min_y=%.3f" % [str(size.snapped(Vector3.ONE * 0.001)), low.y])
		if size.y > 0.0001:
			# Bones sit inside the silhouette, so the visible model is a little
			# taller than the bone extent.
			print("  scale for a 1.8m character: %.1f" % (1.8 / size.y))

	instance.queue_free()
	await process_frame


func _find(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found: Node = _find(child, type_name)
		if found != null:
			return found
	return null

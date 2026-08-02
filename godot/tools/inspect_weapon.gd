extends SceneTree
## Reports where the player's weapon actually is, and which way round it is.
##
##   godot --headless --path godot --script res://tools/inspect_weapon.gd
##
## A weapon parented to a bone has three independent ways to go wrong — the bone
## may not resolve, the offset may put it inside the character, and the model may
## be gripped by the wrong end — and all three look identical from the outside:
## you cannot see it. So all three are reported rather than guessed at.

const PLAYER: String = "res://scenes/player/Player.tscn"
const LUTE: String = "res://assets/weapons/lute_bludgeon.glb"


func _initialize() -> void:
	await process_frame
	await _inspect_model()
	await _inspect_in_player()
	quit(0)


## The weapon on its own, in its own space, so the grip can be reasoned about.
func _inspect_model() -> void:
	print("\n════ the lute model, untransformed")

	var packed := ResourceLoader.load(LUTE) as PackedScene
	if packed == null:
		print("  could not load %s" % LUTE)
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
		print("  no geometry")
		instance.queue_free()
		return

	print("  size    %.3f x %.3f x %.3f" % [bounds.size.x, bounds.size.y, bounds.size.z])
	print("  centre  (%.3f, %.3f, %.3f)" % [
		bounds.get_center().x, bounds.get_center().y, bounds.get_center().z
	])
	print("  origin sits at %.0f%% along its longest axis" % [_origin_fraction(bounds) * 100.0])

	# A guitar is a wide body and a narrow neck. Slicing along the long axis and
	# measuring the girth of each slice says which end is which — which is the
	# thing that decides whether the player is holding the neck or the body.
	var axis: int = _longest_axis(bounds)
	print("  longest axis: %s" % ["X", "Y", "Z"][axis])
	print("  girth along that axis (start -> end):")
	print("    %s" % _girth_profile(instance, bounds, axis))

	instance.queue_free()
	await process_frame


## The weapon as the player scene actually configures it.
func _inspect_in_player() -> void:
	print("\n════ as mounted on the player")

	var packed := ResourceLoader.load(PLAYER) as PackedScene
	var player: Node3D = packed.instantiate()
	root.add_child(player)
	for i in range(4):
		await process_frame

	# Posed before measuring. In the rest pose the arms are wherever the exporter
	# left them, and a grip judged against that tells you nothing about the game.
	var character_visual: Node = _find(player, "CharacterVisual")
	if character_visual != null:
		character_visual.call("reset")
	for i in range(10):
		await process_frame

	var socket := _find(player, "WeaponSocket") as BoneAttachment3D
	if socket == null:
		print("  no WeaponSocket found")
		return

	# Fitted explicitly: the socket defers its fit to the next idle frame, and
	# measuring before that reports the unfitted weapon.
	if socket.has_method("fit_now"):
		socket.call("fit_now")
	await process_frame

	var skeleton := socket.get_parent() as Skeleton3D
	print("  socket bone name   %s" % socket.bone_name)
	print("  socket bone index  %d%s" % [
		socket.bone_idx,
		"   <-- UNRESOLVED, the socket is stuck at the skeleton origin" if socket.bone_idx < 0 else ""
	])
	if skeleton != null:
		var names: PackedStringArray = []
		for i in range(skeleton.get_bone_count()):
			names.append(skeleton.get_bone_name(i))
		print("  skeleton bones     %s" % ", ".join(names))

	# Where the character actually stands. A weapon can be gripped perfectly on a
	# character who is buried to the waist, and the grip numbers would not say so.
	if skeleton != null:
		var lowest: float = INF
		var highest: float = -INF
		var lowest_bone: String = ""
		for i in range(skeleton.get_bone_count()):
			var y: float = (skeleton.global_transform * skeleton.get_bone_global_pose(i)).origin.y
			if y < lowest:
				lowest = y
				lowest_bone = skeleton.get_bone_name(i)
			highest = maxf(highest, y)
		print("  lowest bone        %s at y=%.2f%s" % [
			lowest_bone, lowest,
			"   <-- BURIED" if lowest < -0.04 else ""
		])
		print("  highest bone       y=%.2f (so %.2fm of character)" % [highest, highest - lowest])

	var lute: Node3D = null
	for child in socket.get_children():
		lute = child as Node3D
		if lute != null:
			break

	if lute == null:
		print("  nothing parented to the socket")
		return

	print("  lute visible flag  %s" % str(lute.visible))
	print("  lute in world      (%.2f, %.2f, %.2f)" % [
		lute.global_position.x, lute.global_position.y, lute.global_position.z
	])
	print("  lute world scale   %.3f" % lute.global_transform.basis.get_scale().x)

	var bounds := AABB()
	var first: bool = true
	for visual: VisualInstance3D in _visuals(lute):
		if not visual.is_visible_in_tree():
			print("  HIDDEN: %s is not visible in tree" % visual.name)
		var box: AABB = visual.global_transform * visual.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false

	if first:
		print("  the lute has no geometry at all")
		return

	print("  world size         %.2f x %.2f x %.2f" % [bounds.size.x, bounds.size.y, bounds.size.z])
	print("  world centre       (%.2f, %.2f, %.2f)" % [
		bounds.get_center().x, bounds.get_center().y, bounds.get_center().z
	])

	var hand: Vector3 = socket.global_position
	print("  hand (socket) at   (%.2f, %.2f, %.2f)" % [hand.x, hand.y, hand.z])

	# Which way the bone's own axes point in the world. strike_direction is
	# expressed in this space, so it cannot be chosen without seeing them.
	var bone: Basis = socket.global_transform.basis.orthonormalized()
	print("  bone +X in world   (%+.2f, %+.2f, %+.2f)" % [bone.x.x, bone.x.y, bone.x.z])
	print("  bone +Y in world   (%+.2f, %+.2f, %+.2f)" % [bone.y.x, bone.y.y, bone.y.z])
	print("  bone +Z in world   (%+.2f, %+.2f, %+.2f)" % [bone.z.x, bone.z.y, bone.z.z])

	# Where each end of the instrument ends up. The striking end is the fat body;
	# it should reach away from the hand, not into the character.
	var local: AABB = _local_bounds(lute)
	var axis: int = _longest_axis(local)
	var low: Vector3 = local.get_center()
	var high: Vector3 = local.get_center()
	low[axis] = local.position[axis]
	high[axis] = local.position[axis] + local.size[axis]

	var body_end: Vector3 = lute.global_transform * low
	var head_end: Vector3 = lute.global_transform * high
	print("  body (striking) at (%.2f, %.2f, %.2f), %.2fm from the hand" % [
		body_end.x, body_end.y, body_end.z, body_end.distance_to(hand)
	])
	print("  headstock at       (%.2f, %.2f, %.2f), %.2fm from the hand" % [
		head_end.x, head_end.y, head_end.z, head_end.distance_to(hand)
	])
	print("  body points        (%+.2f, %+.2f, %+.2f) in world" % [
		(body_end - hand).normalized().x,
		(body_end - hand).normalized().y,
		(body_end - hand).normalized().z,
	])
	if body_end.distance_to(hand) < head_end.distance_to(hand):
		print("  WRONG WAY ROUND: the headstock reaches further than the body")


# ── Helpers ──────────────────────────────────────────────────────

func _longest_axis(bounds: AABB) -> int:
	if bounds.size.x >= bounds.size.y and bounds.size.x >= bounds.size.z:
		return 0
	return 1 if bounds.size.y >= bounds.size.z else 2


func _origin_fraction(bounds: AABB) -> float:
	var axis: int = _longest_axis(bounds)
	var low: float = bounds.position[axis]
	var span: float = bounds.size[axis]
	return 0.0 if span <= 0.0 else clampf((0.0 - low) / span, 0.0, 1.0)


## Cross-sectional size in eight slices along the long axis, as a crude bar chart.
func _girth_profile(node: Node3D, bounds: AABB, axis: int) -> String:
	var slices: int = 8
	var widest: Array[float] = []
	for i in range(slices):
		widest.append(0.0)

	for visual: VisualInstance3D in _visuals(node):
		var mesh_node := visual as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		for surface in range(mesh_node.mesh.get_surface_count()):
			var arrays: Array = mesh_node.mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for point: Vector3 in points:
				var t: float = (point[axis] - bounds.position[axis]) / maxf(bounds.size[axis], 0.0001)
				var slot: int = clampi(int(t * float(slices)), 0, slices - 1)
				var girth: float = Vector2(
					point[(axis + 1) % 3], point[(axis + 2) % 3]
				).length()
				widest[slot] = maxf(widest[slot], girth)

	var peak: float = 0.0
	for value: float in widest:
		peak = maxf(peak, value)

	var bars: PackedStringArray = []
	for value: float in widest:
		bars.append("%.2f" % value)
	return " ".join(bars)


func _local_bounds(node: Node3D) -> AABB:
	var into: Transform3D = node.global_transform.affine_inverse()
	var bounds := AABB()
	var first: bool = true
	for visual: VisualInstance3D in _visuals(node):
		var box: AABB = into * visual.global_transform * visual.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds


func _visuals(node: Node) -> Array[VisualInstance3D]:
	var found: Array[VisualInstance3D] = []
	if node is VisualInstance3D:
		found.append(node as VisualInstance3D)
	for child in node.get_children():
		found.append_array(_visuals(child))
	return found


func _find(node: Node, name: String) -> Node:
	if node.name == name:
		return node
	for child in node.get_children():
		var found: Node = _find(child, name)
		if found != null:
			return found
	return null

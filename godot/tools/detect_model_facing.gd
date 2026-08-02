extends SceneTree
## Determines which way each character actually faces, and whether its configured
## yaw correction is right.
##
##   godot --headless --path godot --script res://tools/detect_model_facing.gd
##
## Model facing has been got wrong three times by assuming a vendor's convention.
## It is not guessable — packs differ, and the same vendor differs between packs.
## So it is measured instead.
##
## The signal is the foot: on any humanoid rig the toe bone sits in front of the
## ankle, so the vector from foot to toes points where the character faces. That
## holds regardless of naming, art style or rest pose.

const SUBJECTS: Array[Dictionary] = [
	{"label": "Player", "path": "res://scenes/player/Player.tscn"},
	{"label": "Tone Deaf", "path": "res://scenes/enemies/ToneDeaf.tscn"},
	{"label": "Grave Crawler", "path": "res://scenes/enemies/GraveCrawler.tscn"},
	{"label": "Hollow Choir", "path": "res://scenes/enemies/HollowChoir.tscn"},
	{"label": "Bone Bell Ringer", "path": "res://scenes/enemies/BoneBellRinger.tscn"},
	{"label": "Dirge Cantor", "path": "res://scenes/enemies/DirgeCantor.tscn"},
]

var _wrong: int = 0


func _initialize() -> void:
	await process_frame
	print("\n=== Model facing ===\n")

	for subject: Dictionary in SUBJECTS:
		await _check(String(subject["label"]), String(subject["path"]))

	print("")
	if _wrong > 0:
		print("%d character(s) face the wrong way.\n" % _wrong)
		quit(1)
		return
	print("All characters face forward.\n")
	quit(0)


func _check(label: String, path: String) -> void:
	if not ResourceLoader.exists(path):
		print("  %-18s MISSING" % label)
		return

	var scene := ResourceLoader.load(path) as PackedScene
	var instance := scene.instantiate() as Node3D
	root.add_child(instance)
	await process_frame
	await process_frame

	var visual: Node3D = _find_character_visual(instance)
	var skeleton: Skeleton3D = _find(instance, "Skeleton3D") as Skeleton3D

	if visual == null or skeleton == null:
		print("  %-18s no CharacterVisual or Skeleton3D" % label)
		instance.queue_free()
		await process_frame
		return

	var forward: Vector3 = _measure_forward(visual, skeleton)
	if forward == Vector3.ZERO:
		print("  %-18s no foot/toe bones to measure from" % label)
		instance.queue_free()
		await process_frame
		return

	# Godot's forward is -Z. A positive Z component means the model is turned away.
	var faces_forward: bool = forward.z < 0.0
	var configured: float = float(visual.get("model_yaw_degrees"))
	var needed: float = configured if faces_forward else _flip(configured)

	print("  %-18s toes point %s  yaw=%.0f  %s" % [
		label,
		"-Z (correct)" if faces_forward else "+Z (BACKWARDS)",
		configured,
		"ok" if faces_forward else "-> set model_yaw_degrees = %.0f" % needed,
	])

	if not faces_forward:
		_wrong += 1

	instance.queue_free()
	await process_frame


## Foot-to-toes, expressed in the CharacterVisual's own space so the configured
## yaw correction is included in the result.
func _measure_forward(visual: Node3D, skeleton: Skeleton3D) -> Vector3:
	var foot_index: int = -1
	var toe_index: int = -1

	for i in range(skeleton.get_bone_count()):
		var bone: String = skeleton.get_bone_name(i).to_lower()
		if toe_index < 0 and bone.contains("toe"):
			toe_index = i
		elif foot_index < 0 and bone.contains("foot") and not bone.contains("toe"):
			foot_index = i

	if foot_index < 0 or toe_index < 0:
		return Vector3.ZERO

	var to_visual: Transform3D = visual.global_transform.affine_inverse() * skeleton.global_transform
	var foot: Vector3 = (to_visual * skeleton.get_bone_global_pose(foot_index)).origin
	var toes: Vector3 = (to_visual * skeleton.get_bone_global_pose(toe_index)).origin

	var forward: Vector3 = toes - foot
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.0001 else Vector3.ZERO


func _flip(yaw: float) -> float:
	var flipped: float = yaw + 180.0
	return flipped - 360.0 if flipped > 180.0 else flipped


func _find_character_visual(node: Node) -> Node3D:
	if node.get_script() != null and String(node.get_script().resource_path).ends_with("CharacterVisual.gd"):
		return node as Node3D
	for child in node.get_children():
		var found: Node3D = _find_character_visual(child)
		if found != null:
			return found
	return null


func _find(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found: Node = _find(child, type_name)
		if found != null:
			return found
	return null

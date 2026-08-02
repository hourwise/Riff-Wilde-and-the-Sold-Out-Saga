extends SceneTree
## Reports the real in-world height of everything the player sees side by side.
##
##   godot --headless --path godot --script res://tools/measure_scene_scale.gd
##
## Scale has been guessed wrong repeatedly because each pack is authored at its
## own size and a scene transform hides the result. This measures the visible
## meshes as actually placed, so relative sizes can be judged as numbers rather
## than by eye.

const SUBJECTS: Array[Dictionary] = [
	{"label": "Player (Warrior)", "path": "res://scenes/player/Player.tscn"},
	{"label": "Tone Deaf", "path": "res://scenes/enemies/ToneDeaf.tscn"},
	{"label": "Grave Crawler", "path": "res://scenes/enemies/GraveCrawler.tscn"},
	{"label": "Hollow Choir", "path": "res://scenes/enemies/HollowChoir.tscn"},
	{"label": "Bone Bell Ringer", "path": "res://scenes/enemies/BoneBellRinger.tscn"},
]

const KIT: String = "res://assets/environment/graveyard-kit"
## Scenery is scaled by GraveyardBuilder at runtime, so the raw model height is
## multiplied by the same factor to get what actually appears in the level.
const KIT_SCALE: float = 2.0
## Category multipliers mirror GraveyardBuilder so this reports what the level
## actually shows, not the raw model size.
const SCENERY: Array[Dictionary] = [
	{"label": "Pine tree", "piece": "pine", "mult": 1.15},
	{"label": "Gravestone (cross)", "piece": "gravestone-cross", "mult": 0.65},
	{"label": "Crypt (large)", "piece": "crypt-large", "mult": 1.8},
	{"label": "Lightpost", "piece": "lightpost-single", "mult": 1.05},
	{"label": "Iron fence", "piece": "iron-fence", "mult": 0.75},
]


func _initialize() -> void:
	await process_frame
	print("\n=== Real in-world heights ===\n")

	for subject: Dictionary in SUBJECTS:
		await _report(String(subject["label"]), String(subject["path"]), 1.0)

	for piece: Dictionary in SCENERY:
		var path: String = "%s/%s.glb" % [KIT, piece["piece"]]
		await _report(String(piece["label"]), path, KIT_SCALE * float(piece["mult"]))

	print("")
	quit(0)


func _report(label: String, path: String, extra_scale: float) -> void:
	if not ResourceLoader.exists(path):
		print("  %-22s MISSING" % label)
		return

	var scene := ResourceLoader.load(path) as PackedScene
	var instance := scene.instantiate() as Node3D
	root.add_child(instance)

	# Skinned meshes need a posed frame before their bounds mean anything.
	var player: AnimationPlayer = _find(instance, "AnimationPlayer") as AnimationPlayer
	if player != null:
		for clip: String in player.get_animation_list():
			if clip.to_lower().contains("idle"):
				player.play(clip)
				player.seek(0.1, true)
				break
	await process_frame
	await process_frame

	var height: float = _visible_height(instance) * extra_scale
	print("  %-22s %.2f m" % [label, height])

	instance.queue_free()
	await process_frame


## Uses the rendered AABB of every visible mesh, which accounts for skinning and
## for the scale applied in the scene, unlike a raw mesh resource's bounds.
func _visible_height(node: Node) -> float:
	var low: float = INF
	var high: float = -INF

	for found in _find_all(node, "VisualInstance3D"):
		var visual := found as VisualInstance3D
		var box: AABB = visual.global_transform * visual.get_aabb()
		low = minf(low, box.position.y)
		high = maxf(high, box.position.y + box.size.y)

	return 0.0 if is_inf(low) else high - low


func _find(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found: Node = _find(child, type_name)
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

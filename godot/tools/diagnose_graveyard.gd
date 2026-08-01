extends SceneTree
## One-off diagnostics for reported problems in the Church Graveyard.
##
##   godot --headless --path godot --script res://tools/diagnose_graveyard.gd
##
## Reports what scenery materials actually contain, and measures how fast an
## enemy really travels versus the speed its stats promise.

const LEVEL: String = "res://scenes/levels/ChurchGraveyard.tscn"
const KIT: String = "res://assets/environment/graveyard-kit"


func _initialize() -> void:
	await process_frame
	_report_materials()
	await _report_enemy_movement()
	quit(0)


## White scenery usually means the albedo texture never made it onto the material.
func _report_materials() -> void:
	print("\n=== Scenery materials ===")

	for piece: String in ["gravestone-cross", "pine", "crypt", "iron-fence", "road"]:
		var path: String = "%s/%s.glb" % [KIT, piece]
		var scene := ResourceLoader.load(path) as PackedScene
		if scene == null:
			print("  %s: FAILED TO LOAD" % piece)
			continue

		var instance: Node = scene.instantiate()
		var mesh_instance: MeshInstance3D = _find_mesh(instance)
		if mesh_instance == null or mesh_instance.mesh == null:
			print("  %s: no mesh" % piece)
			instance.free()
			continue

		var surfaces: int = mesh_instance.mesh.get_surface_count()
		var description: String = "%s: %d surface(s)" % [piece, surfaces]
		for surface in range(surfaces):
			var material := mesh_instance.get_active_material(surface) as StandardMaterial3D
			if material == null:
				description += " | surface %d has no StandardMaterial3D" % surface
				continue
			var texture: Texture2D = material.albedo_texture
			description += " | albedo=%s texture=%s vertex_colour=%s" % [
				str(material.albedo_color),
				"yes" if texture != null else "NONE",
				str(material.vertex_color_use_as_albedo),
			]
		print("  " + description)
		instance.free()


## Measures real travel speed. "Running on the spot" is either the animation
## outpacing the movement or the movement being blocked; only measuring separates
## the two.
func _report_enemy_movement() -> void:
	print("\n=== Enemy movement ===")

	change_scene_to_file(LEVEL)
	for i in range(40):
		await process_frame

	var level: Node = current_scene
	var players: Array[Node] = get_nodes_in_group("player")
	if players.is_empty():
		print("  no player")
		return

	var player := players[0] as Node3D

	# Wait for navigation, since pathing is a prime suspect.
	var waited: int = 0
	while not bool(level.call("is_navigation_ready")) and waited < 600:
		waited += 1
		await process_frame
	for i in range(10):
		await physics_frame
	print("  navigation ready after %d frames" % waited)

	var enemy_scene := load("res://scenes/enemies/ToneDeaf.tscn") as PackedScene
	var enemy := enemy_scene.instantiate() as Node3D
	level.add_child(enemy)
	enemy.global_position = player.global_position + Vector3(0.0, 0.0, -14.0)
	for i in range(10):
		await physics_frame

	var stats: Resource = enemy.get("stats")
	var expected: float = float(stats.get("move_speed")) if stats != null else 0.0
	print("  stated move_speed: %.2f m/s" % expected)

	var agent := enemy.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if agent != null:
		print("  agent map valid: %s | navigation finished: %s" % [
			str(agent.get_navigation_map().is_valid()), str(agent.is_navigation_finished())
		])

	for sample in range(4):
		var start: Vector3 = enemy.global_position
		var frames: int = 60
		for i in range(frames):
			await physics_frame
		var travelled: float = start.distance_to(enemy.global_position)
		var seconds: float = float(frames) / 60.0
		var speed_now: float = Vector2(enemy.velocity.x, enemy.velocity.z).length()
		print("  sample %d: travelled %.2f m in %.2f s (%.2f m/s) | velocity %.2f | state %d | on_floor %s" % [
			sample, travelled, seconds, travelled / seconds, speed_now,
			int(enemy.get("current_state")), str(enemy.is_on_floor())
		])

	enemy.queue_free()


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found: MeshInstance3D = _find_mesh(child)
		if found != null:
			return found
	return null

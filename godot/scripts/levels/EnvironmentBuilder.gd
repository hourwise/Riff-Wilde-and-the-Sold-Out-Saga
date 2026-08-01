extends Node3D
## EnvironmentBuilder — Procedurally builds arena scenery from the Ultimate Modular Ruins Pack.
## Attach to the "Environment" node in PrototypeArena.tscn.
## Tiles floor, walls, corners, and trees using glTF pieces while keeping
## existing CSGBox3D platforms and ramps intact.

# ── Arena dimensions ─────────────────────────────────────────────
@export var arena_size: float = 50.0         ## Total width/depth of the square arena.
@export var wall_height_levels: int = 2       ## How many wall segments to stack vertically.

# ── Tile sizes (tune these to match your glTF piece dimensions) ──
@export var floor_tile_size: float = 4.0      ## Width/depth of one floor tile.
@export var wall_segment_size: float = 4.0    ## Width of one wall segment.
@export var wall_segment_height: float = 4.0  ## Height of one wall segment.

# ── glTF resource paths ──────────────────────────────────────────
@export var floor_piece_path: String = "res://glTF/Floor_Brick.gltf"
@export var wall_piece_path: String = "res://glTF/Wall_Plaster_Straight.gltf"
@export var wall_piece_variant_path: String = "res://glTF/Wall_UnevenBrick_Straight.gltf"
@export var corner_piece_path: String = "res://glTF/Corner_Exterior_Brick.gltf"
@export var tree_piece_path: String = "res://Models/GLTF format/tree_tall.glb"
@export var tree_thin_path: String = "res://Models/GLTF format/tree_thin.glb"

# ── Spawn probabilities ──────────────────────────────────────────
@export_range(0.0, 1.0) var variant_wall_chance: float = 0.35
@export_range(0.0, 1.0) var tree_spawn_chance: float = 0.4     ## Chance a tree spawns at each perimeter slot.
@export var tree_offset_distance: float = 4.0                   ## How far outside walls trees sit.

# ── Internal ─────────────────────────────────────────────────────
var _floor_scene: PackedScene
var _wall_scene: PackedScene
var _wall_variant_scene: PackedScene
var _corner_scene: PackedScene
var _tree_scene: PackedScene
var _tree_thin_scene: PackedScene


func _ready() -> void:
	print("[EnvironmentBuilder] Building arena scenery...")
	_preload_resources()
	_build_floor()
	_build_walls()
	_build_corners()
	_build_trees()
	_build_collision_floor()
	print("[EnvironmentBuilder] Arena scenery complete.")


func _preload_resources() -> void:
	_floor_scene = _safe_load(floor_piece_path) as PackedScene
	_wall_scene = _safe_load(wall_piece_path) as PackedScene
	_wall_variant_scene = _safe_load(wall_piece_variant_path) as PackedScene
	_corner_scene = _safe_load(corner_piece_path) as PackedScene
	_tree_scene = _safe_load(tree_piece_path) as PackedScene
	_tree_thin_scene = _safe_load(tree_thin_path) as PackedScene


func _safe_load(path: String) -> Resource:
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res:
			return res
		else:
			push_warning("[EnvironmentBuilder] Failed to load: %s" % path)
	else:
		push_warning("[EnvironmentBuilder] Resource not found: %s" % path)
	return null


# ── Floor ────────────────────────────────────────────────────────

func _build_floor() -> void:
	if not _floor_scene:
		push_warning("[EnvironmentBuilder] No floor scene loaded. Skipping floor.")
		return

	var half: float = arena_size / 2.0
	var tile_count: int = maxi(1, int(ceil(arena_size / floor_tile_size)))
	var start_offset: float = -half + floor_tile_size / 2.0

	for x: int in range(tile_count):
		for z: int in range(tile_count):
			var pos_x: float = start_offset + float(x) * floor_tile_size
			var pos_z: float = start_offset + float(z) * floor_tile_size
			_place_piece(_floor_scene, Vector3(pos_x, 0.0, pos_z), Vector3.ZERO, "Floor")


# ── Walls ────────────────────────────────────────────────────────

func _build_walls() -> void:
	if not _wall_scene:
		push_warning("[EnvironmentBuilder] No wall scene loaded. Skipping walls.")
		return

	var half: float = arena_size / 2.0
	var seg_count: int = maxi(1, int(ceil(arena_size / wall_segment_size)))
	var start_offset: float = -half + wall_segment_size / 2.0

	# Build each cardinal wall: [position_along_wall, wall_z, wall_x, yaw_rotation]
	var wall_defs: Array[Dictionary] = [
		{"along": Vector3(1, 0, 0),  "fixed_z": -half, "yaw": deg_to_rad(0.0)},    # North
		{"along": Vector3(1, 0, 0),  "fixed_z":  half, "yaw": deg_to_rad(180.0)},  # South
		{"along": Vector3(0, 0, 1),  "fixed_x": -half, "yaw": deg_to_rad(90.0)},   # West
		{"along": Vector3(0, 0, 1),  "fixed_x":  half, "yaw": deg_to_rad(-90.0)},  # East
	]

	for wdef: Dictionary in wall_defs:
		for seg: int in range(seg_count):
			var pos_along: float = start_offset + float(seg) * wall_segment_size

			# Skip corner positions — corners get dedicated pieces.
			var dist_from_end: float = absf(pos_along) + wall_segment_size / 2.0
			if dist_from_end >= half - wall_segment_size * 0.6:
				continue

			var pos: Vector3
			if wdef.has("fixed_z"):
				pos = Vector3(pos_along, 0.0, wdef["fixed_z"])
			else:
				pos = Vector3(wdef["fixed_x"], 0.0, pos_along)

			var yaw: float = wdef["yaw"]

			for level: int in range(wall_height_levels):
				var height_offset: float = wall_segment_height / 2.0 + float(level) * wall_segment_height
				var stacked_pos: Vector3 = Vector3(pos.x, height_offset, pos.z)

				# Mix in variant wall pieces occasionally.
				var scene: PackedScene = _wall_variant_scene if (_wall_variant_scene and randf() < variant_wall_chance) else _wall_scene
				_place_piece(scene, stacked_pos, Vector3(0.0, yaw, 0.0), "Wall")


# ── Corners ──────────────────────────────────────────────────────

func _build_corners() -> void:
	if not _corner_scene:
		push_warning("[EnvironmentBuilder] No corner scene loaded. Skipping corners.")
		return

	var half: float = arena_size / 2.0
	var corner_yaws: Array[float] = [deg_to_rad(0.0), deg_to_rad(90.0), deg_to_rad(180.0), deg_to_rad(-90.0)]
	var corner_positions: Array[Vector3] = [
		Vector3(-half, 0.0, -half),
		Vector3( half, 0.0, -half),
		Vector3( half, 0.0,  half),
		Vector3(-half, 0.0,  half),
	]

	for i: int in range(4):
		for level: int in range(wall_height_levels):
			var h: float = wall_segment_height / 2.0 + float(level) * wall_segment_height
			var pos: Vector3 = Vector3(corner_positions[i].x, h, corner_positions[i].z)
			_place_piece(_corner_scene, pos, Vector3(0.0, corner_yaws[i], 0.0), "Corner")


# ── Trees ────────────────────────────────────────────────────────

func _build_trees() -> void:
	if not _tree_scene:
		print("[EnvironmentBuilder] No tree scene loaded. Skipping trees.")
		return

	var half: float = arena_size / 2.0 + tree_offset_distance
	var spacing: float = 5.0
	var count: int = maxi(1, int(ceil(arena_size / spacing)))

	for side: int in range(4):
		for i: int in range(count):
			if randf() > tree_spawn_chance:
				continue

			var along: float = -half + float(i) * spacing + randf_range(-1.0, 1.0)
			var pos: Vector3

			match side:
				0: pos = Vector3(along, 0.0, -half)  # North perimeter
				1: pos = Vector3(along, 0.0,  half)  # South perimeter
				2: pos = Vector3(-half, 0.0, along)  # West perimeter
				3: pos = Vector3( half, 0.0, along)  # East perimeter

			# Mix in thin trees.
			var scene: PackedScene = _tree_thin_scene if (_tree_thin_scene and randf() < 0.5) else _tree_scene
			var yaw: float = randf_range(0.0, TAU)
			var scale: float = randf_range(0.8, 1.3)
			_place_piece(scene, pos, Vector3(0.0, yaw, 0.0), "Tree", Vector3(scale, scale, scale))


# ── Collision floor (invisible physics ground) ───────────────────

func _build_collision_floor() -> void:
	# Place a large invisible StaticBody3D under everything to ensure
	# reliable floor collision regardless of individual piece colliders.
	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	body.collision_layer = 1
	body.collision_mask = 1

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(arena_size, 0.2, arena_size)
	shape.shape = box
	shape.position = Vector3(0.0, -0.1, 0.0)
	body.add_child(shape)
	add_child(body)


# ── Helpers ──────────────────────────────────────────────────────

func _place_piece(scene: PackedScene, position: Vector3, rotation_euler: Vector3, label: String, scale_override: Vector3 = Vector3.ONE) -> void:
	if not scene:
		return

	var instance: Node = scene.instantiate()
	instance.name = "%s_%d" % [label, get_child_count()]
	add_child(instance)

	if instance is Node3D:
		var node3d := instance as Node3D
		node3d.position = position
		node3d.rotation = rotation_euler
		node3d.scale = scale_override

		# Ensure the piece has collision by adding a StaticBody3D sibling if needed.
		_ensure_collision(node3d)


func _ensure_collision(node: Node3D) -> void:
	# Check if the imported glTF already has collision shapes.
	if _has_collision_descendant(node):
		return

	# Create a simple collision body from the mesh bounds.
	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(node, meshes)

	if meshes.is_empty():
		return

	var body := StaticBody3D.new()
	body.name = "CollisionBody"

	for mesh_instance: MeshInstance3D in meshes:
		var mesh: Mesh = mesh_instance.mesh
		if not mesh:
			continue

		var collision_shape := CollisionShape3D.new()
		var trimesh := ConcavePolygonShape3D.new()
		trimesh.set_faces(mesh.get_faces())
		collision_shape.shape = trimesh
		collision_shape.transform = mesh_instance.transform
		body.add_child(collision_shape)

	node.add_child(body)


func _has_collision_descendant(node: Node) -> bool:
	for child in node.get_children():
		if child is CollisionShape3D or child is StaticBody3D or child is CharacterBody3D or child is RigidBody3D:
			return true
		if _has_collision_descendant(child):
			return true
	return false


func _collect_mesh_instances(node: Node, out_array: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out_array.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_mesh_instances(child, out_array)

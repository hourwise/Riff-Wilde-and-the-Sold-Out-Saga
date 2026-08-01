class_name ChurchBuilder
extends Node3D
## Assembles the church from the medieval modular kit.
##
## The church is the cemetery's landmark: ADR-0002 requires it to stay visible
## throughout the level so the player always has a bearing. That makes the bell
## tower the most important silhouette in the demo, so it is built tall and set
## on the far side of the courtyard where it reads against the sky from the gate.
##
## Every dimension below comes from measuring the kit, not from guessing. Walls
## are 2.0 wide by 3.123 tall and BOTTOM-anchored — their origin is at the base,
## so a level is stacked by multiplying, never by offsetting half a height.

const KIT: String = "res://glTF"

const WALL_WIDTH: float = 2.0
const WALL_HEIGHT: float = 3.123

## Nave footprint in wall modules. Odd width so a door can sit centred.
@export var nave_width_modules: int = 5
@export var nave_length_modules: int = 8
@export var nave_storeys: int = 2

## The tower is what the player navigates by, so it is deliberately taller than
## anything else in the level.
@export var tower_storeys: int = 4
@export var tower_offset: Vector2 = Vector2(0.0, -9.0)

## Where the bell hangs, relative to this node. The ChurchBell node is placed here.
var bell_position: Vector3 = Vector3.ZERO

var _scene_cache: Dictionary = {}
var _pieces: Node3D = null


func _ready() -> void:
	build()


func build() -> void:
	_pieces = Node3D.new()
	_pieces.name = "Pieces"
	add_child(_pieces)

	_build_floor()
	_build_nave()
	_build_roof()
	_build_tower()
	_build_collision()

	print("[ChurchBuilder] Church built: %d pieces." % _pieces.get_child_count())


# ── Nave ─────────────────────────────────────────────────────────

func _build_floor() -> void:
	var half_x: float = float(nave_width_modules) * WALL_WIDTH * 0.5
	var half_z: float = float(nave_length_modules) * WALL_WIDTH * 0.5

	var x: float = -half_x + WALL_WIDTH * 0.5
	while x < half_x:
		var z: float = -half_z + WALL_WIDTH * 0.5
		while z < half_z:
			_place("Floor_Brick", Vector3(x, 0.02, z), 0.0)
			z += WALL_WIDTH
		x += WALL_WIDTH


## Four walls of stacked modules. The south face carries the door, the long faces
## carry windows — the openings are what stop it reading as a shed.
func _build_nave() -> void:
	var half_x: float = float(nave_width_modules) * WALL_WIDTH * 0.5
	var half_z: float = float(nave_length_modules) * WALL_WIDTH * 0.5
	var centre_module: int = nave_width_modules / 2

	for storey in range(nave_storeys):
		var y: float = float(storey) * WALL_HEIGHT

		# South wall, facing the player's approach. Ground floor gets the door.
		for module in range(nave_width_modules):
			var x: float = -half_x + WALL_WIDTH * (float(module) + 0.5)
			var piece: String = "Wall_Plaster_Straight"
			if storey == 0 and module == centre_module:
				piece = "Wall_Plaster_Door_Round"
			elif storey == 1:
				piece = "Wall_Plaster_Window_Thin_Round"
			_place(piece, Vector3(x, y, half_z), 0.0)

		# North wall.
		for module in range(nave_width_modules):
			var x: float = -half_x + WALL_WIDTH * (float(module) + 0.5)
			var piece: String = "Wall_Plaster_Window_Thin_Round" if storey == 1 else "Wall_Plaster_Straight"
			_place(piece, Vector3(x, y, -half_z), PI)

		# Long side walls, windowed on the upper storey.
		for module in range(nave_length_modules):
			var z: float = -half_z + WALL_WIDTH * (float(module) + 0.5)
			var piece: String = "Wall_Plaster_Window_Wide_Round" if storey == 1 else "Wall_UnevenBrick_Straight"
			_place(piece, Vector3(-half_x, y, z), -PI * 0.5)
			_place(piece, Vector3(half_x, y, z), PI * 0.5)


func _build_roof() -> void:
	# The kit's roof pieces are sized in modules; 6x8 covers the nave closely
	# enough that the overhang reads as eaves.
	var roof_y: float = float(nave_storeys) * WALL_HEIGHT
	_place("Roof_RoundTiles_6x8", Vector3(0.0, roof_y, 0.0), 0.0)


# ── Tower ────────────────────────────────────────────────────────

## A square tower of stacked wall modules, capped with the kit's tower roof. The
## belfry storey is left open on all four sides so the bell is visible from the
## courtyard below.
func _build_tower() -> void:
	var side_modules: int = 2
	var half: float = float(side_modules) * WALL_WIDTH * 0.5
	var origin := Vector3(tower_offset.x, 0.0, tower_offset.y)

	for storey in range(tower_storeys):
		var y: float = float(storey) * WALL_HEIGHT
		var is_belfry: bool = storey == tower_storeys - 1

		for module in range(side_modules):
			var offset: float = -half + WALL_WIDTH * (float(module) + 0.5)

			# The belfry uses open arches so the bell reads from the ground.
			var piece: String = "Wall_Arch" if is_belfry else "Wall_UnevenBrick_Straight"

			_place(piece, origin + Vector3(offset, y, half), 0.0)
			_place(piece, origin + Vector3(offset, y, -half), PI)
			_place(piece, origin + Vector3(-half, y, offset), -PI * 0.5)
			_place(piece, origin + Vector3(half, y, offset), PI * 0.5)

	var cap_y: float = float(tower_storeys) * WALL_HEIGHT
	_place("Roof_Tower_RoundTiles", origin + Vector3(0.0, cap_y, 0.0), 0.0)

	# Bell hangs in the middle of the belfry storey.
	bell_position = origin + Vector3(0.0, float(tower_storeys - 1) * WALL_HEIGHT + 1.6, 0.0)


# ── Collision ────────────────────────────────────────────────────

## Simple boxes rather than per-piece mesh collision. The player never goes
## inside, so the church only needs to be solid, and a handful of boxes is both
## cheaper and far less likely to catch a character than hundreds of trimeshes.
func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "ChurchCollision"
	body.collision_layer = 1
	add_child(body)

	var half_x: float = float(nave_width_modules) * WALL_WIDTH * 0.5
	var half_z: float = float(nave_length_modules) * WALL_WIDTH * 0.5
	var height: float = float(nave_storeys) * WALL_HEIGHT

	_add_box(body, Vector3(0.0, height * 0.5, 0.0), Vector3(half_x * 2.0, height, half_z * 2.0))

	var tower_half: float = WALL_WIDTH
	var tower_height: float = float(tower_storeys) * WALL_HEIGHT
	_add_box(
		body,
		Vector3(tower_offset.x, tower_height * 0.5, tower_offset.y),
		Vector3(tower_half * 2.0, tower_height, tower_half * 2.0)
	)

	body.add_to_group("navmesh_source")


func _add_box(body: StaticBody3D, at: Vector3, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	body.add_child(shape)


# ── Placement ────────────────────────────────────────────────────

func _place(piece: String, at: Vector3, yaw: float) -> Node3D:
	var scene: PackedScene = _load_piece(piece)
	if scene == null:
		return null

	var node := scene.instantiate() as Node3D
	if node == null:
		return null

	_pieces.add_child(node)
	node.position = at
	node.rotation.y = yaw
	return node


func _load_piece(piece: String) -> PackedScene:
	if _scene_cache.has(piece):
		return _scene_cache[piece]

	var path: String = "%s/%s.gltf" % [KIT, piece]
	if not ResourceLoader.exists(path):
		push_warning("[ChurchBuilder] Missing kit piece: %s" % path)
		_scene_cache[piece] = null
		return null

	var scene := ResourceLoader.load(path) as PackedScene
	_scene_cache[piece] = scene
	return scene

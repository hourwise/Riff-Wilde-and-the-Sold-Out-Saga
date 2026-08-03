class_name GraveyardBuilder
extends Node3D
## Builds the Church Graveyard's scenery from the Kenney Graveyard Kit.
##
## The districts of ADR-0002 are authored as data — rectangles with a character
## each — and dressed procedurally from a fixed seed. Layout is deliberate; the
## thousand gravestones are not worth placing by hand.
##
## Three rules the arena taught:
##   1. Piece sizes are measured, never assumed. See tools/measure_kit_pieces.gd —
##      a road tile is 0.797 units, not the 1.0 that seemed obvious, and that kind
##      of guess is what left visible seams across the whole prototype arena.
##   2. Scenery carries no collision. One ground box handles the floor, and a
##      handful of blockers handle the walls. Hundreds of concave colliders
##      meeting edge to edge is how characters fall through seams.
##   3. Anything the player must not walk through needs its own blocker, because
##      of rule 2. The maze walls below are the only scenery that gets one.

const KIT: String = "res://assets/environment/graveyard-kit"

## Where each art pack lives. A piece is named "pack/piece", or just "piece" for
## the graveyard kit, which is most of them.
##
## The ground cover comes from KayKit's forest and Halloween packs because the
## graveyard kit has none — it is headstones and buildings, with nothing to put
## between them. Those packs ship .gltf referencing their textures by relative
## path, so their folder structure has to be preserved on disk.
const PACKS: Dictionary = {
	"forest": {"dir": "res://assets/kaykit/forest/Assets/gltf", "ext": "gltf"},
	"halloween": {"dir": "res://assets/kaykit/halloween/Assets/gltf", "ext": "gltf"},
}

## What grows between the graves. Scattered thickly and cheaply: all of it is
## batched, none of it collides, and none of it is placed where the player walks.
const GRASS: Array = [
	"forest/Grass_1_A_Color1", "forest/Grass_1_B_Color1", "forest/Grass_1_C_Color1",
	"forest/Grass_1_D_Color1", "forest/Grass_2_A_Color1", "forest/Grass_2_B_Color1",
	"forest/Grass_2_C_Color1", "forest/Grass_2_D_Color1",
]
const STONES: Array = [
	"forest/Rock_1_A_Color1", "forest/Rock_1_D_Color1", "forest/Rock_1_H_Color1",
	"forest/Rock_2_B_Color1", "forest/Rock_2_E_Color1", "forest/Rock_3_C_Color1",
	"forest/Rock_3_J_Color1", "forest/Rock_3_P_Color1",
]
const UNDERGROWTH: Array = [
	"forest/Bush_1_A_Color1", "forest/Bush_1_D_Color1", "forest/Bush_2_B_Color1",
	"forest/Bush_2_E_Color1", "forest/Bush_4_A_Color1", "forest/Bush_4_D_Color1",
]
## Scattered remains, for the districts that have earned them.
const BONES: Array = [
	"halloween/bone_A", "halloween/bone_B", "halloween/bone_C",
	"halloween/skull", "halloween/ribcage",
]

## Measured with tools/measure_kit_pieces.gd: kit pieces are ~1 unit where a
## character needs ~2, so everything is scaled uniformly and the grid follows.
const KIT_SCALE: float = 2.0
const GRID: float = 2.0

## Road tiles are 0.797 units square, not 1.0. Laid at exactly their own width so
## a path is continuous without stacking overlapping tiles.
const ROAD_TILE: float = 0.797 * KIT_SCALE

## Per-category size, as a multiplier on KIT_SCALE. Derived from the measured
## heights reported by tools/measure_scene_scale.gd against a ~1.25 m character:
## a headstone should reach the chest, a crypt should tower, a tree should
## dominate. A single uniform factor gets all three wrong at once.
const GRAVE_SCALE: float = 0.65
const CRYPT_SCALE: float = 1.8
const TREE_SCALE: float = 1.15
const LIGHT_SCALE: float = 1.05

## Scenery shorter than this casts no shadow. See _batch for why.
const SHADOW_HEIGHT_FLOOR: float = 0.45

## Fixed so the graveyard is identical every run. A level that reshuffles itself
## cannot be learned, play-tested or bug-reported against.
const LAYOUT_SEED: int = 20260801

## District rectangles in world XZ, laid out south (entrance) to north (church).
## Kept as data so the shape of the level is readable in one place.
##
## Sized for a 12–15 minute run: seven districts across roughly 200 x 220 metres,
## two of them optional loops off the main route.
const REGIONS: Array[Dictionary] = [
	{
		"id": &"entrance",
		"name": "Cemetery Gate",
		"rect": Rect2(Vector2(-22.0, 24.0), Vector2(44.0, 30.0)),
		"graves": 14, "crypts": 0, "trees": 12, "lights": 5,
	},
	{
		"id": &"graveyard",
		"name": "The Graveyard",
		"rect": Rect2(Vector2(-44.0, -20.0), Vector2(88.0, 42.0)),
		"graves": 78, "crypts": 3, "trees": 20, "lights": 9,
	},
	{
		# A dead end off the east side of the graveyard. No altar, no route
		# onward — it exists to reward looking around, and to make the map read as
		# a place rather than a corridor.
		"id": &"hollow",
		"name": "Weeping Hollow",
		"rect": Rect2(Vector2(48.0, -26.0), Vector2(34.0, 40.0)),
		"graves": 26, "crypts": 1, "trees": 22, "lights": 4,
	},
	{
		"id": &"mausoleum",
		"name": "The Mausoleum",
		"rect": Rect2(Vector2(-84.0, -66.0), Vector2(40.0, 46.0)),
		"graves": 30, "crypts": 9, "trees": 12, "lights": 8,
	},
	{
		# The maze district. Dressed lightly, because the walls built by
		# _build_maze are the content here.
		"id": &"crypts",
		"name": "The Crypt Maze",
		"rect": Rect2(Vector2(31.0, -91.0), Vector2(51.0, 51.0)),
		"graves": 18, "crypts": 0, "trees": 0, "lights": 0,
	},
	{
		"id": &"bonefield",
		"name": "The Bone Field",
		"rect": Rect2(Vector2(-34.0, -112.0), Vector2(68.0, 38.0)),
		"graves": 54, "crypts": 2, "trees": 14, "lights": 7,
	},
	{
		"id": &"courtyard",
		"name": "Church Courtyard",
		"rect": Rect2(Vector2(-30.0, -152.0), Vector2(60.0, 38.0)),
		"graves": 12, "crypts": 0, "trees": 10, "lights": 12,
	},
]

## Circles kept clear of scenery: altar plazas, the boss arena, spawn, and the
## routes between regions. Without these, procedural clutter blocks the level.
const CLEARINGS: Array[Dictionary] = [
	{"at": Vector2(0.0, 40.0), "radius": 8.0},     # player spawn
	{"at": Vector2(0.0, 0.0), "radius": 10.0},     # graveyard altar plaza
	{"at": Vector2(-64.0, -44.0), "radius": 9.0},  # mausoleum altar
	{"at": Vector2(67.0, -76.6), "radius": 9.0},   # crypt altar chamber
	{"at": Vector2(0.0, -124.0), "radius": 16.0},  # courtyard altar and boss arena
	{"at": Vector2(0.0, -140.0), "radius": 18.0},  # the church itself
	{"at": Vector2(64.0, -6.0), "radius": 8.0},    # Weeping Hollow shrine
	{"at": Vector2(0.0, 24.0), "radius": 7.0},     # gate to graveyard
	{"at": Vector2(44.0, -4.0), "radius": 6.0},    # graveyard to the hollow
	{"at": Vector2(-46.0, -30.0), "radius": 7.0},  # graveyard to mausoleum
	{"at": Vector2(56.2, -38.0), "radius": 7.0},   # graveyard to the maze mouth
	{"at": Vector2(-38.0, -84.0), "radius": 7.0},  # mausoleum to bone field
	{"at": Vector2(29.0, -87.4), "radius": 7.0},   # maze exit to bone field
	{"at": Vector2(0.0, -100.0), "radius": 9.0},   # bone field crossroads
]

## Paths joining the districts. Multiple routes and a loop, per the ADR's
## requirement that the cemetery can be explored in different orders.
##
## Each route names its surface. The kit ships one road tile, so the variety is
## made with tint and width rather than with more meshes: a swept stone approach
## to the church should not look like the dirt track someone wore into the grass
## between two crypts.
const PATHS: Array[Dictionary] = [
	{
		"surface": &"stone", "width": 3,
		"points": [Vector2(0.0, 44.0), Vector2(0.0, 0.0)],
	},
	{
		"surface": &"dirt", "width": 2,
		"points": [Vector2(0.0, 0.0), Vector2(24.0, -2.0), Vector2(44.0, -4.0), Vector2(64.0, -6.0)],
	},
	{
		"surface": &"gravel", "width": 3,
		"points": [Vector2(0.0, 0.0), Vector2(-26.0, -14.0), Vector2(-46.0, -30.0), Vector2(-64.0, -44.0)],
	},
	{
		"surface": &"gravel", "width": 3,
		"points": [Vector2(0.0, 0.0), Vector2(30.0, -18.0), Vector2(56.2, -38.0)],
	},
	{
		"surface": &"dirt", "width": 2,
		"points": [Vector2(-64.0, -44.0), Vector2(-52.0, -68.0), Vector2(-38.0, -84.0), Vector2(-14.0, -96.0), Vector2(0.0, -100.0)],
	},
	{
		"surface": &"dirt", "width": 2,
		"points": [Vector2(29.0, -87.4), Vector2(12.0, -94.0), Vector2(0.0, -100.0)],
	},
	{
		# The approach to the church is the one the player walks last and slowest.
		"surface": &"stone", "width": 4,
		"points": [Vector2(0.0, -100.0), Vector2(0.0, -124.0)],
	},
]

## Albedo tint per surface, multiplied over the kit's road texture.
const SURFACE_TINTS: Dictionary = {
	&"stone": Color(0.72, 0.72, 0.74),
	&"gravel": Color(0.58, 0.55, 0.48),
	&"dirt": Color(0.42, 0.33, 0.24),
}

# ── The crypt maze ───────────────────────────────────────────────

## Wall segments are 1 unit long, so at KIT_SCALE they span GRID. Scaled up again
## for the maze: a wall you can see over is not a maze wall.
const MAZE_WALL_SCALE: float = 1.8
const MAZE_WALL_SPAN: float = 1.0 * KIT_SCALE * MAZE_WALL_SCALE
## Two segments per cell edge. One would give a corridor too tight for the
## third-person camera to sit behind the player.
const MAZE_CELL: float = MAZE_WALL_SPAN * 2.0
const MAZE_COLS: int = 7
const MAZE_ROWS: int = 7
const MAZE_ORIGIN := Vector2(31.0, -91.0)

## Cells whose internal walls are removed, opening a chamber big enough to fight
## in. The crypt altar stands in the middle of it.
const MAZE_CHAMBER := Rect2i(Vector2i(4, 1), Vector2i(2, 2))

## Where the maze connects to the rest of the cemetery: {cell, side}. Sides are
## 0 north (-z), 1 east (+x), 2 south (+z), 3 west (-x).
const MAZE_DOORS: Array[Dictionary] = [
	{"cell": Vector2i(3, 6), "side": 2},  # mouth, from the graveyard
	{"cell": Vector2i(0, 0), "side": 3},  # far exit, onto the bone field
]

@export var build_on_ready: bool = true
## Overall bounds of the walled cemetery.
@export var ground_size: Vector2 = Vector2(200.0, 220.0)
@export var ground_centre: Vector2 = Vector2(0.0, -50.0)

## How far the forest extends beyond the cemetery wall. The point is that the
## horizon is never visible, so this is deep enough that the far edge is lost in
## fog rather than seen ending.
@export var forest_depth: float = 70.0
## Sample points per metre along each axis, so 0.35 is a candidate tree every
## ~3 m. Set as a rate rather than a count because the band area changes
## whenever the cemetery is resized.
@export var forest_density: float = 0.35

var _rng := RandomNumberGenerator.new()
var _scenery: Node3D = null
var _scene_cache: Dictionary = {}
## Cell -> bitmask of open sides, in the same order as MAZE_DOORS uses.
var _maze_cells: Dictionary = {}
var _dead_ends: Array[Vector2] = []
var _maze: Node3D = null
## "group/piece" -> the transforms to draw it at. Flushed into MultiMeshes once
## everything is placed.
var _batches: Dictionary = {}
## Which batch new pieces join. Set per district so each one culls separately.
var _batch_group: String = "world"
## Every piece placed, batched or not, as {piece, at}. The batched ones have no
## node to inspect afterwards, and the layout still has to be verifiable.
var _placements: Array[Dictionary] = []
var _terrain: GraveyardTerrain = null
var _height_cache: Dictionary = {}
## Batches whose pieces are too small for their shadows to be worth drawing.
var _unshadowed: Dictionary = {}


func _ready() -> void:
	if build_on_ready:
		build()


func build() -> void:
	_rng.seed = LAYOUT_SEED

	_scenery = Node3D.new()
	_scenery.name = "Scenery"
	add_child(_scenery)

	_build_terrain()

	_batch_group = "paths"
	_build_paths()
	_batch_group = "perimeter"
	_build_perimeter()
	_batch_group = "maze"
	_build_maze()

	for region: Dictionary in REGIONS:
		_batch_group = String(region["id"])
		_dress_region(region)
	_batch_group = "world"

	_scatter_ground_cover()
	_flush_batches()
	_build_forest()

	print("[GraveyardBuilder] Built %d districts, %d pieces (%d drawn individually), %d maze dead ends." % [
		REGIONS.size(), _placements.size(), _scenery.get_child_count(), _dead_ends.size()
	])


## Returns the region containing a world position, or an empty dictionary.
static func region_at(position: Vector3) -> Dictionary:
	for region: Dictionary in REGIONS:
		if (region["rect"] as Rect2).has_point(Vector2(position.x, position.z)):
			return region
	return {}


## Ground height at a world XZ position, for anything that has to sit on the
## terrain — altars, spawn points, encounter markers, the church.
func height_at(point: Vector2) -> float:
	return _terrain.height_at(point) if _terrain != null else 0.0


## The terrain node, for callers that need slope as well as height.
func get_terrain() -> GraveyardTerrain:
	return _terrain


## Every scenery piece placed, as {piece, at, height}.
##
## Height is recorded here rather than read back from the MultiMesh afterwards.
## Under the headless rendering server, MultiMesh instance transforms are written
## into a no-op and read back as identity — every piece appears unscaled at the
## world origin, including the ones plainly rendering correctly on screen. Any
## check built on reading them back measures the dummy server, not the level.
func get_placements() -> Array[Dictionary]:
	return _placements.duplicate()


## World positions of the maze's dead ends. Used to place the lore props and, by
## callers, anything else worth hiding down a wrong turn.
func get_dead_ends() -> Array[Vector2]:
	return _dead_ends.duplicate()


# ── Ground and walls ─────────────────────────────────────────────

## Raises the terrain the whole cemetery stands on.
##
## Used to be a single flat box. The box was reliable and seamless, which is why
## it lasted, but it also meant the level had no horizon of its own and nowhere
## that was not immediately visible from everywhere else.
##
## The clearings and paths already authored for scenery are handed over as
## levelling instructions, so a plaza is flat and a road runs along a slope
## instead of across it — without having to describe the same places twice.
func _build_terrain() -> void:
	_terrain = GraveyardTerrain.new()
	_terrain.name = "Terrain"
	_terrain.ground_size = ground_size
	_terrain.ground_centre = ground_centre

	var zones: Array[Dictionary] = []
	for clearing: Dictionary in CLEARINGS:
		# Level the plaza itself, then blend back over a similar distance, so a
		# clearing sits in a saucer rather than on a pedestal.
		var radius: float = float(clearing["radius"])
		zones.append({"at": clearing["at"], "flat": radius * 0.8, "taper": radius * 0.9})
	# The maze is walled and gridded; a slope through it would leave walls
	# floating at one end and buried at the other.
	# Wide enough that the whole maze, corners included, falls inside the fully
	# level part of the zone rather than its taper. A corridor on a slope puts one
	# end of a wall in the air and the other underground, and tilts the floor
	# enough that navigation drops it — which seals off the crypt altar.
	# Flat across the maze's own half-diagonal plus a margin, then a short taper.
	# A long taper here reaches most of the cemetery and levels the ridges with it.
	var maze_reach: float = Vector2(MAZE_COLS, MAZE_ROWS).length() * MAZE_CELL * 0.5
	zones.append({
		"at": MAZE_ORIGIN + Vector2(MAZE_COLS, MAZE_ROWS) * MAZE_CELL * 0.5,
		"flat": maze_reach + 4.0,
		"taper": 12.0,
	})
	_terrain.flatten_zones = zones

	var lines: Array[Dictionary] = []
	for path: Dictionary in PATHS:
		lines.append({
			"points": path["points"],
			"margin": 2.0 + float(path["width"]) * ROAD_TILE * 0.5,
		})
	_terrain.flatten_lines = lines

	add_child(_terrain)
	_terrain.build()

	# An apron under the forest, so the ground does not visibly stop at the wall.
	var apron := MeshInstance3D.new()
	apron.name = "ForestFloor"
	var apron_plane := PlaneMesh.new()
	apron_plane.size = ground_size + Vector2.ONE * forest_depth * 2.0
	var apron_material := StandardMaterial3D.new()
	apron_material.albedo_color = Color(0.18, 0.19, 0.14)
	apron_material.roughness = 1.0
	apron_plane.material = apron_material
	apron.mesh = apron_plane
	apron.position = Vector3(ground_centre.x, _terrain.height_at(ground_centre) - 1.2, ground_centre.y)
	add_child(apron)


## Invisible walls at the cemetery bounds. The fence is scenery; this is what
## actually stops the player, which keeps collision cheap and predictable.
func _build_perimeter() -> void:
	var half: Vector2 = ground_size * 0.5
	var walls: Array[Dictionary] = [
		{"offset": Vector3(0.0, 3.0, -half.y), "size": Vector3(ground_size.x, 6.0, 1.0)},
		{"offset": Vector3(0.0, 3.0, half.y), "size": Vector3(ground_size.x, 6.0, 1.0)},
		{"offset": Vector3(-half.x, 3.0, 0.0), "size": Vector3(1.0, 6.0, ground_size.y)},
		{"offset": Vector3(half.x, 3.0, 0.0), "size": Vector3(1.0, 6.0, ground_size.y)},
	]

	var body := StaticBody3D.new()
	body.name = "PerimeterWalls"
	body.collision_layer = 1
	add_child(body)

	for wall: Dictionary in walls:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = wall["size"]
		shape.shape = box
		var at: Vector3 = Vector3(ground_centre.x, 0.0, ground_centre.y) + (wall["offset"] as Vector3)
		at.y += height_at(Vector2(at.x, at.z))
		shape.position = at
		body.add_child(shape)

	# Fence line just inside the invisible wall, so the boundary is legible.
	var inset: float = 1.6
	_line_of_pieces("iron-fence", Vector2(-half.x + inset, -half.y + inset), Vector2(half.x - inset, -half.y + inset), 0.0)
	_line_of_pieces("iron-fence", Vector2(-half.x + inset, half.y - inset), Vector2(half.x - inset, half.y - inset), 0.0)
	_line_of_pieces("iron-fence", Vector2(-half.x + inset, -half.y + inset), Vector2(-half.x + inset, half.y - inset), 90.0)
	_line_of_pieces("iron-fence", Vector2(half.x - inset, -half.y + inset), Vector2(half.x - inset, half.y - inset), 90.0)


func _line_of_pieces(piece: String, from: Vector2, to: Vector2, yaw_degrees: float) -> void:
	var origin := Vector2(ground_centre.x, ground_centre.y)
	var start: Vector2 = origin + from
	var end: Vector2 = origin + to
	var length: float = start.distance_to(end)
	var steps: int = maxi(1, int(length / GRID))

	for step in range(steps + 1):
		var point: Vector2 = start.lerp(end, float(step) / float(steps))
		_batch(piece, point, deg_to_rad(yaw_degrees), 0.75)


# ── The forest boundary ──────────────────────────────────────────

## A wall of trees around the whole cemetery, deep enough that its far side is
## lost in fog. This is what removes the horizon: without it the level ends in a
## visible edge and reads as a diorama.
##
## Drawn as a MultiMesh rather than thousands of instantiated scenes. At this
## count the difference is not an optimisation, it is whether the level loads.
func _build_forest() -> void:
	var trunk_mesh: Mesh = _mesh_of("pine")
	if trunk_mesh == null:
		return

	var inner: Rect2 = Rect2(
		Vector2(ground_centre.x, ground_centre.y) - ground_size * 0.5,
		ground_size
	).grow(2.0)
	var outer: Rect2 = inner.grow(forest_depth)

	var transforms: Array[Transform3D] = []
	var columns: int = int(outer.size.x * forest_density)
	var rows: int = int(outer.size.y * forest_density)

	for column in range(columns):
		for row in range(rows):
			# Jittered grid rather than uniform random: random points clump and
			# leave gaps you can see straight through, which defeats the purpose.
			var point := Vector2(
				outer.position.x + (float(column) + _rng.randf()) / float(columns) * outer.size.x,
				outer.position.y + (float(row) + _rng.randf()) / float(rows) * outer.size.y
			)
			if inner.has_point(point):
				continue

			# Denser and taller further out, so the wall thickens into the fog
			# instead of stopping at a clean line.
			var depth: float = _distance_outside(inner, point) / forest_depth
			if _rng.randf() > 0.45 + depth * 0.55:
				continue

			var height: float = _rng.randf_range(1.5, 2.4) + depth * 0.8
			# Outside the cemetery the terrain grid has no samples, so the edge
			# height is carried outward. Trees beyond the wall only need to not
			# hover; they are seen as a silhouette through fog.
			var ground: float = height_at(Vector2(
				clampf(point.x, inner.position.x, inner.end.x),
				clampf(point.y, inner.position.y, inner.end.y)
			))
			var transform := Transform3D(Basis.IDENTITY, Vector3(point.x, ground - 0.2, point.y))
			transform = transform.rotated_local(Vector3.UP, _rng.randf_range(0.0, TAU))
			transform = transform.scaled_local(Vector3(
				height * _rng.randf_range(0.85, 1.05), height, height * _rng.randf_range(0.85, 1.05)
			))
			transforms.append(transform)

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = trunk_mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])

	var instance := MultiMeshInstance3D.new()
	instance.name = "ForestWall"
	instance.multimesh = multimesh
	# Shadows from ten thousand trunks buy nothing: the forest is beyond the wall
	# and reads as a silhouette in fog.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

	print("[GraveyardBuilder] Forest wall: %d trees." % transforms.size())


func _distance_outside(rect: Rect2, point: Vector2) -> float:
	var dx: float = maxf(maxf(rect.position.x - point.x, 0.0), point.x - rect.end.x)
	var dy: float = maxf(maxf(rect.position.y - point.y, 0.0), point.y - rect.end.y)
	return Vector2(dx, dy).length()


## The first mesh inside a kit piece, for MultiMesh use. The kit's materials are
## carried on the mesh surfaces, so they come along with it.
func _mesh_of(piece: String) -> Mesh:
	var scene: PackedScene = _load_piece(piece)
	if scene == null:
		return null

	var instance: Node = scene.instantiate()
	var found: MeshInstance3D = _find_mesh_instance(instance)
	var mesh: Mesh = found.mesh if found != null else null
	instance.free()
	return mesh


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found: MeshInstance3D = _find_mesh_instance(child)
		if found != null:
			return found
	return null


# ── The crypt maze ───────────────────────────────────────────────

## Carves a perfect maze with a depth-first backtracker, then walls it.
##
## A perfect maze has exactly one route between any two cells, which is what
## makes it worth walking: every wrong turn is a real dead end rather than a
## slightly longer way round.
func _build_maze() -> void:
	_carve_maze()
	_open_chamber()
	for door: Dictionary in MAZE_DOORS:
		_open_side(door["cell"], int(door["side"]))

	# The maze is authored structure, not dressing, so it lives in its own branch:
	# its walls stand exactly where a doorway clearing is, which is correct for a
	# doorway and would read as stray scatter anywhere else.
	_maze = Node3D.new()
	_maze.name = "Maze"
	add_child(_maze)

	var body := StaticBody3D.new()
	body.name = "MazeWalls"
	body.collision_layer = 1
	_maze.add_child(body)
	body.add_to_group("navmesh_source")

	# Each wall is drawn once. Iterating every cell's four sides would build every
	# internal wall twice, doubling both the geometry and the collision.
	for col in range(MAZE_COLS):
		for row in range(MAZE_ROWS):
			var cell := Vector2i(col, row)
			if not _is_open(cell, 0):
				_wall_between(body, cell, 0)
			if not _is_open(cell, 3):
				_wall_between(body, cell, 3)
			if row == MAZE_ROWS - 1 and not _is_open(cell, 2):
				_wall_between(body, cell, 2)
			if col == MAZE_COLS - 1 and not _is_open(cell, 1):
				_wall_between(body, cell, 1)

	_dress_dead_ends()


func _carve_maze() -> void:
	for col in range(MAZE_COLS):
		for row in range(MAZE_ROWS):
			_maze_cells[Vector2i(col, row)] = 0

	var visited: Dictionary = {}
	var stack: Array[Vector2i] = [Vector2i(0, 0)]
	visited[stack[0]] = true

	while not stack.is_empty():
		var cell: Vector2i = stack[-1]
		var options: Array[int] = []
		for side in range(4):
			var neighbour: Vector2i = cell + _side_step(side)
			if _in_maze(neighbour) and not visited.has(neighbour):
				options.append(side)

		if options.is_empty():
			stack.pop_back()
			continue

		var side: int = options[_rng.randi_range(0, options.size() - 1)]
		_open_side(cell, side)
		var next: Vector2i = cell + _side_step(side)
		visited[next] = true
		stack.append(next)


## Removes the internal walls of the chamber so there is somewhere to fight.
func _open_chamber() -> void:
	for col in range(MAZE_CHAMBER.position.x, MAZE_CHAMBER.end.x):
		for row in range(MAZE_CHAMBER.position.y, MAZE_CHAMBER.end.y):
			var cell := Vector2i(col, row)
			if col + 1 < MAZE_CHAMBER.end.x:
				_open_side(cell, 1)
			if row + 1 < MAZE_CHAMBER.end.y:
				_open_side(cell, 2)


func _side_step(side: int) -> Vector2i:
	match side:
		0: return Vector2i(0, -1)
		1: return Vector2i(1, 0)
		2: return Vector2i(0, 1)
		_: return Vector2i(-1, 0)


func _in_maze(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < MAZE_COLS and cell.y < MAZE_ROWS


func _is_open(cell: Vector2i, side: int) -> bool:
	return (int(_maze_cells.get(cell, 0)) & (1 << side)) != 0


## Opens a wall from both sides at once. Storing it on only one cell means the
## neighbour still believes it is walled and builds geometry there.
func _open_side(cell: Vector2i, side: int) -> void:
	if not _in_maze(cell):
		return
	_maze_cells[cell] = int(_maze_cells.get(cell, 0)) | (1 << side)

	var neighbour: Vector2i = cell + _side_step(side)
	if _in_maze(neighbour):
		_maze_cells[neighbour] = int(_maze_cells.get(neighbour, 0)) | (1 << ((side + 2) % 4))


func _cell_centre(cell: Vector2i) -> Vector2:
	return MAZE_ORIGIN + Vector2(
		(float(cell.x) + 0.5) * MAZE_CELL,
		(float(cell.y) + 0.5) * MAZE_CELL
	)


## Builds one cell edge: two wall segments plus a matching collision box.
func _wall_between(body: StaticBody3D, cell: Vector2i, side: int) -> void:
	var centre: Vector2 = _cell_centre(cell)
	var step := Vector2(_side_step(side))
	var edge: Vector2 = centre + step * (MAZE_CELL * 0.5)
	var along: Vector2 = step.orthogonal()
	var horizontal: bool = absf(step.y) > 0.5

	for offset in [-0.5, 0.5]:
		var point: Vector2 = edge + along * MAZE_WALL_SPAN * offset
		var piece: String = "stone-wall-damaged" if _rng.randf() < 0.25 else "stone-wall"
		_batch(piece, point, 0.0 if horizontal else PI * 0.5, MAZE_WALL_SCALE)

	# Pillars at the ends tie neighbouring runs together, so corners do not show a
	# gap where two walls meet at right angles.
	_batch("stone-wall-column", edge + along * MAZE_CELL * 0.5, 0.0, MAZE_WALL_SCALE)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var thickness: float = 0.9
	box.size = Vector3(MAZE_CELL if horizontal else thickness, 5.0, thickness if horizontal else MAZE_CELL)
	shape.shape = box
	shape.position = Vector3(edge.x, height_at(edge) + 2.0, edge.y)
	body.add_child(shape)


## A dead end with nothing in it is just a mistake the player made. Each one gets
## a lit tableau, so a wrong turn still shows you something.
func _dress_dead_ends() -> void:
	for col in range(MAZE_COLS):
		for row in range(MAZE_ROWS):
			var cell := Vector2i(col, row)
			if MAZE_CHAMBER.has_point(Vector2i(col, row)):
				continue

			var exits: int = 0
			for side in range(4):
				if _is_open(cell, side):
					exits += 1
			if exits != 1:
				continue

			var centre: Vector2 = _cell_centre(cell)
			_dead_ends.append(centre)

			var tableau: Array = [
				["coffin-old", "candle-multiple", "urn-round"],
				["gravestone-broken", "shovel-dirt", "debris"],
				["crypt-door", "candle", "urn-square"],
				["cross-wood", "detail-chalice", "hay-bale"],
			][_rng.randi_range(0, 3)]

			for index in range(tableau.size()):
				var angle: float = TAU * float(index) / float(tableau.size()) + _rng.randf()
				_batch(
					tableau[index],
					centre + Vector2(cos(angle), sin(angle)) * _rng.randf_range(1.2, 2.4),
					_rng.randf_range(0.0, TAU),
					GRAVE_SCALE
				)

			var basket: Node3D = _place("fire-basket", centre, _rng.randf_range(0.0, TAU), LIGHT_SCALE, false, _maze)
			if basket != null:
				_add_lamp(basket, Color(0.45, 0.72, 1.0), 1.6, 9.0)


# ── Paths ────────────────────────────────────────────────────────

## Cobbled routes between districts. They are the player's main read on where to
## go next, so they are laid before scenery and kept clear of it.
func _build_paths() -> void:
	for path: Dictionary in PATHS:
		var points: Array = path["points"]
		var surface: StringName = path["surface"]
		var lanes: int = int(path["width"])
		# One batch per surface, so each can carry its own tint.
		_batch_group = "path_%s" % surface

		for index in range(points.size() - 1):
			var from: Vector2 = points[index]
			var to: Vector2 = points[index + 1]
			var length: float = from.distance_to(to)
			# Stepped by the tile's own measured width, so tiles meet rather than
			# leaving the seams the arena had.
			var steps: int = maxi(1, int(length / ROAD_TILE))

			for step in range(steps + 1):
				var point: Vector2 = from.lerp(to, float(step) / float(steps))
				# Several tiles wide, so a path reads as a road rather than a trail.
				var perpendicular: Vector2 = (to - from).orthogonal().normalized()
				for lane in range(lanes):
					var offset: float = float(lane) - float(lanes - 1) * 0.5
					_batch("road", point + perpendicular * ROAD_TILE * offset, 0.0)


# ── Region dressing ──────────────────────────────────────────────

func _dress_region(region: Dictionary) -> void:
	var rect: Rect2 = region["rect"]

	# Chest height. At the kit's default scale a headstone stood as tall as Riff,
	# which flattens the whole sense of size.
	_scatter(rect, int(region["graves"]), [
		"gravestone-cross", "gravestone-bevel", "gravestone-round",
		"gravestone-wide", "gravestone-broken", "gravestone-decorative", "grave",
		"gravestone-cross-large", "gravestone-roof", "grave-border", "cross", "cross-wood",
	], GRAVE_SCALE)

	# Crypts are buildings and must read as such — you should feel small beside
	# one, and be unable to see over it.
	_scatter(rect, int(region["crypts"]), ["crypt", "crypt-large", "crypt-small", "crypt-a", "crypt-b"], CRYPT_SCALE, true)

	# "trunk" is a felled stump, not a tree; mixing it in made a quarter of the
	# woodland shorter than the player.
	_scatter(rect, int(region["trees"]), ["pine", "pine-crooked", "pine-fall", "pine-fall-crooked"], TREE_SCALE)
	_scatter(rect, int(region["trees"]) / 2, ["trunk", "trunk-long", "rocks", "rocks-tall", "debris", "debris-wood"], GRAVE_SCALE)

	# Small dressing: the difference between a field of headstones and a place
	# people actually buried their dead.
	_scatter(rect, int(region["graves"]) / 3, [
		"urn-round", "urn-square", "bench", "bench-damaged", "shovel", "shovel-dirt",
		"pillar-small", "pillar-square", "pillar-obelisk", "coffin", "coffin-old",
		"lantern-candle", "candle-multiple", "pumpkin", "pumpkin-carved", "hay-bale",
	], GRAVE_SCALE)

	# Lightposts are the navigation aid: warm points in a dark, foggy level.
	_scatter(rect, int(region["lights"]), ["lightpost-single", "lightpost-double"], LIGHT_SCALE, false, true)


## Grass, stones and undergrowth across the whole cemetery.
##
## Separate from district dressing because it follows the ground rather than the
## layout: it thins out on the banks where soil would not hold, thickens in the
## hollows, and keeps off the roads. The point is that the floor stops being a
## flat colour between the headstones.
##
## All of it is batched and none of it collides, so the count can be large enough
## to actually cover the ground without costing draw calls or physics.
func _scatter_ground_cover() -> void:
	var half: Vector2 = ground_size * 0.5
	var area: Rect2 = Rect2(ground_centre - half, ground_size).grow(-3.0)
	var terrain: GraveyardTerrain = _terrain

	# A jittered grid rather than random points: random scattering clumps, and
	# clumped ground cover leaves bald patches that read as missing geometry.
	# Tightened once the pieces were the right size. At the old spacing, cover
	# sized correctly leaves most of the ground bare between tufts.
	var spacing: float = 1.7
	var columns: int = int(area.size.x / spacing)
	var rows: int = int(area.size.y / spacing)
	var placed: int = 0

	for column in range(columns):
		for row in range(rows):
			var point := Vector2(
				area.position.x + (float(column) + _rng.randf()) / float(columns) * area.size.x,
				area.position.y + (float(row) + _rng.randf()) / float(rows) * area.size.y
			)

			# Roads stay clear; plazas do not. Grass across an altar plaza is
			# correct — it is bare earth that would look unfinished.
			if _is_on_a_road(point) or _is_in_maze_walls(point):
				continue

			var steepness: float = terrain.slope_at(point) if terrain != null else 0.0
			var region: Dictionary = region_at(Vector3(point.x, 0.0, point.y))
			var district: StringName = region["id"] if region.has("id") else &"world"
			_batch_group = "cover_%s" % district

			var roll: float = _rng.randf()

			if steepness > 0.45:
				# Bare banks: loose stone only, and not much of it.
				if roll < 0.3:
					_scatter_one(STONES, point, 0.12, 0.34)
					placed += 1
				continue

			if roll < 0.62:
				_scatter_one(GRASS, point, 0.16, 0.34)
			elif roll < 0.78:
				_scatter_one(STONES, point, 0.10, 0.30)
			elif roll < 0.88:
				_scatter_one(UNDERGROWTH, point, 0.30, 0.62)
			elif roll < 0.93 and district == &"bonefield":
				# The Bone Field is named for what is lying in it.
				_scatter_one(BONES, point, 0.14, 0.28)
			else:
				continue

			placed += 1

	_batch_group = "world"
	print("[GraveyardBuilder] Ground cover: %d pieces." % placed)


## Places one piece from a pool at a height in metres.
func _scatter_one(pool: Array, point: Vector2, lowest: float, highest: float) -> void:
	var piece: String = pool[_rng.randi_range(0, pool.size() - 1)]
	_batch(
		piece,
		point,
		_rng.randf_range(0.0, TAU),
		_scale_for_height(piece, _rng.randf_range(lowest, highest))
	)


## The extra_scale that makes a piece stand a given height in world metres.
##
## Ground cover was sized by multiplier, on the assumption that the forest pack
## was authored at the same scale as the graveyard kit. It is not: a grass tuft is
## 0.919 units tall against a gravestone's 0.915, so "a bit smaller than a
## headstone" produced grass nearly three metres high, taller than the trees it
## was meant to grow under.
##
## Saying how tall something should be and deriving the number is the same fix the
## weapon socket needed, for the same reason — a multiplier is only meaningful
## relative to an authored scale nobody wrote down.
func _scale_for_height(piece: String, metres: float) -> float:
	var height: float = _piece_height(piece)
	if height <= 0.0001:
		return 1.0
	return metres / (height * KIT_SCALE)


## Height of a kit piece in its own units, measured once and remembered.
func _piece_height(piece: String) -> float:
	if _height_cache.has(piece):
		return float(_height_cache[piece])

	var bounds := AABB()
	var first: bool = true
	for part: Dictionary in _meshes_of(piece):
		var mesh: Mesh = part["mesh"]
		if mesh == null:
			continue
		var box: AABB = (part["transform"] as Transform3D) * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false

	var height: float = 0.0 if first else bounds.size.y
	_height_cache[piece] = height
	return height


## Whether a point lies on a road surface. Ground cover keeps off the roads but is
## welcome everywhere else, unlike the dressing which also avoids the plazas.
func _is_on_a_road(point: Vector2) -> bool:
	for path: Dictionary in PATHS:
		var points: Array = path["points"]
		var margin: float = float(path["width"]) * ROAD_TILE * 0.5 + 0.6
		for index in range(points.size() - 1):
			if _distance_to_segment(point, points[index], points[index + 1]) < margin:
				return true
	return false


## Places count pieces at random points in rect, skipping clearings. Rejection
## sampling with a bounded retry: simple, and good enough for scenery.
func _scatter(
	rect: Rect2,
	count: int,
	pieces: Array,
	scale_jitter: float = 1.0,
	blocks_navigation: bool = false,
	add_light: bool = false
) -> void:
	if pieces.is_empty():
		return

	var placed: int = 0
	var attempts: int = 0
	var attempt_limit: int = count * 12

	while placed < count and attempts < attempt_limit:
		attempts += 1
		var point := Vector2(
			_rng.randf_range(rect.position.x, rect.position.x + rect.size.x),
			_rng.randf_range(rect.position.y, rect.position.y + rect.size.y)
		)
		if _is_in_clearing(point) or _is_in_maze_walls(point):
			continue

		var piece: String = pieces[_rng.randi_range(0, pieces.size() - 1)]
		var yaw: float = _rng.randf_range(0.0, TAU)
		# scale_jitter is the category multiplier; vary it slightly so a field of
		# headstones is not visibly cloned.
		var piece_scale: float = scale_jitter * _rng.randf_range(0.88, 1.12)
		# Only pieces that carry a light or block navigation need a node of their
		# own. Everything else is drawn from a batch.
		var node: Node3D = null
		if add_light or blocks_navigation:
			node = _place(piece, point, yaw, piece_scale, blocks_navigation)
		else:
			_batch(piece, point, yaw, piece_scale)
		placed += 1

		if add_light and node != null:
			_add_lamp(node, Color(1.0, 0.68, 0.34), _rng.randf_range(2.2, 3.0), 13.0)


## Keeps scenery off the paths as well as out of the plazas, so routes stay walkable.
func _is_in_clearing(point: Vector2) -> bool:
	for clearing: Dictionary in CLEARINGS:
		if point.distance_to(clearing["at"]) <= float(clearing["radius"]):
			return true

	for path: Dictionary in PATHS:
		var points: Array = path["points"]
		# Clearance scales with the road, so a four-lane approach is not overgrown
		# by the same margin that keeps a two-lane track clear.
		var margin: float = 2.0 + float(path["width"]) * 0.55
		for index in range(points.size() - 1):
			if _distance_to_segment(point, points[index], points[index + 1]) < margin:
				return true

	return false


## Scatter inside the maze has to stay clear of the walls, or headstones grow
## through them and corridors silt up.
func _is_in_maze_walls(point: Vector2) -> bool:
	var local: Vector2 = point - MAZE_ORIGIN
	if local.x < 0.0 or local.y < 0.0:
		return false
	if local.x > MAZE_COLS * MAZE_CELL or local.y > MAZE_ROWS * MAZE_CELL:
		return false

	var within := Vector2(fmod(local.x, MAZE_CELL), fmod(local.y, MAZE_CELL))
	var margin: float = 2.2
	return (
		within.x < margin or within.x > MAZE_CELL - margin
		or within.y < margin or within.y > MAZE_CELL - margin
	)


func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var segment: Vector2 = to - from
	var length_squared: float = segment.length_squared()
	if length_squared < 0.0001:
		return point.distance_to(from)

	var t: float = clampf((point - from).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(from + segment * t)


# ── Placement ────────────────────────────────────────────────────

## Records a piece to be drawn from a MultiMesh rather than as its own node.
##
## The target machine has an onboard GPU, where the level's cost is dominated by
## draw calls rather than triangles: measured with tools/count_draw_load.gd, the
## dressed cemetery asked for 2,223 of them, almost all from scenery that never
## moves and never needs a node. Batching collapses that by about twenty to one.
##
## Batched per district rather than level-wide, so the renderer can still cull a
## district the player cannot see. One batch for the whole cemetery would be a
## single object 200 metres across, which is never off screen and never culled.
func _batch(piece: String, point: Vector2, yaw: float, extra_scale: float = 1.0) -> void:
	if _load_piece(piece) == null:
		return

	var key: String = "%s/%s" % [_batch_group, piece]
	if not _batches.has(key):
		_batches[key] = []

	var transform := Transform3D(Basis.IDENTITY, Vector3(point.x, height_at(point), point.y))
	transform.basis = Basis(Vector3.UP, yaw).scaled(Vector3.ONE * KIT_SCALE * extra_scale)
	(_batches[key] as Array).append(transform)

	var world_height: float = _piece_height(piece) * KIT_SCALE * extra_scale
	# Below ankle height a shadow is a few pixels of noise that never resolves
	# into a recognisable shape, and under a 0.3-energy moon it contributes
	# nothing at all. Ten thousand of them cost real fill rate on the onboard GPU
	# this is built for, and they were the worst of the detached-shadow artefact
	# because bias is a fixed distance regardless of how small the caster is.
	if world_height < SHADOW_HEIGHT_FLOOR:
		_unshadowed[key] = true

	_placements.append({"piece": piece, "at": point, "height": world_height})


## Turns the recorded batches into one MultiMeshInstance3D per mesh per district.
func _flush_batches() -> void:
	var batched := Node3D.new()
	batched.name = "BatchedScenery"
	add_child(batched)

	var drawn: int = 0

	for key: String in _batches.keys():
		var transforms: Array = _batches[key]
		# Only the first slash separates the batch group from the piece. Splitting
		# on every slash turns "cover_graveyard/forest/Grass_1_A" into a request for
		# a piece called "forest".
		var piece: String = key.substr(key.find("/") + 1)

		# A kit piece is not always one mesh — a lightpost is a post and a lamp,
		# each with its own material and its own offset inside the piece. Taking
		# only the first would silently drop half the model.
		for part: Dictionary in _meshes_of(piece):
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = part["mesh"]
			multimesh.instance_count = transforms.size()

			var local: Transform3D = part["transform"]
			for index in range(transforms.size()):
				multimesh.set_instance_transform(index, (transforms[index] as Transform3D) * local)

			var instance := MultiMeshInstance3D.new()
			instance.name = "%s_%d" % [key.replace("/", "_"), drawn]
			instance.multimesh = multimesh
			if _unshadowed.has(key):
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_tint_surface(instance, key)
			batched.add_child(instance)
			drawn += 1

	print("[GraveyardBuilder] Batched scenery into %d draws." % drawn)


## Tints a path batch to its surface. Applied as an override on the whole batch
## rather than per instance, which is why each surface gets its own batch.
func _tint_surface(instance: MultiMeshInstance3D, key: String) -> void:
	if not key.begins_with("path_"):
		return

	var surface := StringName(key.split("/")[0].trim_prefix("path_"))
	if not SURFACE_TINTS.has(surface):
		return

	var material := StandardMaterial3D.new()
	material.albedo_color = SURFACE_TINTS[surface]
	material.roughness = 1.0
	instance.material_override = material


## Every mesh inside a kit piece, with its transform relative to the piece root.
func _meshes_of(piece: String) -> Array[Dictionary]:
	var scene: PackedScene = _load_piece(piece)
	if scene == null:
		return []

	var instance := scene.instantiate() as Node3D
	if instance == null:
		return []

	var parts: Array[Dictionary] = []
	# Starts from identity and multiplies down, rather than reading the root's own
	# transform: the piece is being measured relative to itself, and a kit root
	# that carries a rotation would otherwise apply it twice.
	_collect_meshes(instance, Transform3D.IDENTITY, parts)
	instance.free()
	return parts


## Accumulates transforms down the tree by hand. global_transform is only
## meaningful for a node inside the scene tree, and this piece is instantiated
## purely to be read and thrown away.
func _collect_meshes(node: Node, inherited: Transform3D, into: Array[Dictionary]) -> void:
	var spatial := node as Node3D
	var here: Transform3D = inherited * spatial.transform if spatial != null else inherited

	var mesh_node := node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		into.append({"mesh": mesh_node.mesh, "transform": here})

	for child in node.get_children():
		_collect_meshes(child, here, into)


func _place(
	piece: String,
	point: Vector2,
	yaw: float,
	extra_scale: float = 1.0,
	blocks_navigation: bool = false,
	parent: Node3D = null
) -> Node3D:
	var scene: PackedScene = _load_piece(piece)
	if scene == null:
		return null

	var node := scene.instantiate() as Node3D
	if node == null:
		return null

	_placements.append({
		"piece": piece,
		"at": point,
		"height": _piece_height(piece) * KIT_SCALE * extra_scale,
	})

	var host: Node3D = parent if parent != null else _scenery
	host.add_child(node)
	# Named after the piece rather than inheriting the glb's root name, so scenery
	# can be identified reliably by callers and tests.
	node.name = piece.replace("/", "_")
	node.position = Vector3(point.x, height_at(point), point.y)
	node.rotation.y = yaw
	node.scale = Vector3.ONE * KIT_SCALE * extra_scale

	# Only pieces big enough to path around are worth telling navigation about.
	if blocks_navigation:
		node.add_to_group("navmesh_source")

	return node


## Warm, flickering light on lamp posts. The demo's whole lighting idea is
## torchlight against fog, and these are what make the graveyard readable at all
## — and what give the player something to navigate between.
func _add_lamp(post: Node3D, colour: Color, energy: float, range_metres: float) -> void:
	var light := TorchFlicker.new()
	light.light_color = colour
	light.base_energy = energy
	light.light_energy = energy
	light.omni_range = range_metres
	# Shadows from every lamp would be ruinous with this many lights; the fog and
	# the moonlight's shadows carry the depth instead.
	light.shadow_enabled = false
	# Switched off beyond the distance the fog already hides them at. Fifty-odd
	# live lights is a real cost on an onboard GPU, and a lamp four fog-lengths
	# away contributes nothing to the image it is being paid for.
	light.distance_fade_enabled = true
	light.distance_fade_begin = 38.0
	light.distance_fade_length = 12.0
	light.position = Vector3(0.0, 1.2, 0.0)
	post.add_child(light)


func _load_piece(piece: String) -> PackedScene:
	if _scene_cache.has(piece):
		return _scene_cache[piece]

	var directory: String = KIT
	var extension: String = "glb"
	var name: String = piece

	var split: int = piece.find("/")
	if split > 0:
		var pack: String = piece.substr(0, split)
		if PACKS.has(pack):
			directory = PACKS[pack]["dir"]
			extension = PACKS[pack]["ext"]
			name = piece.substr(split + 1)

	var path: String = "%s/%s.%s" % [directory, name, extension]
	if not ResourceLoader.exists(path):
		push_warning("[GraveyardBuilder] Missing kit piece: %s" % path)
		_scene_cache[piece] = null
		return null

	var scene := ResourceLoader.load(path) as PackedScene
	_scene_cache[piece] = scene
	return scene

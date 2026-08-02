class_name GraveyardBuilder
extends Node3D
## Builds the Church Graveyard's scenery from the Kenney Graveyard Kit.
##
## The five regions of ADR-0002 are authored as data — rectangles with a
## character each — and dressed procedurally from a fixed seed. Layout is
## deliberate; the thousand gravestones are not worth placing by hand.
##
## Two rules the arena taught:
##   1. Piece sizes are measured, never assumed. The kit is authored at roughly
##      half the scale of a 2 m character, hence KIT_SCALE.
##   2. Scenery carries no collision. One ground box handles the floor, and a
##      handful of blockers handle the walls. Hundreds of concave colliders
##      meeting edge to edge is how characters fall through seams.

const KIT: String = "res://assets/environment/graveyard-kit"

## Measured with tools/measure_model.gd: kit pieces are ~1 unit where a 2 m
## character needs ~2, so everything is scaled uniformly and the grid follows.
const KIT_SCALE: float = 2.0
const GRID: float = 2.0

## Per-category size, as a multiplier on KIT_SCALE. Derived from the measured
## heights reported by tools/measure_scene_scale.gd against a ~2 m character:
## a headstone should reach the chest, a crypt should tower, a tree should
## dominate. A single uniform factor gets all three wrong at once.
const GRAVE_SCALE: float = 0.65
const CRYPT_SCALE: float = 1.8
const TREE_SCALE: float = 1.15
const LIGHT_SCALE: float = 1.05

## Fixed so the graveyard is identical every run. A level that reshuffles itself
## cannot be learned, play-tested or bug-reported against.
const LAYOUT_SEED: int = 20260801

## Region rectangles in world XZ, laid out south (entrance) to north (church).
## Kept as data so the shape of the level is readable in one place.
const REGIONS: Array[Dictionary] = [
	{
		"id": &"entrance",
		"name": "Cemetery Gate",
		"rect": Rect2(Vector2(-18.0, 12.0), Vector2(36.0, 26.0)),
		"graves": 10, "crypts": 0, "trees": 8, "lights": 4,
	},
	{
		"id": &"graveyard",
		"name": "The Graveyard",
		"rect": Rect2(Vector2(-26.0, -18.0), Vector2(52.0, 30.0)),
		"graves": 46, "crypts": 2, "trees": 10, "lights": 6,
	},
	{
		"id": &"crypts",
		"name": "The Crypts",
		"rect": Rect2(Vector2(14.0, -46.0), Vector2(30.0, 28.0)),
		"graves": 14, "crypts": 7, "trees": 4, "lights": 5,
	},
	{
		"id": &"mausoleum",
		"name": "The Mausoleum",
		"rect": Rect2(Vector2(-44.0, -46.0), Vector2(30.0, 28.0)),
		"graves": 12, "crypts": 5, "trees": 5, "lights": 5,
	},
	{
		"id": &"courtyard",
		"name": "Church Courtyard",
		"rect": Rect2(Vector2(-20.0, -76.0), Vector2(40.0, 28.0)),
		"graves": 8, "crypts": 0, "trees": 6, "lights": 8,
	},
]

## Circles kept clear of scenery: altar plazas, the boss arena, spawn, and the
## routes between regions. Without these, procedural clutter blocks the level.
const CLEARINGS: Array[Dictionary] = [
	{"at": Vector2(0.0, 22.0), "radius": 7.0},    # player spawn
	{"at": Vector2(0.0, 0.0), "radius": 9.0},     # graveyard altar plaza
	{"at": Vector2(28.0, -32.0), "radius": 8.0},  # crypts altar
	{"at": Vector2(-30.0, -32.0), "radius": 8.0}, # mausoleum altar
	{"at": Vector2(0.0, -58.0), "radius": 14.0},  # courtyard altar and boss arena
	{"at": Vector2(0.0, 12.0), "radius": 6.0},    # gate to graveyard
	{"at": Vector2(16.0, -20.0), "radius": 6.0},  # graveyard to crypts
	{"at": Vector2(-18.0, -20.0), "radius": 6.0}, # graveyard to mausoleum
	{"at": Vector2(0.0, -44.0), "radius": 7.0},   # approach to the courtyard
]

## Paths joining the regions, as polylines. Multiple routes and a loop, per the
## ADR's requirement that the cemetery can be explored in different orders.
const PATHS: Array[Array] = [
	[Vector2(0.0, 24.0), Vector2(0.0, 0.0)],                                        # gate to centre
	[Vector2(0.0, 0.0), Vector2(16.0, -12.0), Vector2(26.0, -30.0)],                # centre to crypts
	[Vector2(0.0, 0.0), Vector2(-18.0, -12.0), Vector2(-28.0, -30.0)],              # centre to mausoleum
	[Vector2(26.0, -30.0), Vector2(14.0, -44.0), Vector2(0.0, -50.0)],              # crypts to courtyard
	[Vector2(-28.0, -30.0), Vector2(-14.0, -44.0), Vector2(0.0, -50.0)],            # mausoleum to courtyard
	[Vector2(0.0, 0.0), Vector2(0.0, -50.0)],                                        # direct centre to church
]

@export var build_on_ready: bool = true
## Overall bounds of the walled cemetery.
@export var ground_size: Vector2 = Vector2(120.0, 132.0)
@export var ground_centre: Vector2 = Vector2(-4.0, -26.0)

var _rng := RandomNumberGenerator.new()
var _scenery: Node3D = null
var _scene_cache: Dictionary = {}


func _ready() -> void:
	if build_on_ready:
		build()


func build() -> void:
	_rng.seed = LAYOUT_SEED

	_scenery = Node3D.new()
	_scenery.name = "Scenery"
	add_child(_scenery)

	_build_ground()
	_build_paths()
	_build_perimeter()

	for region: Dictionary in REGIONS:
		_dress_region(region)

	print("[GraveyardBuilder] Built %d regions, %d scenery pieces." % [REGIONS.size(), _scenery.get_child_count()])


## Returns the region containing a world position, or an empty dictionary.
static func region_at(position: Vector3) -> Dictionary:
	for region: Dictionary in REGIONS:
		if (region["rect"] as Rect2).has_point(Vector2(position.x, position.z)):
			return region
	return {}


# ── Ground and walls ─────────────────────────────────────────────

## One box for the whole cemetery floor. Reliable, seamless, and the only thing
## the player actually stands on.
func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	add_child(body)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ground_size.x, 2.0, ground_size.y)
	shape.shape = box
	shape.position = Vector3(ground_centre.x, -1.0, ground_centre.y)
	body.add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = ground_size
	var material := StandardMaterial3D.new()
	# Damp earth: dark, desaturated, so torchlight and spectral flame carry all
	# the colour in the scene.
	material.albedo_color = Color(0.16, 0.14, 0.11)
	material.roughness = 1.0
	plane.material = material
	mesh_instance.mesh = plane
	mesh_instance.position = Vector3(ground_centre.x, 0.0, ground_centre.y)
	body.add_child(mesh_instance)

	# Navigation is baked from this group, so the floor must be in it.
	body.add_to_group("navmesh_source")


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
		shape.position = Vector3(ground_centre.x, 0.0, ground_centre.y) + (wall["offset"] as Vector3)
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
		_place(piece, point, deg_to_rad(yaw_degrees), 0.75)


# ── Paths ────────────────────────────────────────────────────────

## Cobbled routes between regions. They are the player's main read on where to go
## next, so they are laid before scenery and kept clear of it.
func _build_paths() -> void:
	for path: Array in PATHS:
		for index in range(path.size() - 1):
			var from: Vector2 = path[index]
			var to: Vector2 = path[index + 1]
			var length: float = from.distance_to(to)
			var steps: int = maxi(1, int(length / 1.4))

			for step in range(steps + 1):
				var point: Vector2 = from.lerp(to, float(step) / float(steps))
				# Two tiles wide, so the path reads as a road rather than a trail.
				var perpendicular: Vector2 = (to - from).orthogonal().normalized()
				_place("road", point + perpendicular * 0.7, 0.0, 1.0, false)
				_place("road", point - perpendicular * 0.7, 0.0, 1.0, false)


# ── Region dressing ──────────────────────────────────────────────

func _dress_region(region: Dictionary) -> void:
	var rect: Rect2 = region["rect"]

	# Chest height. At the kit's default scale a headstone stood as tall as Riff,
	# which flattens the whole sense of size.
	_scatter(rect, int(region["graves"]), [
		"gravestone-cross", "gravestone-bevel", "gravestone-round",
		"gravestone-wide", "gravestone-broken", "gravestone-decorative", "grave",
	], GRAVE_SCALE)

	# Crypts are buildings and must read as such — you should feel small beside
	# one, and be unable to see over it.
	_scatter(rect, int(region["crypts"]), ["crypt", "crypt-large", "crypt-small"], CRYPT_SCALE, true)

	# "trunk" is a felled stump, not a tree; mixing it in made a quarter of the
	# woodland shorter than the player.
	_scatter(rect, int(region["trees"]), ["pine", "pine-crooked", "pine-fall"], TREE_SCALE)
	_scatter(rect, int(region["trees"]) / 3, ["trunk", "rocks", "rocks-tall"], GRAVE_SCALE)

	# Lightposts are the navigation aid: warm points in a dark, foggy level.
	_scatter(rect, int(region["lights"]), ["lightpost-single", "lightpost-double"], LIGHT_SCALE, false, true)


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
		if _is_in_clearing(point):
			continue

		var piece: String = pieces[_rng.randi_range(0, pieces.size() - 1)]
		var yaw: float = _rng.randf_range(0.0, TAU)
		# scale_jitter is the category multiplier; vary it slightly so a field of
		# headstones is not visibly cloned.
		var piece_scale: float = scale_jitter * _rng.randf_range(0.88, 1.12)
		var node: Node3D = _place(piece, point, yaw, piece_scale, blocks_navigation)
		placed += 1

		if add_light and node != null:
			_add_lamp(node)


## Keeps scenery off the paths as well as out of the plazas, so routes stay walkable.
func _is_in_clearing(point: Vector2) -> bool:
	for clearing: Dictionary in CLEARINGS:
		if point.distance_to(clearing["at"]) <= float(clearing["radius"]):
			return true

	for path: Array in PATHS:
		for index in range(path.size() - 1):
			if _distance_to_segment(point, path[index], path[index + 1]) < 3.0:
				return true

	return false


func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var segment: Vector2 = to - from
	var length_squared: float = segment.length_squared()
	if length_squared < 0.0001:
		return point.distance_to(from)

	var t: float = clampf((point - from).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(from + segment * t)


# ── Placement ────────────────────────────────────────────────────

func _place(
	piece: String,
	point: Vector2,
	yaw: float,
	extra_scale: float = 1.0,
	blocks_navigation: bool = false
) -> Node3D:
	var scene: PackedScene = _load_piece(piece)
	if scene == null:
		return null

	var node := scene.instantiate() as Node3D
	if node == null:
		return null

	_scenery.add_child(node)
	# Named after the piece rather than inheriting the glb's root name, so scenery
	# can be identified reliably by callers and tests.
	node.name = piece
	node.position = Vector3(point.x, 0.0, point.y)
	node.rotation.y = yaw
	node.scale = Vector3.ONE * KIT_SCALE * extra_scale

	# Only pieces big enough to path around are worth telling navigation about.
	if blocks_navigation:
		node.add_to_group("navmesh_source")

	return node


## Warm, flickering light on lamp posts. The demo's whole lighting idea is
## torchlight against fog, and these are what make the graveyard readable at all
## — and what give the player something to navigate between.
func _add_lamp(post: Node3D) -> void:
	var light := TorchFlicker.new()
	light.light_color = Color(1.0, 0.68, 0.34)
	light.base_energy = _rng.randf_range(2.2, 3.0)
	light.light_energy = light.base_energy
	light.omni_range = 13.0
	# Shadows from every lamp would be ruinous with this many lights; the fog and
	# the moonlight's shadows carry the depth instead.
	light.shadow_enabled = false
	light.position = Vector3(0.0, 1.2, 0.0)
	post.add_child(light)


func _load_piece(piece: String) -> PackedScene:
	if _scene_cache.has(piece):
		return _scene_cache[piece]

	var path: String = "%s/%s.glb" % [KIT, piece]
	if not ResourceLoader.exists(path):
		push_warning("[GraveyardBuilder] Missing kit piece: %s" % path)
		_scene_cache[piece] = null
		return null

	var scene := ResourceLoader.load(path) as PackedScene
	_scene_cache[piece] = scene
	return scene

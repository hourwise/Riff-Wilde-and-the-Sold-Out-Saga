class_name GraveyardTerrain
extends Node3D
## The shape of the ground under the cemetery.
##
## Replaces the flat plane the graveyard used to stand on. Relief does three jobs
## that a flat field cannot: it breaks the horizon so the level does not read as a
## tabletop, it makes somewhere to explore rather than merely cross, and — by
## being steep in the right places — it decides where the player may wander and
## where they must take the road.
##
## That last one is the reason the ridges below are authored rather than left to
## noise. Noise makes texture; it does not make a barrier you can rely on. A ridge
## that is only sometimes too steep to climb is worse than no ridge at all,
## because the player cannot learn it.
##
## Everything else in the level asks this node where the ground is, through
## height_at(). Scenery, roads, trees, altars and spawn points all sit on whatever
## it answers, so the terrain can be reshaped without touching any of them.

## Metres between height samples. Also the collision shape's sample spacing, which
## Godot fixes at one unit — so this is 1.0 and the shape is left unscaled.
## Scaled collision shapes are a known source of quiet misbehaviour.
const SAMPLE_SPACING: float = 1.0

## Fixed, like the layout seed: a level whose hills move between runs cannot be
## learned or bug-reported against.
const TERRAIN_SEED: int = 20260802

## Gentle relief everywhere, so no part of the cemetery is truly flat.
const HILL_FREQUENCY: float = 0.011
const HILL_AMPLITUDE: float = 3.2
## A second, finer layer. Without it the ground reads as smooth swells rather than
## broken graveyard soil.
const DETAIL_FREQUENCY: float = 0.055
const DETAIL_AMPLITUDE: float = 0.55

## Authored banks that separate one district from another. Anything steeper than
## the navigation agent's slope limit becomes impassable, which is what turns a
## route into the only route.
##
## The bank is a raised cosine, so its steepest grade is height * PI / (2 * width)
## — and that has to clear the agent's 38 degree limit with room to spare, or the
## bake bridges the crest anyway and the whole barrier quietly stops existing.
## The first attempt used widths around 13, which peaked at 42 degrees and was
## walkable in practice. These are about half as wide for the same height, which
## puts every bank past 48 degrees.
const RIDGES: Array[Dictionary] = [
	{
		# Wraps Weeping Hollow on three sides, leaving its road as the way in. A
		# bank across the front alone was not enough: the route simply walked round
		# the southern end of it, which is only eight per cent further and reads to
		# the player as the ridge not existing.
		"points": [
			Vector2(84.0, 18.0), Vector2(62.0, 20.0), Vector2(40.0, 16.0),
			Vector2(46.0, -2.0),
			Vector2(44.0, -24.0), Vector2(64.0, -30.0), Vector2(84.0, -28.0),
		],
		"height": 7.5, "width": 8.5,
	},
	{
		# The long western bank, between the graveyard and the mausoleum.
		"points": [Vector2(-38.0, -6.0), Vector2(-50.0, -22.0), Vector2(-58.0, -40.0)],
		"height": 6.5, "width": 9.0,
	},
	{
		# Screens the crypt maze, so its mouth is found by following the road.
		"points": [Vector2(26.0, -30.0), Vector2(40.0, -34.0), Vector2(58.0, -30.0), Vector2(80.0, -34.0)],
		"height": 8.0, "width": 8.5,
	},
	{
		# Divides the bone field from the courtyard, so the church is approached
		# up its own causeway rather than seen and walked at.
		"points": [Vector2(-46.0, -110.0), Vector2(-16.0, -114.0), Vector2(16.0, -114.0), Vector2(46.0, -110.0)],
		"height": 7.0, "width": 10.0,
	},
]

## Dips. Shallow enough to walk through, deep enough to hide what is in them until
## the player is close.
const HOLLOWS: Array[Dictionary] = [
	{"at": Vector2(-20.0, 6.0), "radius": 16.0, "depth": 2.6},
	{"at": Vector2(64.0, -6.0), "radius": 20.0, "depth": 3.4},   # Weeping Hollow earns its name
	{"at": Vector2(22.0, -12.0), "radius": 14.0, "depth": 2.0},
	{"at": Vector2(-70.0, -54.0), "radius": 18.0, "depth": 2.2},
	{"at": Vector2(-10.0, -92.0), "radius": 22.0, "depth": 2.8},
	{"at": Vector2(28.0, -100.0), "radius": 16.0, "depth": 2.4},
]

@export var ground_size: Vector2 = Vector2(200.0, 220.0)
@export var ground_centre: Vector2 = Vector2(0.0, -50.0)

## Circles levelled off, so altars, spawns and the boss arena are fought on flat
## ground. Filled in by the builder from its own clearing list.
##
## Each is {at, flat, taper}: level out to `flat`, then blend back to the natural
## ground over `taper`. The taper is stated in metres rather than as a proportion
## of the radius, because a proportional one scales with the zone — and the crypt
## maze needs a fifty-metre plateau, whose proportional taper reached seventy-five
## metres and quietly levelled a third of the cemetery, flattening the authored
## ridges down to gentle bumps.
var flatten_zones: Array[Dictionary] = []
## Routes levelled across their width, so a road runs along a slope rather than
## up the side of one. Filled in by the builder from its own path list.
var flatten_lines: Array[Dictionary] = []

var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _heights: PackedFloat32Array = PackedFloat32Array()
var _columns: int = 0
var _rows: int = 0
var _origin: Vector2 = Vector2.ZERO


func _ready() -> void:
	_configure_noise()


func _configure_noise() -> void:
	_hills.seed = TERRAIN_SEED
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = HILL_FREQUENCY

	_detail.seed = TERRAIN_SEED + 1
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.frequency = DETAIL_FREQUENCY


## Builds the heightfield, its mesh and its collision body.
func build() -> void:
	_configure_noise()

	_origin = ground_centre - ground_size * 0.5
	_columns = int(ground_size.x / SAMPLE_SPACING) + 1
	_rows = int(ground_size.y / SAMPLE_SPACING) + 1

	# Sampled once into a grid, then read from the grid. height_at is called for
	# every scenery piece, every road tile and every one of seven thousand trees,
	# and re-evaluating four noise layers and every ridge each time is the
	# difference between a level that loads and one that appears to hang.
	_heights.resize(_columns * _rows)
	for row in range(_rows):
		for column in range(_columns):
			_heights[row * _columns + column] = _sample(Vector2(
				_origin.x + float(column) * SAMPLE_SPACING,
				_origin.y + float(row) * SAMPLE_SPACING
			))

	_build_mesh()
	_build_collision()

	print("[GraveyardTerrain] %d x %d samples, relief %.1fm to %.1fm." % [
		_columns, _rows, _lowest(), _highest()
	])


## Ground height at a world XZ position.
##
## Interpolated from the baked grid rather than recomputed, so this agrees exactly
## with the mesh and the collision shape. A separate evaluation would drift from
## them and leave scenery hovering or sunk by a few centimetres everywhere.
func height_at(point: Vector2) -> float:
	if _heights.is_empty():
		return _sample(point)

	var local: Vector2 = (point - _origin) / SAMPLE_SPACING
	var column: int = clampi(int(floor(local.x)), 0, _columns - 2)
	var row: int = clampi(int(floor(local.y)), 0, _rows - 2)
	var fx: float = clampf(local.x - float(column), 0.0, 1.0)
	var fy: float = clampf(local.y - float(row), 0.0, 1.0)

	var top: float = lerpf(_height_at_index(column, row), _height_at_index(column + 1, row), fx)
	var bottom: float = lerpf(_height_at_index(column, row + 1), _height_at_index(column + 1, row + 1), fx)
	return lerpf(top, bottom, fy)


## Steepness at a world position, 0 flat and 1 vertical. Used to decide what grows
## where: grass on the flat, bare stone on the banks.
func slope_at(point: Vector2) -> float:
	var step: float = SAMPLE_SPACING
	var dx: float = height_at(point + Vector2(step, 0.0)) - height_at(point - Vector2(step, 0.0))
	var dz: float = height_at(point + Vector2(0.0, step)) - height_at(point - Vector2(0.0, step))
	return clampf(Vector2(dx, dz).length() / (2.0 * step), 0.0, 1.0)


# ── Height model ─────────────────────────────────────────────────

func _sample(point: Vector2) -> float:
	var height: float = _hills.get_noise_2d(point.x, point.y) * HILL_AMPLITUDE
	height += _detail.get_noise_2d(point.x, point.y) * DETAIL_AMPLITUDE
	height += _ridge_height(point)
	height -= _hollow_depth(point)

	# Levelling comes last, so a plaza is flat regardless of what the noise and
	# the ridges did there.
	return _apply_flattening(point, height)


func _ridge_height(point: Vector2) -> float:
	var raised: float = 0.0

	for ridge: Dictionary in RIDGES:
		var points: Array = ridge["points"]
		var nearest: float = INF
		for index in range(points.size() - 1):
			nearest = minf(nearest, _distance_to_segment(point, points[index], points[index + 1]))

		var width: float = float(ridge["width"])
		if nearest >= width:
			continue

		# Raised cosine, so the bank rises and falls smoothly and has no crease
		# along the top for a character to catch on.
		var across: float = nearest / width
		raised = maxf(raised, float(ridge["height"]) * 0.5 * (1.0 + cos(across * PI)))

	return raised


func _hollow_depth(point: Vector2) -> float:
	var sunk: float = 0.0
	for hollow: Dictionary in HOLLOWS:
		var distance: float = point.distance_to(hollow["at"])
		var radius: float = float(hollow["radius"])
		if distance >= radius:
			continue
		sunk = maxf(sunk, float(hollow["depth"]) * 0.5 * (1.0 + cos(distance / radius * PI)))
	return sunk


## Blends the sampled height toward a level value near plazas and along roads.
##
## Zones level first, then roads level on top of them. The order matters and so
## does what each one levels *toward*: a plaza levels to the height the land was
## already at in its middle, and a road levels to a running average of the ground
## it crosses, so a road follows the land lengthways while staying level across
## its width.
##
## Crucially the road's average is taken over ground that has already been
## levelled by the zones. Averaging raw ground instead makes a road disagree with
## any plaza it runs into, and the disagreement appears as a step at the join —
## which is what sealed the crypt maze off behind a cliff at its own entrance.
func _apply_flattening(point: Vector2, height: float) -> float:
	var result: float = _blend_zones(point, height)

	for line: Dictionary in flatten_lines:
		var points: Array = line["points"]
		var margin: float = float(line["margin"])
		var nearest: float = INF
		var nearest_point: Vector2 = point

		for index in range(points.size() - 1):
			var candidate: Vector2 = _closest_on_segment(point, points[index], points[index + 1])
			var distance: float = point.distance_to(candidate)
			if distance < nearest:
				nearest = distance
				nearest_point = candidate

		if nearest >= margin * 1.6:
			continue

		var weight: float = 1.0 - smoothstep(margin, margin * 1.6, nearest)
		result = lerpf(result, _road_height(points, nearest_point), weight)

	return result


## Levels the ground toward each plaza's own height.
func _blend_zones(point: Vector2, height: float) -> float:
	var result: float = height

	for zone: Dictionary in flatten_zones:
		var centre: Vector2 = zone["at"]
		var flat: float = float(zone["flat"])
		var taper: float = float(zone["taper"])
		var distance: float = point.distance_to(centre)
		if distance >= flat + taper:
			continue

		var weight: float = 1.0 - smoothstep(flat, flat + taper, distance)
		result = lerpf(result, _raw(centre), weight)

	return result


## Height of a road at a point on its centreline, smoothed along its length.
##
## Levelling a road only across its width leaves it climbing whatever it crosses
## — the church causeway went straight up and over a seven-metre ridge, at a
## grade steep enough that the navigation bake dropped it and the boss arena
## became unreachable on foot.
##
## Averaging over a stretch of the route in both directions cuts a gentle grade
## through high ground and banks up across low ground, which is what a road
## actually does to a landscape.
func _road_height(points: Array, at: Vector2) -> float:
	const REACH: float = 14.0
	const STEP: float = 2.0

	var total: float = 0.0
	var samples: int = 0

	# Walked along the polyline rather than sampled in a straight line, so the
	# average follows the route round its corners instead of cutting across them.
	for index in range(points.size() - 1):
		var from: Vector2 = points[index]
		var to: Vector2 = points[index + 1]
		var length: float = from.distance_to(to)
		if length < 0.001:
			continue

		var steps: int = maxi(1, int(length / STEP))
		for step in range(steps + 1):
			var along: Vector2 = from.lerp(to, float(step) / float(steps))
			if along.distance_to(at) > REACH:
				continue
			total += _blend_zones(along, _raw(along))
			samples += 1

	return _blend_zones(at, _raw(at)) if samples == 0 else total / float(samples)


## Height before any levelling. Used as the target to level toward, which is why
## it must not itself be levelled — that would be circular.
func _raw(point: Vector2) -> float:
	var height: float = _hills.get_noise_2d(point.x, point.y) * HILL_AMPLITUDE
	height += _detail.get_noise_2d(point.x, point.y) * DETAIL_AMPLITUDE
	height += _ridge_height(point)
	height -= _hollow_depth(point)
	return height


# ── Mesh and collision ───────────────────────────────────────────

func _build_mesh() -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	vertices.resize(_columns * _rows)
	normals.resize(_columns * _rows)
	colours.resize(_columns * _rows)
	uvs.resize(_columns * _rows)

	for row in range(_rows):
		for column in range(_columns):
			var index: int = row * _columns + column
			var world := Vector2(
				_origin.x + float(column) * SAMPLE_SPACING,
				_origin.y + float(row) * SAMPLE_SPACING
			)
			vertices[index] = Vector3(world.x, _height_at_index(column, row), world.y)
			normals[index] = _normal_at_index(column, row)
			colours[index] = _ground_colour(world, normals[index])
			uvs[index] = world / 8.0

	for row in range(_rows - 1):
		for column in range(_columns - 1):
			var top_left: int = row * _columns + column
			var top_right: int = top_left + 1
			var bottom_left: int = top_left + _columns
			var bottom_right: int = bottom_left + 1

			indices.append(top_left)
			indices.append(bottom_left)
			indices.append(top_right)

			indices.append(top_right)
			indices.append(bottom_left)
			indices.append(bottom_right)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var material := StandardMaterial3D.new()
	# Ground cover is painted into the vertex colours rather than textured: the
	# kit has no ground textures, and at this scale a per-vertex blend of grass,
	# earth and stone reads better than one flat albedo anyway.
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mesh.surface_set_material(0, material)

	var instance := MeshInstance3D.new()
	instance.name = "TerrainMesh"
	instance.mesh = mesh
	add_child(instance)

	# Navigation bakes from this group, so the ground the enemies walk on has to
	# be in it. Slopes steeper than the agent's limit are simply left out of the
	# baked mesh, which is exactly how the ridges become impassable.
	#
	# The mesh AND the collision body are both registered, and the navigation mesh
	# is set to parse both kinds. It parses static colliders by default, so a
	# terrain contributed only as a MeshInstance3D is silently ignored — which
	# bakes eighteen polygons for a two-hundred-metre level and reads as the
	# terrain having no walkable ground at all.
	instance.add_to_group("navmesh_source")


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	add_child(body)

	var shape := HeightMapShape3D.new()
	shape.map_width = _columns
	shape.map_depth = _rows
	shape.map_data = _heights

	var collider := CollisionShape3D.new()
	collider.shape = shape
	# The shape is centred on its own origin and samples at one unit, so it is
	# positioned rather than scaled. Scaling a heightmap shape is the kind of
	# thing that works until something stands on the seam.
	body.add_to_group("navmesh_source")

	collider.position = Vector3(
		_origin.x + float(_columns - 1) * SAMPLE_SPACING * 0.5,
		0.0,
		_origin.y + float(_rows - 1) * SAMPLE_SPACING * 0.5
	)
	body.add_child(collider)


## Grass on the flat, worn earth on the slopes, bare stone on the banks. Blended
## by steepness, so the transition follows the shape of the land.
func _ground_colour(point: Vector2, normal: Vector3) -> Color:
	const GRASS := Color(0.17, 0.21, 0.13)
	const EARTH := Color(0.19, 0.15, 0.11)
	const STONE := Color(0.24, 0.24, 0.26)

	var flatness: float = clampf(normal.dot(Vector3.UP), 0.0, 1.0)
	var steepness: float = 1.0 - flatness

	var colour: Color = GRASS.lerp(EARTH, smoothstep(0.06, 0.26, steepness))
	colour = colour.lerp(STONE, smoothstep(0.3, 0.55, steepness))

	# A little variation so a hillside is not one flat sheet of colour.
	var mottle: float = _detail.get_noise_2d(point.x * 2.0, point.y * 2.0) * 0.05
	return Color(
		clampf(colour.r + mottle, 0.0, 1.0),
		clampf(colour.g + mottle, 0.0, 1.0),
		clampf(colour.b + mottle, 0.0, 1.0)
	)


func _normal_at_index(column: int, row: int) -> Vector3:
	var left: float = _height_at_index(column - 1, row)
	var right: float = _height_at_index(column + 1, row)
	var back: float = _height_at_index(column, row - 1)
	var front: float = _height_at_index(column, row + 1)
	return Vector3(left - right, 2.0 * SAMPLE_SPACING, back - front).normalized()


func _height_at_index(column: int, row: int) -> float:
	var x: int = clampi(column, 0, _columns - 1)
	var y: int = clampi(row, 0, _rows - 1)
	return _heights[y * _columns + x]


func _lowest() -> float:
	var lowest: float = INF
	for height: float in _heights:
		lowest = minf(lowest, height)
	return 0.0 if is_inf(lowest) else lowest


func _highest() -> float:
	var highest: float = -INF
	for height: float in _heights:
		highest = maxf(highest, height)
	return 0.0 if is_inf(highest) else highest


func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	return point.distance_to(_closest_on_segment(point, from, to))


func _closest_on_segment(point: Vector2, from: Vector2, to: Vector2) -> Vector2:
	var segment: Vector2 = to - from
	var length_squared: float = segment.length_squared()
	if length_squared < 0.0001:
		return from
	return from + segment * clampf((point - from).dot(segment) / length_squared, 0.0, 1.0)

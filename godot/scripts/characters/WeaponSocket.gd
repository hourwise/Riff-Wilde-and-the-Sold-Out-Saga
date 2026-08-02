class_name WeaponSocket
extends BoneAttachment3D
## Mounts a weapon on a hand bone at a real-world size, gripped at a chosen point.
##
## Bone space is not world space. Riff's rig comes out of Meshy with the armature
## scaled to roughly 1/136, so a lute set to "1.5" in the scene rendered eleven
## millimetres across — present, correct, parented to the right bone, and
## completely invisible. Baking the reciprocal into the scene would fix it until
## the next re-export silently changed the armature scale again.
##
## So nothing here is a magic number. The socket measures the bone's world scale
## and the weapon's own bounds, and sizes it to a length in metres.
##
## The grip is described the way a person would describe it: which end you hold,
## and which way the business end points.

## How long the weapon should be in the world, along its longest axis.
@export var weapon_length_metres: float = 0.72

## Where along the weapon the hand closes, from 0 at the striking end to 1 at the
## far end. Riff holds his lute by the neck and hits with the body, so this sits
## well up the neck, short of the headstock.
@export_range(0.0, 1.0, 0.01) var grip_fraction: float = 0.78

## Direction, in the bone's own space, that the striking end points.
##
## Expressed in bone space so the grip holds through a swing rather than only in
## the idle pose. Which axis to use has to be measured, not reasoned about — a
## hand bone's axes are whatever the rigger left them as. On Riff's rig, bone +Y
## comes out pointing down in the world, so the lute hangs body-down from his
## fist like a club. tools/inspect_weapon.gd prints all six.
@export var strike_direction: Vector3 = Vector3(0.0, 1.0, 0.0)

## Which way the weapon's face is turned about its own long axis.
@export_range(-180.0, 180.0, 15.0) var roll_degrees: float = 0.0

## Fine adjustment after everything else, in metres.
@export var grip_offset: Vector3 = Vector3.ZERO


func _ready() -> void:
	# Deferred so the skeleton has posed itself. Measured against an unposed
	# skeleton, the bone's world scale is whatever the rest pose happens to say.
	call_deferred("_fit_weapons")


## Fits immediately rather than waiting for the deferred call. Tools and tests
## measure the weapon in the same frame they build the player, which is before
## the deferred fit would have run.
func fit_now() -> void:
	_fit_weapons()


## The weapon's world size and its bone's scale, for tools and tests.
func describe() -> Dictionary:
	var weapon: Node3D = _weapon()
	if weapon == null:
		return {}

	var bounds: AABB = _bounds(weapon, weapon.global_transform.affine_inverse())
	return {
		"bone_scale": _bone_scale(),
		"world_length": _longest(bounds.size) * weapon.global_transform.basis.get_scale().x,
		"grip_error": _grip_point(weapon).distance_to(global_position),
	}


func _fit_weapons() -> void:
	for child in get_children():
		var weapon := child as Node3D
		if weapon != null:
			_fit(weapon)


func _fit(weapon: Node3D) -> void:
	# Measured with the weapon's own transform taken out, so re-fitting an already
	# fitted weapon gives the same answer rather than compounding.
	weapon.transform = Transform3D.IDENTITY
	# Measured in the weapon's own space, not the world's. Measuring in world
	# space folds the bone's 1/136 armature scale into the very length being
	# corrected for, and the correction then squares it.
	var bounds: AABB = _bounds(weapon, weapon.global_transform.affine_inverse())
	if bounds.size == Vector3.ZERO:
		push_warning("[WeaponSocket] %s has no geometry to fit." % weapon.name)
		return

	var axis: int = _longest_axis(bounds)
	var length: float = bounds.size[axis]
	var bone_scale: float = _bone_scale()
	if length <= 0.0 or bone_scale <= 0.0:
		return

	# The scale that makes the weapon weapon_length_metres long in the world,
	# whatever the armature was exported at.
	var fitted: float = weapon_length_metres / (length * bone_scale)

	# The weapon's long axis is rotated onto the strike direction. Its low end is
	# the striking end: on this lute, slicing the mesh along its length shows the
	# fat body at the low end, the narrow neck above it, and the headstock
	# flaring out at the top. See tools/inspect_weapon.gd.
	var forward: Vector3 = strike_direction.normalized()
	if forward == Vector3.ZERO:
		forward = Vector3.DOWN

	var local_axis: Vector3 = Vector3.ZERO
	local_axis[axis] = -1.0

	var basis: Basis = _rotation_between(local_axis, forward)
	basis = Basis(forward, deg_to_rad(roll_degrees)) * basis

	# The grip point is pulled back to the socket, so the hand closes there
	# instead of at the model's origin.
	var grip_local: Vector3 = bounds.get_center()
	grip_local[axis] = bounds.position[axis] + bounds.size[axis] * grip_fraction

	weapon.transform = Transform3D(
		basis.scaled(Vector3.ONE * fitted),
		grip_offset - basis * (grip_local * fitted)
	)


## Shortest rotation taking one direction onto another.
func _rotation_between(from: Vector3, to: Vector3) -> Basis:
	var a: Vector3 = from.normalized()
	var b: Vector3 = to.normalized()
	var dot: float = a.dot(b)

	if dot > 0.9999:
		return Basis.IDENTITY
	if dot < -0.9999:
		# Opposed: any perpendicular axis will do for a half turn.
		var perpendicular: Vector3 = a.cross(Vector3.UP)
		if perpendicular.length_squared() < 0.0001:
			perpendicular = a.cross(Vector3.RIGHT)
		return Basis(perpendicular.normalized(), PI)

	return Basis(a.cross(b).normalized(), acos(clampf(dot, -1.0, 1.0)))


## World scale of the bone this socket rides, which is what the weapon inherits.
func _bone_scale() -> float:
	return global_transform.basis.get_scale().x


func _weapon() -> Node3D:
	for child in get_children():
		var weapon := child as Node3D
		if weapon != null:
			return weapon
	return null


func _grip_point(weapon: Node3D) -> Vector3:
	var bounds: AABB = _bounds(weapon, weapon.global_transform.affine_inverse())
	var axis: int = _longest_axis(bounds)
	var point: Vector3 = bounds.get_center()
	point[axis] = bounds.position[axis] + bounds.size[axis] * grip_fraction
	return weapon.global_transform * point


func _bounds(node: Node3D, relative_to: Transform3D) -> AABB:
	var bounds := AABB()
	var first: bool = true
	for visual: VisualInstance3D in _visuals(node):
		var box: AABB = relative_to * visual.global_transform * visual.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds


func _longest_axis(bounds: AABB) -> int:
	if bounds.size.x >= bounds.size.y and bounds.size.x >= bounds.size.z:
		return 0
	return 1 if bounds.size.y >= bounds.size.z else 2


func _longest(size: Vector3) -> float:
	return maxf(size.x, maxf(size.y, size.z))


func _visuals(node: Node) -> Array[VisualInstance3D]:
	var found: Array[VisualInstance3D] = []
	if node is VisualInstance3D:
		found.append(node as VisualInstance3D)
	for child in node.get_children():
		found.append_array(_visuals(child))
	return found

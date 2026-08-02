class_name DirgeCantorAI
extends EnemyAI
## Dirge Cantor. A hooded chorister who sings notes at you from across the yard.
##
## Exists to make the dodge matter. Riff has had an invulnerability window and a
## dodge animation since Phase 2, and nothing in the roster gave either a reason
## to be used: every attack in the game was a melee swing you could walk out of.
## A note crossing twelve metres is something you have to time a roll against.
##
## It kites — backing off when approached and firing when it has room — so the
## answer to it is to close, which is exactly the pressure the rest of the roster
## does not apply. Left alone at range it is a slow, steady tax on health; run
## down, it dies quickly.
##
## The wind-up is long and lit, because a projectile you cannot see coming is not
## a dodge test, it is a health tax with extra steps.

## Range at which it is happy to stand and sing.
@export var preferred_distance: float = 12.0
## Closer than this and it gives ground rather than firing.
@export var retreat_distance: float = 7.0
## Beyond this it moves up instead of wasting notes at extreme range.
@export var engage_distance: float = 16.0

@export var projectile_scene: PackedScene = null
## Height the note leaves from, so it flies from the chest rather than the ankles.
@export var muzzle_height: float = 1.2

@export_group("Telegraph")
## Colour of the gathering note. Blue spectral light, per the art direction.
@export var telegraph_colour: Color = Color(0.45, 0.8, 1.0)
@export var telegraph_radius: float = 0.35

var _telegraph: MeshInstance3D = null
var _telegraph_material: StandardMaterial3D = null


func _ready() -> void:
	super._ready()
	_build_telegraph()


## Kites instead of closing.
##
## The base class walks at the player until it is within attack range. Overriding
## the movement rather than the attack is deliberate: the distance it keeps *is*
## its behaviour, and expressing that as "attack range = 12" while still charging
## in would have it firing point blank.
func _update_ai(delta: float) -> void:
	if target == null:
		_change_state(State.IDLE)
		_patrol(delta)
		return

	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	var distance: float = to_target.length()

	if distance > _stat_detection_range():
		if chase_memory_timer <= 0.0 or distance > _stat_leash_range():
			_change_state(State.IDLE)
			_patrol(delta)
			return
	else:
		last_known_target_position = target.global_position
		chase_memory_timer = _stat_chase_memory()

	# Always facing the player while it has one: it is aiming, and a caster that
	# fires over its shoulder reads as a bug.
	if to_target != Vector3.ZERO:
		_face(to_target.normalized(), delta)

	if distance < retreat_distance:
		_change_state(State.CHASE)
		_give_ground(delta)
		return

	if distance > engage_distance:
		_change_state(State.CHASE)
		_close_in(delta, target.global_position)
		return

	# In its window: stand and sing.
	_change_state(State.ATTACK)
	_apply_friction(delta)
	_try_start_attack()


func _give_ground(delta: float) -> void:
	var direction: Vector3 = (
		steering.get_retreat_direction(target.global_position, retreat_distance * 1.5)
		if steering != null
		else (global_position - target.global_position).normalized()
	)
	if direction == Vector3.ZERO:
		_apply_friction(delta)
		return

	# Backing away is slower than advancing, so closing on a Cantor is always
	# possible. A kiter that outruns the player is not a fight, it is a chore.
	var speed: float = _stat_move_speed() * 0.75
	velocity.x = move_toward(velocity.x, direction.x * speed, _stat_acceleration() * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, _stat_acceleration() * delta)


func _close_in(delta: float, goal: Vector3) -> void:
	var direction: Vector3 = (
		steering.get_direction_to(goal) if steering != null
		else (goal - global_position).normalized()
	)
	if direction == Vector3.ZERO:
		_apply_friction(delta)
		return

	var speed: float = _stat_move_speed()
	velocity.x = move_toward(velocity.x, direction.x * speed, _stat_acceleration() * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, _stat_acceleration() * delta)


## The gathering note, shown for the whole wind-up.
func _begin_attack() -> void:
	super._begin_attack()
	if _telegraph != null:
		_telegraph.visible = true
		_telegraph.scale = Vector3.ONE * 0.2


func _process(delta: float) -> void:
	if _telegraph == null or not _telegraph.visible:
		return

	# Swells as the wind-up runs down, so the moment of release is readable.
	var windup: float = maxf(_stat_attack_windup(), 0.001)
	var charged: float = clampf(1.0 - attack_windup_timer / windup, 0.0, 1.0)
	_telegraph.scale = Vector3.ONE * lerpf(0.2, 1.0, charged)
	if _telegraph_material != null:
		_telegraph_material.emission_energy_multiplier = lerpf(1.0, 4.0, charged)


func _resolve_attack() -> void:
	if _telegraph != null:
		_telegraph.visible = false

	if target == null or projectile_scene == null:
		return

	var note := projectile_scene.instantiate() as Node3D
	if note == null:
		return

	# Parented to the level, not to the Cantor: a note must keep flying after its
	# singer is cut down, or killing the caster deletes a shot already in the air
	# and the player learns to ignore telegraphs.
	var host: Node = get_parent()
	host.add_child(note)

	var muzzle: Vector3 = global_position + Vector3.UP * muzzle_height
	note.global_position = muzzle

	var aim: Vector3 = target.global_position + Vector3.UP * 0.8 - muzzle
	if note.has_method("launch"):
		note.call("launch", aim.normalized(), target)
	note.set("attacker", self)

	AudioManager.play_sfx_3d(&"cantor_note", muzzle)


func _cancel_attack() -> void:
	super._cancel_attack()
	if _telegraph != null:
		_telegraph.visible = false


func _build_telegraph() -> void:
	_telegraph = MeshInstance3D.new()
	_telegraph.name = "NoteTelegraph"

	var sphere := SphereMesh.new()
	sphere.radius = telegraph_radius
	sphere.height = telegraph_radius * 2.0
	sphere.radial_segments = 10
	sphere.rings = 6

	_telegraph_material = StandardMaterial3D.new()
	_telegraph_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_telegraph_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_telegraph_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_telegraph_material.albedo_color = telegraph_colour
	_telegraph_material.emission_enabled = true
	_telegraph_material.emission = telegraph_colour
	sphere.material = _telegraph_material

	_telegraph.mesh = sphere
	_telegraph.position = Vector3(0.0, muzzle_height, -0.45)
	_telegraph.visible = false
	add_child(_telegraph)

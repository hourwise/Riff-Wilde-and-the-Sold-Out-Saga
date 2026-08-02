class_name SpectralNote
extends Area3D
## A sung note, thrown. The Dirge Cantor's ranged attack.
##
## The reason a projectile exists at all is the dodge. Riff has an invulnerability
## window and a dodge animation, and until now nothing in the roster made either
## worth using: every enemy attack was a melee swing you could simply walk out of.
## A note that crosses the graveyard at a readable speed is something you have to
## actually time a roll against.
##
## So its speed and telegraph are the design, not its damage. It travels slowly
## enough to be seen coming and read, and its lifetime is bounded so a miss ends
## rather than sailing on into another district.

## Metres per second. Slow enough to react to, fast enough not to be strolled away
## from — roughly a second and a half of travel at the Cantor's firing range.
@export var speed: float = 11.0
@export var damage: float = 12.0
@export var knockback_force: float = 5.0
## Seconds before it gives up. A note that never expires is a leak with a
## collision shape.
@export var lifetime: float = 4.0
## How sharply it curves toward the player, in degrees per second. A little
## tracking punishes standing still without making the dodge pointless.
@export var homing_degrees_per_second: float = 45.0
## Tracking stops this close, so a well-timed dodge cannot be followed around.
@export var homing_cutoff: float = 3.5

var attacker: Node = null

var _direction: Vector3 = Vector3.FORWARD
var _target: Node3D = null
var _age: float = 0.0


func _ready() -> void:
	add_to_group("enemy_projectiles")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


## Aimed when fired rather than steered from a fixed origin, so the note carries
## the direction it was launched in even if the Cantor dies mid-flight.
func launch(direction: Vector3, target: Node3D = null) -> void:
	_direction = direction.normalized()
	if _direction == Vector3.ZERO:
		_direction = Vector3.FORWARD
	_target = target
	look_at(global_position + _direction, Vector3.UP)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		_dissipate()
		return

	_steer(delta)
	global_position += _direction * speed * delta


func _steer(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return

	var to_target: Vector3 = _target.global_position + Vector3.UP * 0.8 - global_position
	if to_target.length() <= homing_cutoff:
		return

	var limit: float = deg_to_rad(homing_degrees_per_second) * delta
	var desired: Vector3 = to_target.normalized()
	var angle: float = _direction.angle_to(desired)
	if angle <= 0.0001:
		return

	var axis: Vector3 = _direction.cross(desired)
	if axis.length_squared() < 0.000001:
		return

	_direction = _direction.rotated(axis.normalized(), minf(angle, limit)).normalized()
	look_at(global_position + _direction, Vector3.UP)


## The player is damaged through PlayerStats, not through a Hurtbox.
##
## Riff has no Hurtbox node — his invulnerability lives in PlayerStats.can_take_
## damage(), which reads the dodge window off the controller, and every melee
## enemy already damages him by calling it directly. A projectile that looked for
## a Hurtbox instead found nothing and passed straight through him, silently.
func _on_body_entered(body: Node3D) -> void:
	# Fired past its own side rather than into it.
	if body.is_in_group("enemies"):
		return

	if body.is_in_group("player"):
		var stats: Node = body.get("stats")
		if stats != null and bool(stats.call("can_take_damage")):
			stats.call("take_damage", damage)
			_push(body)
		# Spent either way: a note absorbed during i-frames is still spent, so
		# dodging costs the Cantor its shot rather than delaying it.
		_dissipate()
		return

	# Anything else is world geometry. The note breaks on a crypt wall rather than
	# passing through it, so taking cover is a real answer to being shot at.
	_dissipate()


## Knockback, matching how Hitbox does it: horizontal, away from the impact.
func _push(body: Node3D) -> void:
	if not body.has_method("apply_knockback"):
		return
	var away: Vector3 = body.global_position - global_position
	away.y = 0.0
	if away == Vector3.ZERO:
		away = _direction
	body.call("apply_knockback", away.normalized() * knockback_force)


## Hurtboxes are still handled, for anything that has one — Sir Brass, and
## whatever else ends up standing in front of a Cantor.
func _on_area_entered(area: Area3D) -> void:
	var hurtbox := area as Hurtbox
	if hurtbox == null:
		return

	var victim: Node = hurtbox.get_parent()
	if victim != null and victim.is_in_group("enemies"):
		return

	var push: Vector3 = (hurtbox.global_position - global_position)
	push.y = 0.0
	push = push.normalized() if push != Vector3.ZERO else _direction

	var event := DamageEvent.new(
		damage, knockback_force, push, attacker, &"", 0.0, &"spectral_note", 0.0
	)
	hurtbox.receive_damage(event)
	_dissipate()


func _dissipate() -> void:
	set_physics_process(false)
	monitoring = false
	queue_free()

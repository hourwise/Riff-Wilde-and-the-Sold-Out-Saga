class_name GraveCrawlerAI
extends EnemyAI
## Grave Crawler. Fast, fragile swarm enemy that closes with a leap.
##
## Teaches crowd control: individually trivial, dangerous in numbers. The leap
## means backing away is not a reliable answer, which pushes the player toward
## the Crescendo shockwave and the Sing cone instead of retreating.

const TELEGRAPH_COLOUR: Color = Color(0.55, 1.0, 0.45)

## Range at which the crawler commits to a leap instead of walking in.
@export var leap_range: float = 6.5
@export var leap_speed: float = 13.0
@export var leap_rise: float = 4.5
@export var leap_cooldown: float = 3.0
## Damage dealt on landing, distinct from the ordinary swipe.
@export var leap_damage: float = 10.0
@export var leap_impact_radius: float = 1.8

var _is_leaping: bool = false
var _leap_cooldown_timer: float = 0.0


func _tick_timers(delta: float) -> void:
	super._tick_timers(delta)
	if _leap_cooldown_timer > 0.0:
		_leap_cooldown_timer -= delta


func _update_ai(delta: float) -> void:
	# A leap is ballistic: hand control to gravity until it lands, or the crawler
	# would steer mid-air and the arc would read as floaty.
	if _is_leaping:
		if is_on_floor() and velocity.y <= 0.0:
			_land()
		return

	if _should_leap():
		_start_leap()
		return

	super._update_ai(delta)


func _should_leap() -> bool:
	if _leap_cooldown_timer > 0.0 or target == null or _target_is_defeated():
		return false
	if not is_on_floor():
		return false

	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	var distance: float = to_target.length()

	# Leap from mid-range only: too close and it overshoots, too far and the
	# player has no chance to read it.
	return distance > _stat_attack_range() * 1.5 and distance <= leap_range


func _start_leap() -> void:
	_is_leaping = true
	_leap_cooldown_timer = leap_cooldown
	_cancel_attack()
	_change_state(State.ATTACK)

	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	var direction: Vector3 = to_target.normalized()

	velocity = direction * leap_speed
	velocity.y = leap_rise

	flash(TELEGRAPH_COLOUR, 2.6, 0.35)
	if visual != null:
		# Index 1 is the jump clip; index 0 is the ordinary swipe.
		visual.play_attack(1)
	AudioManager.play_sfx_3d(&"gravecrawler_leap", global_position)


func _land() -> void:
	_is_leaping = false
	velocity.x = 0.0
	velocity.z = 0.0

	if target == null or not is_instance_valid(target) or _target_is_defeated():
		return

	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() <= leap_impact_radius and target.stats.can_take_damage():
		target.stats.take_damage(leap_damage)


func _begin_attack() -> void:
	super._begin_attack()
	flash(TELEGRAPH_COLOUR, 1.8, _stat_attack_windup())
	AudioManager.play_sfx_3d(&"gravecrawler_screech", global_position)


## A crawler knocked out of the air must stop leaping, or it keeps its ballistic
## velocity and skates across the ground on landing.
func _on_damaged(event: DamageEvent) -> void:
	_is_leaping = false
	super._on_damaged(event)


func die() -> void:
	if is_dead:
		return
	AudioManager.play_sfx_3d(&"gravecrawler_death", global_position)
	super.die()

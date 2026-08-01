class_name EnemyAI
extends EnemyBase
## Shared behaviour for every enemy: perception, chase, telegraphed attack,
## stagger and leash.
##
## Subclasses tune via an EnemyStats resource and override the attack hooks
## (_begin_attack / _resolve_attack) rather than reimplementing the loop. Movement
## direction always comes from EnemySteering, so the whole roster paths and
## spreads out consistently.

enum State { IDLE, CHASE, ATTACK, STAGGER, DEAD }

## Tuning. Assigning one overrides the inline exports inherited from EnemyBase.
@export var stats: EnemyStats

var current_state: State = State.IDLE
var target: PlayerController = null

var attack_cooldown_timer: float = 0.0
var attack_windup_timer: float = 0.0
var is_winding_up_attack: bool = false
var hit_stun_timer: float = 0.0
var chase_memory_timer: float = 0.0
var last_known_target_position: Vector3 = Vector3.ZERO

## Damage absorbed since the poise window opened. Heavies shrug off chip damage
## and only stagger once this exceeds their poise.
var poise_damage: float = 0.0
var poise_timer: float = 0.0

## Set by the Hollow Choir's song. Multiplies outgoing damage while it lasts.
var _damage_multiplier: float = 1.0
var _buff_timer: float = 0.0

@onready var steering: EnemySteering = get_node_or_null("EnemySteering") as EnemySteering
@onready var visual: CharacterVisual = get_node_or_null("CharacterVisual") as CharacterVisual


func _ready() -> void:
	_apply_stats()
	super._ready()
	add_to_group("enemies")
	_find_target()


## Copies the stats resource onto the runtime fields. Kept explicit rather than
## reading stats everywhere so an enemy can still be tweaked per-instance in a
## scene, and so scenes with no stats resource keep their inline values.
func _apply_stats() -> void:
	if stats == null:
		return

	max_health = stats.max_health
	knockback_resistance = stats.knockback_resistance
	friction = stats.friction


func _physics_process(delta: float) -> void:
	if is_dead:
		current_state = State.DEAD
		return

	_tick_timers(delta)

	if target == null or not is_instance_valid(target):
		_find_target()

	if _target_is_defeated():
		_cancel_attack()
		_change_state(State.IDLE)
		_apply_gravity(delta)
		_apply_friction(delta)
		move_and_slide()
		return

	if is_knocked_down:
		_change_state(State.STAGGER)
		apply_movement_decay(delta)
		move_and_slide()
		return

	if hit_stun_timer > 0.0:
		_cancel_attack()
		_change_state(State.STAGGER)
		_apply_gravity(delta)
		_apply_friction(delta)
		move_and_slide()
		return

	_apply_gravity(delta)
	_update_ai(delta)
	_update_visual()
	move_and_slide()


func _tick_timers(delta: float) -> void:
	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer -= delta
	if hit_stun_timer > 0.0:
		hit_stun_timer -= delta
	if chase_memory_timer > 0.0:
		chase_memory_timer -= delta

	if poise_timer > 0.0:
		poise_timer -= delta
		if poise_timer <= 0.0:
			poise_damage = 0.0

	if _buff_timer > 0.0:
		_buff_timer -= delta
		if _buff_timer <= 0.0:
			_damage_multiplier = 1.0
			flash(Color(0.5, 0.5, 0.55), 0.6, 0.3)

	if attack_windup_timer > 0.0:
		attack_windup_timer -= delta
		if attack_windup_timer <= 0.0:
			is_winding_up_attack = false
			attack_cooldown_timer = _stat_attack_cooldown()
			_resolve_attack()


func _update_ai(delta: float) -> void:
	if target == null:
		_change_state(State.IDLE)
		return

	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	var distance: float = to_target.length()
	var can_see: bool = distance <= _stat_detection_range()

	if can_see:
		last_known_target_position = target.global_position
		chase_memory_timer = _stat_chase_memory()
	elif distance > _stat_leash_range() or chase_memory_timer <= 0.0:
		_change_state(State.IDLE)
		_apply_friction(delta)
		return

	if can_see and distance <= _stat_attack_range():
		_change_state(State.ATTACK)
		_apply_friction(delta)
		_face(to_target.normalized(), delta)
		_try_start_attack()
		return

	var goal: Vector3 = target.global_position if can_see else last_known_target_position
	var to_goal: Vector3 = goal - global_position
	to_goal.y = 0.0

	_change_state(State.CHASE)
	if to_goal.length() <= _stat_attack_range() * 0.75:
		_apply_friction(delta)
		return

	var direction: Vector3 = steering.get_direction_to(goal) if steering != null else to_goal.normalized()
	if direction == Vector3.ZERO:
		_apply_friction(delta)
		return

	var target_velocity: Vector3 = direction * _stat_move_speed()
	velocity.x = move_toward(velocity.x, target_velocity.x, _stat_acceleration() * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, _stat_acceleration() * delta)
	_face(direction, delta)


# ── Attacking ────────────────────────────────────────────────────

func _try_start_attack() -> void:
	if attack_cooldown_timer > 0.0 or is_winding_up_attack:
		return
	if target == null or _target_is_defeated():
		return

	is_winding_up_attack = true
	attack_windup_timer = _stat_attack_windup()
	_begin_attack()


## Called by the Hollow Choir when its song completes. Public because the Choir
## needs to reach any enemy type without knowing what it is.
func apply_choir_buff(multiplier: float, duration: float) -> void:
	if is_dead:
		return

	_damage_multiplier = maxf(_damage_multiplier, multiplier)
	_buff_timer = duration
	# Buffed enemies must be visually distinct, or the player cannot tell why the
	# fight suddenly got harder.
	flash(Color(0.45, 0.8, 1.0), 2.0, duration)


## Hook: called as the wind-up starts. Override to telegraph.
func _begin_attack() -> void:
	if visual != null:
		visual.play_attack(0)


## Hook: called when the wind-up completes. Override for non-melee attacks.
func _resolve_attack() -> void:
	if target == null or not is_instance_valid(target) or _target_is_defeated():
		return

	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	# Re-check range on resolve, so stepping out of a telegraph actually works.
	if to_target.length() > _stat_attack_range() + 0.35:
		return

	if target.stats.can_take_damage():
		target.stats.take_damage(_stat_attack_damage())


func _cancel_attack() -> void:
	is_winding_up_attack = false
	attack_windup_timer = 0.0


# ── Damage ───────────────────────────────────────────────────────

func _on_damaged(event: DamageEvent) -> void:
	super._on_damaged(event)
	if is_dead:
		return

	if visual != null:
		visual.play_hit()

	if event.status_effect == &"knockdown":
		return

	# Poise: fodder staggers on every hit, heavies only once the window fills.
	var poise_limit: float = _stat_poise()
	if poise_limit <= 0.0:
		hit_stun_timer = _stat_hit_stun()
		return

	poise_damage += event.damage_amount
	poise_timer = _stat_poise_window()
	if poise_damage >= poise_limit:
		poise_damage = 0.0
		poise_timer = _stat_poise_recovery()
		hit_stun_timer = _stat_hit_stun()
		EventBus.enemy_staggered.emit(self)


func die() -> void:
	if is_dead:
		return
	if visual != null:
		visual.play_death()
	super.die()


# ── Helpers ──────────────────────────────────────────────────────

func _update_visual() -> void:
	if visual == null:
		return
	var speed: float = Vector2(velocity.x, velocity.z).length()
	visual.play_locomotion(speed / maxf(_stat_move_speed(), 0.01))


## direction is world-space; mesh.rotation is local to this body, which a level may
## place at any yaw, so convert before deriving the angle.
func _face(direction: Vector3, delta: float) -> void:
	if mesh == null or direction == Vector3.ZERO:
		return

	var local_direction: Vector3 = global_transform.basis.orthonormalized().inverse() * direction
	local_direction.y = 0.0
	if local_direction.length_squared() < 0.0001:
		return

	mesh.rotation.y = lerp_angle(
		mesh.rotation.y,
		atan2(-local_direction.x, -local_direction.z),
		_stat_turn_speed() * delta
	)


func _find_target() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty() and players[0] is PlayerController:
		target = players[0] as PlayerController


func _target_is_defeated() -> bool:
	return target != null and target.is_dead


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0


func _apply_friction(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	velocity.z = move_toward(velocity.z, 0.0, friction * delta)


func _change_state(new_state: State) -> void:
	if current_state == new_state:
		return
	current_state = new_state


# ── Stat accessors ───────────────────────────────────────────────
# Fall back to sensible defaults so a scene without a stats resource still runs.

func _stat_move_speed() -> float:
	return stats.move_speed if stats else 3.2

func _stat_acceleration() -> float:
	return stats.acceleration if stats else 10.0

func _stat_turn_speed() -> float:
	return stats.turn_speed if stats else 8.0

func _stat_detection_range() -> float:
	return stats.detection_range if stats else 20.0

func _stat_leash_range() -> float:
	return stats.leash_range if stats else 32.0

func _stat_chase_memory() -> float:
	return stats.chase_memory_seconds if stats else 4.0

func _stat_attack_range() -> float:
	return stats.attack_range if stats else 1.6

func _stat_attack_damage() -> float:
	var base: float = stats.attack_damage if stats else 8.0
	return base * _damage_multiplier

func _stat_attack_cooldown() -> float:
	return stats.attack_cooldown if stats else 1.0

func _stat_attack_windup() -> float:
	return stats.attack_windup if stats else 0.35

func _stat_hit_stun() -> float:
	return stats.hit_stun_duration if stats else 0.25

func _stat_poise() -> float:
	return stats.poise if stats else 0.0

func _stat_poise_window() -> float:
	return stats.poise_window if stats else 1.6

func _stat_poise_recovery() -> float:
	return stats.poise_recovery_seconds if stats else 3.0

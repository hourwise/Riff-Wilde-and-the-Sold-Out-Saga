class_name HollowChoirAI
extends EnemyAI
## Hollow Choir. Support caster that empowers nearby undead by singing.
##
## Teaches target prioritisation. It keeps its distance and never threatens the
## player directly — the pressure comes from what it does to everything else. The
## channel is interruptible, so the correct answer is to break off and silence it
## rather than grind through the buffed front line.

const CHANNEL_COLOUR: Color = Color(0.45, 0.8, 1.0)

## Preferred distance from the player. The Choir retreats if approached.
@export var preferred_distance: float = 9.0
@export var retreat_distance: float = 6.0
@export var channel_duration: float = 3.2
@export var channel_cooldown: float = 5.0
@export var buff_radius: float = 12.0
## Damage multiplier granted to allies for buff_duration.
@export var buff_multiplier: float = 1.45
@export var buff_duration: float = 8.0

var is_channelling: bool = false

var _channel_timer: float = 0.0
var _channel_cooldown_timer: float = 0.0
var _aura: MeshInstance3D = null
var _aura_material: StandardMaterial3D = null


func _ready() -> void:
	super._ready()
	_build_aura()


func _tick_timers(delta: float) -> void:
	super._tick_timers(delta)

	if _channel_cooldown_timer > 0.0:
		_channel_cooldown_timer -= delta

	if not is_channelling:
		return

	_channel_timer -= delta
	_pulse_aura()
	if _channel_timer <= 0.0:
		_complete_channel()


func _update_ai(delta: float) -> void:
	if target == null:
		_change_state(State.IDLE)
		return

	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	var distance: float = to_target.length()

	if distance > _stat_detection_range():
		_interrupt_channel(false)
		_change_state(State.IDLE)
		_apply_friction(delta)
		return

	last_known_target_position = target.global_position

	# Channelling roots the Choir. That is the whole point: it is the window in
	# which the player can reach and silence it.
	if is_channelling:
		_apply_friction(delta)
		_face(to_target.normalized(), delta)
		return

	if distance < retreat_distance:
		_change_state(State.CHASE)
		_retreat(to_target, delta)
		return

	if _channel_cooldown_timer <= 0.0:
		_start_channel()
		_apply_friction(delta)
		_face(to_target.normalized(), delta)
		return

	# Hold station between channels rather than closing to melee.
	if distance > preferred_distance:
		_change_state(State.CHASE)
		var direction: Vector3 = steering.get_direction_to(target.global_position) if steering != null else to_target.normalized()
		var goal_velocity: Vector3 = direction * _stat_move_speed()
		velocity.x = move_toward(velocity.x, goal_velocity.x, _stat_acceleration() * delta)
		velocity.z = move_toward(velocity.z, goal_velocity.z, _stat_acceleration() * delta)
		_face(direction, delta)
	else:
		_apply_friction(delta)
		_face(to_target.normalized(), delta)


func _retreat(to_target: Vector3, delta: float) -> void:
	var away: Vector3 = -to_target.normalized()
	var goal_velocity: Vector3 = away * _stat_move_speed()
	velocity.x = move_toward(velocity.x, goal_velocity.x, _stat_acceleration() * delta)
	velocity.z = move_toward(velocity.z, goal_velocity.z, _stat_acceleration() * delta)
	# Keep facing the player while backing off, so the silhouette stays readable.
	_face(to_target.normalized(), delta)


# ── Channelling ──────────────────────────────────────────────────

func _start_channel() -> void:
	is_channelling = true
	_channel_timer = channel_duration
	_change_state(State.ATTACK)

	if _aura != null:
		_aura.visible = true
	if visual != null:
		visual.play_attack(0)

	flash(CHANNEL_COLOUR, 2.4, channel_duration)
	AudioManager.play_sfx_3d(&"hollowchoir_channel_start", global_position)


func _complete_channel() -> void:
	is_channelling = false
	_channel_cooldown_timer = channel_cooldown
	_hide_aura()

	var buffed: int = 0
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == self or not (node is Node3D):
			continue
		if global_position.distance_to((node as Node3D).global_position) > buff_radius:
			continue
		if node.has_method("apply_choir_buff"):
			node.call("apply_choir_buff", buff_multiplier, buff_duration)
			buffed += 1

	if buffed > 0:
		AudioManager.play_sfx_3d(&"choir_corrupted_loop", global_position)


## Cancels the channel. Any damage interrupts, which is the counterplay.
func _interrupt_channel(announce: bool) -> void:
	if not is_channelling:
		return

	is_channelling = false
	_channel_timer = 0.0
	# Punished with a shorter cooldown than a completed channel, so interrupting
	# is rewarding but does not permanently disable the enemy.
	_channel_cooldown_timer = channel_cooldown * 0.5
	_hide_aura()

	if announce:
		EventBus.enemy_channel_interrupted.emit(self)
		AudioManager.play_sfx_3d(&"hollowchoir_interrupt", global_position)


func _on_damaged(event: DamageEvent) -> void:
	_interrupt_channel(true)
	super._on_damaged(event)


func die() -> void:
	if is_dead:
		return
	_interrupt_channel(false)
	AudioManager.play_sfx_3d(&"hollowchoir_death", global_position)
	super.die()


# ── Aura ─────────────────────────────────────────────────────────

## A spectral ring that grows while channelling. Built in code because it is one
## procedural mesh whose only job is to make the channel visible from across the
## graveyard.
func _build_aura() -> void:
	_aura = MeshInstance3D.new()
	_aura.name = "ChannelAura"
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura.visible = false

	var ring := TorusMesh.new()
	ring.inner_radius = 1.05
	ring.outer_radius = 1.25
	ring.rings = 24

	_aura_material = StandardMaterial3D.new()
	_aura_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aura_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aura_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_aura_material.albedo_color = Color(CHANNEL_COLOUR.r, CHANNEL_COLOUR.g, CHANNEL_COLOUR.b, 0.55)
	ring.material = _aura_material

	_aura.mesh = ring
	_aura.position = Vector3(0.0, 0.12, 0.0)
	add_child(_aura)


func _pulse_aura() -> void:
	if _aura == null:
		return

	# Scale tracks channel progress, so how close the buff is to landing is
	# readable at a glance.
	var progress: float = 1.0 - clampf(_channel_timer / maxf(channel_duration, 0.01), 0.0, 1.0)
	var scale: float = lerpf(0.6, 1.9, progress)
	_aura.scale = Vector3(scale, 1.0, scale)


func _hide_aura() -> void:
	if _aura != null:
		_aura.visible = false

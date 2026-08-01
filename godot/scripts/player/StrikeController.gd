class_name StrikeController
extends Node
## Riff's melee chain.
##
## Runs a data-driven sequence of AttackStep resources. Each step is
## windup -> active -> recovery; pressing strike during a step buffers the next
## one, so the chain flows without needing frame-perfect timing. Dodging cancels
## out of recovery, which is what stops combat feeling committal and stiff.
##
## The Verse-Chorus combos (Intro / Bridge / Crescendo) still run on top via
## CombatBuffer — those are pattern-matched specials, distinct from this chain.

enum Phase { IDLE, WINDUP, ACTIVE, RECOVERY }

## The light attack chain. Left empty, a sensible three-hit default is built at
## runtime so the player scene works without authored resources.
@export var chain: Array[AttackStep] = []
## Grace period after the last step's recovery during which pressing strike
## continues the chain rather than restarting it.
@export var chain_reset_seconds: float = 0.45

@export_group("Combo specials")
@export var crescendo_damage: float = 18.0
@export var crescendo_knockback_force: float = 18.0
@export var crescendo_radius: float = 6.0
@export var crescendo_knockdown_duration: float = 1.0
@export var bridge_damage: float = 14.0
@export var bridge_pull_force: float = 20.0

var is_attacking: bool = false

var _phase: Phase = Phase.IDLE
var _phase_timer: float = 0.0
var _step_timer: float = 0.0
var _chain_index: int = -1
var _reset_timer: float = 0.0
var _buffered_input: bool = false
var _current_step: AttackStep = null

@onready var player: PlayerController = get_parent()
@onready var hitbox: Hitbox = get_node("../MeshInstance3D/LuteWeapon/Hitbox")
@onready var weapon_mesh: MeshInstance3D = get_node("../MeshInstance3D/LuteWeapon/MeshInstance3D")
@onready var sing_controller: SingController = get_node("../SingController")


func _ready() -> void:
	if chain.is_empty():
		chain = _build_default_chain()

	if hitbox:
		hitbox.attacker = player
		hitbox.damage_type = &"strike"
		_set_hitbox_active(false)


func _process(delta: float) -> void:
	if player.is_dead:
		_abort()
		return

	# Dodging cancels any attack outright, including active frames.
	if player.is_dodging and _phase != Phase.IDLE:
		_abort()
		return

	if _reset_timer > 0.0:
		_reset_timer -= delta
		if _reset_timer <= 0.0 and _phase == Phase.IDLE:
			_chain_index = -1

	_read_input()
	_advance_phase(delta)


# ── Input ────────────────────────────────────────────────────────

func _read_input() -> void:
	if not Input.is_action_just_pressed("strike"):
		return
	if player.state_machine.current_state == PlayerStateMachine.State.STAGGERED:
		return

	if _phase == Phase.IDLE:
		_begin_step(_chain_index + 1)
		return

	# Mid-attack: remember the press and act on it when the window opens, rather
	# than dropping it. This is the difference between a chain that feels tight
	# and one that eats inputs.
	if _step_timer >= _current_step.buffer_open:
		_buffered_input = true


func _advance_phase(delta: float) -> void:
	if _phase == Phase.IDLE:
		return

	_phase_timer -= delta
	_step_timer += delta
	_update_swing()

	if _phase_timer > 0.0:
		return

	match _phase:
		Phase.WINDUP:
			_enter_active()
		Phase.ACTIVE:
			_enter_recovery()
		Phase.RECOVERY:
			if _buffered_input and _chain_index + 1 < chain.size():
				_begin_step(_chain_index + 1)
			else:
				_end_chain()
		_:
			pass


# ── Steps ────────────────────────────────────────────────────────

func _begin_step(index: int) -> void:
	if index >= chain.size():
		index = 0

	_chain_index = index
	_current_step = chain[index]
	_buffered_input = false
	_step_timer = 0.0
	is_attacking = true

	_phase = Phase.WINDUP
	_phase_timer = _current_step.windup

	# The Verse-Chorus special is resolved on the input that starts the swing, so
	# its effect lands with the same hit rather than a frame later.
	_resolve_combo_special()

	# A small lunge keeps Riff pressing forward through a chain instead of
	# rooting in place.
	if _current_step.step_impulse > 0.0:
		var forward: Vector3 = -player.mesh.global_transform.basis.z
		forward.y = 0.0
		player.velocity += forward.normalized() * _current_step.step_impulse

	player.visual.play_attack(index)
	AudioManager.play_sfx(&"riff_strike_swing")


func _enter_active() -> void:
	_phase = Phase.ACTIVE
	_phase_timer = _current_step.active

	if hitbox:
		hitbox.damage = _current_step.damage
		hitbox.knockback_force = _current_step.knockback_force
		hitbox.resonance_gain = _current_step.resonance_gain
		hitbox.status_effect = _current_step.status_effect
		hitbox.status_duration = _current_step.status_duration
	_set_hitbox_active(true)


func _enter_recovery() -> void:
	_phase = Phase.RECOVERY
	_phase_timer = _current_step.recovery
	_set_hitbox_active(false)


func _end_chain() -> void:
	_phase = Phase.IDLE
	_phase_timer = 0.0
	is_attacking = false
	_buffered_input = false
	_reset_timer = chain_reset_seconds
	_set_hitbox_active(false)
	_reset_weapon()


func _abort() -> void:
	if _phase == Phase.IDLE:
		return

	_phase = Phase.IDLE
	_phase_timer = 0.0
	is_attacking = false
	_buffered_input = false
	_chain_index = -1
	_set_hitbox_active(false)
	_reset_weapon()


## Sweeps the weapon through its arc across windup and active, then eases back
## during recovery. Driven from the phase timers rather than a tween so it stays
## in lockstep with the hitbox and survives cancels.
func _update_swing() -> void:
	if weapon_mesh == null or _current_step == null:
		return

	var from: float = deg_to_rad(_current_step.swing_from_degrees)
	var to: float = deg_to_rad(_current_step.swing_to_degrees)

	match _phase:
		Phase.WINDUP:
			var wind_ratio: float = 1.0 - clampf(_phase_timer / maxf(_current_step.windup, 0.001), 0.0, 1.0)
			weapon_mesh.rotation.x = lerpf(0.0, from, ease(wind_ratio, 0.4))
		Phase.ACTIVE:
			var swing_ratio: float = 1.0 - clampf(_phase_timer / maxf(_current_step.active, 0.001), 0.0, 1.0)
			weapon_mesh.rotation.x = lerpf(from, to, ease(swing_ratio, 2.6))
		Phase.RECOVERY:
			var recover_ratio: float = 1.0 - clampf(_phase_timer / maxf(_current_step.recovery, 0.001), 0.0, 1.0)
			weapon_mesh.rotation.x = lerpf(to, 0.0, ease(recover_ratio, 0.6))
		_:
			pass


func _reset_weapon() -> void:
	if weapon_mesh:
		weapon_mesh.rotation.x = 0.0


func _set_hitbox_active(active: bool) -> void:
	if hitbox == null:
		return

	hitbox.monitoring = active
	for child in hitbox.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = not active


## Default three-hit chain: two quick swings into a heavier finisher.
func _build_default_chain() -> Array[AttackStep]:
	var first := AttackStep.new()
	first.display_name = "Opening Riff"
	first.damage = 16.0
	first.knockback_force = 4.0
	first.windup = 0.09
	first.active = 0.13
	first.recovery = 0.20
	first.buffer_open = 0.08
	first.step_impulse = 2.2

	var second := AttackStep.new()
	second.display_name = "Backbeat"
	second.damage = 18.0
	second.knockback_force = 5.0
	second.windup = 0.08
	second.active = 0.13
	second.recovery = 0.22
	second.buffer_open = 0.08
	second.swing_from_degrees = -40.0
	second.swing_to_degrees = 90.0
	second.step_impulse = 2.6

	var finisher := AttackStep.new()
	finisher.display_name = "Power Chord"
	finisher.damage = 30.0
	finisher.knockback_force = 12.0
	finisher.resonance_gain = 14.0
	finisher.windup = 0.20
	finisher.active = 0.17
	finisher.recovery = 0.42
	finisher.buffer_open = 0.24
	finisher.swing_from_degrees = 60.0
	finisher.swing_to_degrees = -110.0
	finisher.step_impulse = 3.6

	return [first, second, finisher]


# ── Verse-Chorus specials ────────────────────────────────────────

## Records the input with CombatBuffer and applies any matched special. Bridge and
## Crescendo both require the preceding Sing to have connected.
func _resolve_combo_special() -> void:
	if player.combat_buffer == null:
		return

	var combo_id: StringName = player.combat_buffer.record_input(&"strike")
	if combo_id == &"":
		return

	if combo_id in [&"crescendo_combo", &"bridge_combo"] and not sing_controller.was_last_sing_hit_confirmed():
		player.combat_buffer.reject_combo(combo_id)
		return

	player.combat_buffer.accept_combo(combo_id)
	EventBus.combo_completed.emit(combo_id)

	match combo_id:
		&"bridge_combo":
			_trigger_bridge_smash()
		&"crescendo_combo":
			_trigger_crescendo_blast()
		_:
			pass


func _trigger_crescendo_blast() -> void:
	_play_crescendo_visual()
	var origin: Vector3 = player.global_position

	for node in get_tree().get_nodes_in_group("hurtboxes"):
		var hurtbox := node as Hurtbox
		if not hurtbox or hurtbox.is_invulnerable:
			continue

		var to_target: Vector3 = hurtbox.global_position - origin
		to_target.y = 0.0
		if to_target.length() > crescendo_radius:
			continue

		var knockback_direction: Vector3 = to_target.normalized()
		if knockback_direction == Vector3.ZERO:
			knockback_direction = -player.mesh.global_transform.basis.z.normalized()

		hurtbox.receive_damage(DamageEvent.new(
			crescendo_damage,
			crescendo_knockback_force,
			knockback_direction,
			player,
			&"knockdown",
			crescendo_knockdown_duration,
			&"crescendo",
			player.stats.resonance / player.stats.max_resonance
		))


func _trigger_bridge_smash() -> void:
	var hurtbox: Hurtbox = sing_controller.get_last_sing_hit_hurtbox()
	if hurtbox == null:
		return

	var to_player: Vector3 = player.global_position - hurtbox.global_position
	to_player.y = 0.0

	var pull_direction: Vector3 = to_player.normalized()
	if pull_direction == Vector3.ZERO:
		pull_direction = player.mesh.global_transform.basis.z.normalized()

	hurtbox.receive_damage(DamageEvent.new(
		bridge_damage,
		bridge_pull_force,
		pull_direction,
		player,
		&"bridge_pull",
		0.12,
		&"bridge",
		player.stats.resonance / player.stats.max_resonance
	))


func _play_crescendo_visual() -> void:
	var mesh_instance := MeshInstance3D.new()
	var ring := CylinderMesh.new()
	ring.top_radius = 1.0
	ring.bottom_radius = 1.0
	ring.height = 0.06
	ring.radial_segments = 48

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.72, 0.15, 0.45)
	ring.material = material

	mesh_instance.mesh = ring
	mesh_instance.position = Vector3(0.0, 0.06, 0.0)
	mesh_instance.scale = Vector3(0.1, 1.0, 0.1)
	player.add_child(mesh_instance)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(mesh_instance, "scale", Vector3(crescendo_radius, 1.0, crescendo_radius), 0.3)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.3)
	tween.set_parallel(false)
	tween.tween_callback(mesh_instance.queue_free)

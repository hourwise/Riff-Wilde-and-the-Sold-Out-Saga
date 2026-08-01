class_name BoneBellRingerAI
extends EnemyAI
## Bone Bell Ringer. Slow heavy that swings a funeral bell in shockwaves.
##
## Teaches stagger and spacing. High poise means chip damage bounces off — the
## player has to commit to the heavy finisher or a Crescendo to break it, and the
## shockwave punishes standing still to do so. It is the roster's answer to a
## player who never moves.

const TELEGRAPH_COLOUR: Color = Color(1.0, 0.85, 0.35)
const STAGGER_COLOUR: Color = Color(1.0, 0.45, 0.1)

@export_group("Shockwave")
@export var shockwave_radius: float = 4.6
@export var shockwave_damage: float = 18.0
@export var shockwave_knockback: float = 14.0
## Bell rings inside this arc in front of the Ringer. Sidestepping beats blocking.
@export var shockwave_half_angle_degrees: float = 110.0

@export_group("Stagger")
## Extra vulnerable time after poise breaks, on top of the normal hit stun.
@export var poise_break_stagger: float = 1.5


func _begin_attack() -> void:
	super._begin_attack()
	# Long, bright, unmistakable. The whole design depends on the player having
	# time to read this and move.
	flash(TELEGRAPH_COLOUR, 3.0, _stat_attack_windup())
	AudioManager.play_sfx_3d(&"bellringer_bell_swing", global_position)


## Replaces the default single-target melee with an arced shockwave.
func _resolve_attack() -> void:
	if target == null or not is_instance_valid(target) or _target_is_defeated():
		return

	_spawn_shockwave_visual()
	AudioManager.play_sfx_3d(&"bellringer_shockwave", global_position)

	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() > shockwave_radius:
		return

	# Facing check: the bell only sweeps in front, so stepping behind is a valid
	# answer as well as backing out of range.
	var facing: Vector3 = -mesh.global_transform.basis.z if mesh != null else -global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() > 0.001:
		var angle: float = rad_to_deg(facing.normalized().angle_to(to_target.normalized()))
		if angle > shockwave_half_angle_degrees:
			return

	if target.stats.can_take_damage():
		target.stats.take_damage(shockwave_damage)
		# Shove the player out of the bell's reach so a second ring cannot land
		# before they have any chance to recover.
		target.velocity += to_target.normalized() * shockwave_knockback


## Poise breaking is the payoff for committing, so it gets its own longer stagger
## and a distinct colour from an ordinary hit.
func _on_damaged(event: DamageEvent) -> void:
	var poise_before: float = poise_damage
	super._on_damaged(event)

	if is_dead:
		return

	# super() resets poise_damage to zero when the threshold is crossed.
	var poise_broke: bool = poise_before > 0.0 and poise_damage == 0.0 and hit_stun_timer > 0.0
	if poise_broke:
		hit_stun_timer += poise_break_stagger
		_cancel_attack()
		flash(STAGGER_COLOUR, 3.4, 0.5)
		AudioManager.play_sfx_3d(&"bellringer_stagger", global_position)


func die() -> void:
	if is_dead:
		return
	AudioManager.play_sfx_3d(&"bellringer_death", global_position)
	super.die()


## Expanding ring showing exactly how far the shockwave reached, so its range can
## be learned rather than guessed.
func _spawn_shockwave_visual() -> void:
	var ring := MeshInstance3D.new()
	var mesh_resource := CylinderMesh.new()
	mesh_resource.top_radius = 1.0
	mesh_resource.bottom_radius = 1.0
	mesh_resource.height = 0.05
	mesh_resource.radial_segments = 40

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(TELEGRAPH_COLOUR.r, TELEGRAPH_COLOUR.g, TELEGRAPH_COLOUR.b, 0.5)
	mesh_resource.material = material

	ring.mesh = mesh_resource
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(0.2, 1.0, 0.2)

	var host: Node = get_tree().current_scene
	if host == null:
		return
	host.add_child(ring)
	ring.global_position = global_position + Vector3.UP * 0.1

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(shockwave_radius, 1.0, shockwave_radius), 0.28)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.28)
	tween.set_parallel(false)
	tween.tween_callback(ring.queue_free)

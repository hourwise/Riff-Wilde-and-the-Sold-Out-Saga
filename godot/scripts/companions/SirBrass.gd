class_name SirBrass
extends Node3D
## Sir Brass. Spectral bugler, summoned for one trumpet blast and gone.
##
## Deliberately not an AI follower — ADR-0002 trades permanent companion logic for
## spectacle. The whole life cycle is a fixed sequence: materialise, raise the
## trumpet, blast, fade. That makes him cheap to build, impossible to get stuck,
## and lets all the effort go into the moment itself.
##
## Self-contained: instanced, run, and freed. He never registers anywhere and
## nothing holds a reference to him.

const COMPANION_ID: StringName = &"sir_brass"

## Spectral blue, matching the concept art's ghost band.
const SPECTRAL_COLOUR: Color = Color(0.35, 0.75, 1.0)

@export_group("Timing")
@export var materialise_seconds: float = 0.5
@export var wind_up_seconds: float = 0.6
@export var linger_seconds: float = 0.7
@export var dismiss_seconds: float = 0.5

@export_group("Attack")
@export var damage: float = 45.0
@export var knockback_force: float = 22.0
@export var radius: float = 8.0
## Blast is a wide cone in front of where he is summoned, not a full circle, so
## positioning still matters.
@export var half_angle_degrees: float = 120.0
@export var knockdown_duration: float = 1.6

@export_group("Presentation")
@export var hover_height: float = 0.4
@export var shake_strength: float = 0.7
@export var hitstop_seconds: float = 0.12

var _summoner: Node3D = null
var _visual: Node3D = null
var _material: StandardMaterial3D = null


## Spawns Sir Brass and runs his whole performance. The caller does not need to
## track him — he frees himself when finished.
static func summon(summoner: Node3D, facing: Vector3) -> SirBrass:
	var brass := SirBrass.new()
	brass.name = "SirBrass"
	brass._summoner = summoner

	var host: Node = summoner.get_tree().current_scene
	if host == null:
		brass.free()
		return null

	host.add_child(brass)

	# Materialise just in front and to the side of Riff — visible without blocking
	# the player's view of what he is about to hit.
	var forward: Vector3 = facing.normalized() if facing.length_squared() > 0.01 else Vector3.FORWARD
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	brass.global_position = summoner.global_position + forward * 1.6 + right * 1.2 + Vector3.UP * brass.hover_height
	brass.look_at(brass.global_position + forward, Vector3.UP)

	brass._perform(forward)
	return brass


func _perform(forward: Vector3) -> void:
	_build_visual()
	EventBus.companion_summoned.emit(COMPANION_ID)
	AudioManager.play_sfx_3d(&"sirbrass_summon", global_position)

	await _materialise()
	await get_tree().create_timer(wind_up_seconds).timeout

	_blast(forward)

	await get_tree().create_timer(linger_seconds).timeout
	await _dismiss()

	EventBus.companion_dismissed.emit(COMPANION_ID)
	queue_free()


# ── The attack ───────────────────────────────────────────────────

func _blast(forward: Vector3) -> void:
	AudioManager.play_sfx_3d(&"sirbrass_trumpet_attack", global_position)
	_spawn_blast_visual()

	GameManager.apply_hitstop(hitstop_seconds, 0.08)
	_shake_camera()

	var hit_any: bool = false
	for node in get_tree().get_nodes_in_group("hurtboxes"):
		var hurtbox := node as Hurtbox
		if hurtbox == null or hurtbox.is_invulnerable:
			continue
		# Never hit Riff with his own companion.
		if _summoner != null and hurtbox.is_ancestor_of(_summoner):
			continue
		if hurtbox.get_parent() == _summoner:
			continue

		var to_target: Vector3 = hurtbox.global_position - global_position
		to_target.y = 0.0
		if to_target.length() > radius:
			continue

		if rad_to_deg(forward.angle_to(to_target.normalized())) > half_angle_degrees:
			continue

		hurtbox.receive_damage(DamageEvent.new(
			damage,
			knockback_force,
			to_target.normalized(),
			_summoner,
			&"knockdown",
			knockdown_duration,
			&"trumpet",
			1.0
		))
		hit_any = true

	if hit_any:
		EventBus.companion_attack_landed.emit(COMPANION_ID)


func _shake_camera() -> void:
	if _summoner == null:
		return
	var rig: Node = _summoner.get("camera_rig")
	if rig != null and rig.has_method("add_shake"):
		rig.call("add_shake", shake_strength)


# ── Presentation ─────────────────────────────────────────────────

## Built in code rather than as a scene: Sir Brass has no model yet, and this
## keeps the placeholder in one place so a real spectral mesh can replace it by
## swapping this method alone.
func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.albedo_color = Color(SPECTRAL_COLOUR.r, SPECTRAL_COLOUR.g, SPECTRAL_COLOUR.b, 0.0)

	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.34
	capsule.height = 1.9
	capsule.material = _material
	body.mesh = capsule
	body.position = Vector3(0.0, 0.95, 0.0)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(body)

	# A stand-in for the trumpet, angled up and forward like a fanfare.
	var horn := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.22
	cone.bottom_radius = 0.05
	cone.height = 0.8
	cone.material = _material
	horn.mesh = cone
	horn.position = Vector3(0.0, 1.5, -0.55)
	horn.rotation = Vector3(deg_to_rad(-70.0), 0.0, 0.0)
	horn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(horn)

	_visual.scale = Vector3(0.6, 0.6, 0.6)


func _materialise() -> void:
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_material, "albedo_color:a", 0.85, materialise_seconds)
	tween.tween_property(_visual, "scale", Vector3.ONE, materialise_seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	await tween.finished


func _dismiss() -> void:
	AudioManager.play_sfx_3d(&"sirbrass_dismiss", global_position)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_material, "albedo_color:a", 0.0, dismiss_seconds)
	tween.tween_property(_visual, "position:y", 1.2, dismiss_seconds)
	tween.set_parallel(false)
	await tween.finished


## Expanding spectral ring showing the blast's reach.
func _spawn_blast_visual() -> void:
	var ring := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.08
	mesh.radial_segments = 48

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(SPECTRAL_COLOUR.r, SPECTRAL_COLOUR.g, SPECTRAL_COLOUR.b, 0.7)
	mesh.material = material

	ring.mesh = mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(0.15, 1.0, 0.15)

	var host: Node = get_tree().current_scene
	if host == null:
		return
	host.add_child(ring)
	ring.global_position = global_position

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(radius, 1.0, radius), 0.35)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.35)
	tween.set_parallel(false)
	tween.tween_callback(ring.queue_free)

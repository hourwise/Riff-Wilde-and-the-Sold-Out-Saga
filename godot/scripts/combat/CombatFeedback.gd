class_name CombatFeedback
extends Node
## Turns combat events into game feel: hitstop, camera shake, impact sparks.
##
## Purely a consumer — it listens on EventBus and never calls into combat. This is
## what lets impact feel be tuned in one place without touching attack code, and
## why enemies and the companion get the same treatment for free.

## Damage at or above this counts as a heavy hit and gets the stronger treatment.
@export var heavy_damage_threshold: float = 16.0

@export_group("Hitstop")
@export var light_hitstop_seconds: float = 0.045
@export var heavy_hitstop_seconds: float = 0.09
@export var hitstop_time_scale: float = 0.06

@export_group("Shake")
@export var light_shake: float = 0.22
@export var heavy_shake: float = 0.45
@export var damage_taken_shake: float = 0.55

@export_group("Impact spark")
@export var spark_colour: Color = Color(1.0, 0.78, 0.32)
@export var spectral_colour: Color = Color(0.35, 0.75, 1.0)
@export var spark_lifetime: float = 0.22

var _player: PlayerController = null


func _ready() -> void:
	_player = get_parent() as PlayerController

	EventBus.player_attack_landed.connect(_on_attack_landed)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.combo_completed.connect(_on_combo_completed)


func _on_attack_landed(damage: float, damage_type: StringName, target: Node3D) -> void:
	var is_heavy: bool = damage >= heavy_damage_threshold

	GameManager.apply_hitstop(
		heavy_hitstop_seconds if is_heavy else light_hitstop_seconds,
		hitstop_time_scale
	)
	_shake(heavy_shake if is_heavy else light_shake)

	if target != null and is_instance_valid(target):
		_spawn_impact(target.global_position + Vector3.UP, damage_type)

	AudioManager.play_sfx(&"riff_strike_impact")


func _on_player_damaged(_amount: float, _health_ratio: float) -> void:
	_shake(damage_taken_shake)
	AudioManager.play_sfx(&"riff_hurt")


func _on_combo_completed(_combo_id: StringName) -> void:
	AudioManager.play_sfx(&"riff_combo_finisher")


func _shake(amount: float) -> void:
	if _player == null or _player.camera_rig == null:
		return
	_player.camera_rig.add_shake(amount)


## A short-lived unshaded burst. Deliberately built in code rather than as a scene:
## it is one mesh with no configuration worth exposing, and this keeps the impact
## colour tied to the damage type in a single place.
func _spawn_impact(position: Vector3, damage_type: StringName) -> void:
	var burst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	sphere.radial_segments = 8
	sphere.rings = 4

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = spectral_colour if damage_type == &"sing" else spark_colour
	sphere.material = material

	burst.mesh = sphere
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst.global_position = position

	# Parented to the level, not the target, so it survives the target's death.
	var host: Node = get_tree().current_scene
	if host == null:
		return
	host.add_child(burst)
	burst.global_position = position

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(burst, "scale", Vector3.ONE * 2.4, spark_lifetime)
	tween.tween_property(material, "albedo_color:a", 0.0, spark_lifetime)
	tween.set_parallel(false)
	tween.tween_callback(burst.queue_free)

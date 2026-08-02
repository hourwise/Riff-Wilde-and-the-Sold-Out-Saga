class_name SingController
extends Node

@export var min_breath_cost: float = 20.0
@export var max_breath_cost: float = 65.0
@export var base_damage: float = 5.0
@export var base_knockback: float = 12.0
@export var active_duration: float = 0.25
@export var min_half_angle_degrees: float = 10.0
@export var max_half_angle_degrees: float = 180.0
@export var min_range: float = 2.0
@export var max_range: float = 6.0
@export var show_aim_indicator: bool = true

var is_singing: bool = false
var last_sing_hit_confirmed: bool = false
var last_sing_hit_hurtbox: Hurtbox = null
var aim_indicator: MeshInstance3D = null
var aim_indicator_material: StandardMaterial3D = null

@onready var player: PlayerController = get_parent()
## Held as a plain Node, not typed. Naming the class here forces RestorativeSong
## to compile whenever this script does — including from a test script compiled
## before autoloads register, at which point its EventBus references cannot
## resolve and both scripts fail to load.
@onready var restorative_song: Node = get_node_or_null("../RestorativeSong")
@onready var player_mesh: MeshInstance3D = get_node("../MeshInstance3D")
@onready var sing_area: Hitbox = get_node("../MeshInstance3D/SingBlastArea")
@onready var shockwave_mesh: MeshInstance3D = get_node("../MeshInstance3D/SingBlastArea/ShockwaveMesh")

func _ready() -> void:
	if sing_area:
		sing_area.attacker = player
		sing_area.damage_type = &"sing"
		sing_area.use_directional_filter = true
		sing_area.hit_landed.connect(_on_sing_hit_landed)
		_set_sing_active(false)
	_create_aim_indicator()
	print("[SingController] Initialized.")

func _process(delta: float) -> void:
	_update_aim_indicator()

	if player.is_dead:
		return

	if Input.is_action_just_pressed("sing") and not is_singing:
		# Singing is locked out while dodging or staggered.
		if player.is_dodging or player.state_machine.current_state == PlayerStateMachine.State.STAGGERED:
			return

		# Offered before the blast. Out of combat the blast has nothing to hit, so
		# the same button becomes the restorative song; RestorativeSong itself
		# decides whether the moment qualifies and reports why when it does not.
		if restorative_song != null and bool(restorative_song.call("try_perform")):
			return

		var breath_cost: float = _get_current_breath_cost()
		if not player.stats.use_breath(breath_cost):
			AudioManager.play_ui(&"ui_back")
			return

		var combo_id: StringName = &""
		if player.combat_buffer:
			combo_id = player.combat_buffer.record_input(&"sing")
		if combo_id != &"":
			player.combat_buffer.accept_combo(combo_id)
			EventBus.combo_completed.emit(combo_id)
		trigger_sing(combo_id)
		AudioManager.play_sfx(&"riff_sing_blast")

func trigger_sing(combo_id: StringName = &"") -> void:
	is_singing = true
	last_sing_hit_confirmed = false
	last_sing_hit_hurtbox = null
	print("[SingController] Sing triggered.")
	
	# Step 3.3: Resonance Multiplier
	var resonance_ratio: float = player.stats.resonance / player.stats.max_resonance
	var powered_ratio: float = pow(resonance_ratio, 2.0)
	var resonance_mult: float = 1.0 + resonance_ratio
	var half_angle_degrees: float = lerpf(min_half_angle_degrees, max_half_angle_degrees, resonance_ratio)
	var blast_range: float = lerpf(min_range, max_range, powered_ratio)
	var damage_mult: float = resonance_mult
	var knockback_mult: float = resonance_mult
	var status_effect: StringName = &""
	var status_duration: float = 0.0

	if combo_id == &"intro_combo":
		damage_mult *= 1.5
		knockback_mult *= 1.75
		half_angle_degrees = maxf(half_angle_degrees, 75.0)
		blast_range = maxf(blast_range, 4.0)
		status_effect = &"knockdown"
		status_duration = 1.4
		print("[SingController] Intro Combo shout empowered.")
	
	if sing_area:
		sing_area.damage = base_damage * damage_mult
		sing_area.knockback_force = base_knockback * knockback_mult
		sing_area.directional_half_angle_degrees = half_angle_degrees
		sing_area.directional_range = blast_range
		sing_area.status_effect = status_effect
		sing_area.status_duration = status_duration
		sing_area.power_ratio = resonance_ratio
		
	# Programmatic visual shockwave expand and fade
	if shockwave_mesh:
		var mat := shockwave_mesh.get_active_material(0) as StandardMaterial3D
		shockwave_mesh.mesh = _create_arc_mesh(half_angle_degrees, blast_range)
		if mat:
			shockwave_mesh.set_surface_override_material(0, mat)

		shockwave_mesh.visible = true
		shockwave_mesh.scale = Vector3(0.1, 0.1, 0.1)
		
		if mat:
			mat.albedo_color.a = 0.7
			
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(shockwave_mesh, "scale", Vector3.ONE, active_duration)
		if mat:
			tween.tween_property(mat, "albedo_color:a", 0.0, active_duration)
		
		tween.set_parallel(false)
		tween.tween_callback(func() -> void:
			shockwave_mesh.visible = false
		)
		
	_set_sing_active(true)
	
	await get_tree().create_timer(active_duration).timeout
	
	_set_sing_active(false)
	is_singing = false

func _set_sing_active(active: bool) -> void:
	if sing_area:
		sing_area.monitoring = active
		for child in sing_area.get_children():
			if child is CollisionShape3D:
				child.disabled = not active

func _get_current_breath_cost() -> float:
	var resonance_ratio: float = player.stats.resonance / player.stats.max_resonance
	return lerpf(min_breath_cost, max_breath_cost, resonance_ratio)

func _get_current_sing_shape() -> Dictionary:
	var resonance_ratio: float = player.stats.resonance / player.stats.max_resonance
	var powered_ratio: float = pow(resonance_ratio, 2.0)
	return {
		"half_angle_degrees": lerpf(min_half_angle_degrees, max_half_angle_degrees, resonance_ratio),
		"range": lerpf(min_range, max_range, powered_ratio)
	}

func was_last_sing_hit_confirmed() -> bool:
	return last_sing_hit_confirmed

func get_last_sing_hit_hurtbox() -> Hurtbox:
	return last_sing_hit_hurtbox if is_instance_valid(last_sing_hit_hurtbox) else null

func _on_sing_hit_landed(area: Area3D, event: DamageEvent) -> void:
	last_sing_hit_confirmed = true
	if area is Hurtbox:
		last_sing_hit_hurtbox = area as Hurtbox

func _create_aim_indicator() -> void:
	if not show_aim_indicator:
		return

	aim_indicator = MeshInstance3D.new()
	aim_indicator.name = "SingAimIndicator"
	aim_indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	aim_indicator_material = StandardMaterial3D.new()
	aim_indicator_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	aim_indicator_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aim_indicator_material.albedo_color = Color(0.25, 0.75, 1.0, 0.22)

	aim_indicator.mesh = _create_arc_mesh(min_half_angle_degrees, min_range)
	aim_indicator.set_surface_override_material(0, aim_indicator_material)
	player_mesh.add_child(aim_indicator)

func _update_aim_indicator() -> void:
	if not aim_indicator:
		return

	var shape: Dictionary = _get_current_sing_shape()
	aim_indicator.mesh = _create_arc_mesh(shape["half_angle_degrees"], shape["range"])
	if aim_indicator_material:
		aim_indicator.set_surface_override_material(0, aim_indicator_material)
		var breath_cost: float = _get_current_breath_cost()
		var can_sing: bool = player.stats.breath + player.stats.breath_spend_tolerance >= breath_cost
		aim_indicator_material.albedo_color = Color(0.25, 0.75, 1.0, 0.22) if can_sing else Color(0.9, 0.15, 0.1, 0.16)

	aim_indicator.position = Vector3(0.0, -0.98, 0.0)
	aim_indicator.rotation = Vector3.ZERO

func _create_arc_mesh(half_angle_degrees: float, blast_range: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var steps: int = 48

	vertices.append(Vector3.ZERO)
	for step in range(steps + 1):
		var t: float = float(step) / float(steps)
		var angle: float = deg_to_rad(lerpf(-half_angle_degrees, half_angle_degrees, t))
		vertices.append(Vector3(sin(angle) * blast_range, 0.0, -cos(angle) * blast_range))

	for step in range(steps):
		indices.append(0)
		indices.append(step + 1)
		indices.append(step + 2)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

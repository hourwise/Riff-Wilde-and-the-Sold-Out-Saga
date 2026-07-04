class_name StrikeController
extends Node

@export var attack_cooldown: float = 0.35
@export var active_start_time: float = 0.1
@export var active_duration: float = 0.2
@export var crescendo_damage: float = 18.0
@export var crescendo_knockback_force: float = 18.0
@export var crescendo_radius: float = 6.0
@export var crescendo_knockdown_duration: float = 1.0
@export var bridge_damage: float = 14.0
@export var bridge_pull_force: float = 20.0

var is_attacking: bool = false
var cooldown_timer: float = 0.0

@onready var player: PlayerController = get_parent()
@onready var hitbox: Hitbox = get_node("../MeshInstance3D/LuteWeapon/Hitbox")
@onready var weapon_mesh: MeshInstance3D = get_node("../MeshInstance3D/LuteWeapon/MeshInstance3D")
@onready var sing_controller: SingController = get_node("../SingController")

func _ready() -> void:
	if hitbox:
		hitbox.attacker = player
		hitbox.damage_type = &"strike"
		_set_hitbox_active(false)
	print("[StrikeController] Initialized.")
		
func _process(delta: float) -> void:
	if cooldown_timer > 0.0:
		cooldown_timer -= delta
		
	if player.is_dead:
		return

	if Input.is_action_just_pressed("strike") and not is_attacking and cooldown_timer <= 0.0:
		# Only strike if not dodging or staggered
		if player.state_machine.current_state != PlayerStateMachine.State.DODGE and player.state_machine.current_state != PlayerStateMachine.State.STAGGERED:
			var combo_id: StringName = &""
			if player.combat_buffer and player.combat_buffer.has_method("record_input"):
				combo_id = player.combat_buffer.call("record_input", &"strike")
			if combo_id == &"crescendo_combo" and not sing_controller.was_last_sing_hit_confirmed():
				print("[StrikeController] Crescendo failed: prior Sing missed.")
				if player.combat_buffer and player.combat_buffer.has_method("reject_combo"):
					player.combat_buffer.call("reject_combo", combo_id)
				combo_id = &""
			if combo_id == &"bridge_combo" and not sing_controller.was_last_sing_hit_confirmed():
				print("[StrikeController] Bridge failed: prior Sing missed.")
				if player.combat_buffer and player.combat_buffer.has_method("reject_combo"):
					player.combat_buffer.call("reject_combo", combo_id)
				combo_id = &""
			if combo_id != &"" and player.combat_buffer and player.combat_buffer.has_method("accept_combo"):
				player.combat_buffer.call("accept_combo", combo_id)
			trigger_strike(combo_id)

func trigger_strike(combo_id: StringName = &"") -> void:
	is_attacking = true
	cooldown_timer = attack_cooldown
	print("[StrikeController] Swing triggered.")
	
	var tween := create_tween()
	# Rotate the bludgeon visual mesh forward to simulate a swing
	tween.tween_property(weapon_mesh, "rotation:x", deg_to_rad(-90.0), active_start_time)

	if combo_id == &"bridge_combo":
		tween.tween_callback(_trigger_bridge_smash)
		tween.tween_interval(0.12)

	# Activate the collision area after any combo setup.
	tween.tween_callback(func() -> void: _set_hitbox_active(true))
	if combo_id == &"crescendo_combo":
		tween.tween_callback(_trigger_crescendo_blast)

	# Keep active for attack frames
	tween.tween_interval(active_duration)
	# Deactivate collision area
	tween.tween_callback(func() -> void: _set_hitbox_active(false))
	# Rotate weapon mesh back to default rest position
	tween.tween_property(weapon_mesh, "rotation:x", deg_to_rad(0.0), 0.15)
	# Reset attack lock
	tween.tween_callback(func() -> void: is_attacking = false)

func _set_hitbox_active(active: bool) -> void:
	if hitbox:
		hitbox.monitoring = active
		# Force collision update
		for child in hitbox.get_children():
			if child is CollisionShape3D:
				child.disabled = not active

func _trigger_crescendo_blast() -> void:
	print("[StrikeController] Crescendo shockwave triggered.")
	_play_crescendo_visual()
	var origin: Vector3 = player.global_position

	for node in get_tree().get_nodes_in_group("hurtboxes"):
		var hurtbox := node as Hurtbox
		if not hurtbox or hurtbox.is_invulnerable:
			continue

		var to_target: Vector3 = hurtbox.global_position - origin
		to_target.y = 0.0
		var distance: float = to_target.length()
		if distance > crescendo_radius:
			continue

		var knockback_direction: Vector3 = to_target.normalized()
		if knockback_direction == Vector3.ZERO:
			knockback_direction = -player.mesh.global_transform.basis.z.normalized()

		var event := DamageEvent.new(
			crescendo_damage,
			crescendo_knockback_force,
			knockback_direction,
			player,
			&"knockdown",
			crescendo_knockdown_duration,
			&"crescendo",
			player.stats.resonance / player.stats.max_resonance
		)
		hurtbox.receive_damage(event)

func _trigger_bridge_smash() -> void:
	var hurtbox: Hurtbox = sing_controller.get_last_sing_hit_hurtbox()
	if not hurtbox:
		print("[StrikeController] Bridge failed: Sing target is gone.")
		return

	print("[StrikeController] Bridge pull-smash triggered.")
	var to_player: Vector3 = player.global_position - hurtbox.global_position
	to_player.y = 0.0

	var pull_direction: Vector3 = to_player.normalized()
	if pull_direction == Vector3.ZERO:
		pull_direction = player.mesh.global_transform.basis.z.normalized()

	var event := DamageEvent.new(
		bridge_damage,
		bridge_pull_force,
		pull_direction,
		player,
		&"bridge_pull",
		0.12,
		&"bridge",
		player.stats.resonance / player.stats.max_resonance
	)
	hurtbox.receive_damage(event)

func _play_crescendo_visual() -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.06
	mesh.radial_segments = 48

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.72, 0.15, 0.45)
	mesh.material = material

	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(0.0, 0.06, 0.0)
	mesh_instance.scale = Vector3(0.1, 1.0, 0.1)
	player.add_child(mesh_instance)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(mesh_instance, "scale", Vector3(crescendo_radius, 1.0, crescendo_radius), 0.3)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.3)
	tween.set_parallel(false)
	tween.tween_callback(mesh_instance.queue_free)

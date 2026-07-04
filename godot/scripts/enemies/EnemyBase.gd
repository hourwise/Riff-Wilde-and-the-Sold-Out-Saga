class_name EnemyBase
extends CharacterBody3D

signal died(enemy: EnemyBase)
signal damaged(event: DamageEvent)

@export var max_health: float = 60.0
@export var friction: float = 18.0
@export var gravity: float = 20.0
@export var knockback_resistance: float = 1.0
@export var knockdown_friction_multiplier: float = 2.5
@export var death_cleanup_delay: float = 1.2
@export var show_debug_health_label: bool = false

var current_health: float = max_health
var is_dead: bool = false
var is_knocked_down: bool = false
var reaction_tween: Tween = null

@onready var hurtbox: Hurtbox = get_node_or_null("Hurtbox") as Hurtbox
@onready var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
@onready var health_label: Label3D = get_node_or_null("Label3D") as Label3D
@onready var status_bars: Node = get_node_or_null("EnemyStatusBars")

func _ready() -> void:
	current_health = max_health
	if hurtbox:
		hurtbox.damaged.connect(_on_damaged)
	if health_label:
		health_label.visible = show_debug_health_label
	update_health_label()

func _on_damaged(event: DamageEvent) -> void:
	if is_dead:
		return

	current_health = maxf(0.0, current_health - event.damage_amount)
	damaged.emit(event)
	if event.attacker is PlayerController:
		var progression_manager := get_node_or_null("/root/ProgressionManager")
		if progression_manager and progression_manager.has_method("record_damage_dealt"):
			progression_manager.call("record_damage_dealt", event.damage_amount)
	print("[%s] Damage received: %.1f. HP remaining: %.1f" % [name, event.damage_amount, current_health])
	update_health_label()

	var resistance: float = maxf(knockback_resistance, 0.01)
	var kb_velocity: Vector3 = event.knockback_direction * (event.knockback_force / resistance)
	velocity.x = kb_velocity.x
	velocity.z = kb_velocity.z

	if event.status_effect == &"knockdown":
		apply_knockdown(event.status_duration)
	else:
		play_hit_reaction()

	if current_health <= 0.0:
		die()

func apply_movement_decay(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	var current_friction: float = friction * knockdown_friction_multiplier if is_knocked_down else friction
	velocity.x = move_toward(velocity.x, 0.0, current_friction * delta)
	velocity.z = move_toward(velocity.z, 0.0, current_friction * delta)

func apply_knockdown(duration: float) -> void:
	is_knocked_down = true
	print("[%s] Knocked down for %.1fs." % [name, duration])

	if not mesh:
		await get_tree().create_timer(duration).timeout
		is_knocked_down = false
		return

	reset_reaction_tween()
	reaction_tween.set_parallel(true)
	reaction_tween.tween_property(mesh, "rotation:x", deg_to_rad(90.0), 0.12)
	reaction_tween.tween_property(mesh, "position:y", 0.4, 0.12)
	reaction_tween.set_parallel(false)
	reaction_tween.tween_interval(duration)
	reaction_tween.set_parallel(true)
	reaction_tween.tween_property(mesh, "rotation:x", 0.0, 0.2)
	reaction_tween.tween_property(mesh, "position:y", 0.8, 0.2)
	reaction_tween.set_parallel(false)
	reaction_tween.tween_callback(func() -> void:
		is_knocked_down = false
	)

func play_hit_reaction() -> void:
	if not mesh:
		return

	reset_reaction_tween()
	mesh.rotation = Vector3.ZERO
	mesh.position = Vector3(0.0, 0.8, 0.0)
	reaction_tween.tween_property(mesh, "scale", Vector3(1.2, 0.8, 1.2), 0.05)
	reaction_tween.tween_property(mesh, "scale", Vector3.ONE, 0.12)

func die() -> void:
	if is_dead:
		return

	is_dead = true
	var progression_manager := get_node_or_null("/root/ProgressionManager")
	if progression_manager and progression_manager.has_method("record_enemy_defeated"):
		progression_manager.call("record_enemy_defeated")
	died.emit(self)
	print("[%s] Defeated." % name)
	if hurtbox:
		hurtbox.is_invulnerable = true
	set_collision_layer_value(3, false)
	await get_tree().create_timer(death_cleanup_delay).timeout
	queue_free()

func update_health_label() -> void:
	if health_label:
		health_label.text = "%s HP: %d/%d" % [name, int(current_health), int(max_health)]
	if status_bars and status_bars.has_method("set_health"):
		status_bars.call("set_health", current_health, max_health)

func reset_reaction_tween() -> void:
	if reaction_tween:
		reaction_tween.kill()
	reaction_tween = create_tween()

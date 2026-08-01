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
@export var hit_flash_duration: float = 0.16
@export var hit_flash_energy: float = 3.2
## Multiplied into the model's albedo at spawn. Three enemies share one skeleton
## model, so tint is what keeps them readable as distinct creatures.
@export var visual_tint: Color = Color(1.0, 1.0, 1.0, 1.0)

const HIT_FLASH_COLOUR: Color = Color(1.0, 0.92, 0.78)

var current_health: float = max_health
var is_dead: bool = false
var is_knocked_down: bool = false
var reaction_tween: Tween = null
## Materials copied per instance so flashing one enemy does not flash them all.
var _flash_materials: Array[StandardMaterial3D] = []
var _hit_flash_tween: Tween = null
## Neutral pose of the visual root, restored after knockdown and hit reactions.
var _visual_rest_position: Vector3 = Vector3.ZERO
var _visual_rest_scale: Vector3 = Vector3.ONE

@onready var hurtbox: Hurtbox = get_node_or_null("Hurtbox") as Hurtbox
## The node that gets turned, squashed and knocked over. Typed Node3D rather than
## MeshInstance3D so an enemy can be either a placeholder primitive or a rigged
## model with its meshes nested under a skeleton.
@onready var mesh: Node3D = _resolve_visual_root()
@onready var health_label: Label3D = get_node_or_null("Label3D") as Label3D
@onready var status_bars: Node = get_node_or_null("EnemyStatusBars")

func _ready() -> void:
	current_health = max_health
	if hurtbox:
		hurtbox.damaged.connect(_on_damaged)
	if health_label:
		health_label.visible = show_debug_health_label
	if mesh != null:
		_visual_rest_position = mesh.position
		_visual_rest_scale = mesh.scale
	update_health_label()
	_cache_flash_materials()
	EventBus.enemy_spawned.emit(self)


## Prefers an explicit CharacterVisual, so rigged enemies rotate the node that
## holds their model and animation player. Falls back to a bare mesh for
## placeholder enemies built from primitives.
func _resolve_visual_root() -> Node3D:
	var character_visual := get_node_or_null("CharacterVisual") as Node3D
	if character_visual != null:
		return character_visual
	return get_node_or_null("MeshInstance3D") as Node3D

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

	play_hit_flash()

	if event.status_effect == &"knockdown":
		EventBus.enemy_staggered.emit(self)
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

	# Drop toward the ground from wherever the visual normally sits, rather than
	# assuming a fixed height — rigged models and primitives rest differently.
	var floored: float = _visual_rest_position.y - 0.4

	reset_reaction_tween()
	reaction_tween.set_parallel(true)
	reaction_tween.tween_property(mesh, "rotation:x", deg_to_rad(90.0), 0.12)
	reaction_tween.tween_property(mesh, "position:y", floored, 0.12)
	reaction_tween.set_parallel(false)
	reaction_tween.tween_interval(duration)
	reaction_tween.set_parallel(true)
	reaction_tween.tween_property(mesh, "rotation:x", 0.0, 0.2)
	reaction_tween.tween_property(mesh, "position:y", _visual_rest_position.y, 0.2)
	reaction_tween.set_parallel(false)
	reaction_tween.tween_callback(func() -> void:
		is_knocked_down = false
	)

## Flashes the enemy white on hit. Reads instantly at any distance and in fog,
## which the squash-and-stretch reaction alone does not.
func play_hit_flash() -> void:
	flash(HIT_FLASH_COLOUR, hit_flash_energy, hit_flash_duration)


## Pulses the enemy's emission. Used for hit confirmation and, with a different
## colour and a longer fade, for attack telegraphs — both need to read at distance
## and through fog, which silhouette animation alone does not achieve.
func flash(colour: Color, energy: float, duration: float) -> void:
	if _flash_materials.is_empty():
		return

	if _hit_flash_tween:
		_hit_flash_tween.kill()

	for material: StandardMaterial3D in _flash_materials:
		material.emission_enabled = true
		material.emission = colour
		material.emission_energy_multiplier = energy

	_hit_flash_tween = create_tween()
	_hit_flash_tween.set_parallel(true)
	for material: StandardMaterial3D in _flash_materials:
		_hit_flash_tween.tween_property(material, "emission_energy_multiplier", 0.0, duration)
	_hit_flash_tween.set_parallel(false)
	_hit_flash_tween.tween_callback(func() -> void:
		for material: StandardMaterial3D in _flash_materials:
			material.emission_enabled = false
	)


## Takes a unique copy of every surface material under the visual root, so
## flashing one enemy does not flash every enemy sharing the same resource.
##
## Walks the whole subtree because a rigged model's meshes sit under a skeleton
## rather than directly on the enemy, and may have several surfaces each.
func _cache_flash_materials() -> void:
	if mesh == null:
		return

	for mesh_instance: MeshInstance3D in _collect_mesh_instances(mesh):
		if mesh_instance.mesh == null:
			continue

		for surface in range(mesh_instance.mesh.get_surface_count()):
			# Only override a material that already exists — installing a fresh
			# one where there was none would repaint the enemy default white.
			var source: Material = mesh_instance.get_active_material(surface)
			if source == null:
				continue

			var duplicated := source.duplicate() as StandardMaterial3D
			if duplicated == null:
				continue

			duplicated.albedo_color *= visual_tint
			mesh_instance.set_surface_override_material(surface, duplicated)
			_flash_materials.append(duplicated)


func _collect_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_collect_mesh_instances(child))
	return found


func play_hit_reaction() -> void:
	if not mesh:
		return

	reset_reaction_tween()
	mesh.rotation = Vector3(0.0, mesh.rotation.y, 0.0)
	mesh.position = _visual_rest_position
	reaction_tween.tween_property(mesh, "scale", _visual_rest_scale * Vector3(1.2, 0.8, 1.2), 0.05)
	reaction_tween.tween_property(mesh, "scale", _visual_rest_scale, 0.12)

func die() -> void:
	if is_dead:
		return

	is_dead = true
	var progression_manager := get_node_or_null("/root/ProgressionManager")
	if progression_manager and progression_manager.has_method("record_enemy_defeated"):
		progression_manager.call("record_enemy_defeated")
	died.emit(self)
	EventBus.enemy_died.emit(self)
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

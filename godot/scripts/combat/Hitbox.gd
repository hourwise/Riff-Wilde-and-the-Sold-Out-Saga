class_name Hitbox
extends Area3D

signal hit_landed(area: Area3D, event: DamageEvent)

@export var damage: float = 15.0
@export var knockback_force: float = 8.0
@export var resonance_gain: float = 0.0
@export var use_directional_filter: bool = false
@export var directional_half_angle_degrees: float = 180.0
@export var directional_range: float = 6.0
@export var status_effect: StringName = &""
@export var status_duration: float = 0.0
@export var damage_type: StringName = &"generic"
@export_range(0.0, 1.0, 0.01) var power_ratio: float = 0.0

# Optional owner reference (e.g. the player node)
var attacker: Node = null

func _ready() -> void:
	area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area3D) -> void:
	if area is Hurtbox:
		if not _passes_directional_filter(area):
			return

		# Calculate direction of impact (away from the hitbox origin)
		var kb_dir := (area.global_position - global_position).normalized()
		kb_dir.y = 0.0 # Maintain flat horizontal knockback
		
		if kb_dir == Vector3.ZERO:
			kb_dir = -global_transform.basis.z.normalized()
		else:
			kb_dir = kb_dir.normalized()
			
		var parent_attacker: Node = attacker if attacker else owner
		var event := DamageEvent.new(damage, knockback_force, kb_dir, parent_attacker, status_effect, status_duration, damage_type, power_ratio)
		area.receive_damage(event)
		hit_landed.emit(area, event)
		
		if parent_attacker is PlayerController:
			var player_attacker := parent_attacker as PlayerController
			if resonance_gain > 0.0:
				player_attacker.stats.add_resonance(resonance_gain)

			# Announced rather than acted on: impact feedback, music and the Encore
			# meter all key off this without the hitbox knowing any of them exist.
			EventBus.player_attack_landed.emit(damage, damage_type, area.get_parent() as Node3D)

func _passes_directional_filter(area: Area3D) -> bool:
	if not use_directional_filter:
		return true

	var source := attacker as Node3D
	var origin: Vector3 = source.global_position if source else global_position
	var to_target: Vector3 = area.global_position - origin
	to_target.y = 0.0

	var distance: float = to_target.length()
	if distance > directional_range:
		return false
	if distance <= 0.001:
		return true
	if directional_half_angle_degrees >= 179.9:
		return true

	var facing: Vector3 = -global_transform.basis.z
	facing.y = 0.0
	facing = facing.normalized()

	var target_direction: Vector3 = to_target.normalized()
	var angle_degrees: float = rad_to_deg(facing.angle_to(target_direction))
	return angle_degrees <= directional_half_angle_degrees

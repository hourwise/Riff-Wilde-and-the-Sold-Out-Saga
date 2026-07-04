class_name DamageEvent
extends RefCounted

var damage_amount: float = 0.0
var knockback_force: float = 0.0
var knockback_direction: Vector3 = Vector3.ZERO
var attacker: Node = null
var status_effect: StringName = &""
var status_duration: float = 0.0
var damage_type: StringName = &"generic"
var power_ratio: float = 0.0

func _init(
	p_damage: float,
	p_kb_force: float,
	p_kb_dir: Vector3,
	p_attacker: Node = null,
	p_status_effect: StringName = &"",
	p_status_duration: float = 0.0,
	p_damage_type: StringName = &"generic",
	p_power_ratio: float = 0.0
) -> void:
	damage_amount = p_damage
	knockback_force = p_kb_force
	knockback_direction = p_kb_dir
	attacker = p_attacker
	status_effect = p_status_effect
	status_duration = p_status_duration
	damage_type = p_damage_type
	power_ratio = clampf(p_power_ratio, 0.0, 1.0)

class_name Hurtbox
extends Area3D

signal damaged(event: DamageEvent)

@export var is_invulnerable: bool = false

func _ready() -> void:
	add_to_group("hurtboxes")

func receive_damage(event: DamageEvent) -> void:
	if is_invulnerable:
		return
	emit_signal("damaged", event)

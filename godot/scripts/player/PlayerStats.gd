class_name PlayerStats
extends Node

signal health_changed(value: float, max_value: float)
signal breath_changed(value: float, max_value: float)
signal resonance_changed(value: float, max_value: float)
signal health_depleted

@export var max_health: float = 100.0
@export var max_breath: float = 100.0
@export var max_resonance: float = 100.0

@export var breath_regen_rate: float = 7.0
@export var breath_regen_delay: float = 1.75
@export var breath_spend_tolerance: float = 0.25
@export var resonance_decay_rate: float = 8.0
@export var resonance_decay_delay: float = 2.5

var health: float
var breath: float
var resonance: float
var is_depleted: bool = false

var breath_timer: float = 0.0
var resonance_timer: float = 0.0

func _ready() -> void:
	health = max_health
	breath = max_breath
	resonance = 0.0
	
	# Force initial update emissions
	health_changed.emit(health, max_health)
	breath_changed.emit(breath, max_breath)
	resonance_changed.emit(resonance, max_resonance)
	print("[PlayerStats] Configured.")

func _process(delta: float) -> void:
	# Breath recovery timer check
	if breath_timer > 0.0:
		breath_timer -= delta
	elif breath < max_breath:
		set_breath(breath + breath_regen_rate * delta)
		
	# Resonance decay timer check
	if resonance_timer > 0.0:
		resonance_timer -= delta
	elif resonance > 0.0:
		set_resonance(resonance - resonance_decay_rate * delta)

func take_damage(amount: float) -> void:
	if not can_take_damage():
		return
	var progression_manager := get_node_or_null("/root/ProgressionManager")
	if progression_manager and progression_manager.has_method("record_damage_taken"):
		progression_manager.call("record_damage_taken", amount)
	set_health(health - amount)

func can_take_damage() -> bool:
	var parent := get_parent()
	if parent and "is_invulnerable" in parent and parent.is_invulnerable:
		return false
	return health > 0.0

func use_breath(amount: float) -> bool:
	if breath + breath_spend_tolerance >= amount:
		set_breath(breath - amount)
		breath_timer = breath_regen_delay
		return true
	return false

func add_resonance(amount: float) -> void:
	set_resonance(resonance + amount)
	resonance_timer = resonance_decay_delay

func set_health(value: float) -> void:
	var was_alive: bool = health > 0.0
	health = clamp(value, 0.0, max_health)
	health_changed.emit(health, max_health)
	if was_alive and health <= 0.0 and not is_depleted:
		is_depleted = true
		health_depleted.emit()

func set_breath(value: float) -> void:
	breath = clamp(value, 0.0, max_breath)
	breath_changed.emit(breath, max_breath)

func set_resonance(value: float) -> void:
	resonance = clamp(value, 0.0, max_resonance)
	resonance_changed.emit(resonance, max_resonance)

class_name IroncladWardenAI
extends "res://scripts/enemies/ToneDeafAI.gd"

@export var max_armor: float = 100.0
@export var min_sing_armor_damage: float = 8.0
@export var max_sing_armor_damage: float = 65.0
@export var intro_combo_armor_multiplier: float = 1.2
@export var armor_break_stagger_duration: float = 1.2

var armor: float = 0.0
var armor_broken: bool = false
var armor_shell_material: StandardMaterial3D = null
var armor_flash_tween: Tween = null

func _ready() -> void:
	armor = max_armor
	var armor_shell := get_node_or_null("ArmorShell") as MeshInstance3D
	if armor_shell:
		armor_shell_material = armor_shell.get_active_material(0).duplicate() as StandardMaterial3D
		armor_shell.set_surface_override_material(0, armor_shell_material)
	super._ready()
	print("[IroncladWardenAI] Ready. Armor: %.1f" % armor)

func _on_damaged(event: DamageEvent) -> void:
	if is_dead:
		return

	if not armor_broken:
		if event.damage_type == &"sing":
			_damage_armor(event)
		else:
			print("[%s] Armor blocked %s." % [name, String(event.damage_type)])
			_flash_armor(Color(0.85, 0.9, 1.0, 0.9), 0.1)
			update_health_label()
		return

	super._on_damaged(event)

func _damage_armor(event: DamageEvent) -> void:
	var powered_ratio: float = pow(clampf(event.power_ratio, 0.0, 1.0), 2.0)
	var armor_damage: float = lerpf(min_sing_armor_damage, max_sing_armor_damage, powered_ratio)
	if event.status_effect == &"knockdown":
		armor_damage *= intro_combo_armor_multiplier

	armor = maxf(0.0, armor - armor_damage)
	if event.attacker is PlayerController:
		var progression_manager := get_node_or_null("/root/ProgressionManager")
		if progression_manager and progression_manager.has_method("record_armor_damage"):
			progression_manager.call("record_armor_damage", armor_damage)
	print("[%s] Sing cracked armor for %.1f. Armor remaining: %.1f" % [name, armor_damage, armor])
	_update_armor_shell()
	_flash_armor(Color(0.18, 0.72, 1.0, 0.95), 0.16)
	update_health_label()
	play_hit_reaction()

	if armor <= 0.0:
		_break_armor()

func _break_armor() -> void:
	if armor_broken:
		return

	armor_broken = true
	hit_stun_timer = armor_break_stagger_duration
	_change_state(State.STAGGER)
	_update_armor_shell()
	_flash_armor(Color(1.0, 0.42, 0.1, 0.95), 0.35)
	print("[%s] Armor broken! Vulnerable to Strikes." % name)
	update_health_label()

func update_health_label() -> void:
	if health_label:
		var armor_text: String = "Armor broken" if armor_broken else "Armor: %d/%d" % [int(armor), int(max_armor)]
		health_label.text = "%s HP: %d/%d\n%s" % [name, int(current_health), int(max_health), armor_text]

	if status_bars:
		if status_bars.has_method("set_health"):
			status_bars.call("set_health", current_health, max_health)
		if status_bars.has_method("set_armor"):
			status_bars.call("set_armor", armor, max_armor)
		if status_bars.has_method("set_armor_visible"):
			status_bars.call("set_armor_visible", not armor_broken)

func _update_armor_shell() -> void:
	if not armor_shell_material:
		return

	if armor_broken:
		armor_shell_material.albedo_color = Color(0.18, 0.18, 0.18, 0.22)
		return

	var armor_ratio: float = armor / maxf(max_armor, 0.01)
	armor_shell_material.albedo_color = Color(0.32 + armor_ratio * 0.3, 0.38 + armor_ratio * 0.28, 0.46 + armor_ratio * 0.26, 0.42 + armor_ratio * 0.36)

func _flash_armor(color: Color, duration: float) -> void:
	if not armor_shell_material:
		return

	if armor_flash_tween:
		armor_flash_tween.kill()

	var restore_color: Color = armor_shell_material.albedo_color
	armor_shell_material.albedo_color = color
	armor_flash_tween = create_tween()
	armor_flash_tween.tween_property(armor_shell_material, "albedo_color", restore_color, duration)

func _change_state(new_state: State) -> void:
	if current_state == new_state:
		return

	print("[IroncladWardenAI] State changed: %s -> %s" % [State.keys()[current_state], State.keys()[new_state]])
	current_state = new_state

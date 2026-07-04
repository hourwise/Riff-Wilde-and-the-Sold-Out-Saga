extends Control

@onready var health_bar: ProgressBar = $VBoxContainer/HealthBar
@onready var breath_bar: ProgressBar = $VBoxContainer/BreathBar
@onready var resonance_bar: ProgressBar = $VBoxContainer/ResonanceBar
@onready var combo_label: Label = $ComboLabel
@onready var center_message_label: Label = $CenterMessageLabel

var combo_tween: Tween = null
var center_message_tween: Tween = null

func _ready() -> void:
	_set_mouse_filter_ignore(self)
	combo_label.visible = false
	center_message_label.visible = false

func setup_stats(stats: PlayerStats) -> void:
	stats.health_changed.connect(_on_health_changed)
	stats.breath_changed.connect(_on_breath_changed)
	stats.resonance_changed.connect(_on_resonance_changed)
	
	# Initialize values
	_on_health_changed(stats.health, stats.max_health)
	_on_breath_changed(stats.breath, stats.max_breath)
	_on_resonance_changed(stats.resonance, stats.max_resonance)
	print("[HUDController] Connected to PlayerStats.")

func setup_combat_buffer(combat_buffer: Node) -> void:
	combat_buffer.combo_accepted.connect(_on_combo_accepted)
	print("[HUDController] Connected to CombatBuffer.")

func _on_health_changed(val: float, max_val: float) -> void:
	if health_bar:
		health_bar.max_value = max_val
		health_bar.value = val
	
func _on_breath_changed(val: float, max_val: float) -> void:
	if breath_bar:
		breath_bar.max_value = max_val
		breath_bar.value = val
	
func _on_resonance_changed(val: float, max_val: float) -> void:
	if resonance_bar:
		resonance_bar.max_value = max_val
		resonance_bar.value = val

func _set_mouse_filter_ignore(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control:
			_set_mouse_filter_ignore(child)

func _on_combo_accepted(combo_id: StringName) -> void:
	combo_label.text = "Combo: %s" % String(combo_id).capitalize()
	combo_label.visible = true
	combo_label.modulate.a = 1.0

	if combo_tween:
		combo_tween.kill()

	combo_tween = create_tween()
	combo_tween.tween_interval(1.0)
	combo_tween.tween_property(combo_label, "modulate:a", 0.0, 0.35)
	combo_tween.tween_callback(func() -> void:
		combo_label.visible = false
	)

func show_defeat_prompt() -> void:
	show_center_message("Defeated - Press R to Restart")

func show_center_message(message: String) -> void:
	if center_message_tween:
		center_message_tween.kill()
		center_message_tween = null

	center_message_label.text = message
	center_message_label.visible = true
	center_message_label.modulate.a = 1.0

func show_temporary_center_message(message: String, duration: float = 1.8) -> void:
	show_center_message(message)

	center_message_tween = create_tween()
	center_message_tween.tween_interval(duration)
	center_message_tween.tween_property(center_message_label, "modulate:a", 0.0, 0.35)
	center_message_tween.tween_callback(func() -> void:
		center_message_label.visible = false
		center_message_tween = null
	)

extends Control

@onready var health_bar: ProgressBar = $VBoxContainer/HealthBar
@onready var breath_bar: ProgressBar = $VBoxContainer/BreathBar
@onready var resonance_bar: ProgressBar = $VBoxContainer/ResonanceBar
@onready var encore_bar: ProgressBar = $VBoxContainer/EncoreBar
@onready var combo_label: Label = $ComboLabel
@onready var center_message_label: Label = $CenterMessageLabel

const RETICLE_SIZE: Vector2 = Vector2(46.0, 46.0)

var combo_tween: Tween = null
var center_message_tween: Tween = null

var _lock_on_reticle: Panel = null
var _lock_on_target: Node3D = null
var _reticle_tween: Tween = null
var _encore_tween: Tween = null

func _ready() -> void:
	_set_mouse_filter_ignore(self)
	combo_label.visible = false
	center_message_label.visible = false
	_build_lock_on_reticle()
	EventBus.lock_on_changed.connect(_on_lock_on_changed)
	EventBus.encore_changed.connect(_on_encore_changed)
	EventBus.encore_full.connect(_on_encore_full)


func _on_encore_changed(value: float, max_value: float) -> void:
	if encore_bar == null:
		return
	encore_bar.max_value = max_value
	encore_bar.value = value


## A full meter is the cue to summon Sir Brass, so it has to be impossible to
## miss mid-fight — the bar pulses and says what to press.
func _on_encore_full() -> void:
	if encore_bar == null:
		return

	if _encore_tween:
		_encore_tween.kill()

	var label := encore_bar.get_node_or_null("Label") as Label
	if label != null:
		label.text = "ENCORE READY  —  F"

	_encore_tween = create_tween()
	_encore_tween.set_loops(6)
	_encore_tween.tween_property(encore_bar, "modulate", Color(1.6, 1.6, 1.6, 1.0), 0.28)
	_encore_tween.tween_property(encore_bar, "modulate", Color.WHITE, 0.28)

	show_temporary_center_message("ENCORE READY", 1.6)


func _process(_delta: float) -> void:
	_update_lock_on_reticle()


# ── Lock-on reticle ──────────────────────────────────────────────

## Built in code rather than added to HUD.tscn: it is a single procedural marker
## with no authored content, and keeping it here keeps its behaviour and its
## appearance in one place.
func _build_lock_on_reticle() -> void:
	_lock_on_reticle = Panel.new()
	_lock_on_reticle.name = "LockOnReticle"
	_lock_on_reticle.custom_minimum_size = RETICLE_SIZE
	_lock_on_reticle.size = RETICLE_SIZE
	_lock_on_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_on_reticle.visible = false
	_lock_on_reticle.pivot_offset = RETICLE_SIZE * 0.5

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_color = Color(0.85, 0.92, 1.0, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(RETICLE_SIZE.x * 0.5))
	_lock_on_reticle.add_theme_stylebox_override("panel", style)

	add_child(_lock_on_reticle)


func _on_lock_on_changed(target: Node3D) -> void:
	_lock_on_target = target
	_lock_on_reticle.visible = target != null

	if target == null:
		return

	# Snap in from oversized so acquiring a target reads as a deliberate action.
	_lock_on_reticle.scale = Vector2.ONE * 2.2
	if _reticle_tween:
		_reticle_tween.kill()
	_reticle_tween = create_tween()
	_reticle_tween.set_ease(Tween.EASE_OUT)
	_reticle_tween.tween_property(_lock_on_reticle, "scale", Vector2.ONE, 0.18)


func _update_lock_on_reticle() -> void:
	if _lock_on_target == null or not is_instance_valid(_lock_on_target):
		if _lock_on_reticle and _lock_on_reticle.visible:
			_lock_on_reticle.visible = false
		return

	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return

	var anchor := _lock_on_target.get_node_or_null("LockOnPoint") as Node3D
	var world_position: Vector3 = anchor.global_position if anchor != null else _lock_on_target.global_position + Vector3.UP

	# Behind the camera unprojects to a mirrored on-screen point, which would draw
	# the reticle over empty space.
	if camera.is_position_behind(world_position):
		_lock_on_reticle.visible = false
		return

	_lock_on_reticle.visible = true
	_lock_on_reticle.position = camera.unproject_position(world_position) - RETICLE_SIZE * 0.5

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

## Hides the centre message immediately. Used when a contextual prompt stops
## applying — walking away from an altar, for instance — where fading out would
## leave stale instructions on screen.
func clear_center_message() -> void:
	if center_message_tween:
		center_message_tween.kill()
		center_message_tween = null

	center_message_label.visible = false


func show_temporary_center_message(message: String, duration: float = 1.8) -> void:
	show_center_message(message)

	center_message_tween = create_tween()
	center_message_tween.tween_interval(duration)
	center_message_tween.tween_property(center_message_label, "modulate:a", 0.0, 0.35)
	center_message_tween.tween_callback(func() -> void:
		center_message_label.visible = false
		center_message_tween = null
	)

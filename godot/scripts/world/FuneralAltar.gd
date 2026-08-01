class_name FuneralAltar
extends Node3D
## A corrupted Funeral Altar. Cleansing all four is what summons the Choirmaster.
##
## ADR-0002 asks for a narrative gate rather than an invisible completion
## percentage, so the altar is a physical object the player walks to and acts on,
## guarded by a group that must be cleared first. Three states, each visually
## distinct at a distance:
##
##   CORRUPTED  — guarded. Sickly green flame, cannot be touched.
##   READY      — its guards are dead. Flame turns spectral blue and calls out.
##   CLEANSED   — restored. Warm gold, and the graveyard is one step quieter.

signal cleansed(altar: FuneralAltar)

enum State { CORRUPTED, READY, CLEANSED }

const CORRUPTED_COLOUR: Color = Color(0.35, 0.95, 0.45)
const READY_COLOUR: Color = Color(0.35, 0.75, 1.0)
const CLEANSED_COLOUR: Color = Color(1.0, 0.78, 0.35)

## Tall enough to clear the crypts and be seen over them from across a region.
const BEACON_HEIGHT: float = 14.0

@export var altar_id: StringName = &"altar"
@export var display_name: String = "Funeral Altar"
## The group guarding this altar. Until it is cleared the altar cannot be
## cleansed, which is what makes clearing a region meaningful.
@export var encounter_path: NodePath
@export var interact_radius: float = 3.2

var state: State = State.CORRUPTED

var _player_in_range: bool = false
var _flame: OmniLight3D = null
var _flame_mesh: MeshInstance3D = null
var _flame_material: StandardMaterial3D = null
var _beacon: MeshInstance3D = null
var _beacon_material: StandardMaterial3D = null
var _pulse_time: float = 0.0


func _ready() -> void:
	add_to_group("funeral_altars")
	_build_flame()
	_apply_state_visuals()

	var encounter := get_node_or_null(encounter_path) as EnemyEncounter
	if encounter == null:
		# No guards: ready from the start.
		_set_state(State.READY)
		return

	if encounter.is_cleared:
		_set_state(State.READY)
	else:
		encounter.cleared.connect(_on_encounter_cleared)


func _process(delta: float) -> void:
	_animate_flame(delta)

	if state == State.CLEANSED:
		return

	var player: Node3D = _get_player()
	if player == null:
		return

	var in_range: bool = global_position.distance_to(player.global_position) <= interact_radius
	if in_range != _player_in_range:
		_player_in_range = in_range
		_update_prompt()

	if in_range and state == State.READY and Input.is_action_just_pressed("interact"):
		cleanse()


func cleanse() -> void:
	if state != State.READY:
		return

	_set_state(State.CLEANSED)
	_player_in_range = false
	_update_prompt()

	AudioManager.play_sfx_3d(&"altar_cleanse", global_position)
	_play_cleanse_burst()
	cleansed.emit(self)


## Restores a cleansed altar without ceremony. Used when loading a save.
func restore_cleansed() -> void:
	_set_state(State.CLEANSED)


func is_cleansed() -> bool:
	return state == State.CLEANSED


func _on_encounter_cleared() -> void:
	if state != State.CORRUPTED:
		return
	_set_state(State.READY)

	var player: Node3D = _get_player()
	if player != null and player.get("hud_controller") != null:
		var hud: Node = player.get("hud_controller")
		if hud.has_method("show_temporary_center_message"):
			hud.call("show_temporary_center_message", "%s can be cleansed" % display_name, 2.4)


# ── Visuals ──────────────────────────────────────────────────────

func _set_state(new_state: State) -> void:
	state = new_state
	_apply_state_visuals()


func _state_colour() -> Color:
	match state:
		State.READY:
			return READY_COLOUR
		State.CLEANSED:
			return CLEANSED_COLOUR
		_:
			return CORRUPTED_COLOUR


func _apply_state_visuals() -> void:
	var colour: Color = _state_colour()
	if _flame != null:
		_flame.light_color = colour
		# Cleansed altars burn steady and bright; corrupted ones smoulder.
		_flame.light_energy = 3.2 if state == State.CLEANSED else 1.8
	if _flame_material != null:
		_flame_material.albedo_color = Color(colour.r, colour.g, colour.b, 0.85)
	if _beacon_material != null:
		# A cleansed altar dims its beacon: it is no longer somewhere to go, but it
		# still marks where the player has been.
		var beam_alpha: float = 0.10 if state == State.CLEANSED else 0.22
		_beacon_material.albedo_color = Color(colour.r, colour.g, colour.b, beam_alpha)


## The flame is the altar's entire language: colour says its state and the pulse
## says it is alive. Built in code so all three states are defined in one place.
func _build_flame() -> void:
	_flame_material = StandardMaterial3D.new()
	_flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	var sphere := SphereMesh.new()
	sphere.radius = 0.55
	sphere.height = 1.3
	sphere.radial_segments = 12
	sphere.rings = 6
	sphere.material = _flame_material

	_flame_mesh = MeshInstance3D.new()
	_flame_mesh.name = "Flame"
	_flame_mesh.mesh = sphere
	_flame_mesh.position = Vector3(0.0, 1.5, 0.0)
	_flame_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flame_mesh)

	# A tall shaft of light. The altars are the level's objectives in a dark, foggy
	# cemetery, so they have to be findable from the far side of a region — a flame
	# at head height is a few pixels at that distance and reads as nothing.
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.16
	beam_mesh.bottom_radius = 0.5
	beam_mesh.height = BEACON_HEIGHT
	beam_mesh.radial_segments = 12

	_beacon_material = StandardMaterial3D.new()
	_beacon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beacon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	# Drawn from inside as well as outside, so walking through it is not a hole.
	_beacon_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_mesh.material = _beacon_material

	_beacon = MeshInstance3D.new()
	_beacon.name = "Beacon"
	_beacon.mesh = beam_mesh
	_beacon.position = Vector3(0.0, BEACON_HEIGHT * 0.5, 0.0)
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beacon)

	_flame = OmniLight3D.new()
	_flame.name = "FlameLight"
	_flame.position = Vector3(0.0, 1.6, 0.0)
	_flame.omni_range = 18.0
	_flame.shadow_enabled = false
	add_child(_flame)


func _animate_flame(delta: float) -> void:
	if _flame_mesh == null:
		return

	_pulse_time += delta
	# A ready altar pulses harder than a corrupted one, so "come and cleanse me"
	# reads from across a region.
	var rate: float = 4.5 if state == State.READY else 2.2
	var depth: float = 0.22 if state == State.READY else 0.10
	var pulse: float = 1.0 + sin(_pulse_time * rate) * depth

	_flame_mesh.scale = Vector3.ONE * pulse
	if _flame != null:
		_flame.light_energy = (3.2 if state == State.CLEANSED else 1.8) * pulse

	# The beacon breathes with the flame but at a fraction of the depth, so it
	# stays a steady landmark rather than a distracting strobe.
	if _beacon != null:
		var beam_pulse: float = 1.0 + (pulse - 1.0) * 0.35
		_beacon.scale = Vector3(beam_pulse, 1.0, beam_pulse)


func _play_cleanse_burst() -> void:
	var ring := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.06
	mesh.radial_segments = 48

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(CLEANSED_COLOUR.r, CLEANSED_COLOUR.g, CLEANSED_COLOUR.b, 0.8)
	mesh.material = material

	ring.mesh = mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(0.2, 1.0, 0.2)
	add_child(ring)
	ring.position = Vector3(0.0, 0.2, 0.0)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(14.0, 1.0, 14.0), 0.9)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.9)
	tween.set_parallel(false)
	tween.tween_callback(ring.queue_free)


# ── Prompt ───────────────────────────────────────────────────────

func _update_prompt() -> void:
	var player: Node3D = _get_player()
	if player == null:
		return

	var hud: Node = player.get("hud_controller")
	if hud == null or not hud.has_method("show_center_message"):
		return

	if not _player_in_range:
		if hud.has_method("clear_center_message"):
			hud.call("clear_center_message")
		return

	if state == State.READY:
		hud.call("show_center_message", "Press E to cleanse the %s" % display_name)
	elif state == State.CORRUPTED:
		hud.call("show_center_message", "%s is protected. Destroy its guardians." % display_name)


func _get_player() -> Node3D:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	return players[0] as Node3D if not players.is_empty() else null

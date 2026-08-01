class_name ChurchBell
extends Node3D
## The church bell. Rings when the last Funeral Altar is cleansed, and its toll is
## what summons the Choirmaster.
##
## ADR-0002 asks for this beat specifically: bell, choir echo, Sir Brass comments,
## boss appears. It is the demo's turning point, so it is deliberately slow — the
## player gets several seconds of dread between the toll and the fight.

signal toll_finished

## Seconds between the bell ringing and the boss being announced. Long enough for
## the sound to land and the player to look toward the church.
@export var dread_seconds: float = 4.0
## How far the bell's light flare reaches.
@export var flare_range: float = 40.0

var has_rung: bool = false

var _flare: OmniLight3D = null


func _ready() -> void:
	_build_flare()
	EventBus.all_altars_cleansed.connect(ring)


func ring() -> void:
	if has_rung:
		return

	has_rung = true
	AudioManager.play_sfx_3d(&"church_bell_toll", global_position, AudioManager.BUS_SFX_WORLD, 4.0)
	EventBus.church_bell_rang.emit()

	_flash()
	_announce("The bell tolls...")

	await get_tree().create_timer(dread_seconds).timeout

	AudioManager.play_sfx_3d(&"choir_corrupted_loop", global_position)
	_announce("Something answers.")

	toll_finished.emit()


## A pulse of cold light across the whole graveyard on the toll, so the moment is
## felt even by a player looking the other way.
func _build_flare() -> void:
	_flare = OmniLight3D.new()
	_flare.name = "BellFlare"
	_flare.light_color = Color(0.7, 0.85, 1.0)
	_flare.light_energy = 0.0
	_flare.omni_range = flare_range
	_flare.shadow_enabled = false
	add_child(_flare)


func _flash() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(_flare, "light_energy", 6.0, 0.25)
	tween.tween_property(_flare, "light_energy", 0.0, 2.6)


func _announce(message: String) -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return

	var hud: Node = players[0].get("hud_controller")
	if hud != null and hud.has_method("show_temporary_center_message"):
		hud.call("show_temporary_center_message", message, 3.0)

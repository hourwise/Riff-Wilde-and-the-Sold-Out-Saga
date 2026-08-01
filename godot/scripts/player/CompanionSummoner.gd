class_name CompanionSummoner
extends Node
## Handles the player's side of calling Sir Brass.
##
## Kept separate from the companion itself so the player knows only "summon", and
## Sir Brass knows only how to perform. Neither holds a reference to the other
## beyond the single call.

## Encore must be full to summon. The meter exists for this.
@export var require_full_encore: bool = true
## Seconds before he can be called again, on top of rebuilding the meter.
@export var cooldown_seconds: float = 1.0

var _player: PlayerController = null
var _encore: EncoreMeter = null
var _cooldown_timer: float = 0.0


func _ready() -> void:
	_player = get_parent() as PlayerController
	_encore = get_parent().get_node_or_null("EncoreMeter") as EncoreMeter


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	if not Input.is_action_just_pressed("summon_companion"):
		return
	if not can_summon():
		AudioManager.play_ui(&"ui_back")
		return

	summon()


func can_summon() -> bool:
	if _player == null or _player.is_dead or _cooldown_timer > 0.0:
		return false
	if require_full_encore and (_encore == null or not _encore.is_full()):
		return false
	return true


func summon() -> void:
	var facing: Vector3 = -_player.mesh.global_transform.basis.z
	facing.y = 0.0

	# Aim the blast at whatever is locked on, if anything — the player has already
	# told us what they care about.
	if _player.lock_on != null and _player.lock_on.has_target():
		var to_target: Vector3 = _player.lock_on.get_target_position() - _player.global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.01:
			facing = to_target

	SirBrass.summon(_player, facing)

	_cooldown_timer = cooldown_seconds
	if _encore != null:
		_encore.spend_all()

	if _player.visual != null:
		_player.visual.play_attack(0)

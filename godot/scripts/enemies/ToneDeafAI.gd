class_name ToneDeafAI
extends EnemyAI
## The Tone Deaf. Basic shambling undead.
##
## Deliberately the most forgiving enemy in the roster: slow approach, long
## telegraph, modest damage. This is where the player learns the combo chain, so
## it must be safe to experiment against.
##
## All behaviour comes from EnemyAI; only the telegraph is specialised.

const TELEGRAPH_COLOUR: Color = Color(1.0, 0.45, 0.25)


func _begin_attack() -> void:
	super._begin_attack()
	# Warm amber warning held for the length of the wind-up, so the player can
	# read the incoming swing without watching the animation closely.
	flash(TELEGRAPH_COLOUR, 2.2, _stat_attack_windup())
	AudioManager.play_sfx_3d(&"tonedeaf_attack", global_position)


func _resolve_attack() -> void:
	super._resolve_attack()


func die() -> void:
	if is_dead:
		return
	AudioManager.play_sfx_3d(&"tonedeaf_death", global_position)
	super.die()

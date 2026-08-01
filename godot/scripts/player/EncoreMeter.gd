class_name EncoreMeter
extends Node
## The Encore meter: the crowd's excitement, and the demo's central feedback loop.
##
## Encore rises when Riff performs well and decays when he stops. It drives three
## things at once, which is what makes it the spine of the slice:
##   1. Music layers — higher Encore adds instruments (MusicDirector).
##   2. Sir Brass — a full meter is the cue to summon him.
##   3. Player read — one number telling you how well you are doing.
##
## Purely a producer: it listens to EventBus combat events and announces its own
## changes. It never reaches into music, UI or the companion.

## Tier thresholds as fractions of the maximum. Chosen to match the four combat
## stems in docs/AUDIO_SPEC.md: guitar, +percussion, +trumpet, +lead.
const TIER_THRESHOLDS: Array[float] = [0.0, 0.33, 0.66, 1.0]

@export var max_value: float = 100.0

@export_group("Gains")
@export var gain_per_hit: float = 3.0
## Combos are the skill expression, so they pay far better than mashing.
@export var gain_per_combo: float = 12.0
@export var gain_per_kill: float = 8.0
## Dodging through an attack rewards nerve.
@export var gain_per_dodge: float = 1.5

@export_group("Decay")
## Seconds of inactivity before Encore starts draining.
@export var decay_delay: float = 3.5
@export var decay_per_second: float = 6.0
## Taking damage costs Encore — the crowd notices when you get hit.
@export var loss_per_damage_taken: float = 0.6

## Once the meter fills, the Encore stays charged until it is spent or the meter
## falls this far. Without the latch, decay drains the meter within a fifth of a
## second of it filling, so the summon prompt would appear and the ability would
## be gone before the player could react to it.
@export_range(0.0, 1.0, 0.05) var charge_release_ratio: float = 0.55

var value: float = 0.0

var _decay_timer: float = 0.0
var _tier: int = 0
## Latched "ready to summon" state, distinct from the meter being literally full.
var _charged: bool = false


func _ready() -> void:
	EventBus.player_attack_landed.connect(_on_attack_landed)
	EventBus.combo_completed.connect(_on_combo_completed)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.player_dodged.connect(_on_dodged)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.combat_ended.connect(_on_combat_ended)

	_announce()


func _process(delta: float) -> void:
	if _decay_timer > 0.0:
		_decay_timer -= delta
		return

	if value > 0.0:
		_add(-decay_per_second * delta, false)


func get_ratio() -> float:
	return clampf(value / maxf(max_value, 0.01), 0.0, 1.0)


func get_tier() -> int:
	return _tier


## True while the Encore is banked and Sir Brass can be called. Deliberately not
## the same as "the bar is at 100%" — see charge_release_ratio.
func is_full() -> bool:
	return _charged


## Spends the whole meter. Called when Sir Brass is summoned — the companion is
## what the meter is *for*, so it costs all of it.
func spend_all() -> void:
	if value <= 0.0 and not _charged:
		return
	value = 0.0
	_charged = false
	_decay_timer = decay_delay
	_announce()


# ── Events ───────────────────────────────────────────────────────

func _on_attack_landed(_damage: float, _damage_type: StringName, _target: Node3D) -> void:
	_add(gain_per_hit, true)


func _on_combo_completed(_combo_id: StringName) -> void:
	_add(gain_per_combo, true)


func _on_enemy_died(_enemy: Node3D) -> void:
	_add(gain_per_kill, true)


func _on_dodged() -> void:
	_add(gain_per_dodge, true)


func _on_player_damaged(amount: float, _health_ratio: float) -> void:
	_add(-amount * loss_per_damage_taken, false)


## Leaving combat drains the meter faster than idling does, so the player does not
## walk into the next fight with a free Encore banked from the last one.
func _on_combat_ended() -> void:
	_decay_timer = minf(_decay_timer, decay_delay * 0.5)


# ── Internals ────────────────────────────────────────────────────

func _add(amount: float, refresh_decay: bool) -> void:
	if is_zero_approx(amount):
		return

	var previous: float = value
	value = clampf(value + amount, 0.0, max_value)

	if refresh_decay:
		_decay_timer = decay_delay

	if is_equal_approx(previous, value):
		return

	_announce()


func _announce() -> void:
	EventBus.encore_changed.emit(value, max_value)
	_update_charge()

	var new_tier: int = _calculate_tier()
	if new_tier == _tier:
		return

	_tier = new_tier
	EventBus.encore_tier_changed.emit(_tier)


## Charges on reaching a full meter, and only releases once the meter has fallen
## well back — so the prompt fires once, stays true long enough to act on, and
## does not flicker as the bar wobbles around the top.
func _update_charge() -> void:
	var ratio: float = get_ratio()

	if not _charged and ratio >= 1.0:
		_charged = true
		EventBus.encore_full.emit()
		AudioManager.play_ui(&"ui_encore_full")
		return

	if _charged and ratio < charge_release_ratio:
		_charged = false


func _calculate_tier() -> int:
	var ratio: float = get_ratio()
	var tier: int = 0
	for index in range(TIER_THRESHOLDS.size()):
		if ratio >= TIER_THRESHOLDS[index]:
			tier = index
	return tier

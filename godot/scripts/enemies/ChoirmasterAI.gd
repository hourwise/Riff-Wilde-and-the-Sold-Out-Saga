class_name ChoirmasterAI
extends EnemyAI
## The Choirmaster. The demo's mini boss.
##
## Fought in four bouts separated by three conducted interludes. At each health
## threshold he turns his back on Riff, faces the great altar, and conducts —
## invulnerable, harmless, and summoning a wave of the dead. The bout resumes only
## when the wave is cleared.
##
## The structure is the point. A single health bar drained at a constant rate is a
## damage race; breaking it into bouts gives the fight a shape the player can
## read, and hands them three moments where the correct move is to stop hitting
## the boss and deal with the room instead. It also gives the music somewhere to
## go, since the interludes are exactly where the choir layer belongs.
##
## He is invulnerable while conducting rather than merely tough, because a boss
## who can be burned down through his own set piece turns the interlude into a
## damage check and throws the shape away.

## Health fractions at which he breaks off to conduct, and what he calls up.
##
## Ordered high to low and consumed in order. "Low" is the shambling front line;
## "mid" is something that demands attention on its own — a caster or a heavy.
const INTERLUDES: Array[Dictionary] = [
	{"at": 0.75, "low": 5, "mid": 0},
	{"at": 0.50, "low": 5, "mid": 1},
	{"at": 0.25, "low": 5, "mid": 3},
]

enum Bout { FIGHTING, CONDUCTING }

@export_group("Summoning")
## Rank and file. Cheap, numerous, and no threat alone.
@export var low_summons: Array[PackedScene] = []
## The ones worth answering first.
@export var mid_summons: Array[PackedScene] = []
## Where the wave rises, as a radius around the altar he conducts toward.
@export var summon_radius: float = 9.0
## Seconds between each one clawing its way up, so a wave arrives rather than
## appearing.
@export var summon_stagger: float = 0.35

@export_group("Conducting")
## What he turns to face. Set by the level; falls back to his own spawn point, so
## he still performs the set piece in a test scene with no altar in it.
@export var altar_path: NodePath
## Held for at least this long even if the wave dies instantly, so the interlude
## always reads as a deliberate beat rather than a stutter.
@export var minimum_conduct_seconds: float = 3.0

@export_group("Ranged attack")
@export var projectile_scene: PackedScene = null
## Notes per volley. More than one, because a single note is a Cantor's attack and
## he should not read as a large Cantor.
@export var volley_size: int = 3
@export var volley_spread_degrees: float = 22.0
@export var volley_interval: float = 0.12
@export var muzzle_height: float = 1.9
## Closer than this and he stops casting and swings instead.
@export var melee_distance: float = 3.4

var bout: Bout = Bout.FIGHTING
## Which interlude comes next. Also how many are done, for the HUD and the music.
var interlude_index: int = 0

var _summoned: Array[Node] = []
var _conduct_timer: float = 0.0
var _wave_pending: int = 0
var _altar: Node3D = null


func _ready() -> void:
	super._ready()
	add_to_group("boss")
	_altar = get_node_or_null(altar_path) as Node3D


func _physics_process(delta: float) -> void:
	if bout == Bout.CONDUCTING:
		_tick_conducting(delta)
		_apply_gravity(delta)
		_apply_friction(delta)
		move_and_slide()
		return

	super._physics_process(delta)


## Health is checked after damage rather than on a timer, so the interlude starts
## on the hit that crosses the threshold.
func _on_damaged(event: DamageEvent) -> void:
	# Refused here, not only on the hurtbox. The hurtbox flag is what stops
	# incoming hitboxes, but the boss owning the rule means nothing that reaches
	# him by another route — a summon's stray attack, a script, a future ability —
	# can quietly drain him through his own set piece.
	if bout == Bout.CONDUCTING:
		return

	super._on_damaged(event)

	if is_dead or interlude_index >= INTERLUDES.size():
		return

	var ratio: float = current_health / maxf(max_health, 0.001)
	if ratio <= float(INTERLUDES[interlude_index]["at"]):
		_begin_conducting()


# ── Conducting ───────────────────────────────────────────────────

func _begin_conducting() -> void:
	bout = Bout.CONDUCTING
	_cancel_attack()
	_conduct_timer = 0.0

	# Untouchable and harmless together. One without the other turns the interlude
	# into either a free damage window or an unfair one.
	if hurtbox != null:
		hurtbox.is_invulnerable = true

	if visual != null and visual.has_method("play_song"):
		visual.call("play_song")

	var wave: Dictionary = INTERLUDES[interlude_index]
	EventBus.boss_interlude_started.emit(interlude_index + 1, INTERLUDES.size())
	AudioManager.play_sfx_3d(&"choirmaster_conduct", global_position)

	_summon_wave(int(wave["low"]), int(wave["mid"]))


func _tick_conducting(delta: float) -> void:
	_conduct_timer += delta

	# Turned toward the altar, not the player: he is addressing the choir, and his
	# back being turned is the readable sign that he cannot be hurt.
	var facing: Vector3 = _conducting_target() - global_position
	facing.y = 0.0
	if facing != Vector3.ZERO:
		_face(facing.normalized(), delta)

	if visual != null:
		visual.play_locomotion(0.0)

	_forget_dead_summons()
	if _wave_pending > 0 or not _summoned.is_empty():
		return
	if _conduct_timer < minimum_conduct_seconds:
		return

	_end_conducting()


func _end_conducting() -> void:
	bout = Bout.FIGHTING
	interlude_index += 1

	if hurtbox != null:
		hurtbox.is_invulnerable = false

	# Straight back onto the offensive rather than idling: the player has just
	# finished a wave and the fight should close on them again.
	attack_cooldown_timer = 0.6
	EventBus.boss_interlude_finished.emit(interlude_index, INTERLUDES.size())


func _conducting_target() -> Vector3:
	return _altar.global_position if _altar != null else global_position - global_transform.basis.z * 6.0


func _summon_wave(low: int, mid: int) -> void:
	var wave: Array[PackedScene] = []
	for index in range(low):
		wave.append(_pick(low_summons, index))
	for index in range(mid):
		wave.append(_pick(mid_summons, index))

	_wave_pending = wave.size()
	for index in range(wave.size()):
		_summon_one(wave[index], index, wave.size())


func _pick(pool: Array[PackedScene], index: int) -> PackedScene:
	if pool.is_empty():
		return null
	return pool[index % pool.size()]


func _summon_one(scene: PackedScene, index: int, total: int) -> void:
	if scene == null:
		_wave_pending -= 1
		return

	# Staggered by a timer that ignores time scale, so a hitstop landing on the
	# summon does not bunch the whole wave into one frame.
	var delay: float = float(index) * summon_stagger
	var timer: SceneTreeTimer = get_tree().create_timer(delay, true, false, true)
	timer.timeout.connect(func() -> void: _rise(scene, index, total))


func _rise(scene: PackedScene, index: int, total: int) -> void:
	_wave_pending -= 1
	if is_dead or not is_inside_tree():
		return

	var minion := scene.instantiate() as Node3D
	if minion == null:
		return

	# Parented to the level, not to the boss: a summon that chases Riff across the
	# courtyard must not be dragged around by whoever called it up.
	get_parent().add_child(minion)

	var angle: float = TAU * float(index) / float(maxi(total, 1))
	var around: Vector3 = _conducting_target()
	minion.global_position = around + Vector3(cos(angle), 0.0, sin(angle)) * summon_radius
	minion.global_position.y = global_position.y + 0.5

	_summoned.append(minion)
	EventBus.boss_summon_raised.emit(interlude_index + 1)
	AudioManager.play_sfx_3d(&"choirmaster_summon", minion.global_position)


func _forget_dead_summons() -> void:
	var alive: Array[Node] = []
	for minion: Node in _summoned:
		if not is_instance_valid(minion):
			continue
		# "Dead" is not the same as "freed": a corpse lingers for its death
		# animation, and waiting for the node to disappear would hold the
		# interlude open past the point the player has finished the wave.
		if bool(minion.get("is_dead")):
			continue
		alive.append(minion)
	_summoned = alive


## How much of the current wave is left, for the HUD.
func get_remaining_summons() -> int:
	_forget_dead_summons()
	return _summoned.size() + _wave_pending


# ── Attacking ────────────────────────────────────────────────────

## Casts at range, swings up close. He should never be safe to stand next to.
func _try_start_attack() -> void:
	if bout == Bout.CONDUCTING:
		return
	super._try_start_attack()


func _resolve_attack() -> void:
	if target == null or bout == Bout.CONDUCTING:
		return

	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0

	if to_target.length() <= melee_distance:
		if target.stats.can_take_damage():
			target.stats.take_damage(_stat_attack_damage() * 1.4)
		AudioManager.play_sfx_3d(&"choirmaster_stomp", global_position)
		return

	_cast_volley(to_target)


## A fan of notes rather than one. Spread so that standing still is punished and a
## roll through the gap is rewarded.
func _cast_volley(to_target: Vector3) -> void:
	if projectile_scene == null:
		return

	var muzzle: Vector3 = global_position + Vector3.UP * muzzle_height
	var aim: Vector3 = (target.global_position + Vector3.UP * 0.8 - muzzle).normalized()

	for index in range(volley_size):
		var offset: float = 0.0
		if volley_size > 1:
			offset = (float(index) / float(volley_size - 1) - 0.5) * deg_to_rad(volley_spread_degrees)
		var direction: Vector3 = aim.rotated(Vector3.UP, offset)

		var delay: float = float(index) * volley_interval
		if delay <= 0.0:
			_fire(muzzle, direction)
			continue
		var timer: SceneTreeTimer = get_tree().create_timer(delay, true, false, true)
		timer.timeout.connect(func() -> void: _fire(global_position + Vector3.UP * muzzle_height, direction))


func _fire(from: Vector3, direction: Vector3) -> void:
	if is_dead or not is_inside_tree() or projectile_scene == null:
		return

	var note := projectile_scene.instantiate() as Node3D
	if note == null:
		return

	get_parent().add_child(note)
	note.global_position = from
	note.set("attacker", self)
	if note.has_method("launch"):
		note.call("launch", direction, target)

	AudioManager.play_sfx_3d(&"choirmaster_cast", from)


func die() -> void:
	# The room is cleared with him. Leaving a half-finished wave alive after the
	# boss falls turns the end of the fight into mopping up.
	for minion: Node in _summoned:
		if is_instance_valid(minion) and minion.has_method("die"):
			minion.call("die")
	_summoned.clear()

	EventBus.boss_defeated.emit(&"choirmaster")
	super.die()

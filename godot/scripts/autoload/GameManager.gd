extends Node
## Owns coarse game state: which chapter of the demo the player is in, and whether
## play is currently suspended (pause menu, cinematic, dialogue).
##
## Input actions are defined in project.godot — see tools/generate_input_map.gd.
## They are no longer registered at runtime, so they survive export and can be
## rebound by the player.

## Broad location/mode. Systems that only care about "am I in the hub or a mission"
## read this; anything finer-grained belongs to QuestDirector.
enum GameState { INN_HUB, MISSION, CINEMATIC, GAME_OVER }

## Reasons play can be suspended. Tracked as a set so that, for example, closing the
## pause menu during a cinematic does not resume gameplay.
enum SuspendReason { PAUSE_MENU, CINEMATIC, DIALOGUE }

var current_state: GameState = GameState.INN_HUB

var _suspend_reasons: Dictionary = {}
var _hitstop_active: bool = false
## Bumped by every hitstop, so a superseded one knows not to restore time.
var _hitstop_generation: int = 0


func _ready() -> void:
	# Autoloads must keep ticking while the tree is paused, otherwise the pause
	# menu cannot unpause itself.
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("[GameManager] Ready.")


func change_state(new_state: GameState) -> void:
	if new_state == current_state:
		return

	var previous: GameState = current_state
	current_state = new_state
	EventBus.game_state_changed.emit(previous, new_state)
	print("[GameManager] State: %s -> %s" % [GameState.keys()[previous], GameState.keys()[new_state]])


func is_state(state: GameState) -> bool:
	return current_state == state


## Suspends gameplay for a named reason. Play resumes only once every reason has
## been released, so overlapping systems cannot unpause each other by accident.
func suspend(reason: SuspendReason) -> void:
	if _suspend_reasons.has(reason):
		return

	_suspend_reasons[reason] = true
	_apply_suspend_state()


func release_suspend(reason: SuspendReason) -> void:
	if not _suspend_reasons.has(reason):
		return

	_suspend_reasons.erase(reason)
	_apply_suspend_state()


func is_suspended() -> bool:
	return not _suspend_reasons.is_empty()


func is_suspended_by(reason: SuspendReason) -> bool:
	return _suspend_reasons.has(reason)


# ── Hitstop ──────────────────────────────────────────────────────

## Briefly slows time on impact. This is the single largest contributor to how
## heavy an attack feels, so it lives here rather than in any one combat script:
## every source of impact shares one budget and they cannot stack into a freeze.
##
## Duration is in real seconds, independent of the slowdown applied.
func apply_hitstop(duration: float, time_scale: float = 0.05) -> void:
	if duration <= 0.0 or is_suspended():
		return

	# A stronger hit overrides a weaker one already running; a weaker one is
	# ignored so rapid combo hits do not compound into a stall.
	if _hitstop_active and time_scale >= Engine.time_scale:
		return

	# Each hitstop takes a ticket, and only the newest one is allowed to restore
	# time. Overriding a weaker freeze left the weaker one still waiting on its own
	# timer: a 60 ms light hit followed 10 ms later by a 120 ms finisher had the
	# light hit wake at 60 ms and end the finisher's freeze less than halfway
	# through. The stronger the hit, the more likely it was to be cut short —
	# exactly backwards, and it reads as hitstop being inconsistent or absent.
	_hitstop_generation += 1
	var generation: int = _hitstop_generation

	_hitstop_active = true
	Engine.time_scale = clampf(time_scale, 0.01, 1.0)

	# ignore_time_scale is essential — a scaled timer would take proportionally
	# longer to fire, stretching a 60 ms hitstop into more than a second.
	var timer: SceneTreeTimer = get_tree().create_timer(duration, true, false, true)
	await timer.timeout

	# Superseded while waiting: the newer freeze owns time now.
	if generation != _hitstop_generation:
		return

	Engine.time_scale = 1.0
	_hitstop_active = false


func _apply_suspend_state() -> void:
	var suspended: bool = is_suspended()
	if get_tree().paused == suspended:
		return

	get_tree().paused = suspended
	EventBus.game_suspended_changed.emit(suspended)

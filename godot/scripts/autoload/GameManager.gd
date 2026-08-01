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


func _apply_suspend_state() -> void:
	var suspended: bool = is_suspended()
	if get_tree().paused == suspended:
		return

	get_tree().paused = suspended
	EventBus.game_suspended_changed.emit(suspended)

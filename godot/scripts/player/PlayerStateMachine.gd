class_name PlayerStateMachine
extends Node

# Signal emitted when player changes movement state
signal state_changed(old_state: State, new_state: State)

enum State { IDLE, MOVE, DODGE, STAGGERED }

var current_state: State = State.IDLE

func change_state(new_state: State) -> void:
	if new_state == current_state:
		return
		
	var old_state := current_state
	current_state = new_state
	
	emit_signal("state_changed", old_state, new_state)
	print("[PlayerStateMachine] State changed: %s -> %s" % [State.keys()[old_state], State.keys()[new_state]])

func is_state(state: State) -> bool:
	return current_state == state

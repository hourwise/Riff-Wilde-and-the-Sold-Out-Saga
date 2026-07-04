class_name QuestBoard
extends Area3D

signal player_entered
signal player_exited
signal mission_requested

var player_in_range: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _unhandled_input(event: InputEvent) -> void:
	if player_in_range and event.is_action_pressed("interact"):
		mission_requested.emit()

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		player_in_range = true
		player_entered.emit()

func _on_body_exited(body: Node3D) -> void:
	if body is PlayerController:
		player_in_range = false
		player_exited.emit()

class_name ExtractionPoint
extends Area3D

signal player_entered
signal player_exited
signal extraction_requested

@export var active: bool = false

var player_in_range: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _unhandled_input(event: InputEvent) -> void:
	if active and player_in_range and event.is_action_pressed("interact"):
		extraction_requested.emit()

func set_active(is_active: bool) -> void:
	active = is_active
	visible = is_active
	monitoring = is_active

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		player_in_range = true
		player_entered.emit()

func _on_body_exited(body: Node3D) -> void:
	if body is PlayerController:
		player_in_range = false
		player_exited.emit()

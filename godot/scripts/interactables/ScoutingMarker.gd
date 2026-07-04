class_name ScoutingMarker
extends Area3D

signal scouted

@export var marker_name: String = "Scouting point"

var is_scouted: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if is_scouted:
		return

	if body is PlayerController:
		is_scouted = true
		scouted.emit()
		print("[ScoutingMarker] %s scouted." % marker_name)

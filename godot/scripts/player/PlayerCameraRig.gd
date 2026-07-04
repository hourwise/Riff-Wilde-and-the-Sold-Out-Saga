class_name PlayerCameraRig
extends Node3D

@export var sensitivity: float = 0.003
@export var pitch_min: float = -60.0
@export var pitch_max: float = 45.0

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.current = true

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Rotate the rig horizontally (yaw)
		rotate_y(-event.relative.x * sensitivity)
		
		# Rotate the spring arm vertically (pitch)
		var pitch_change: float = -event.relative.y * sensitivity
		var new_pitch: float = spring_arm.rotation.x + pitch_change
		spring_arm.rotation.x = clamp(new_pitch, deg_to_rad(pitch_min), deg_to_rad(pitch_max))
		
	if event.is_action_pressed("pause"):
		# Toggle mouse capture for testing / menu usage
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

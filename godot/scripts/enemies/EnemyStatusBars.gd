class_name EnemyStatusBars
extends Node3D

@export var bar_width: float = 1.25
@export var bar_height: float = 0.08
@export var armor_gap: float = 0.05
@export var show_armor_bar: bool = false
@export_range(0.0, 0.2, 0.01) var border_thickness: float = 0.08

var health_mesh: MeshInstance3D = null
var armor_mesh: MeshInstance3D = null

const BAR_SHADER = preload("res://shaders/status_bar.gdshader")

func _ready() -> void:
	health_mesh = _create_bar_mesh(&"Health", 0.0, Color(0.1, 0.02, 0.02, 0.78), Color(0.9, 0.12, 0.08, 0.95))
	add_child(health_mesh)

	if show_armor_bar:
		armor_mesh = _create_bar_mesh(&"Armor", -(bar_height + armor_gap), Color(0.02, 0.04, 0.08, 0.78), Color(0.22, 0.62, 1.0, 0.95))
		add_child(armor_mesh)

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	var target: Vector3 = camera.global_position
	if global_position.distance_squared_to(target) <= 0.001:
		return

	look_at(target, Vector3.UP)

func set_health(current: float, maximum: float) -> void:
	_set_progress(health_mesh, current, maximum)

func set_armor(current: float, maximum: float) -> void:
	_set_progress(armor_mesh, current, maximum)

func set_armor_visible(is_visible: bool) -> void:
	if armor_mesh:
		armor_mesh.visible = is_visible

func _create_bar_mesh(node_name: StringName, y_offset: float, bg_color: Color, fill_color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name

	var quad := QuadMesh.new()
	quad.size = Vector2(bar_width, bar_height)
	mesh_instance.mesh = quad
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.position = Vector3(0.0, y_offset, 0.0)

	var mat := ShaderMaterial.new()
	mat.shader = BAR_SHADER
	# Important: duplicate the material to ensure each enemy has its own instance
	# Otherwise, changing one enemy's health changes them all.
	mat = mat.duplicate()
	mat.set_shader_parameter(&"background_color", bg_color)
	mat.set_shader_parameter(&"fill_color", fill_color)
	mat.set_shader_parameter(&"border_color", Color(0.015, 0.012, 0.01, 0.95))
	mat.set_shader_parameter(&"border_thickness", border_thickness)
	mat.set_shader_parameter(&"progress", 1.0)

	mesh_instance.set_surface_override_material(0, mat)
	return mesh_instance

func _set_progress(mesh_instance: MeshInstance3D, current: float, maximum: float) -> void:
	if not mesh_instance:
		return

	var ratio: float = clampf(current / maxf(maximum, 0.01), 0.0, 1.0)
	var mat := mesh_instance.get_surface_override_material(0) as ShaderMaterial
	if mat:
		mat.set_shader_parameter(&"progress", ratio)

# res://scripts/SpacePlasmaField.gd
# ==============================================================================
# BioGenesis-X: Procedural Space Plasma Nebula & Ion Cloud Generator
# ==============================================================================

@tool
class_name SpacePlasmaField
extends Node3D

const PlasmaShaderResource: Shader = preload("res://shaders/space_plasma_nebula.gdshader")

@export var cloud_count: int = 6
@export var field_radius_m: float = 1200.0
@export var min_cloud_size_m: float = 120.0
@export var max_cloud_size_m: float = 380.0
@export var plasma_color_core: Color = Color(0.0, 0.95, 0.75, 1.0)
@export var plasma_color_fringe: Color = Color(0.55, 0.08, 0.85, 1.0)

var cloud_instances: Array[MeshInstance3D] = []

func _ready() -> void:
	_generate_plasma_clouds()

func _generate_plasma_clouds() -> void:
	for c: MeshInstance3D in cloud_instances:
		if is_instance_valid(c):
			c.queue_free()
	cloud_instances.clear()

	var sphere_mesh: SphereMesh = SphereMesh.new()
	sphere_mesh.radial_segments = 32
	sphere_mesh.rings = 16

	for i: int in range(cloud_count):
		var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		mesh_inst.name = "PlasmaCloud_%d" % i
		add_child(mesh_inst)

		var theta: float = (float(i) / float(cloud_count)) * TAU + (float(i) * 1.3)
		var dist: float = 250.0 + (float(i) / float(cloud_count)) * field_radius_m
		var height: float = (sin(float(i) * 2.1)) * (field_radius_m * 0.25)
		
		mesh_inst.position = Vector3(cos(theta) * dist, height, sin(theta) * dist)
		var sz: float = randf_range(min_cloud_size_m, max_cloud_size_m)
		mesh_inst.scale = Vector3(sz, sz * 0.65, sz * 1.3)
		mesh_inst.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)

		mesh_inst.mesh = sphere_mesh

		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = PlasmaShaderResource
		mat.set_shader_parameter("plasma_color_core", plasma_color_core)
		mat.set_shader_parameter("plasma_color_fringe", plasma_color_fringe)
		mat.set_shader_parameter("plasma_scale", 0.08 + (float(i) * 0.02))
		mat.set_shader_parameter("plasma_flow_speed", 0.06 + (float(i % 3) * 0.03))
		mesh_inst.material_override = mat

		cloud_instances.append(mesh_inst)

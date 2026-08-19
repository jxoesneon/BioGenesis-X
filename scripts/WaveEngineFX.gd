@tool
class_name WaveEngineFX
extends Node3D

## WaveEngineFX.gd
## Alcubierre warp plane visual effect for the Wave Engine supercruise.
## Spawns a translucent grid plane around the ship that deforms:
## front dips down (spacetime contraction), back raises up (spacetime expansion).
## The plane materializes (fades in) on engage and dematerializes (fades out) on disengage.

const WAVE_SHADER_PATH := "res://shaders/wave_engine.gdshader"

var _plane_mesh: PlaneMesh
var _mesh_instance: MeshInstance3D
var _shader_mat: ShaderMaterial
var _materialize_t: float = 0.0 ## 0 = invisible, 1 = fully visible
var _is_active: bool = true

func _ready() -> void:
	# Build the warp plane mesh (lies flat in XZ, will be positioned below ship)
	_plane_mesh = PlaneMesh.new()
	_plane_mesh.size = Vector2(60.0, 60.0)
	_plane_mesh.subdivide_width = 80
	_plane_mesh.subdivide_depth = 80
	# Orient plane so it lies horizontally beneath/around the ship
	# PlaneMesh default is in XZ plane facing +Y, which is what we want

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "WaveEnginePlane"
	_mesh_instance.mesh = _plane_mesh
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.transparency = 0.5

	# Load and assign the wave engine shader
	var shader := load(WAVE_SHADER_PATH)
	if shader:
		_shader_mat = ShaderMaterial.new()
		_shader_mat.shader = shader
		_shader_mat.set_shader_parameter("opacity", 0.0)
		_shader_mat.set_shader_parameter("wave_velocity", 0.0)
		_mesh_instance.material_override = _shader_mat

	add_child(_mesh_instance)

	# Position the plane slightly below the ship centerline so it surrounds
	# the hull like a spacetime membrane
	_mesh_instance.position = Vector3(0.0, -2.0, 0.0)

func _process(delta: float) -> void:
	if not _is_active:
		# Dematerializing: fade out then queue_free
		_materialize_t = move_toward(_materialize_t, 0.0, delta * 3.0)
		_apply_materialize()
		if _materialize_t <= 0.001:
			queue_free()
		return

	# Materializing: fade in to full opacity
	_materialize_t = move_toward(_materialize_t, 1.0, delta * 2.0)
	_apply_materialize()

func _apply_materialize() -> void:
	if not _shader_mat:
		return
	_shader_mat.set_shader_parameter("opacity", _materialize_t * 0.7)

## Called by FlightController each frame during ENGAGED state.
## speed_ratio: 0.0 = just engaged, 1.0 = full supercruise velocity.
func update_wave_state(speed_ratio: float, _delta: float) -> void:
	if not _shader_mat:
		return
	_shader_mat.set_shader_parameter("wave_velocity", speed_ratio)
	# Subtle plane pulsing with speed
	var pulse_scale := 1.0 + sin(Time.get_ticks_msec() * 0.003) * 0.02 * speed_ratio
	if _mesh_instance:
		_mesh_instance.scale = Vector3(pulse_scale, 1.0, pulse_scale)

## Triggers dematerialization and self-destruction.
func despawn() -> void:
	_is_active = false

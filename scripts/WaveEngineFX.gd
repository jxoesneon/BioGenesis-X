@tool
class_name WaveEngineFX
extends Node3D

## WaveEngineFX.gd
## Alcubierre warp plane visual effect for the Wave Engine supercruise.
## Spawns a translucent grid plane around the ship that deforms:
## front dips down (spacetime contraction), back raises up (spacetime expansion).
## The plane materializes (fades in) on engage and dematerializes (fades out) on disengage.
##
## WHY THIS EXISTS — LORE.md "The Wave Engine — Visual Manifestation":
## The translucent plane is the visible projection of the warped spacetime
## membrane. The Void-Fauna's caudal siphon system, resonantly tuned to
## deform spacetime, produces this projection. The ship's vascular conduit
## network distributes the warp field evenly around the hull, replacing the
## mechanical ring structures of the legacy drive with a living membrane.
## Per DESIGN_DIRECTION.md §7, the effect should feel elegant and
## scientific — the Alcubierre metric made visible, not explosive or fiery.

const WAVE_SHADER_PATH := "res://shaders/wave_engine.gdshader"

var _plane_mesh: PlaneMesh
var _mesh_instance: MeshInstance3D
var _shader_mat: ShaderMaterial
var _materialize_t: float = 0.0 ## 0 = invisible, 1 = fully visible
var _is_active: bool = true
# Wormhole vortex visual — a swirling bioluminescent disc that materializes in
# front of the ship when the Wave Engine engages (bio_wormhole_vortex shader).
var _vortex_mesh: MeshInstance3D
var _vortex_mat: ShaderMaterial

func _ready() -> void:
	# Build the warp plane mesh (lies flat in XZ, will be positioned below ship)
	_plane_mesh = PlaneMesh.new()
	# 60m square — large enough to surround the ship with a visible warp-field
	# margin, small enough to not clip into nearby geometry (stations, asteroids).
	_plane_mesh.size = Vector2(60.0, 60.0)
	# 32x32 subdivisions — the wave_engine.gdshader's vertex displacement uses a
	# tanh-based York time curve (smooth derivative, not high-frequency), so 32
	# subdivisions per axis capture the contraction/expansion shape without
	# wasting vertices on detail the shader can't use.
	_plane_mesh.subdivide_width = 32
	_plane_mesh.subdivide_depth = 32
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

	# Wormhole vortex disc — appears in front of the ship (−Z is forward) so the
	# supercruise reads as the ship diving into a swirling energy throat. The
	# disc is a CylinderMesh oriented face-on along the ship's forward axis.
	# Null-safe: skipped if the bio_wormhole_vortex shader isn't registered.
	var vortex_shader: Shader = ShaderRegistry.get_shader(ShaderRegistry.ID_WORMHOLE_VORTEX)
	if vortex_shader:
		_vortex_mesh = MeshInstance3D.new()
		_vortex_mesh.name = "WormholeVortex"
		var disc := CylinderMesh.new()
		# The vortex represents the bio-plasma resonance at the ship's caudal
		# siphon — the point where the Void-Fauna's siphon system channels
		# warp-frequency plasma (LORE.md "Adaptation: The Biological Wave
		# Engine"). 14m radius reads as a swirling energy throat at ship scale.
		disc.top_radius = 14.0
		disc.bottom_radius = 14.0
		# 0.2m height — the disc is nearly flat so it reads as a 2D vortex face,
		# not a 3D cylinder. 48 radial segments is sufficient for a smooth
		# circle; 4 rings is enough because the disc has almost no depth to
		# tessellate (height 0.2m).
		disc.height = 0.2
		disc.radial_segments = 48
		disc.rings = 4
		_vortex_mesh.mesh = disc
		_vortex_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_vortex_mat = ShaderMaterial.new()
		_vortex_mat.shader = vortex_shader
		_vortex_mat.set_shader_parameter("spiral_arms", 3.0)
		# 3 spiral arms represent the bio-plasma swirling through the vascular
		# conduit network (LORE.md organ pipeline #1). An odd count avoids the
		# symmetric "turbine blade" look — it should read as organic, not
		# mechanical.
		_vortex_mat.set_shader_parameter("rotation_speed", 0.8)
		# Rotation speed 0.8 is slow enough to feel like a biological vortex
		# (a living organ circulating plasma), not a mechanical turbine.
		_vortex_mat.set_shader_parameter("throat_radius", 0.18)
		_vortex_mat.set_shader_parameter("emission_boost", 3.5)
		# Start invisible; fades in with the rest of the effect via _apply_materialize.
		_vortex_mat.set_shader_parameter("emission_boost", 0.0)
		_vortex_mesh.material_override = _vortex_mat
		add_child(_vortex_mesh)
		# Orient the cylinder's central axis along the ship's forward (−Z) axis.
		# CylinderMesh axis is +Y by default, so rotate 90° around X to face forward.
		_vortex_mesh.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
		# Place the disc ahead of the bow so the ship appears to fly into it.
		# −22.0 Z is behind the ship's center, at the caudal siphon location —
		# anatomically where the Void-Fauna's propulsion organ sits (the siphon
		# vents face aft, so the vortex reads as the siphon's warp-frequency
		# plasma projection trailing the hull).
		_vortex_mesh.position = Vector3(0.0, 0.0, -22.0)

func _process(delta: float) -> void:
	if not _is_active:
		# Dematerializing: fade out then queue_free.
		# Speed 3.0 (faster than materialize's 2.0) because bubble collapse is
		# more violent than formation — per DESIGN_DIRECTION.md §7, "Shake on
		# engage/disengage (bubble formation/collapse is violent — spacetime is
		# being torn open and sealed)." Spacetime snaps back to flat faster
		# than it tears open.
		_materialize_t = move_toward(_materialize_t, 0.0, delta * 3.0)
		_apply_materialize()
		if _materialize_t <= 0.001:
			queue_free()
		return

	# Materializing: fade in to full opacity.
	# Speed 2.0 (slower than dematerialize's 3.0) because bubble formation is a
	# gradual tearing-open of spacetime, not a snap — the siphon system must
	# build resonance before the warp field fully projects.
	_materialize_t = move_toward(_materialize_t, 1.0, delta * 2.0)
	_apply_materialize()

func _apply_materialize() -> void:
	if _shader_mat:
		_shader_mat.set_shader_parameter("opacity", _materialize_t * 0.7)
	# Fade the wormhole vortex emission in/out with the materialize envelope.
	if _vortex_mat:
		_vortex_mat.set_shader_parameter("emission_boost", _materialize_t * 3.5)

## Called by FlightController each frame during ENGAGED state.
## speed_ratio: 0.0 = just engaged, 1.0 = full supercruise velocity.
func update_wave_state(speed_ratio: float, _delta: float) -> void:
	if _shader_mat:
		_shader_mat.set_shader_parameter("wave_velocity", speed_ratio)
	# Subtle plane pulsing with speed
	var pulse_scale := 1.0 + sin(Time.get_ticks_msec() * 0.003) * 0.02 * speed_ratio
	if _mesh_instance:
		_mesh_instance.scale = Vector3(pulse_scale, 1.0, pulse_scale)
	# Spin the wormhole vortex faster and brighten it as supercruise velocity
	# builds — reads as the throat opening up to swallow the ship.
	if _vortex_mat:
		var spin := 0.4 + speed_ratio * 2.2
		_vortex_mat.set_shader_parameter("rotation_speed", spin)
		_vortex_mat.set_shader_parameter("inflow_speed", 0.4 + speed_ratio * 1.6)
	if _vortex_mesh:
		# Grow the disc slightly with speed so the throat widens at full warp.
		var throat_scale := 1.0 + speed_ratio * 0.25
		_vortex_mesh.scale = Vector3(throat_scale, 1.0, throat_scale)

## Triggers dematerialization and self-destruction.
func despawn() -> void:
	_is_active = false

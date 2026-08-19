# ==============================================================================
# AtmosphereVisualSystem.gd - BioGenesis-X Planetary Atmosphere & Cloud Manager
# Pumilio Studios & Ciel Aerospace Physics Division
# ==============================================================================
# Manages the atmospheric scattering shell (atmosphere_scattering.gdshader) and
# the volumetric cloud layer (cloud_layer.gdshader) used for the 4-layer
# planetary descent sequence. Builds two concentric sphere meshes around the
# planet, drives per-archetype visual profiles, and updates shader uniforms
# every frame from the sun direction, camera/ship position, planet archetype
# and elapsed time. Includes distance-based LOD that exaggerates the shell
# thickness when viewed from orbit and thins it when on the surface.
#
# SHADERS DRIVEN:
#   res://shaders/atmosphere_scattering.gdshader  (spatial, sphere shell)
#   res://shaders/cloud_layer.gdshader            (spatial, sphere shell)
#
# ARCHETYPE SUPPORT:
#   0 MOLTEN           - thick orange/red atmosphere, ash clouds, high scatter
#   1 METALLIC_BARREN  - very thin atmosphere, no clouds, minimal scattering
#   2 DESERT_ARID      - thin dusty atmosphere, dust storm clouds, warm tint
#   3 TERRAN_OCEANIC   - Earth-like blue atmosphere, white clouds, standard
#   4 ICE_WORLD        - thin pale blue atmosphere, ice crystal clouds, cold
#   5 GAS_GIANT_JOVIAN - extremely thick atmosphere, turbulent banded clouds
#   6 GAS_GIANT_ICE    - thick methane atmosphere, turquoise clouds
#   7 RADIOTROPHIC_BIO - moderate green-tinted atmosphere, spore clouds, bio
# ==============================================================================
class_name AtmosphereVisualSystem
extends Node3D

# ------------------------------------------------------------------------------
# Planet Archetype (mirrors ProceduralPlanet / OceanSystem values)
# ------------------------------------------------------------------------------
enum PlanetArchetype {
	MOLTEN,           ## 0
	METALLIC_BARREN,  ## 1
	DESERT_ARID,      ## 2
	TERRAN_OCEANIC,   ## 3
	ICE_WORLD,        ## 4
	GAS_GIANT_JOVIAN, ## 5
	GAS_GIANT_ICE,    ## 6
	RADIOTROPHIC_BIO, ## 7
}

# ------------------------------------------------------------------------------
# Signals
# ------------------------------------------------------------------------------
signal visuals_ready()

# ------------------------------------------------------------------------------
# Shader Resource Paths
# ------------------------------------------------------------------------------
const ATMOSPHERE_SHADER_PATH: String = "res://shaders/atmosphere_scattering.gdshader"
const CLOUD_SHADER_PATH: String = "res://shaders/cloud_layer.gdshader"

# ------------------------------------------------------------------------------
# LOD Tunables
# ------------------------------------------------------------------------------
## Atmosphere thickness multiplier when the camera is on the surface.
@export var lod_surface_thickness_mult: float = 0.35
## Atmosphere thickness multiplier when the camera is in orbit (far away).
@export var lod_orbit_thickness_mult: float = 1.5
## Altitude (in atmosphere heights) over which LOD blends from surface to orbit.
@export var lod_blend_atmospheres: float = 12.0
## LOD smoothing rate (1.0 = instant).
@export var lod_lerp_rate: float = 3.0

# ------------------------------------------------------------------------------
# Internal State
# ------------------------------------------------------------------------------
var _active: bool = false
var _archetype: int = PlanetArchetype.TERRAN_OCEANIC
var _planet_radius: float = 1000.0
var _atmosphere_height: float = 80.0
var _sun_direction: Vector3 = Vector3(0.35, 0.85, 0.4)
var _camera_position: Vector3 = Vector3(0.0, 0.0, 0.0)
var _time_of_day: float = 0.3
var _elapsed_time: float = 0.0
var _current_lod_mult: float = 1.0
var _has_clouds: bool = true
var _lod_counter: int = 0

# Node references
var _atmosphere_mesh: MeshInstance3D = null
var _atmosphere_material: ShaderMaterial = null
var _cloud_mesh: MeshInstance3D = null
var _cloud_material: ShaderMaterial = null
var _camera: Camera3D = null

# ------------------------------------------------------------------------------
# Per-Archetype Atmosphere Profile
# ------------------------------------------------------------------------------
class AtmosphereProfile:
	var rayleigh_coeff: Vector3 = Vector3(0.018, 0.042, 0.10)
	var mie_coeff: float = 0.012
	var mie_g: float = 0.76
	var scale_height_frac: float = 0.25
	var sky_color_day: Color = Color(0.40, 0.62, 1.00, 1.0)
	var sky_color_sunset: Color = Color(1.00, 0.45, 0.20, 1.0)
	var sky_color_night: Color = Color(0.02, 0.03, 0.08, 1.0)
	var archetype_tint: Color = Color(1.0, 1.0, 1.0, 1.0)
	var intensity: float = 1.6
	var has_clouds: bool = true
	var cloud_color: Color = Color(1.0, 1.0, 1.0, 1.0)
	var cloud_shadow_color: Color = Color(0.18, 0.20, 0.26, 1.0)
	var cloud_density: float = 1.0
	var cloud_scale: float = 4.0
	var coverage_threshold: float = 0.55
	var wind_speed: float = 0.6
	var wind_direction: Vector2 = Vector2(1.0, 0.0)
	var band_intensity: float = 0.0
	var sun_color: Color = Color(1.0, 0.95, 0.82, 1.0)

# ------------------------------------------------------------------------------
# Godot Lifecycle
# ------------------------------------------------------------------------------
func _ready() -> void:
	_build_atmosphere_shell()
	_build_cloud_layer()
	_apply_archetype_profile(_archetype)
	set_active(false)
	visuals_ready.emit()


func _process(delta: float) -> void:
	_elapsed_time += delta
	if not _active:
		return
	_update_camera_reference()
	_update_camera_position()
	_update_lod(delta)
	_push_atmosphere_uniforms()
	_push_cloud_uniforms()
	_lod_counter += 1
	if _lod_counter >= 15:
		_lod_counter = 0
		_update_shader_lod()

# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------
## Configure the system for a given planet archetype, radius and atmosphere
## height. Rebuilds mesh scales and reapplies the archetype profile.
func configure(archetype: int, planet_radius: float, atmosphere_height: float) -> void:
	_archetype = clampi(archetype, 0, 7)
	_planet_radius = maxf(planet_radius, 1.0)
	_atmosphere_height = maxf(atmosphere_height, 1.0)
	_apply_archetype_profile(_archetype)
	_rebuild_mesh_scales(_current_lod_mult)


## Set the sun direction (normalized) in world space.
func set_sun_direction(dir: Vector3) -> void:
	var n: Vector3 = dir
	if is_equal_approx(n.length_squared(), 0.0):
		n = Vector3(0.0, 1.0, 0.0)
	else:
		n = n.normalized()
	_sun_direction = n


## Set the camera/ship position used for view-ray scattering.
func set_camera_position(pos: Vector3) -> void:
	_camera_position = pos


## Set the time of day as a normalized value [0.0, 1.0]. 0.25 = sunrise,
## 0.5 = noon, 0.75 = sunset, 0.0/1.0 = midnight. Drives the sun direction
## around the planet when no explicit sun direction is being set externally.
func set_time_of_day(time_normalized: float) -> void:
	_time_of_day = clampf(time_normalized, 0.0, 1.0)
	# Derive a sun direction from the time of day: sun travels in the XZ plane
	# with elevation peaking at noon (0.5) and dipping below at midnight (0.0).
	var angle: float = _time_of_day * TAU - PI * 0.5
	var elev: float = sin(angle)  # -1 (midnight) .. +1 (noon)
	var azim: float = cos(angle)
	_sun_direction = Vector3(azim, elev, 0.35).normalized()


## Activate or deactivate the atmosphere + cloud visuals.
func set_active(active: bool) -> void:
	_active = active
	_set_atmosphere_visible(active)
	_set_clouds_visible(active and _has_clouds)

# ------------------------------------------------------------------------------
# Construction
# ------------------------------------------------------------------------------
func _build_atmosphere_shell() -> void:
	_atmosphere_mesh = MeshInstance3D.new()
	_atmosphere_mesh.name = "AtmosphereShell"
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = _planet_radius + _atmosphere_height
	sphere.height = (_planet_radius + _atmosphere_height) * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	sphere.material = _create_atmosphere_material()
	_atmosphere_mesh.mesh = sphere
	_atmosphere_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_atmosphere_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_atmosphere_mesh)
	_atmosphere_material = _atmosphere_mesh.get_active_material(0) as ShaderMaterial


func _create_atmosphere_material() -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = load(ATMOSPHERE_SHADER_PATH)
	if shader != null:
		mat.shader = shader
	return mat


func _build_cloud_layer() -> void:
	_cloud_mesh = MeshInstance3D.new()
	_cloud_mesh.name = "CloudLayer"
	var sphere: SphereMesh = SphereMesh.new()
	var cloud_r: float = _planet_radius + _atmosphere_height * 0.6
	sphere.radius = cloud_r
	sphere.height = cloud_r * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	sphere.material = _create_cloud_material()
	_cloud_mesh.mesh = sphere
	_cloud_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cloud_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_cloud_mesh)
	_cloud_material = _cloud_mesh.get_active_material(0) as ShaderMaterial


func _create_cloud_material() -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	var shader: Shader = load(CLOUD_SHADER_PATH)
	if shader != null:
		mat.shader = shader
	return mat

# ------------------------------------------------------------------------------
# Archetype Profiles
# ------------------------------------------------------------------------------
func _apply_archetype_profile(archetype: int) -> void:
	var profile: AtmosphereProfile = _get_archetype_profile(archetype)
	_has_clouds = profile.has_clouds

	if _atmosphere_material != null:
		_atmosphere_material.set_shader_parameter("rayleigh_coeff", profile.rayleigh_coeff)
		_atmosphere_material.set_shader_parameter("mie_coeff", profile.mie_coeff)
		_atmosphere_material.set_shader_parameter("mie_g", profile.mie_g)
		_atmosphere_material.set_shader_parameter("scale_height_frac", profile.scale_height_frac)
		_atmosphere_material.set_shader_parameter("sky_color_day", profile.sky_color_day)
		_atmosphere_material.set_shader_parameter("sky_color_sunset", profile.sky_color_sunset)
		_atmosphere_material.set_shader_parameter("sky_color_night", profile.sky_color_night)
		_atmosphere_material.set_shader_parameter("archetype_tint", profile.archetype_tint)
		_atmosphere_material.set_shader_parameter("intensity", profile.intensity)
		_atmosphere_material.set_shader_parameter("planet_radius", _planet_radius)
		_atmosphere_material.set_shader_parameter("atmosphere_height", _atmosphere_height)

	if _cloud_material != null:
		_cloud_material.set_shader_parameter("cloud_color", profile.cloud_color)
		_cloud_material.set_shader_parameter("cloud_shadow_color", profile.cloud_shadow_color)
		_cloud_material.set_shader_parameter("cloud_density", profile.cloud_density)
		_cloud_material.set_shader_parameter("cloud_scale", profile.cloud_scale)
		_cloud_material.set_shader_parameter("coverage_threshold", profile.coverage_threshold)
		_cloud_material.set_shader_parameter("wind_speed", profile.wind_speed)
		_cloud_material.set_shader_parameter("wind_direction", profile.wind_direction)
		_cloud_material.set_shader_parameter("band_intensity", profile.band_intensity)
		_cloud_material.set_shader_parameter("sun_color", profile.sun_color)
		_cloud_material.set_shader_parameter("archetype_id", archetype)


func _get_archetype_profile(archetype: int) -> AtmosphereProfile:
	var p: AtmosphereProfile = AtmosphereProfile.new()
	match archetype:
		PlanetArchetype.MOLTEN:
			p.rayleigh_coeff = Vector3(0.05, 0.025, 0.008)
			p.mie_coeff = 0.05
			p.mie_g = 0.82
			p.scale_height_frac = 0.35
			p.sky_color_day = Color(0.85, 0.35, 0.12, 1.0)
			p.sky_color_sunset = Color(1.0, 0.25, 0.05, 1.0)
			p.sky_color_night = Color(0.10, 0.02, 0.0, 1.0)
			p.archetype_tint = Color(1.3, 0.6, 0.3, 1.0)
			p.intensity = 2.4
			p.has_clouds = true
			p.cloud_color = Color(0.35, 0.18, 0.10, 1.0)
			p.cloud_shadow_color = Color(0.10, 0.03, 0.0, 1.0)
			p.cloud_density = 1.3
			p.cloud_scale = 5.0
			p.coverage_threshold = 0.48
			p.wind_speed = 1.2
			p.wind_direction = Vector2(0.7, 0.7)
			p.sun_color = Color(1.0, 0.6, 0.3, 1.0)
		PlanetArchetype.METALLIC_BARREN:
			p.rayleigh_coeff = Vector3(0.002, 0.003, 0.005)
			p.mie_coeff = 0.002
			p.mie_g = 0.6
			p.scale_height_frac = 0.12
			p.sky_color_day = Color(0.25, 0.28, 0.32, 1.0)
			p.sky_color_sunset = Color(0.45, 0.35, 0.30, 1.0)
			p.sky_color_night = Color(0.01, 0.01, 0.02, 1.0)
			p.archetype_tint = Color(0.8, 0.8, 0.85, 1.0)
			p.intensity = 0.5
			p.has_clouds = false
		PlanetArchetype.DESERT_ARID:
			p.rayleigh_coeff = Vector3(0.025, 0.030, 0.020)
			p.mie_coeff = 0.03
			p.mie_g = 0.7
			p.scale_height_frac = 0.2
			p.sky_color_day = Color(0.78, 0.62, 0.42, 1.0)
			p.sky_color_sunset = Color(1.0, 0.40, 0.15, 1.0)
			p.sky_color_night = Color(0.05, 0.04, 0.06, 1.0)
			p.archetype_tint = Color(1.15, 0.95, 0.7, 1.0)
			p.intensity = 1.4
			p.has_clouds = true
			p.cloud_color = Color(0.78, 0.62, 0.42, 1.0)
			p.cloud_shadow_color = Color(0.25, 0.18, 0.12, 1.0)
			p.cloud_density = 1.1
			p.cloud_scale = 6.0
			p.coverage_threshold = 0.50
			p.wind_speed = 1.8
			p.wind_direction = Vector2(1.0, 0.3)
			p.sun_color = Color(1.0, 0.85, 0.6, 1.0)
		PlanetArchetype.TERRAN_OCEANIC:
			# Defaults are Earth-like.
			p.has_clouds = true
			p.cloud_color = Color(1.0, 1.0, 1.0, 1.0)
			p.cloud_shadow_color = Color(0.20, 0.22, 0.30, 1.0)
			p.cloud_density = 1.0
			p.cloud_scale = 4.0
			p.coverage_threshold = 0.55
			p.wind_speed = 0.6
			p.wind_direction = Vector2(1.0, 0.0)
			p.sun_color = Color(1.0, 0.95, 0.82, 1.0)
		PlanetArchetype.ICE_WORLD:
			p.rayleigh_coeff = Vector3(0.020, 0.045, 0.085)
			p.mie_coeff = 0.008
			p.mie_g = 0.65
			p.scale_height_frac = 0.18
			p.sky_color_day = Color(0.55, 0.72, 0.92, 1.0)
			p.sky_color_sunset = Color(0.95, 0.55, 0.45, 1.0)
			p.sky_color_night = Color(0.03, 0.05, 0.12, 1.0)
			p.archetype_tint = Color(0.85, 0.95, 1.05, 1.0)
			p.intensity = 1.2
			p.has_clouds = true
			p.cloud_color = Color(0.92, 0.96, 1.0, 1.0)
			p.cloud_shadow_color = Color(0.25, 0.32, 0.42, 1.0)
			p.cloud_density = 0.8
			p.cloud_scale = 5.0
			p.coverage_threshold = 0.58
			p.wind_speed = 0.4
			p.wind_direction = Vector2(0.5, 0.85)
			p.sun_color = Color(0.95, 0.97, 1.0, 1.0)
		PlanetArchetype.GAS_GIANT_JOVIAN:
			p.rayleigh_coeff = Vector3(0.012, 0.030, 0.060)
			p.mie_coeff = 0.06
			p.mie_g = 0.85
			p.scale_height_frac = 0.4
			p.sky_color_day = Color(0.70, 0.55, 0.38, 1.0)
			p.sky_color_sunset = Color(0.85, 0.40, 0.20, 1.0)
			p.sky_color_night = Color(0.08, 0.05, 0.03, 1.0)
			p.archetype_tint = Color(1.1, 0.85, 0.55, 1.0)
			p.intensity = 2.8
			p.has_clouds = true
			p.cloud_color = Color(0.82, 0.66, 0.45, 1.0)
			p.cloud_shadow_color = Color(0.20, 0.14, 0.08, 1.0)
			p.cloud_density = 1.6
			p.cloud_scale = 8.0
			p.coverage_threshold = 0.40
			p.wind_speed = 2.5
			p.wind_direction = Vector2(1.0, 0.0)
			p.band_intensity = 1.8
			p.sun_color = Color(1.0, 0.9, 0.7, 1.0)
		PlanetArchetype.GAS_GIANT_ICE:
			p.rayleigh_coeff = Vector3(0.010, 0.040, 0.055)
			p.mie_coeff = 0.045
			p.mie_g = 0.8
			p.scale_height_frac = 0.38
			p.sky_color_day = Color(0.30, 0.62, 0.60, 1.0)
			p.sky_color_sunset = Color(0.55, 0.85, 0.80, 1.0)
			p.sky_color_night = Color(0.02, 0.08, 0.10, 1.0)
			p.archetype_tint = Color(0.7, 1.05, 1.0, 1.0)
			p.intensity = 2.2
			p.has_clouds = true
			p.cloud_color = Color(0.45, 0.85, 0.82, 1.0)
			p.cloud_shadow_color = Color(0.05, 0.18, 0.20, 1.0)
			p.cloud_density = 1.4
			p.cloud_scale = 7.0
			p.coverage_threshold = 0.44
			p.wind_speed = 2.0
			p.wind_direction = Vector2(0.8, 0.6)
			p.band_intensity = 1.2
			p.sun_color = Color(0.95, 1.0, 0.98, 1.0)
		PlanetArchetype.RADIOTROPHIC_BIO:
			p.rayleigh_coeff = Vector3(0.030, 0.045, 0.020)
			p.mie_coeff = 0.018
			p.mie_g = 0.7
			p.scale_height_frac = 0.28
			p.sky_color_day = Color(0.40, 0.62, 0.45, 1.0)
			p.sky_color_sunset = Color(0.85, 0.55, 0.30, 1.0)
			p.sky_color_night = Color(0.03, 0.06, 0.04, 1.0)
			p.archetype_tint = Color(0.7, 1.15, 0.8, 1.0)
			p.intensity = 1.8
			p.has_clouds = true
			p.cloud_color = Color(0.55, 0.95, 0.60, 1.0)
			p.cloud_shadow_color = Color(0.05, 0.12, 0.08, 1.0)
			p.cloud_density = 1.0
			p.cloud_scale = 4.5
			p.coverage_threshold = 0.52
			p.wind_speed = 0.5
			p.wind_direction = Vector2(0.3, 0.95)
			p.sun_color = Color(0.9, 1.0, 0.85, 1.0)
	return p

# ------------------------------------------------------------------------------
# Per-Frame Updates
# ------------------------------------------------------------------------------
func _update_camera_reference() -> void:
	if _camera != null and is_instance_valid(_camera):
		return
	_camera = get_viewport().get_camera_3d()


func _update_camera_position() -> void:
	if _camera != null and is_instance_valid(_camera):
		_camera_position = _camera.global_position


func _update_lod(delta: float) -> void:
	# Altitude of the camera above the planet surface, in atmosphere heights.
	var cam_dist: float = _camera_position.length()
	var altitude: float = cam_dist - _planet_radius
	var lod_t: float = clampf(altitude / maxf(_atmosphere_height * lod_blend_atmospheres, 1.0), 0.0, 1.0)
	var target_mult: float = lerpf(lod_surface_thickness_mult, lod_orbit_thickness_mult, lod_t)
	var rate: float = 1.0 - exp(-lod_lerp_rate * delta)
	_current_lod_mult = lerpf(_current_lod_mult, target_mult, rate)
	_rebuild_mesh_scales(_current_lod_mult)


func _rebuild_mesh_scales(lod_mult: float) -> void:
	var effective_h: float = _atmosphere_height * lod_mult
	if _atmosphere_mesh != null and is_instance_valid(_atmosphere_mesh):
		var atmo_sphere: SphereMesh = _atmosphere_mesh.mesh as SphereMesh
		if atmo_sphere != null:
			var r: float = _planet_radius + effective_h
			atmo_sphere.radius = r
			atmo_sphere.height = r * 2.0
		if _atmosphere_material != null:
			_atmosphere_material.set_shader_parameter("atmosphere_height", effective_h)
			_atmosphere_material.set_shader_parameter("planet_radius", _planet_radius)
	if _cloud_mesh != null and is_instance_valid(_cloud_mesh):
		var cloud_sphere: SphereMesh = _cloud_mesh.mesh as SphereMesh
		if cloud_sphere != null:
			var cr: float = _planet_radius + effective_h * 0.6
			cloud_sphere.radius = cr
			cloud_sphere.height = cr * 2.0


func _push_atmosphere_uniforms() -> void:
	if _atmosphere_material == null:
		return
	_atmosphere_material.set_shader_parameter("sun_direction", _sun_direction)
	_atmosphere_material.set_shader_parameter("camera_position", _camera_position)
	_atmosphere_material.set_shader_parameter("time", _elapsed_time)


func _push_cloud_uniforms() -> void:
	if _cloud_material == null:
		return
	_cloud_material.set_shader_parameter("time", _elapsed_time)
	_cloud_material.set_shader_parameter("sun_direction", _sun_direction)
	_cloud_material.set_shader_parameter("camera_position", _camera_position)
	# Night factor derived from sun elevation for cloud dimming.
	var night: float = clampf(-_sun_direction.y * 1.5 + 0.5, 0.0, 1.0)
	_cloud_material.set_shader_parameter("night_factor", night)

# ------------------------------------------------------------------------------
# Shader LOD
# ------------------------------------------------------------------------------
## Adjusts the atmosphere shader's quality_scale uniform based on camera
## distance so distant/orbital views use fewer ray-march samples, reducing GPU
## cost. Called every 15 frames from _process() to save CPU.
func _update_shader_lod() -> void:
	if _atmosphere_material == null:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var dist: float = global_position.distance_to(cam.global_position)
	var alt: float = dist - _planet_radius
	# Quality: 1.0 at surface, 0.5 at mid-atmosphere, 0.25 at orbit.
	var quality: float = clampf(1.0 - alt / (_atmosphere_height * 5.0), 0.25, 1.0)
	_atmosphere_material.set_shader_parameter("quality_scale", quality)

# ------------------------------------------------------------------------------
# Visibility Helpers
# ------------------------------------------------------------------------------
func _set_atmosphere_visible(p_visible: bool) -> void:
	if _atmosphere_mesh != null and is_instance_valid(_atmosphere_mesh):
		_atmosphere_mesh.visible = p_visible


func _set_clouds_visible(p_visible: bool) -> void:
	if _cloud_mesh != null and is_instance_valid(_cloud_mesh):
		_cloud_mesh.visible = p_visible

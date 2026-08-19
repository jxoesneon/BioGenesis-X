# ==============================================================================
# OceanSurfaceManager.gd
# BioGenesis-X: Boujie Water Shader Ocean Surface Director
# ==============================================================================
# Manages a large follow-plane ocean surface rendered with the Boujie Water
# Shader addon (res://addons/boujie_water_shader/shader/water.gdshader).
# Only activates on ocean-bearing planet archetypes:
#   - Archetype 3 (Terran Oceanic): full Earth-like blue ocean
#   - Archetype 4 (Ice World): cold dark ocean when liquid water is present
#
# The manager places a tangent water plane at sea level above the terrain
# sphere, oriented so its +Y axis points away from the planet center (local
# "up" at the player's location). It follows the player horizontally so the
# plane stays centered under the camera, hiding the horizon edge.
#
# Wave height, direction, speed and water color are derived from the planet's
# procedural properties (wind, gravity, temperature, archetype). The surface
# fades in smoothly as the player descends through the atmosphere toward the
# ocean, and disables cleanly when the player leaves the planet.
#
# Per the Council verdict, only the core water shader + Gerstner wave system
# are used. The CameraFollower3D and WaterMaterialDesigner addon features are
# NOT used — this manager drives the shader uniforms directly.
# ==============================================================================
class_name OceanSurfaceManager
extends Node3D

# ------------------------------------------------------------------------------
# Boujie Water Shader resources
# ------------------------------------------------------------------------------
const WaterShader: Shader = preload("res://addons/boujie_water_shader/shader/water.gdshader")
const GerstnerWaveScript: GDScript = preload("res://addons/boujie_water_shader/types/gerstner_wave.gd")

# ------------------------------------------------------------------------------
# Ocean-bearing archetypes (mirrors PlanetSurfaceManager.Archetype)
# ------------------------------------------------------------------------------
const ARCHETYPE_TERRAN_OCEANIC: int = 3
const ARCHETYPE_ICE_WORLD: int = 4

# ------------------------------------------------------------------------------
# Exports
# ------------------------------------------------------------------------------
@export_group("Sea Level")
## Sea level as a fraction of the planet radius above the terrain surface.
## 0.0 places the water exactly at the terrain sphere surface; positive values
## raise it (flood low-lying terrain), negative values lower it.
@export var sea_level_ratio: float = 0.0
## Absolute sea-level offset in metres above the terrain sphere surface.
## Computed from sea_level_ratio * planet_radius_m if not set explicitly.
@export var sea_level_offset_m: float = 0.0

@export_group("Ocean Geometry")
## Side length of the square ocean follow-plane (metres).
@export var ocean_plane_size: float = 4000.0
## Subdivision of the follow-plane mesh (higher = smoother Gerstner displacement).
@export_range(4, 256) var ocean_plane_subdiv: int = 96
## Horizontal follow smoothing rate (1.0 = instant, lower = smoother).
@export var follow_lerp_rate: float = 6.0

@export_group("Waves")
## Base Gerstner wave height (metres). Scaled by wind strength.
@export var wave_height: float = 1.0
## Primary wave direction in degrees (0 = +X, 90 = +Z in ocean-local frame).
@export var wave_direction_deg: float = 45.0
## Base wave propagation speed.
@export var wave_speed: float = 1.0
## Number of Gerstner wave components (1..8).
@export_range(1, 8) var wave_count: int = 4

@export_group("Water Color")
## Surface albedo color (alpha controls base opacity; fresnel mixes albedo_fresnel).
@export var water_color: Color = Color(0.12, 0.45, 0.75, 0.0)
## Fresnel-edge color (seen at grazing angles).
@export var water_color_fresnel: Color = Color(0.3, 0.6, 0.9, 1.0)
## Deep-water fog color (depth fog blend).
@export var water_color_deep: Color = Color(0.04, 0.15, 0.35, 1.0)
## Shallow-water color (depth fog blend).
@export var water_color_shallow: Color = Color(0.1, 0.4, 0.6, 0.0)

@export_group("Atmospheric Fade")
## Camera altitude (above sea level) at which the ocean is fully visible.
@export var fade_in_altitude_m: float = 300.0
## Camera altitude (above sea level) at which the ocean is fully invisible.
@export var fade_out_altitude_m: float = 1200.0

# ------------------------------------------------------------------------------
# Internal State
# ------------------------------------------------------------------------------
var _archetype: int = ARCHETYPE_TERRAN_OCEANIC
var _planet_radius_m: float = 100.0
var _sea_level_m: float = 0.0
var _seed: int = 0
var _gravity: float = 9.81
var _wind_speed: float = 5.0
var _temperature_k: float = 288.0
var _active: bool = false
var _has_ocean: bool = true
var _current_visibility: float = 0.0
var _target_visibility: float = 0.0

var _water_mesh: MeshInstance3D = null
var _water_material: ShaderMaterial = null
var _waves: Array = [] # Array of GerstnerWave resources

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------
func _ready() -> void:
	_build_ocean_surface()
	_build_gerstner_waves()
	_apply_shader_uniforms()
	# Start invisible; the fade-in is driven by _process once active.
	_set_ocean_visible(false)

func _process(delta: float) -> void:
	if not _active or not _has_ocean:
		return
	_follow_player_horizontal(delta)
	_update_atmospheric_fade(delta)

# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------
## Returns true if the given archetype can host a Boujie water ocean.
static func archetype_has_ocean(archetype: int) -> bool:
	return archetype == ARCHETYPE_TERRAN_OCEANIC or archetype == ARCHETYPE_ICE_WORLD

## Configures the ocean for a planet. Only activates for ocean-bearing
## archetypes; for others it becomes a graceful no-op (no mesh shown).
## archetype: PlanetSurfaceManager.Archetype value.
## p_seed: deterministic seed for procedural wave/color variation.
## radius_m: planet radius in metres (terrain sphere radius).
## gravity: surface gravity in m/s^2 (affects wave propagation speed).
## wind_speed: wind strength in m/s (affects wave amplitude).
## temperature_k: surface temperature in Kelvin (affects color/ice).
func configure(archetype: int, p_seed: int, radius_m: float,
		gravity: float = 9.81, wind_speed: float = 5.0,
		temperature_k: float = 288.0) -> void:
	_archetype = archetype
	_seed = p_seed
	_planet_radius_m = maxf(1.0, radius_m)
	_gravity = maxf(0.1, gravity)
	_wind_speed = clampf(wind_speed, 0.0, 30.0)
	_temperature_k = clampf(temperature_k, 0.0, 2000.0)
	_has_ocean = archetype_has_ocean(archetype)
	# Sea level: ratio * radius + explicit offset. Default 0 (at terrain surface).
	_sea_level_m = sea_level_ratio * _planet_radius_m + sea_level_offset_m
	# Derive wave/color parameters from planet properties.
	_derive_ocean_parameters()
	if is_inside_tree():
		_build_gerstner_waves()
		_apply_shader_uniforms()

## Activates the ocean surface (begins fade-in as the player descends).
func activate() -> void:
	_active = true
	set_process(true)
	if _has_ocean and _water_mesh != null:
		_water_mesh.visible = true

## Deactivates the ocean surface (immediate hide, used on surface exit).
func deactivate() -> void:
	_active = false
	set_process(false)
	_set_ocean_visible(false)

## Returns true when the ocean is active and the archetype supports water.
func is_ocean_active() -> bool:
	return _active and _has_ocean

## Returns the configured sea-level altitude in metres above the terrain sphere.
func get_sea_level_m() -> float:
	return _sea_level_m

## Returns true if this archetype hosts an ocean.
func has_ocean() -> bool:
	return _has_ocean

## Rebases the ocean by a world-space offset (floating-origin shift).
func apply_floating_origin(offset: Vector3) -> void:
	if _water_mesh != null and is_instance_valid(_water_mesh):
		_water_mesh.global_position += offset

# ------------------------------------------------------------------------------
# Construction
# ------------------------------------------------------------------------------
## Builds the water mesh plane and ShaderMaterial from the Boujie water shader.
func _build_ocean_surface() -> void:
	_water_mesh = MeshInstance3D.new()
	_water_mesh.name = "BoujieOceanPlane"
	var plane := PlaneMesh.new()
	plane.size = Vector2(ocean_plane_size, ocean_plane_size)
	plane.subdivide_width = ocean_plane_subdiv
	plane.subdivide_depth = ocean_plane_subdiv
	_water_mesh.mesh = plane
	# The plane renders double-sided (cull_disabled in shader) so it is visible
	# from above and below (underwater looking up at the surface).
	_water_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water_mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

	_water_material = ShaderMaterial.new()
	_water_material.shader = WaterShader
	_water_material.render_priority = 0
	_water_mesh.material_override = _water_material
	add_child(_water_mesh)

## Generates the Gerstner wave component resources from the planet properties.
## Waves are deterministic from the seed so the same planet always looks the same.
func _build_gerstner_waves() -> void:
	_waves.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var count: int = clampi(wave_count, 1, 8)
	for i in range(count):
		var wave: Resource = GerstnerWaveScript.new()
		# Direction: spread around the primary wind direction with seed jitter.
		var dir_jitter: float = rng.randf_range(-35.0, 35.0)
		wave.direction_degrees = fmod(wave_direction_deg + dir_jitter + float(i) * 47.0, 360.0)
		# Steepness decreases for higher-frequency components (swell -> chop).
		wave.steepness = wave_height * (1.0 / float(i + 1)) * 0.6
		# Amplitude scales with wind speed; attenuate for ice worlds (calmer seas).
		var wind_factor: float = clampf(_wind_speed / 10.0, 0.2, 2.0)
		var ice_factor: float = 0.5 if _archetype == ARCHETYPE_ICE_WORLD else 1.0
		wave.amplitude = wave_height * wind_factor * ice_factor * (1.0 / float(i + 1))
		# Frequency: longer wavelength (lower freq) for primary swell.
		wave.frequency = 0.02 + float(i) * 0.015
		# Speed scales with sqrt(gravity * wavelength) — Gerstner deep-water dispersion.
		wave.speed = wave_speed * sqrt(_gravity / 9.81) * (1.0 + float(i) * 0.2)
		wave.phase_degrees = rng.randf_range(0.0, 360.0)
		_waves.append(wave)

## Derives wave height, direction, speed and water color from the planet's
## procedural properties (archetype, wind, gravity, temperature, seed).
func _derive_ocean_parameters() -> void:
	# Wind-driven wave height: Beaufort-style scaling.
	var wind_factor: float = clampf(_wind_speed / 10.0, 0.2, 2.5)
	wave_height = clampf(0.4 + wind_factor * 0.8, 0.1, 4.0)
	# Wave speed scales with gravity (lower gravity = slower, languid waves).
	wave_speed = clampf(sqrt(_gravity / 9.81), 0.3, 2.0)
	# Per-archetype water color palette.
	match _archetype:
		ARCHETYPE_TERRAN_OCEANIC:
			water_color = Color(0.12, 0.45, 0.75, 0.0)
			water_color_fresnel = Color(0.3, 0.6, 0.95, 1.0)
			water_color_deep = Color(0.04, 0.15, 0.35, 1.0)
			water_color_shallow = Color(0.1, 0.45, 0.6, 0.0)
		ARCHETYPE_ICE_WORLD:
			# Cold, dark, high-clarity polar ocean.
			water_color = Color(0.08, 0.22, 0.35, 0.0)
			water_color_fresnel = Color(0.4, 0.6, 0.8, 1.0)
			water_color_deep = Color(0.02, 0.08, 0.18, 1.0)
			water_color_shallow = Color(0.15, 0.35, 0.45, 0.0)
		_:
			water_color = Color(0.12, 0.45, 0.75, 0.0)
			water_color_fresnel = Color(0.3, 0.6, 0.9, 1.0)
			water_color_deep = Color(0.04, 0.15, 0.35, 1.0)
			water_color_shallow = Color(0.1, 0.4, 0.6, 0.0)
	# Seed-deterministic wave direction.
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	wave_direction_deg = fmod(rng.randf_range(0.0, 360.0), 360.0)

# ------------------------------------------------------------------------------
# Shader Uniform Application
# ------------------------------------------------------------------------------
## Pushes all Boujie water shader uniforms from the manager state.
func _apply_shader_uniforms() -> void:
	if _water_material == null:
		return
	# Core surface properties.
	_water_material.set_shader_parameter("albedo", water_color)
	_water_material.set_shader_parameter("albedo_fresnel", water_color_fresnel)
	_water_material.set_shader_parameter("specular", 0.5)
	_water_material.set_shader_parameter("roughness", 0.12)
	_water_material.set_shader_parameter("metallic", 0.0)
	_water_material.set_shader_parameter("freeze_time", false)
	# Vertex displacement along the mesh normal (plane normal = +Y = up).
	_water_material.set_shader_parameter("vertex_displace_from_mesh_normal", true)
	_water_material.set_shader_parameter("normal_wave_from_mesh_normal", true)
	# Depth fog colors.
	_water_material.set_shader_parameter("color_deep", water_color_deep)
	_water_material.set_shader_parameter("color_shallow", water_color_shallow)
	_water_material.set_shader_parameter("beers_law", 2.0)
	_water_material.set_shader_parameter("depth_offset", -0.75)
	# Distance fade — large so the ocean stays visible across the follow-plane.
	var fade_max: float = ocean_plane_size * 0.6
	_water_material.set_shader_parameter("distance_fade_min", fade_max * 0.85)
	_water_material.set_shader_parameter("distance_fade_max", fade_max)
	_water_material.set_shader_parameter("near_fade_min", 1.0)
	_water_material.set_shader_parameter("near_fade_max", 2.0)
	# Feature fades (waves/foam/depth fog fade out at distance).
	var wave_fade: float = ocean_plane_size * 0.4
	_water_material.set_shader_parameter("foam_fade_min", wave_fade * 0.8)
	_water_material.set_shader_parameter("foam_fade_max", wave_fade)
	_water_material.set_shader_parameter("shore_fade_min", wave_fade * 0.8)
	_water_material.set_shader_parameter("shore_fade_max", wave_fade)
	_water_material.set_shader_parameter("vertex_wave_fade_min", wave_fade * 0.8)
	_water_material.set_shader_parameter("vertex_wave_fade_max", wave_fade)
	_water_material.set_shader_parameter("depth_fog_fade_min", wave_fade * 0.8)
	_water_material.set_shader_parameter("depth_fog_fade_max", wave_fade)
	_water_material.set_shader_parameter("refraction_scaling_distance_min", 50.0)
	# Triplanar UV scale (world-space texture repetition).
	_water_material.set_shader_parameter("uv_blend_sharpness", 2.0)
	_water_material.set_shader_parameter("uv_tri_scale", Vector3(36.0, 36.0, 36.0))
	_water_material.set_shader_parameter("uv_tri_offset", Vector3.ZERO)
	# Snell's window (underwater looking up).
	_water_material.set_shader_parameter("albedo_snell", Color(0.0, 0.1, 0.24, 1.0))
	_water_material.set_shader_parameter("snell_direction", Vector3(0.0, 1.0, 0.0))
	_water_material.set_shader_parameter("snell_tightness", 0.6)
	# Refraction defaults (subtle).
	_water_material.set_shader_parameter("refraction", 0.05)
	_water_material.set_shader_parameter("refraction_texture_channel", Vector4(1.0, 0.0, 0.0, 0.0))
	_water_material.set_shader_parameter("refraction_opacity", 1.0)
	# Shore foam blend thresholds.
	_water_material.set_shader_parameter("shore_start_blend", 2.0)
	_water_material.set_shader_parameter("shore_end_blend", 6.0)
	# Push Gerstner wave arrays.
	_push_wave_arrays()

## Converts the GerstnerWave resource array into the shader's packed float arrays.
func _push_wave_arrays() -> void:
	if _water_material == null or _waves.is_empty():
		return
	_push_wave_group("Wave", _waves)
	# Foam waves: reuse the same waves with a smaller amplitude subset for foam.
	var foam_waves: Array = _waves.slice(0, mini(_waves.size(), 6))
	_push_wave_group("FoamWave", foam_waves)
	# UV waves: a couple of low-amplitude waves for texture waviness.
	var uv_waves: Array = _waves.slice(0, mini(_waves.size(), 2))
	_push_wave_group("UVWave", uv_waves)

## Pushes a single wave group (prefix = "Wave", "FoamWave", or "UVWave").
func _push_wave_group(prefix: String, waves: Array) -> void:
	var num: int = mini(waves.size(), 8)
	_water_material.set_shader_parameter(prefix + "Count", num)
	var steepnesses := PackedFloat32Array()
	var amplitudes := PackedFloat32Array()
	var directions := PackedFloat32Array()
	var frequencies := PackedFloat32Array()
	var speeds := PackedFloat32Array()
	var phases := PackedFloat32Array()
	for i in range(num):
		var w = waves[i]
		steepnesses.append(float(w.steepness))
		amplitudes.append(float(w.amplitude))
		directions.append(float(w.direction_degrees))
		frequencies.append(float(w.frequency))
		speeds.append(float(w.speed))
		phases.append(float(w.phase_degrees))
	_water_material.set_shader_parameter(prefix + "Steepnesses", steepnesses)
	_water_material.set_shader_parameter(prefix + "Amplitudes", amplitudes)
	_water_material.set_shader_parameter(prefix + "DirectionsDegrees", directions)
	_water_material.set_shader_parameter(prefix + "Frequencies", frequencies)
	_water_material.set_shader_parameter(prefix + "Speeds", speeds)
	_water_material.set_shader_parameter(prefix + "Phases", phases)

# ------------------------------------------------------------------------------
# Player Follow & Atmospheric Fade
# ------------------------------------------------------------------------------
## Orients and positions the water plane at sea level, tangent to the planet
## sphere at the player's location, following the camera horizontally.
func _follow_player_horizontal(delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or _water_mesh == null or not is_instance_valid(_water_mesh):
		return
	# Planet center is this manager's parent origin (PlanetSurfaceManager sits
	# at the planet center). Local up = direction from center to camera.
	var cam_world: Vector3 = cam.global_position
	var center: Vector3 = global_position
	var to_cam: Vector3 = cam_world - center
	var dist: float = to_cam.length()
	if dist < 0.001:
		return
	var up: Vector3 = to_cam / dist
	# Target position: sea level along the local up direction.
	var target_pos: Vector3 = center + up * (_planet_radius_m + _sea_level_m)
	# Smooth horizontal follow (lerp the plane toward the target).
	var lerp_weight: float = clampf(follow_lerp_rate * delta, 0.0, 1.0)
	_water_mesh.global_position = _water_mesh.global_position.lerp(target_pos, lerp_weight)
	# Orient the plane so its +Y (PlaneMesh normal) points along the local up.
	# Build an orthonormal basis with Y = up and a stable horizontal reference.
	var y_axis: Vector3 = up
	var ref: Vector3 = Vector3.UP if absf(up.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x_axis: Vector3 = ref.cross(y_axis).normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	_water_mesh.global_transform.basis = Basis(x_axis, y_axis, z_axis)

## Fades the ocean in/out based on the camera altitude above sea level.
## As the player descends through the atmosphere, the water appears smoothly.
func _update_atmospheric_fade(delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or _water_mesh == null or not is_instance_valid(_water_mesh):
		return
	var center: Vector3 = global_position
	var cam_dist: float = cam.global_position.distance_to(center)
	var altitude_above_sea: float = cam_dist - (_planet_radius_m + _sea_level_m)
	# Target visibility: 1 below fade_in_altitude, 0 above fade_out_altitude.
	if altitude_above_sea <= fade_in_altitude_m:
		_target_visibility = 1.0
	elif altitude_above_sea >= fade_out_altitude_m:
		_target_visibility = 0.0
	else:
		var t: float = (altitude_above_sea - fade_in_altitude_m) / (fade_out_altitude_m - fade_in_altitude_m)
		_target_visibility = clampf(1.0 - t, 0.0, 1.0)
	# Smooth the visibility transition.
	var lerp_weight: float = clampf(3.0 * delta, 0.0, 1.0)
	_current_visibility = lerpf(_current_visibility, _target_visibility, lerp_weight)
	# Apply via the shader's distance-fade alpha (and mesh visibility).
	if _water_material != null:
		# Modulate the near/distance fade so the whole plane fades together.
		_water_material.set_shader_parameter("near_fade_min", 1.0)
		_water_material.set_shader_parameter("near_fade_max", 2.0)
	_water_mesh.visible = _current_visibility > 0.01
	# Scale opacity through the albedo alpha channel.
	if _water_material != null:
		var base_alpha: float = water_color.a
		var fresnel_alpha: float = water_color_fresnel.a
		_water_material.set_shader_parameter("albedo", Color(water_color.r, water_color.g, water_color.b, base_alpha * _current_visibility))
		_water_material.set_shader_parameter("albedo_fresnel", Color(water_color_fresnel.r, water_color_fresnel.g, water_color_fresnel.b, fresnel_alpha * _current_visibility))

## Shows or hides the ocean mesh immediately.
func _set_ocean_visible(visible_flag: bool) -> void:
	if _water_mesh != null and is_instance_valid(_water_mesh):
		_water_mesh.visible = visible_flag
	_current_visibility = 1.0 if visible_flag else 0.0
	_target_visibility = _current_visibility

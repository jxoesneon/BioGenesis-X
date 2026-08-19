# ==============================================================================
# PlanetSurfaceManager.gd
# BioGenesis-X: Planet Surface Environment & Atmosphere Director
# ==============================================================================
# Root node added to the scene tree when the player is on or near a planet
# surface. Owns the terrain placeholder, procedural sky, atmospheric lighting,
# weather particle systems, and the day/night cycle. Configured per planet
# archetype via configure_for_archetype().
#
# The manager is positioned at the planet CENTER in world space; the terrain
# sphere is a child at the origin with radius = radius_m so the player walks on
# the outer surface. Floating-origin shifts rebase all children by a delta.
# ==============================================================================
class_name PlanetSurfaceManager
extends Node3D

# ------------------------------------------------------------------------------
# Archetype catalog (mirrors PlanetDescentController.PlanetArchetype)
# ------------------------------------------------------------------------------
enum Archetype {
	MOLTEN,           ## 0 - Volcanic hellscape
	METALLIC_BARREN,  ## 1 - Airless rocky
	DESERT_ARID,      ## 2 - Dry dusty
	TERRAN_OCEANIC,   ## 3 - Earth-like
	ICE_WORLD,        ## 4 - Cryogenic
	GAS_GIANT_JOVIAN, ## 5 - No solid surface
	GAS_GIANT_ICE,    ## 6 - Cryogenic gas giant
	RADIOTROPHIC_BIO, ## 7 - Bioluminescent biosphere
}

enum WeatherType {
	NONE,
	RAIN,
	SNOW,
	DUST,
	ASH,
	SPORES,
}

# ------------------------------------------------------------------------------
# Signals
# ------------------------------------------------------------------------------
signal surface_ready()
signal time_of_day_changed(time_normalized: float)
signal weather_changed(type: int, intensity: float)

# ------------------------------------------------------------------------------
# Exports
# ------------------------------------------------------------------------------
@export_group("Day/Night")
@export var day_length_seconds: float = 600.0
@export var sun_base_energy: float = 3.0
@export var moon_base_energy: float = 0.2

@export_group("Weather")
@export var weather_intensity: float = 0.5
@export var weather_particle_count: int = 1200

@export_group("Terrain")
@export var terrain_segments: int = 64

# ------------------------------------------------------------------------------
# Internal State
# ------------------------------------------------------------------------------
var _archetype: int = Archetype.TERRAN_OCEANIC
var _seed: int = 0
var _radius_m: float = 100.0
var _time_of_day: float = 0.3 ## 0..1, 0 = midnight, 0.5 = noon
var _weather_type: int = WeatherType.NONE
var _configured: bool = false

# Child nodes
var _terrain_mesh: MeshInstance3D = null
var _terrain_body: StaticBody3D = null
var _environment_node: WorldEnvironment = null
var _sun_light: DirectionalLight3D = null
var _moon_light: DirectionalLight3D = null
var _weather_particles: GPUParticles3D = null
var _weather_process_mat: ParticleProcessMaterial = null
var _sky_material: ProceduralSkyMaterial = null
var _terrain_material: Material = null
# Boujie Water Shader ocean surface (only spawned for ocean-bearing archetypes).
var _ocean_surface_manager: OceanSurfaceManager = null

# Archetype visual profile.
class ArchetypeProfile:
	var sky_top_color: Color = Color(0.25, 0.55, 1.0)
	var sky_horizon_color: Color = Color(0.6, 0.8, 1.0)
	var sky_bottom_color: Color = Color(0.35, 0.25, 0.2)
	var sun_color: Color = Color(1.0, 0.95, 0.85)
	var sun_energy: float = 3.0
	var ambient_color: Color = Color(0.4, 0.45, 0.55)
	var ambient_energy: float = 0.6
	var terrain_color: Color = Color(0.3, 0.6, 0.25)
	var fog_color: Color = Color(0.6, 0.8, 1.0)
	var fog_density: float = 0.0
	var weather_type: int = WeatherType.NONE
	var has_water: bool = false

	func _init(a: int) -> void:
		_apply(a)

	func _apply(a: int) -> void:
		match a:
			Archetype.MOLTEN:
				sky_top_color = Color(0.1, 0.02, 0.0)
				sky_horizon_color = Color(0.8, 0.2, 0.0)
				sky_bottom_color = Color(0.15, 0.03, 0.0)
				sun_color = Color(1.0, 0.5, 0.2)
				sun_energy = 2.0
				ambient_color = Color(0.5, 0.2, 0.1)
				ambient_energy = 0.8
				terrain_color = Color(0.25, 0.05, 0.02)
				fog_color = Color(0.6, 0.15, 0.05)
				fog_density = 0.08
				weather_type = WeatherType.ASH
			Archetype.METALLIC_BARREN:
				sky_top_color = Color(0.0, 0.0, 0.0)
				sky_horizon_color = Color(0.1, 0.1, 0.12)
				sky_bottom_color = Color(0.0, 0.0, 0.0)
				sun_color = Color(1.0, 1.0, 1.0)
				sun_energy = 4.0
				ambient_color = Color(0.2, 0.2, 0.25)
				ambient_energy = 0.3
				terrain_color = Color(0.35, 0.35, 0.38)
				fog_color = Color(0.0, 0.0, 0.0)
				fog_density = 0.0
				weather_type = WeatherType.NONE
			Archetype.DESERT_ARID:
				sky_top_color = Color(0.3, 0.5, 0.7)
				sky_horizon_color = Color(0.9, 0.7, 0.4)
				sky_bottom_color = Color(0.6, 0.4, 0.2)
				sun_color = Color(1.0, 0.9, 0.7)
				sun_energy = 3.5
				ambient_color = Color(0.5, 0.4, 0.3)
				ambient_energy = 0.7
				terrain_color = Color(0.7, 0.55, 0.3)
				fog_color = Color(0.85, 0.7, 0.45)
				fog_density = 0.02
				weather_type = WeatherType.DUST
			Archetype.TERRAN_OCEANIC:
				sky_top_color = Color(0.25, 0.55, 1.0)
				sky_horizon_color = Color(0.6, 0.8, 1.0)
				sky_bottom_color = Color(0.35, 0.25, 0.2)
				sun_color = Color(1.0, 0.95, 0.85)
				sun_energy = 3.0
				ambient_color = Color(0.4, 0.45, 0.55)
				ambient_energy = 0.6
				terrain_color = Color(0.3, 0.6, 0.25)
				fog_color = Color(0.6, 0.8, 1.0)
				fog_density = 0.01
				weather_type = WeatherType.RAIN
				has_water = true
			Archetype.ICE_WORLD:
				sky_top_color = Color(0.4, 0.6, 0.85)
				sky_horizon_color = Color(0.8, 0.9, 1.0)
				sky_bottom_color = Color(0.5, 0.6, 0.7)
				sun_color = Color(0.9, 0.95, 1.0)
				sun_energy = 2.5
				ambient_color = Color(0.5, 0.55, 0.65)
				ambient_energy = 0.7
				terrain_color = Color(0.85, 0.9, 0.95)
				fog_color = Color(0.8, 0.9, 1.0)
				fog_density = 0.03
				weather_type = WeatherType.SNOW
			Archetype.GAS_GIANT_JOVIAN:
				sky_top_color = Color(0.5, 0.35, 0.2)
				sky_horizon_color = Color(0.8, 0.55, 0.3)
				sky_bottom_color = Color(0.3, 0.15, 0.05)
				sun_color = Color(1.0, 0.85, 0.6)
				sun_energy = 3.0
				ambient_color = Color(0.5, 0.4, 0.3)
				ambient_energy = 0.8
				terrain_color = Color(0.6, 0.45, 0.25)
				fog_color = Color(0.7, 0.5, 0.3)
				fog_density = 0.12
				weather_type = WeatherType.DUST
			Archetype.GAS_GIANT_ICE:
				sky_top_color = Color(0.3, 0.45, 0.6)
				sky_horizon_color = Color(0.55, 0.7, 0.85)
				sky_bottom_color = Color(0.2, 0.3, 0.45)
				sun_color = Color(0.85, 0.9, 1.0)
				sun_energy = 2.5
				ambient_color = Color(0.4, 0.5, 0.6)
				ambient_energy = 0.7
				terrain_color = Color(0.5, 0.6, 0.7)
				fog_color = Color(0.5, 0.65, 0.8)
				fog_density = 0.1
				weather_type = WeatherType.SNOW
			Archetype.RADIOTROPHIC_BIO:
				sky_top_color = Color(0.05, 0.1, 0.05)
				sky_horizon_color = Color(0.1, 0.3, 0.15)
				sky_bottom_color = Color(0.02, 0.05, 0.02)
				sun_color = Color(0.4, 1.0, 0.6)
				sun_energy = 1.8
				ambient_color = Color(0.1, 0.35, 0.2)
				ambient_energy = 0.9
				terrain_color = Color(0.1, 0.25, 0.12)
				fog_color = Color(0.1, 0.3, 0.15)
				fog_density = 0.06
				weather_type = WeatherType.SPORES
			_:
				# Defaults already set as field initializers.
				pass

var _profile: ArchetypeProfile = null

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------
func _ready() -> void:
	if not _configured:
		configure_for_archetype(Archetype.TERRAN_OCEANIC, 0, 100.0)

func _process(delta: float) -> void:
	if not _configured:
		return
	_advance_day_night(delta)
	# Drive animated terrain shaders (e.g. radiotrophic bio pulsing, lava flow).
	if _terrain_material is ShaderMaterial:
		var sm: ShaderMaterial = _terrain_material as ShaderMaterial
		sm.set_shader_parameter("time", Time.get_ticks_msec() / 1000.0)
		# Update camera_position for view-dependent effects (gas giant limb darkening, fresnel).
		var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam != null:
			sm.set_shader_parameter("camera_position", cam.global_position)

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
## Configures the surface environment for a given planet archetype.
## archetype: an Archetype enum value.
## seed: deterministic seed for procedural variation.
## radius_m: planet radius in meters (terrain sphere radius).
func configure_for_archetype(archetype: int, p_seed: int, radius_m: float) -> void:
	_archetype = archetype
	_seed = p_seed
	_radius_m = maxf(1.0, radius_m)
	_profile = ArchetypeProfile.new(archetype)
	_clear_children()
	_build_terrain()
	_build_sky_and_environment()
	_build_sun_and_moon()
	_build_weather()
	_build_ocean_surface()
	_configured = true
	surface_ready.emit()

func _clear_children() -> void:
	for c: Node in get_children():
		c.queue_free()
	_terrain_mesh = null
	_terrain_body = null
	_environment_node = null
	_sun_light = null
	_moon_light = null
	_weather_particles = null
	_weather_process_mat = null
	_sky_material = null
	_terrain_material = null
	_ocean_surface_manager = null

# ------------------------------------------------------------------------------
# Terrain Surface (archetype shader)
# ------------------------------------------------------------------------------
func _build_terrain() -> void:
	_terrain_mesh = MeshInstance3D.new()
	_terrain_mesh.name = "TerrainSurface"
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = _radius_m
	sphere.height = _radius_m * 2.0
	sphere.radial_segments = terrain_segments
	sphere.rings = terrain_segments

	# Attempt to build an archetype-specific procedural terrain shader material.
	var terrain_mat: ShaderMaterial = TerrainMaterialFactory.create_terrain_material(_archetype)
	if terrain_mat != null:
		TerrainMaterialFactory.configure_terrain_material(terrain_mat, _archetype, _seed)
		# Initial lighting uniforms: sun direction toward the current sun and
		# time at zero so animated shaders start in a known state.
		terrain_mat.set_shader_parameter("sun_direction", _get_sun_direction())
		terrain_mat.set_shader_parameter("sun_color", _profile.sun_color if _profile != null else Color(1.0, 0.95, 0.85))
		terrain_mat.set_shader_parameter("time", 0.0)
		_terrain_material = terrain_mat
	else:
		# Graceful degradation: fall back to a plain lit material if the
		# archetype shader failed to load.
		var fallback: StandardMaterial3D = StandardMaterial3D.new()
		fallback.albedo_color = _profile.terrain_color
		fallback.roughness = 0.95
		fallback.metallic = 0.0
		fallback.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_terrain_material = fallback

	sphere.material = _terrain_material
	_terrain_mesh.mesh = sphere
	add_child(_terrain_mesh)

	# Collision so the character can walk on the outer surface.
	_terrain_body = StaticBody3D.new()
	_terrain_body.name = "TerrainCollision"
	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var sphere_shape: SphereShape3D = SphereShape3D.new()
	sphere_shape.radius = _radius_m
	col_shape.shape = sphere_shape
	_terrain_body.add_child(col_shape)
	add_child(_terrain_body)

## Returns the current world-space sun direction (normalized) for terrain
## shader uniforms. Falls back to Vector3.UP before the sun light is built.
func _get_sun_direction() -> Vector3:
	if _sun_light != null:
		var forward: Vector3 = -_sun_light.global_transform.basis.z
		if forward.length_squared() > 1e-6:
			return forward.normalized()
	return Vector3.UP

# ------------------------------------------------------------------------------
# Boujie Water Shader Ocean Surface (ocean archetypes only)
# ------------------------------------------------------------------------------
## Spawns the OceanSurfaceManager for ocean-bearing archetypes (Terran Oceanic
## and Ice worlds with liquid oceans). For non-ocean archetypes this is a no-op.
## The ocean plane is positioned at sea level relative to the terrain sphere and
## fades in as the player descends through the atmosphere.
func _build_ocean_surface() -> void:
	if not OceanSurfaceManager.archetype_has_ocean(_archetype):
		return
	_ocean_surface_manager = OceanSurfaceManager.new()
	_ocean_surface_manager.name = "BoujieOceanSurface"
	add_child(_ocean_surface_manager)
	# Derive planet physical properties for the ocean configuration.
	var gravity: float = 9.81
	var wind_speed: float = 5.0
	var temp_k: float = 288.0
	# Per-archetype physical defaults.
	match _archetype:
		Archetype.TERRAN_OCEANIC:
			gravity = 9.81
			wind_speed = 6.0
			temp_k = 288.0
		Archetype.ICE_WORLD:
			gravity = 9.81
			wind_speed = 3.0
			temp_k = 223.0
	# Sea level ratio: ocean planets have water at ~70% of the terrain amplitude
	# above the base surface. Default 0.0 places water at the terrain sphere.
	var sea_ratio: float = 0.0
	_ocean_surface_manager.sea_level_ratio = sea_ratio
	_ocean_surface_manager.configure(_archetype, _seed, _radius_m, gravity, wind_speed, temp_k)

# ------------------------------------------------------------------------------
# Sky & Environment
# ------------------------------------------------------------------------------
func _build_sky_and_environment() -> void:
	_sky_material = ProceduralSkyMaterial.new()
	_sky_material.sky_top_color = _profile.sky_top_color
	_sky_material.sky_horizon_color = _profile.sky_horizon_color
	_sky_material.ground_bottom_color = _profile.sky_bottom_color
	_sky_material.ground_horizon_color = _profile.sky_horizon_color
	_sky_material.sun_angle_max = 35.0
	_sky_material.sun_curve = 0.15

	var sky: Sky = Sky.new()
	sky.sky_material = _sky_material

	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = _profile.ambient_color
	env.ambient_light_energy = _profile.ambient_energy
	env.fog_enabled = _profile.fog_density > 0.0
	env.fog_light_color = _profile.fog_color
	env.fog_density = _profile.fog_density
	env.fog_aerial_perspective = 0.5
	env.glow_enabled = true
	env.glow_intensity = 0.8

	_environment_node = WorldEnvironment.new()
	_environment_node.name = "SurfaceEnvironment"
	_environment_node.environment = env
	add_child(_environment_node)

# ------------------------------------------------------------------------------
# Sun & Moon Lighting
# ------------------------------------------------------------------------------
func _build_sun_and_moon() -> void:
	_sun_light = DirectionalLight3D.new()
	_sun_light.name = "Sun"
	_sun_light.light_color = _profile.sun_color
	_sun_light.light_energy = _profile.sun_energy
	_sun_light.shadow_enabled = true
	_sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(_sun_light)

	_moon_light = DirectionalLight3D.new()
	_moon_light.name = "Moon"
	_moon_light.light_color = Color(0.7, 0.75, 0.9)
	_moon_light.light_energy = 0.0
	_moon_light.shadow_enabled = false
	add_child(_moon_light)

	_apply_day_night_transforms()

# ------------------------------------------------------------------------------
# Weather Particles
# ------------------------------------------------------------------------------
func _build_weather() -> void:
	_weather_type = _profile.weather_type
	_weather_particles = GPUParticles3D.new()
	_weather_particles.name = "WeatherParticles"
	_weather_particles.amount = weather_particle_count
	_weather_particles.lifetime = 4.0
	_weather_particles.explosiveness = 0.0
	_weather_particles.randomness = 1.0

	_weather_process_mat = ParticleProcessMaterial.new()
	_weather_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_weather_process_mat.emission_box_extents = Vector3(_radius_m * 0.5, 20.0, _radius_m * 0.5)
	_weather_process_mat.direction = Vector3(0.2, -1.0, 0.1)
	_weather_process_mat.spread = 15.0
	_weather_process_mat.gravity = Vector3(0.0, -9.81, 0.0)
	_weather_process_mat.initial_velocity_min = 4.0
	_weather_process_mat.initial_velocity_max = 8.0
	_weather_process_mat.scale_min = 0.5
	_weather_process_mat.scale_max = 1.0

	# Per-archetype particle appearance.
	var particle_mesh: Mesh = SphereMesh.new()
	(particle_mesh as SphereMesh).radius = 0.05
	(particle_mesh as SphereMesh).height = 0.1
	var particle_mat: StandardMaterial3D = StandardMaterial3D.new()
	particle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	match _weather_type:
		WeatherType.RAIN:
			particle_mat.albedo_color = Color(0.6, 0.75, 1.0, 0.7)
			_weather_process_mat.direction = Vector3(0.3, -1.0, 0.2)
			_weather_process_mat.initial_velocity_min = 12.0
			_weather_process_mat.initial_velocity_max = 18.0
		WeatherType.SNOW:
			particle_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
			_weather_process_mat.direction = Vector3(0.1, -0.4, 0.1)
			_weather_process_mat.initial_velocity_min = 1.0
			_weather_process_mat.initial_velocity_max = 2.5
			_weather_process_mat.gravity = Vector3(0.0, -1.5, 0.0)
		WeatherType.DUST:
			particle_mat.albedo_color = Color(0.8, 0.65, 0.4, 0.5)
			_weather_process_mat.direction = Vector3(1.0, -0.2, 0.5)
			_weather_process_mat.initial_velocity_min = 2.0
			_weather_process_mat.initial_velocity_max = 5.0
			_weather_process_mat.gravity = Vector3(0.0, -0.5, 0.0)
		WeatherType.ASH:
			particle_mat.albedo_color = Color(0.2, 0.1, 0.05, 0.8)
			_weather_process_mat.direction = Vector3(0.2, -0.6, 0.3)
			_weather_process_mat.initial_velocity_min = 1.5
			_weather_process_mat.initial_velocity_max = 4.0
			_weather_process_mat.gravity = Vector3(0.0, -2.0, 0.0)
		WeatherType.SPORES:
			particle_mat.albedo_color = Color(0.3, 1.0, 0.5, 0.6)
			particle_mat.emission_energy_multiplier = 1.5
			_weather_process_mat.direction = Vector3(0.2, 0.3, 0.2)
			_weather_process_mat.initial_velocity_min = 0.5
			_weather_process_mat.initial_velocity_max = 1.5
			_weather_process_mat.gravity = Vector3(0.0, 0.3, 0.0)
		WeatherType.NONE:
			_weather_particles.amount = 0
			particle_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.0)

	(particle_mesh as SphereMesh).material = particle_mat
	_weather_particles.process_material = _weather_process_mat
	_weather_particles.draw_pass_1 = particle_mesh
	add_child(_weather_particles)

	if _weather_type != WeatherType.NONE:
		weather_changed.emit(_weather_type, weather_intensity)

# ------------------------------------------------------------------------------
# Day/Night Cycle
# ------------------------------------------------------------------------------
func _advance_day_night(delta: float) -> void:
	if day_length_seconds <= 0.0:
		return
	_time_of_day = fmod(_time_of_day + delta / day_length_seconds, 1.0)
	if _time_of_day < 0.0:
		_time_of_day += 1.0
	time_of_day_changed.emit(_time_of_day)
	_apply_day_night_transforms()

func _apply_day_night_transforms() -> void:
	if _sun_light == null:
		return
	# Sun angle: 0 at midnight (below horizon), PI/2 at noon (overhead).
	var sun_angle: float = _time_of_day * TAU
	# Rotate sun around the X axis (east->west arc).
	var sun_dir: Vector3 = Vector3(cos(sun_angle), sin(sun_angle), 0.2).normalized()
	_sun_light.global_transform.basis = Basis.looking_at(-sun_dir, Vector3.UP)
	# Daylight factor: 1 at noon, 0 at midnight.
	var daylight: float = clampf(sin(sun_angle), 0.0, 1.0)
	_sun_light.light_energy = lerp(0.05, _profile.sun_energy, daylight)
	_sun_light.visible = daylight > 0.01

	# Moon opposes the sun.
	if _moon_light != null:
		var moon_dir: Vector3 = -sun_dir
		_moon_light.global_transform.basis = Basis.looking_at(-moon_dir, Vector3.UP)
		_moon_light.light_energy = lerp(0.0, moon_base_energy, 1.0 - daylight)
		_moon_light.visible = daylight < 0.5

	# Tint the sky based on time of day (dawn/dusk warm shift).
	if _sky_material != null:
		var dusk_factor: float = clampf(1.0 - absf(daylight - 0.5) * 2.0, 0.0, 1.0)
		_sky_material.sky_horizon_color = _profile.sky_horizon_color.lerp(Color(1.0, 0.5, 0.25), dusk_factor * 0.6)

	# Keep the terrain shader's sun direction and color in sync with the day/night arc.
	if _terrain_material is ShaderMaterial:
		var sm: ShaderMaterial = _terrain_material as ShaderMaterial
		sm.set_shader_parameter("sun_direction", sun_dir)
		if _profile != null:
			sm.set_shader_parameter("sun_color", _profile.sun_color)

# ------------------------------------------------------------------------------
# Surface Entry / Exit
# ------------------------------------------------------------------------------
## Activates the surface environment when the player lands.
## player_pos: world position where the player will be placed.
## Returns the surface normal at that position for character alignment.
func enter_surface(player_pos: Vector3) -> Vector3:
	visible = true
	set_process(true)
	if _weather_particles != null:
		_weather_particles.emitting = true
	# Activate the Boujie ocean surface for ocean-bearing archetypes.
	if _ocean_surface_manager != null and is_instance_valid(_ocean_surface_manager):
		_ocean_surface_manager.activate()
	var to_center: Vector3 = global_position - player_pos
	var dist: float = to_center.length()
	if dist < 0.001:
		return Vector3.UP
	return (-to_center / dist).normalized()

## Deactivates the surface environment when the player takes off.
func exit_surface() -> void:
	set_process(false)
	if _weather_particles != null:
		_weather_particles.emitting = false
	# Deactivate the Boujie ocean surface (hides the water plane immediately).
	if _ocean_surface_manager != null and is_instance_valid(_ocean_surface_manager):
		_ocean_surface_manager.deactivate()
	weather_changed.emit(WeatherType.NONE, 0.0)

# ------------------------------------------------------------------------------
# Floating Origin Support
# ------------------------------------------------------------------------------
## Rebases all children by a world-space offset (floating origin shift).
func apply_floating_origin(offset: Vector3) -> void:
	for c: Node in get_children():
		if c is Node3D:
			(c as Node3D).global_position += offset
	# The Boujie ocean plane follows the player independently; propagate the
	# origin shift so it stays aligned with the terrain during rebase.
	if _ocean_surface_manager != null and is_instance_valid(_ocean_surface_manager):
		_ocean_surface_manager.apply_floating_origin(offset)

# ------------------------------------------------------------------------------
# Accessors
# ------------------------------------------------------------------------------
func get_time_of_day() -> float:
	return _time_of_day

func set_time_of_day(t: float) -> void:
	_time_of_day = clampf(t, 0.0, 1.0)
	if _configured:
		_apply_day_night_transforms()
		time_of_day_changed.emit(_time_of_day)

func get_weather_type() -> int:
	return _weather_type

func get_archetype() -> int:
	return _archetype

func get_planet_radius() -> float:
	return _radius_m

## Returns the Boujie OceanSurfaceManager (or null if this archetype has no ocean).
func get_ocean_surface_manager() -> OceanSurfaceManager:
	return _ocean_surface_manager

## Returns true if the current archetype hosts a Boujie water ocean.
func has_ocean() -> bool:
	return _ocean_surface_manager != null and is_instance_valid(_ocean_surface_manager) and _ocean_surface_manager.has_ocean()

## Sets weather intensity (0..1) and adjusts particle count proportionally.
func set_weather_intensity(intensity: float) -> void:
	weather_intensity = clampf(intensity, 0.0, 1.0)
	if _weather_particles != null:
		_weather_particles.amount = int(float(weather_particle_count) * weather_intensity)
		_weather_particles.emitting = weather_intensity > 0.01
	weather_changed.emit(_weather_type, weather_intensity)

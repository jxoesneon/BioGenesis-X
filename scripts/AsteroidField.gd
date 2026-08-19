@tool
class_name AsteroidField
extends Node3D

signal asteroids_generated

const VoidFaunaDroneClass: GDScript = preload("res://scripts/VoidFaunaDrone.gd")
const ProceduralAsteroidMeshClass: GDScript = preload("res://scripts/ProceduralAsteroidMesh.gd")

var _cached_asteroid_meshes: Array[ArrayMesh] = []
var _cached_collision_shapes: Array[Shape3D] = []

## AsteroidField.gd
## Procedural 3D Asteroid Field Generator, Cosmic Biopunk Environment & Void-Fauna Spawns
## Part of BioGenesis-X space environment.

@export_group("Asteroid Field Setup")
@export var asteroid_count: int = 60
@export var field_radius: float = 400.0
@export var min_asteroid_scale: float = 2.0
@export var max_asteroid_scale: float = 12.0
@export var use_multimesh: bool = false # Toggle between RigidBody3D instancing and MultiMesh

@export_group("Asteroid Mesh Generator (LODs & Shape)")
@export_range(1.0, 150.0, 0.5) var asteroid_base_radius: float = 6.0:
	set(v): asteroid_base_radius = v; _request_rebuild()
@export_range(1, 6, 1) var asteroid_subdivision_level: int = 2:
	set(v): asteroid_subdivision_level = v; _request_rebuild()
@export_range(0.0, 1.0, 0.05) var asteroid_roughness: float = 0.45:
	set(v): asteroid_roughness = v; _request_rebuild()

@export_group("Asteroid PAG Integration")
@export_range(0.1, 2.0, 0.1) var voronoi_crater_freq: float = 0.4:
	set(v): voronoi_crater_freq = v; _request_rebuild()
@export_range(0.0, 5.0, 0.1) var voronoi_crater_depth: float = 1.2:
	set(v): voronoi_crater_depth = v; _request_rebuild()
@export_range(0.0, 2.0, 0.1) var voronoi_crater_rim: float = 0.4:
	set(v): voronoi_crater_rim = v; _request_rebuild()
@export_range(0.0, 1.0, 0.1) var voronoi_crater_flatness: float = 0.5:
	set(v): voronoi_crater_flatness = v; _request_rebuild()
@export_range(0.0, 1.0, 0.05) var terracing_amount: float = 0.6:
	set(v): terracing_amount = v; _request_rebuild()
@export_range(0.1, 1.0, 0.05) var max_displacement_ratio: float = 0.55:
	set(v): max_displacement_ratio = v; _request_rebuild()

func _request_rebuild() -> void:
	if not is_inside_tree() or not Engine.is_editor_hint(): return
	_cached_asteroid_meshes.clear()
	_cached_collision_shapes.clear()
	for child: Node in get_children():
		if child is MultiMeshInstance3D or child.name == "Asteroids":
			remove_child(child)
			child.queue_free()
	instantiated_asteroids.clear()
	_generate_asteroid_field()

@export_group("Biopunk Environment & Lighting")
@export var enable_skybox: bool = true
@export var starlight_color: Color = Color(0.4, 0.85, 1.0)
@export var starlight_energy: float = 2.0
@export var bio_fog_color: Color = Color(0.05, 0.15, 0.2)

@export_group("Combat Testing - Void-Fauna & Drones")
@export var drone_count: int = 8
@export var drone_orbit_radius: float = 120.0

var instantiated_asteroids: Array[Node3D] = []
var target_drones: Array[Node3D] = []
var world_environment: WorldEnvironment
var directional_light: DirectionalLight3D
var space_dust_particles: GPUParticles3D

# --- Incremental generation state ---
var _asteroid_container: Node3D = null
var _placed_positions: Array[Vector3] = []
var _placed_radii: Array[float] = []
var _asteroids_spawned: int = 0
var _asteroid_gen_done: bool = false
const ASTEROIDS_PER_FRAME: int = 5  # Default, overridden by HardwareDetector
var _asteroids_per_frame_dynamic: int = ASTEROIDS_PER_FRAME

func _ready() -> void:
	_setup_biopunk_environment()
	_build_procedural_asteroid_cache()
	_spawn_cosmic_space_dust()
	_spawn_target_drones()
	# Query HardwareDetector for per-hardware asteroid generation rate
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root:
		var hw: Node = ml.root.get_node_or_null("HardwareDetector")
		if hw and hw.has_method("get_asteroids_per_frame"):
			_asteroids_per_frame_dynamic = int(hw.get_asteroids_per_frame())
	# Start incremental asteroid generation
	_start_asteroid_generation()

func _process(delta: float) -> void:
	_animate_drones(delta)
	# Continue incremental asteroid generation
	if not _asteroid_gen_done:
		_continue_asteroid_generation()

func _start_asteroid_generation() -> void:
	if use_multimesh:
		# MultiMesh path — generate all at once (fast, no physics)
		_generate_asteroid_field_multimesh()
		_finish_asteroid_generation()
	else:
		# RigidBody path — incremental
		_asteroid_container = Node3D.new()
		_asteroid_container.name = "Asteroids"
		add_child(_asteroid_container)
		_placed_positions.clear()
		_placed_radii.clear()
		_asteroids_spawned = 0

func _continue_asteroid_generation() -> void:
	if _asteroid_gen_done:
		return
	var to_spawn: int = mini(_asteroids_per_frame_dynamic, asteroid_count - _asteroids_spawned)
	for i in range(to_spawn):
		_spawn_single_asteroid(_asteroids_spawned)
		_asteroids_spawned += 1
	if _asteroids_spawned >= asteroid_count:
		_finish_asteroid_generation()

func _finish_asteroid_generation() -> void:
	_asteroid_gen_done = true
	print("[AsteroidField] Generated %d asteroids, %d total children" % [instantiated_asteroids.size(), get_child_count()])
	asteroids_generated.emit()

func _spawn_single_asteroid(i: int) -> void:
	var archetype_idx: int = i % _cached_asteroid_meshes.size()
	var selected_mesh: ArrayMesh = _cached_asteroid_meshes[archetype_idx]
	var selected_shape: Shape3D = _cached_collision_shapes[archetype_idx]

	var body: RigidBody3D = RigidBody3D.new()
	body.name = "Asteroid_%d" % i
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.mesh = selected_mesh
	body.add_child(mesh_inst)

	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	col.shape = selected_shape
	body.add_child(col)

	var scl_factor: float = randf_range(min_asteroid_scale, max_asteroid_scale) / 6.0
	var pos: Vector3 = _get_valid_asteroid_position(scl_factor * 6.0, _placed_positions, _placed_radii)
	_placed_positions.append(pos)
	_placed_radii.append(scl_factor * 6.0)

	body.scale = Vector3.ONE * scl_factor
	body.position = pos
	body.rotation = Vector3(randf_range(0.0, TAU), randf_range(0.0, TAU), randf_range(0.0, TAU))

	body.set_meta("spin", Vector3(
		randf_range(-0.15, 0.15),
		randf_range(-0.15, 0.15),
		randf_range(-0.15, 0.15)
	))

	_asteroid_container.add_child(body)
	instantiated_asteroids.append(body)

func _generate_asteroid_field_multimesh() -> void:
	var multimesh_inst: MultiMeshInstance3D = MultiMeshInstance3D.new()
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _cached_asteroid_meshes[0] if _cached_asteroid_meshes.size() > 0 else null
	mm.instance_count = asteroid_count

	for i: int in range(asteroid_count):
		var scl_factor: float = randf_range(min_asteroid_scale, max_asteroid_scale)
		var pos: Vector3 = _get_valid_asteroid_position(scl_factor, _placed_positions, _placed_radii)
		_placed_positions.append(pos)
		_placed_radii.append(scl_factor)

		var rot: Vector3 = Vector3(randf_range(0.0, TAU), randf_range(0.0, TAU), randf_range(0.0, TAU))
		var scl: Vector3 = Vector3.ONE * scl_factor

		var transform_3d: Transform3D = Transform3D(Basis.from_euler(rot).scaled(scl), pos)
		mm.set_instance_transform(i, transform_3d)

	multimesh_inst.multimesh = mm
	add_child(multimesh_inst)

func _physics_process(delta: float) -> void:
	_animate_asteroids(delta)

## Sets up WorldEnvironment skybox, starlight, glow, and biopunk color grading.
func _setup_biopunk_environment() -> void:
	# Directional Starlight
	directional_light = DirectionalLight3D.new()
	directional_light.name = "CosmicStarlight"
	directional_light.light_color = starlight_color
	directional_light.light_energy = starlight_energy
	directional_light.shadow_enabled = true
	directional_light.rotation_degrees = Vector3(-35, 45, 0)
	add_child(directional_light)

	if not enable_skybox:
		return

	world_environment = WorldEnvironment.new()
	world_environment.name = "BiopunkSpaceEnvironment"
	
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	
	# Procedural Skybox with Deep Space & Nebula Tint
	var sky: Sky = Sky.new()
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.02, 0.05, 0.12)
	sky_mat.sky_horizon_color = Color(0.1, 0.02, 0.15) # Deep purple nebula horizon
	sky_mat.ground_bottom_color = Color(0.01, 0.02, 0.05)
	sky_mat.ground_horizon_color = Color(0.05, 0.1, 0.15)
	sky_mat.sun_angle_max = 10.0
	sky.sky_material = sky_mat
	env.sky = sky

	# Glow / Bloom for Bioluminescent Weapons & Nebulae
	env.glow_enabled = true
	env.glow_intensity = 1.2
	env.glow_strength = 1.1
	env.glow_bloom = 0.25
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# Volumetric Fog / Ambient Bio-Mist
	env.fog_enabled = true
	env.fog_light_color = bio_fog_color
	env.fog_density = 0.0015
	env.fog_aerial_perspective = 0.5

	# Color Grading & Tone Mapping (2 = ACES)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.15
	env.adjustment_saturation = 1.25

	world_environment.environment = env
	add_child(world_environment)

## Procedurally populates 3D space volume with rotating procedural asteroids.
func _generate_asteroid_field() -> void:
	_build_procedural_asteroid_cache()
	var placed_positions: Array[Vector3] = []
	var placed_radii: Array[float] = []

	if use_multimesh:
		var multimesh_inst: MultiMeshInstance3D = MultiMeshInstance3D.new()
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _cached_asteroid_meshes[0] if _cached_asteroid_meshes.size() > 0 else null
		mm.instance_count = asteroid_count

		for i: int in range(asteroid_count):
			var scl_factor: float = randf_range(min_asteroid_scale, max_asteroid_scale)
			var pos: Vector3 = _get_valid_asteroid_position(scl_factor, placed_positions, placed_radii)
			placed_positions.append(pos)
			placed_radii.append(scl_factor)

			var rot: Vector3 = Vector3(randf_range(0.0, TAU), randf_range(0.0, TAU), randf_range(0.0, TAU))
			var scl: Vector3 = Vector3.ONE * scl_factor

			var transform_3d: Transform3D = Transform3D(Basis.from_euler(rot).scaled(scl), pos)
			mm.set_instance_transform(i, transform_3d)

		multimesh_inst.multimesh = mm
		add_child(multimesh_inst)
	else:
		# Instanced RigidBody3D Asteroids for full physics collision
		var asteroid_container: Node3D = Node3D.new()
		asteroid_container.name = "Asteroids"
		add_child(asteroid_container)

		for i: int in range(asteroid_count):
			var archetype_idx: int = i % _cached_asteroid_meshes.size()
			var selected_mesh: ArrayMesh = _cached_asteroid_meshes[archetype_idx]
			var selected_shape: Shape3D = _cached_collision_shapes[archetype_idx]

			var body: RigidBody3D = RigidBody3D.new()
			body.name = "Asteroid_%d" % i
			body.freeze = true # Kinetic / stationary obstacle mode by default
			body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			
			var mesh_inst: MeshInstance3D = MeshInstance3D.new()
			mesh_inst.mesh = selected_mesh
			body.add_child(mesh_inst)

			var col: CollisionShape3D = CollisionShape3D.new()
			col.name = "CollisionShape3D"
			col.shape = selected_shape
			body.add_child(col)

			# Position, Scale & Random Spin metadata
			var scl_factor: float = randf_range(min_asteroid_scale, max_asteroid_scale) / 6.0 # Normalize base mesh radius (6.0m)
			var pos: Vector3 = _get_valid_asteroid_position(scl_factor * 6.0, placed_positions, placed_radii)
			placed_positions.append(pos)
			placed_radii.append(scl_factor * 6.0)

			body.scale = Vector3.ONE * scl_factor
			body.position = pos
			body.rotation = Vector3(randf_range(0.0, TAU), randf_range(0.0, TAU), randf_range(0.0, TAU))

			# Store rotational velocity metadata
			body.set_meta("spin", Vector3(
				randf_range(-0.15, 0.15),
				randf_range(-0.15, 0.15),
				randf_range(-0.15, 0.15)
			))

			asteroid_container.add_child(body)
			instantiated_asteroids.append(body)

func _build_procedural_asteroid_cache() -> void:
	if not _cached_asteroid_meshes.is_empty():
		return
	
	var archetypes: Array[ProceduralAsteroidMesh.AsteroidArchetype] = [
		ProceduralAsteroidMesh.AsteroidArchetype.CARBONACEOUS_C_TYPE,
		ProceduralAsteroidMesh.AsteroidArchetype.SILICATE_S_TYPE,
		ProceduralAsteroidMesh.AsteroidArchetype.CONTACT_BINARY,
		ProceduralAsteroidMesh.AsteroidArchetype.RUBBLE_REGOLITH,
		ProceduralAsteroidMesh.AsteroidArchetype.JAGGED_SHRAPNEL
	]

	var temp_gen: ProceduralAsteroidMesh = ProceduralAsteroidMeshClass.new()
	temp_gen.base_radius = asteroid_base_radius
	temp_gen.subdivision_level = asteroid_subdivision_level
	temp_gen.displacement_roughness = asteroid_roughness
	temp_gen.generate_collision_shape = false
	
	temp_gen.voronoi_crater_freq = voronoi_crater_freq
	temp_gen.voronoi_crater_depth = voronoi_crater_depth
	temp_gen.voronoi_crater_rim = voronoi_crater_rim
	temp_gen.voronoi_crater_flatness = voronoi_crater_flatness
	temp_gen.terracing_amount = terracing_amount
	temp_gen.max_displacement_ratio = max_displacement_ratio

	for a_idx: int in range(archetypes.size()):
		for var_idx: int in range(2): # 2 unique seeds per archetype = 10 unique celestial models
			temp_gen.archetype = archetypes[a_idx]
			temp_gen.asteroid_seed = 1000 + a_idx * 100 + var_idx * 17
			var mesh_res: ArrayMesh = temp_gen.rebuild_asteroid()
			var shape_res: ConvexPolygonShape3D = mesh_res.create_convex_shape(true, true)
			
			_cached_asteroid_meshes.append(mesh_res)
			_cached_collision_shapes.append(shape_res)
	
	temp_gen.queue_free()

func _get_valid_asteroid_position(radius_scale: float, existing_positions: Array[Vector3], existing_radii: Array[float]) -> Vector3:
	# Exclusion zone around the ship spawn point. The ship starts at a known
	# offset from the AsteroidField origin — we must keep a generous clearance
	# so the player never spawns inside or touching an asteroid.
	# The ship is typically at (0, -48, 2) relative to the field.
	var ship_spawn: Vector3 = Vector3(0.0, -48.0, 2.0)
	var ship_clearance: float = 150.0  # 150m exclusion radius around the ship
	var origin_clearance: float = 50.0  # Clearance around field origin too
	for attempt: int in range(80):
		var candidate: Vector3 = _get_random_volume_point(field_radius)
		# Keep clear of the field origin
		if candidate.length() < origin_clearance + radius_scale:
			continue
		# Keep clear of the ship spawn point
		if candidate.distance_to(ship_spawn) < ship_clearance + radius_scale:
			continue
		# Check overlap with already-placed asteroids
		var overlap: bool = false
		for i: int in range(existing_positions.size()):
			var min_dist: float = radius_scale + existing_radii[i] + 2.0
			if candidate.distance_to(existing_positions[i]) < min_dist:
				overlap = true
				break
		if not overlap:
			return candidate
	# Fallback: return a point far from the ship
	return _get_random_volume_point(field_radius) * 0.8 + ship_spawn * -0.5

## Rotates asteroids smoothly over time.
func _animate_asteroids(delta: float) -> void:
	for body: Node3D in instantiated_asteroids:
		if is_instance_valid(body) and body.has_meta("spin"):
			var spin: Vector3 = body.get_meta("spin") as Vector3
			body.rotate_x(spin.x * delta)
			body.rotate_y(spin.y * delta)
			body.rotate_z(spin.z * delta)

## Spawns cosmic space dust GPU particle emitter.
func _spawn_cosmic_space_dust() -> void:
	space_dust_particles = GPUParticles3D.new()
	space_dust_particles.name = "CosmicSpaceDust"
	space_dust_particles.amount = 300
	space_dust_particles.lifetime = 4.0

	var process_mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_mat.emission_box_extents = Vector3(50, 50, 50)
	process_mat.gravity = Vector3.ZERO
	process_mat.direction = Vector3.BACK
	process_mat.initial_velocity_min = 0.5
	process_mat.initial_velocity_max = 2.0
	process_mat.color = Color(0.6, 0.9, 1.0, 0.4)
	space_dust_particles.process_material = process_mat

	var draw_pass: SphereMesh = SphereMesh.new()
	draw_pass.radius = 0.05
	draw_pass.height = 0.1
	space_dust_particles.draw_pass_1 = draw_pass

	add_child(space_dust_particles)

## Spawns simple interactive target drones / void-fauna entities for combat testing.
func _spawn_target_drones() -> void:
	if drone_count <= 0:
		return
	var drone_container: Node3D = Node3D.new()
	drone_container.name = "VoidFaunaEntities"
	add_child(drone_container)

	for i: int in range(drone_count):
		var angle: float = (float(i) / float(drone_count)) * TAU
		var offset: Vector3 = Vector3(
			cos(angle) * drone_orbit_radius,
			randf_range(-20.0, 20.0),
			sin(angle) * drone_orbit_radius
		)

		var drone: Node3D = VoidFaunaDroneClass.new()
		drone.name = "VoidFauna_%d" % i
		drone.position = offset
		drone.add_to_group("targets")
		drone.add_to_group("void_fauna")

		# Mesh representation (Bioluminescent void creature / drone)
		var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		mesh_inst.name = "MeshInstance3D"
		var prism: PrismMesh = PrismMesh.new()
		prism.size = Vector3(1.5, 1.5, 3.0)
		mesh_inst.mesh = prism

		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.2, 0.5) # Glowing bio-magenta
		mat.emission_enabled = true
		mat.emission = Color(0.8, 0.1, 0.4)
		mat.emission_energy_multiplier = 2.0
		mesh_inst.material_override = mat
		drone.add_child(mesh_inst)

		# Collision shape
		var col: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(1.5, 1.5, 3.0)
		col.shape = box
		drone.add_child(col)

		drone_container.add_child(drone)
		target_drones.append(drone)

## Animates drone patrol orbits over time.
func _animate_drones(_delta: float) -> void:
	pass

func _get_random_volume_point(radius: float) -> Vector3:
	var u: float = randf()
	var v: float = randf()
	var theta: float = u * 2.0 * PI
	# Clamp acos input to [-1.0, 1.0] to prevent NaN positions out-of-bounds
	var phi: float = acos(clampf(2.0 * v - 1.0, -1.0, 1.0))
	var r: float = pow(randf(), 1.0 / 3.0) * radius
	var sin_phi: float = sin(phi)
	return Vector3(
		r * sin_phi * cos(theta),
		r * sin_phi * sin(theta),
		r * cos(phi)
	)

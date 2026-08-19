# res://scripts/ProceduralAsteroidMesh.gd
# ==============================================================================
# BioGenesis-X - AAA+ Programmatic Procedural Asteroid & Rock Mesh Generator
# Pumilio Studios - Celestial Environment & Procedural Synthesis Engine
# ==============================================================================
# Generates photorealistic, topologically isotropic 3D asteroid meshes from
# subdivided IcoSpheres. Implements multi-tier vector domain warping, planar
# cleavage chipping, analytical parabolic crater excavation with raised rim lips,
# and ridged multifractal geological crags.
# ==============================================================================

@tool
class_name ProceduralAsteroidMesh
extends MeshInstance3D

enum AsteroidArchetype {
	CARBONACEOUS_C_TYPE, # Dark organic-rich with radiotrophic bio-veins
	SILICATE_S_TYPE,     # Sharp planar-sliced faceted megalith with craters
	CONTACT_BINARY,      # Dumbbell/spindle contact binary asteroid
	RUBBLE_REGOLITH,     # High-density cratered porous rubble pile
	JAGGED_SHRAPNEL      # UE5-style ultra-sharp faceted crystalline shard
}

@export_group("Asteroid Synthesis Parameters")
@export var archetype: AsteroidArchetype = AsteroidArchetype.CARBONACEOUS_C_TYPE:
	set(v): archetype = v; _request_rebuild()
@export var asteroid_seed: int = 1337:
	set(v): asteroid_seed = v; _request_rebuild()
@export_range(1.0, 150.0, 0.5) var base_radius: float = 6.0:
	set(v): base_radius = v; _request_rebuild()
@export_range(1, 6, 1) var subdivision_level: int = 5:
	set(v): subdivision_level = v; _request_rebuild()
@export_range(0.0, 1.0, 0.05) var displacement_roughness: float = 0.45:
	set(v): displacement_roughness = v; _request_rebuild()
@export var generate_collision_shape: bool = true:
	set(v): generate_collision_shape = v; _request_rebuild()

@export_group("PAG Integration Parameters")
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
	if Engine.is_editor_hint() and is_inside_tree():
		rebuild_asteroid()

# Material & Shader reference
var asteroid_material: ShaderMaterial = null

static var _pbr_textures_cached: bool = false
static var _tex_albedo: NoiseTexture2D = null
static var _tex_normal: NoiseTexture2D = null
static var _tex_roughness: NoiseTexture2D = null

static func _ensure_pbr_textures() -> void:
	if _pbr_textures_cached:
		return
	_pbr_textures_cached = true
	
	var n_albedo: FastNoiseLite = FastNoiseLite.new()
	n_albedo.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n_albedo.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	n_albedo.frequency = 0.04
	n_albedo.fractal_octaves = 5
	_tex_albedo = NoiseTexture2D.new()
	_tex_albedo.noise = n_albedo
	_tex_albedo.seamless = true
	_tex_albedo.generate_mipmaps = true
	_tex_albedo.width = 1024
	_tex_albedo.height = 1024
	
	var n_norm: FastNoiseLite = FastNoiseLite.new()
	n_norm.noise_type = FastNoiseLite.TYPE_CELLULAR
	n_norm.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	n_norm.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
	n_norm.frequency = 0.06
	n_norm.fractal_octaves = 4
	_tex_normal = NoiseTexture2D.new()
	_tex_normal.noise = n_norm
	_tex_normal.seamless = true
	_tex_normal.as_normal_map = true
	_tex_normal.bump_strength = 6.0
	_tex_normal.generate_mipmaps = true
	_tex_normal.width = 1024
	_tex_normal.height = 1024
	
	var n_rough: FastNoiseLite = FastNoiseLite.new()
	n_rough.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_rough.frequency = 0.08
	n_rough.fractal_octaves = 4
	_tex_roughness = NoiseTexture2D.new()
	_tex_roughness.noise = n_rough
	_tex_roughness.seamless = true
	_tex_roughness.generate_mipmaps = true
	_tex_roughness.width = 512
	_tex_roughness.height = 512

func _ready() -> void:
	if mesh == null:
		rebuild_asteroid()

## Rebuilds the 3D procedural asteroid geometry and binds PBR shader
func rebuild_asteroid(custom_seed: int = -1) -> ArrayMesh:
	if custom_seed >= 0:
		asteroid_seed = custom_seed
		
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = asteroid_seed

	# 1. Initialize FastNoiseLite generators
	var noise_shape: FastNoiseLite = FastNoiseLite.new()
	noise_shape.seed = rng.randi()
	noise_shape.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_shape.frequency = 0.12

	var noise_crags: FastNoiseLite = FastNoiseLite.new()
	noise_crags.seed = rng.randi()
	noise_crags.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_crags.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise_crags.fractal_octaves = 4
	noise_crags.frequency = 0.28
	
	var noise_sharp: FastNoiseLite = FastNoiseLite.new()
	noise_sharp.seed = rng.randi()
	noise_sharp.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise_sharp.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	noise_sharp.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	noise_sharp.frequency = 0.15
	noise_sharp.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_sharp.fractal_octaves = 3

	# 2. Configure Archetype Morphology Parameters
	var triaxial_scale: Vector3 = Vector3(1.0, 1.0, 1.0)
	var warp_amplitude: float = 0.25 * base_radius
	var planar_planes: Array[Dictionary] = []
	var craters: Array[Dictionary] = []
	var vein_density_val: float = 0.08

	match archetype:
		AsteroidArchetype.CARBONACEOUS_C_TYPE:
			triaxial_scale = Vector3(rng.randf_range(0.85, 1.25), rng.randf_range(0.85, 1.2), rng.randf_range(0.9, 1.45))
			vein_density_val = 0.14
			_generate_craters(rng, craters, rng.randi_range(2, 4), base_radius)
			_generate_slicing_planes(rng, planar_planes, rng.randi_range(2, 4), base_radius)

		AsteroidArchetype.SILICATE_S_TYPE:
			triaxial_scale = Vector3(rng.randf_range(0.7, 1.4), rng.randf_range(0.7, 1.1), rng.randf_range(1.1, 1.6))
			vein_density_val = 0.04
			_generate_craters(rng, craters, rng.randi_range(4, 7), base_radius)
			_generate_slicing_planes(rng, planar_planes, rng.randi_range(5, 8), base_radius)

		AsteroidArchetype.CONTACT_BINARY:
			triaxial_scale = Vector3(0.75, 0.75, 1.95)
			warp_amplitude = 0.45 * base_radius
			vein_density_val = 0.10
			_generate_craters(rng, craters, rng.randi_range(2, 4), base_radius)
			_generate_slicing_planes(rng, planar_planes, rng.randi_range(2, 4), base_radius)

		AsteroidArchetype.RUBBLE_REGOLITH:
			triaxial_scale = Vector3(rng.randf_range(0.9, 1.15), rng.randf_range(0.9, 1.15), rng.randf_range(0.9, 1.2))
			vein_density_val = 0.02
			_generate_craters(rng, craters, rng.randi_range(6, 10), base_radius)
			_generate_slicing_planes(rng, planar_planes, rng.randi_range(1, 3), base_radius)
			
		AsteroidArchetype.JAGGED_SHRAPNEL:
			triaxial_scale = Vector3(rng.randf_range(0.6, 1.6), rng.randf_range(0.5, 1.1), rng.randf_range(0.5, 1.4))
			vein_density_val = 0.18 # Very crystal rich
			warp_amplitude = 0.6 * base_radius # extreme domain warp
			_generate_craters(rng, craters, rng.randi_range(1, 2), base_radius)
			_generate_slicing_planes(rng, planar_planes, rng.randi_range(6, 12), base_radius)

	# 3. Generate Base Normalized Quad Sphere
	var base_verts: Array[Vector3] = []
	var base_indices: Array[int] = []
	var base_uvs: Array[Vector2] = []
	
	# We map the old subdivision_level to a grid resolution. 
	# A sub_level of 5 gives a dense resolution (e.g., 32x32 per face)
	var resolution: int = maxi(2, subdivision_level * 8)
	
	var faces: Array[Dictionary] = [
		{"up": Vector3.UP, "right": Vector3.RIGHT},
		{"up": Vector3.DOWN, "right": Vector3.LEFT},
		{"up": Vector3.LEFT, "right": Vector3.BACK},
		{"up": Vector3.RIGHT, "right": Vector3.FORWARD},
		{"up": Vector3.FORWARD, "right": Vector3.LEFT},
		{"up": Vector3.BACK, "right": Vector3.RIGHT}
	]
	
	for face: Dictionary in faces:
		var local_up: Vector3 = face["up"]
		var local_right: Vector3 = face["right"]
		var local_forward: Vector3 = local_up.cross(local_right)
		var start_vert_idx: int = base_verts.size()
		
		for y: int in range(resolution):
			for x: int in range(resolution):
				var percent: Vector2 = Vector2(float(x), float(y)) / float(maxi(1, resolution - 1))
				var pointOnUnitCube: Vector3 = local_up + (percent.x - 0.5) * 2.0 * local_right + (percent.y - 0.5) * 2.0 * local_forward
				base_verts.append(pointOnUnitCube.normalized())
				base_uvs.append(percent)
				
				if x != resolution - 1 and y != resolution - 1:
					var i: int = start_vert_idx + x + y * resolution
					# CCW winding
					base_indices.append_array([i, i + 1, i + resolution])
					base_indices.append_array([i + resolution, i + 1, i + resolution + 1])

	# 5. Apply Multi-Tier Fractal Deformation Pipeline
	var deformed_verts: Array[Vector3] = []
	deformed_verts.resize(base_verts.size())

	var lobes: Array[Dictionary] = []
	if archetype == AsteroidArchetype.CONTACT_BINARY:
		lobes.append({"center": Vector3.ZERO, "radius": base_radius})
		lobes.append({"center": Vector3(base_radius * 1.2, 0, 0), "radius": base_radius * 0.85})
	elif archetype == AsteroidArchetype.RUBBLE_REGOLITH:
		lobes.append({"center": Vector3.ZERO, "radius": base_radius})
		lobes.append({"center": Vector3(base_radius * 0.8, base_radius * 0.5, 0), "radius": base_radius * 0.7})
		lobes.append({"center": Vector3(-base_radius * 0.6, base_radius * 0.7, base_radius * 0.3), "radius": base_radius * 0.6})
	else:
		lobes.append({"center": Vector3.ZERO, "radius": base_radius})

	for v_idx: int in range(base_verts.size()):
		var n_dir: Vector3 = base_verts[v_idx] # Unit vector on sphere
		
		# A. Multi-Lobe SDF Raymarching with smin (Principle 1)
		var t: float = 0.1
		for _step: int in range(20):
			var p: Vector3 = n_dir * t
			var d: float = p.distance_to(lobes[0]["center"]) - (lobes[0]["radius"] as float)
			for i: int in range(1, lobes.size()):
				var ld: float = p.distance_to(lobes[i]["center"]) - (lobes[i]["radius"] as float)
				d = _smin(d, ld, base_radius * 0.25)
			t += -d
			if absf(d) < 0.01:
				break
				
		var pos: Vector3 = n_dir * t
		pos = pos * triaxial_scale
		
		var base_pos: Vector3 = pos

		# B. Vector Domain Warping
		var warp_offset: Vector3 = Vector3(
			noise_shape.get_noise_3dv(pos * 0.15 + Vector3(12.5, 0, 0)),
			noise_shape.get_noise_3dv(pos * 0.15 + Vector3(0, 45.2, 0)),
			noise_shape.get_noise_3dv(pos * 0.15 + Vector3(0, 0, 89.1))
		) * warp_amplitude

		# If contact binary, pinch the waist along Z=0
		if archetype == AsteroidArchetype.CONTACT_BINARY:
			var waist: float = 1.0 - exp(-pow(pos.z / (base_radius * 0.7), 2.0)) * 0.48
			pos.x *= waist
			pos.y *= waist

		pos += warp_offset

		# C. Planar Cleavage Faceting / Slicing Cuts
		for plane: Dictionary in planar_planes:
			var p_norm: Vector3 = plane["normal"]
			var p_dist: float = plane["dist"]
			var dot_val: float = pos.dot(p_norm)
			if dot_val > p_dist:
				var excess: float = dot_val - p_dist
				pos -= p_norm * excess * 0.85 # Flatten onto cleavage plane

		# D. Analytical Impact Crater Excavation & Raised Rim Lips
		var total_crater_displacement: float = 0.0
		for crater: Dictionary in craters:
			var c_center: Vector3 = crater["center"]
			var c_radius: float = crater["radius"]
			var c_depth: float = crater["depth"]
			var d: float = pos.distance_to(c_center) / c_radius

			if d <= 1.0:
				# Parabolic bowl depression + central peak
				var bowl: float = -c_depth * (1.0 - d * d)
				var peak: float = (c_depth * 0.35) * exp(-pow(d / 0.2, 2.0)) if c_radius > base_radius * 0.35 else 0.0
				total_crater_displacement += (bowl + peak)
			elif d > 1.0 and d <= 1.55:
				# Raised rim lip crest
				var rim_lip: float = (c_depth * 0.28) * exp(-pow((d - 1.0) / 0.18, 2.0))
				total_crater_displacement += rim_lip
				
		# Add Voronoi/Cellular distance-based crater generation (Principle 3)
		var v_crater: float = _voronoi_craters(pos, voronoi_crater_freq, voronoi_crater_depth, voronoi_crater_rim, voronoi_crater_flatness)
		total_crater_displacement += v_crater

		pos += n_dir * total_crater_displacement

		# E. Ridged Multifractal Geological Fissures & Regolith Terrain (Principle 2)
		var raw_crag: float = 0.0
		if archetype == AsteroidArchetype.JAGGED_SHRAPNEL:
			raw_crag = noise_sharp.get_noise_3dv(pos * 0.4) * displacement_roughness * base_radius * 0.65
		else:
			var n: float = absf(noise_crags.get_noise_3dv(pos * 0.35))
			n = 1.0 - n
			n = n * n
			var terracing: float = terracing_amount
			var steps_val: float = lerpf(12.0, 4.0, terracing)
			var ridge: float = floorf(n * steps_val) / steps_val + pow(fmod(n * steps_val, 1.0), 2.5) / steps_val
			raw_crag = ridge * displacement_roughness * base_radius * 0.3
			
		pos += n_dir * raw_crag
		
		# Principle 4: Displacement Soft-Limiting with tanh()
		var displacement_vec: Vector3 = pos - base_pos
		var disp_mag: float = displacement_vec.length()
		if disp_mag > 0.001:
			var max_disp: float = base_radius * max_displacement_ratio
			var soft_mag: float = max_disp * tanh(disp_mag / max_disp)
			pos = base_pos + (displacement_vec / disp_mag) * soft_mag

		deformed_verts[v_idx] = pos

	# 6. Build ArrayMesh via SurfaceTool
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for idx: int in range(deformed_verts.size()):
		st.set_uv(base_uvs[idx])
		st.add_vertex(deformed_verts[idx])

	for f: int in range(0, base_indices.size(), 3):
		st.add_index(base_indices[f])
		st.add_index(base_indices[f + 2])
		st.add_index(base_indices[f + 1])

	st.generate_normals()
	st.generate_tangents()
	var array_mesh: ArrayMesh = st.commit()

	# 7. Apply Triplanar Asteroid Shader Material
	_setup_material(vein_density_val)
	if asteroid_material and array_mesh.get_surface_count() > 0:
		array_mesh.surface_set_material(0, asteroid_material)

	self.mesh = array_mesh

	# 8. Generate Convex Collision Shape if attached to a physics body
	if generate_collision_shape:
		_build_collision_hull(array_mesh)

	return array_mesh

func _setup_material(vein_density_val: float) -> void:
	if asteroid_material == null:
		var shader_res: Shader = load("res://shaders/procedural_asteroid.gdshader") as Shader
		if shader_res:
			asteroid_material = ShaderMaterial.new()
			asteroid_material.shader = shader_res
			
	if asteroid_material:
		_ensure_pbr_textures()
		# BioTextureGenerator: per-asteroid procedural albedo variation
		# (mineral grain, bio-crystal veins, regolith craters) keyed by archetype + seed.
		var bio_albedo: ImageTexture = BioTextureGenerator.generate_asteroid_texture(int(archetype), asteroid_seed)
		if bio_albedo:
			asteroid_material.set_shader_parameter("texture_albedo", bio_albedo)
		else:
			asteroid_material.set_shader_parameter("texture_albedo", _tex_albedo)
		asteroid_material.set_shader_parameter("texture_normal", _tex_normal)
		asteroid_material.set_shader_parameter("texture_roughness", _tex_roughness)
		asteroid_material.set_shader_parameter("vein_density", vein_density_val)
		match archetype:
			AsteroidArchetype.CARBONACEOUS_C_TYPE:
				asteroid_material.set_shader_parameter("base_rock_color", Color(0.06, 0.07, 0.09))
				asteroid_material.set_shader_parameter("bio_crystal_vein_color", Color(0.0, 0.95, 0.8))
			AsteroidArchetype.SILICATE_S_TYPE:
				asteroid_material.set_shader_parameter("base_rock_color", Color(0.14, 0.15, 0.17))
				asteroid_material.set_shader_parameter("bio_crystal_vein_color", Color(0.95, 0.4, 0.2))
			AsteroidArchetype.CONTACT_BINARY:
				asteroid_material.set_shader_parameter("base_rock_color", Color(0.08, 0.09, 0.12))
				asteroid_material.set_shader_parameter("bio_crystal_vein_color", Color(0.85, 0.2, 0.6))
			AsteroidArchetype.RUBBLE_REGOLITH:
				asteroid_material.set_shader_parameter("base_rock_color", Color(0.10, 0.11, 0.13))
				asteroid_material.set_shader_parameter("bio_crystal_vein_color", Color(0.2, 0.8, 1.0))
			AsteroidArchetype.JAGGED_SHRAPNEL:
				asteroid_material.set_shader_parameter("base_rock_color", Color(0.12, 0.13, 0.15))
				asteroid_material.set_shader_parameter("bio_crystal_vein_color", Color(1.0, 0.2, 0.4))

func _build_collision_hull(target_mesh: ArrayMesh) -> void:
	var parent: Node = get_parent()
	if parent and parent is CollisionObject3D:
		var col: CollisionShape3D = null
		for child: Node in parent.get_children():
			if child is CollisionShape3D:
				col = child as CollisionShape3D
				break
		if col == null:
			col = CollisionShape3D.new()
			col.name = "AsteroidCollisionShape"
			parent.add_child(col)

		var shape: ConvexPolygonShape3D = target_mesh.create_convex_shape(true, true)
		if shape:
			col.shape = shape

# ------------------------------------------------------------------------------
# Geometry & Math Procedures
# ------------------------------------------------------------------------------

func _generate_craters(rng: RandomNumberGenerator, list: Array[Dictionary], count: int, radius: float) -> void:
	for _i: int in range(count):
		var center_norm: Vector3 = Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		).normalized()
		
		var c_radius: float = rng.randf_range(radius * 0.25, radius * 0.65)
		var c_depth: float = rng.randf_range(c_radius * 0.25, c_radius * 0.5)
		list.append({
			"center": center_norm * radius,
			"radius": c_radius,
			"depth": c_depth
		})

func _generate_slicing_planes(rng: RandomNumberGenerator, list: Array[Dictionary], count: int, radius: float) -> void:
	for _i: int in range(count):
		var p_norm: Vector3 = Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		).normalized()
		var p_dist: float = rng.randf_range(radius * 0.72, radius * 0.95)
		list.append({
			"normal": p_norm,
			"dist": p_dist
		})

func _smin(a: float, b: float, k: float) -> float:
	var h: float = clampf(0.5 + 0.5 * (b - a) / maxf(k, 0.001), 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)

func _hash3(p: Vector3) -> Vector3:
	var q: Vector3 = Vector3(
		p.dot(Vector3(127.1, 311.7, 74.7)),
		p.dot(Vector3(269.5, 183.3, 246.1)),
		p.dot(Vector3(113.5, 271.9, 124.6))
	)
	return Vector3(
		fmod(absf(sin(q.x) * 43758.5453123), 1.0),
		fmod(absf(sin(q.y) * 43758.5453123), 1.0),
		fmod(absf(sin(q.z) * 43758.5453123), 1.0)
	)

func _voronoi_craters(p: Vector3, freq: float, depth: float, rimHeight: float, flatness: float) -> float:
	var sp: Vector3 = p * freq
	var ip: Vector3 = sp.floor()
	var fp: Vector3 = sp - ip
	var d1: float = 8.0
	for z: int in range(-1, 2):
		for y: int in range(-1, 2):
			for x: int in range(-1, 2):
				var g: Vector3 = Vector3(float(x), float(y), float(z))
				var rand_offset: Vector3 = _hash3(ip + g)
				var r: Vector3 = g + rand_offset - fp
				var d: float = r.length_squared()
				if d < d1:
					d1 = d
	var dist: float = sqrt(d1)
	var craterRadius: float = 0.65
	var normDist: float = dist / craterRadius
	var disp: float = 0.0
	if normDist < 1.0:
		var bowl: float = pow(normDist, lerpf(2.0, 6.0, flatness)) - 1.0
		disp = bowl * depth
	elif normDist < 1.4:
		var rimNorm: float = (normDist - 1.0) / 0.4
		disp = sin(rimNorm * PI) * rimHeight
	return disp

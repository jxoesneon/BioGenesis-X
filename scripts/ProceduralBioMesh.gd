@tool
class_name ProceduralBioMesh
extends MeshInstance3D

# ============================================================================
# PROCEDURAL BIO-MESH GENERATOR - BioGenesis-X
# Pumilio Studios - 3D Organic Mesh & Shader System
# ============================================================================
# Generates dynamic 3D organic bio-ship geometries using Godot 4 SurfaceTool.
# Features 6 distinct bio-structures:
#   1. Vertebral Spine Column & Ribcage
#   2. Overlapping Chitin Carapace Armor Plates
#   3. Caudal Siphon Exhaust Vent Nozzles & Thruster Plumes
#   4. Multispectral Eye Pod Clusters
#   5. Flank Vascular Conduits
#   6. Articulated Thoracic Tentacles & Spines
# ============================================================================

@export_category("Bio-Ship Configuration")
@export_range(4, 32, 1) var segments: int = 14:
	set(val):
		segments = max(4, val)
		if Engine.is_editor_hint(): rebuild_ship_mesh()

@export_range(5.0, 50.0, 0.5) var length: float = 18.0:
	set(val):
		length = max(1.0, abs(val))
		if Engine.is_editor_hint(): rebuild_ship_mesh()

@export_range(0.5, 3.0, 0.1) var chitin_density: float = 1.2:
	set(val):
		chitin_density = max(0.1, abs(val))
		if Engine.is_editor_hint(): rebuild_ship_mesh()

@export_enum("interceptor", "corvette", "dreadnought", "leviathan") var archetype: String = "interceptor":
	set(val):
		archetype = val
		if Engine.is_editor_hint(): rebuild_ship_mesh()

@export var bioluminescent_color: Color = Color(0.0, 0.95, 1.0, 1.0):
	set(val):
		bioluminescent_color = val
		if Engine.is_editor_hint(): rebuild_ship_mesh()

@export var chitin_base_color: Color = Color(0.06, 0.10, 0.08, 1.0):
	set(val):
		chitin_base_color = val
		if Engine.is_editor_hint(): rebuild_ship_mesh()

@export_category("Collision Options")
@export var auto_generate_collision: bool = true

# Preloaded GDShaders
const CHITIN_SHADER_PATH = "res://shaders/chitin_organic.gdshader"
const BIO_SHADER_PATH = "res://shaders/bioluminescence.gdshader"
const THRUSTER_SHADER_PATH = "res://shaders/plasma_thruster.gdshader"
const INTERIOR_SHADER_PATH = "res://shaders/interior_membrane.gdshader"

var mat_chitin: ShaderMaterial
var mat_bio: ShaderMaterial
var mat_thruster: ShaderMaterial
var mat_interior: ShaderMaterial

# Shared Procedural PBR Noise Textures
var noise_tex_macro: NoiseTexture2D
var noise_tex_micro: NoiseTexture2D
var noise_tex_normal: NoiseTexture2D

func _ready() -> void:
	_init_noise_textures()
	_init_materials()
	_connect_bio_manager()
	
	# If BioManager is available, initialize with active ship config
	var initial_cfg := {}
	var bm := _get_bio_manager()
	if bm and bm.has_method("get_ship_config"):
		initial_cfg = bm.call("get_ship_config")
	rebuild_ship_mesh(initial_cfg)

func _get_bio_manager() -> Node:
	if is_inside_tree() and get_tree() and get_tree().root and true:
		return get_tree().root.get_node("BioManager")
	var ml := Engine.get_main_loop()
	if ml and ml.get("root") and ml.root.has_node("BioManager"):
		return ml.root.get_node("BioManager")
	return null

func _connect_bio_manager() -> void:
	var bm := _get_bio_manager()
	if bm and bm.has_signal("ship_configuration_changed"):
		if not bm.is_connected("ship_configuration_changed", Callable(self, "_on_ship_config_changed")):
			bm.connect("ship_configuration_changed", Callable(self, "_on_ship_config_changed"))

func _exit_tree() -> void:
	var bm := _get_bio_manager()
	if bm and bm.has_signal("ship_configuration_changed"):
		if bm.is_connected("ship_configuration_changed", Callable(self, "_on_ship_config_changed")):
			bm.disconnect("ship_configuration_changed", Callable(self, "_on_ship_config_changed"))

func _on_ship_config_changed(config: Dictionary) -> void:
	rebuild_ship_mesh(config)

func _init_noise_textures() -> void:
	if noise_tex_macro == null:
		var fnl_macro := FastNoiseLite.new()
		fnl_macro.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fnl_macro.frequency = 0.02
		fnl_macro.fractal_octaves = 4
		
		noise_tex_macro = NoiseTexture2D.new()
		noise_tex_macro.seamless = true
		noise_tex_macro.width = 512
		noise_tex_macro.height = 512
		noise_tex_macro.noise = fnl_macro

	if noise_tex_micro == null:
		var fnl_micro := FastNoiseLite.new()
		fnl_micro.noise_type = FastNoiseLite.TYPE_CELLULAR
		fnl_micro.frequency = 0.06
		fnl_micro.fractal_octaves = 3
		
		noise_tex_micro = NoiseTexture2D.new()
		noise_tex_micro.seamless = true
		noise_tex_micro.width = 512
		noise_tex_micro.height = 512
		noise_tex_micro.noise = fnl_micro

	if noise_tex_normal == null:
		var fnl_norm := FastNoiseLite.new()
		fnl_norm.noise_type = FastNoiseLite.TYPE_PERLIN
		fnl_norm.frequency = 0.05
		
		noise_tex_normal = NoiseTexture2D.new()
		noise_tex_normal.seamless = true
		noise_tex_normal.as_normal_map = true
		noise_tex_normal.bump_strength = 6.0
		noise_tex_normal.width = 512
		noise_tex_normal.height = 512
		noise_tex_normal.noise = fnl_norm

func _init_materials() -> void:
	_init_noise_textures()

	var shader_chitin := load(CHITIN_SHADER_PATH) as Shader
	var shader_bio := load(BIO_SHADER_PATH) as Shader
	var shader_thruster := load(THRUSTER_SHADER_PATH) as Shader
	var shader_interior := load(INTERIOR_SHADER_PATH) as Shader

	if shader_chitin:
		mat_chitin = ShaderMaterial.new()
		mat_chitin.shader = shader_chitin
		if noise_tex_macro: mat_chitin.set_shader_parameter("noise_texture_macro", noise_tex_macro)
		if noise_tex_micro: mat_chitin.set_shader_parameter("noise_texture_micro", noise_tex_micro)
		if noise_tex_normal: mat_chitin.set_shader_parameter("noise_texture_normal", noise_tex_normal)

	if shader_bio:
		mat_bio = ShaderMaterial.new()
		mat_bio.shader = shader_bio
		if noise_tex_macro: mat_bio.set_shader_parameter("noise_texture_macro", noise_tex_macro)
		if noise_tex_micro: mat_bio.set_shader_parameter("noise_texture_micro", noise_tex_micro)

	if shader_thruster:
		mat_thruster = ShaderMaterial.new()
		mat_thruster.shader = shader_thruster

	if shader_interior:
		mat_interior = ShaderMaterial.new()
		mat_interior.shader = shader_interior

## Re-generates the entire 3D mesh dynamically based on parameters dictionary or inspector properties
func rebuild_ship_mesh(ship_config: Dictionary = {}) -> void:
	if mat_chitin == null or mat_bio == null or mat_thruster == null or mat_interior == null:
		_init_materials()

	# Override inspector settings if config dictionary provided, with strict safety sanitization
	var cfg_segments: int = max(4, int(ship_config.get("segment_count", ship_config.get("segments", segments))))
	var cfg_length: float = max(1.0, abs(float(ship_config.get("length", length))))
	var cfg_scale: float = max(0.001, abs(float(ship_config.get("scale", 1.0))))
	var cfg_chitin_density: float = max(0.1, abs(float(ship_config.get("chitin_density", chitin_density))))
	var cfg_archetype_raw: String = String(ship_config.get("archetype_id", ship_config.get("archetype", ship_config.get("archetype_name", archetype)))).to_lower()
	var cfg_bio_color: Color = ship_config.get("glow_color", ship_config.get("bioluminescent_color", bioluminescent_color))
	var cfg_chitin_color: Color = ship_config.get("chitin_color", ship_config.get("chitin_base_color", chitin_base_color))

	# Update material uniforms
	if mat_chitin:
		mat_chitin.set_shader_parameter("base_color", cfg_chitin_color)
		mat_chitin.set_shader_parameter("secondary_color", cfg_chitin_color.lightened(0.25))
		mat_chitin.set_shader_parameter("tertiary_color", cfg_chitin_color.darkened(0.35))
		mat_chitin.set_shader_parameter("iridescence_color", cfg_bio_color)

	if mat_bio:
		mat_bio.set_shader_parameter("primary_color", cfg_bio_color)
		mat_bio.set_shader_parameter("core_color", cfg_bio_color.lightened(0.35))

	if mat_thruster:
		mat_thruster.set_shader_parameter("mid_flame_color", cfg_bio_color)
		mat_thruster.set_shader_parameter("outer_flame_color", Color(cfg_bio_color.r * 0.4, 0.05, 0.6, 0.85))

	if mat_interior:
		mat_interior.set_shader_parameter("capillary_color", cfg_bio_color)

	# Distinctive Archetype Morphology Multipliers
	var width_mult: float = 1.0
	var height_mult: float = 1.0
	var tentacle_count: int = 4
	var thruster_count: int = 2

	if cfg_archetype_raw.contains("interceptor") or cfg_archetype_raw.contains("neuro"):
		# Neuro-Spore Interceptor: Swept-wing supersonic delta profile
		width_mult = 1.75
		height_mult = 0.55
		tentacle_count = 2
		thruster_count = 2
	elif cfg_archetype_raw.contains("harvester") or cfg_archetype_raw.contains("void_harvester"):
		# Chitinous Void Harvester: Armored shovel prow, massive ventral scoop
		width_mult = 1.65
		height_mult = 1.50
		tentacle_count = 6
		thruster_count = 3
	elif cfg_archetype_raw.contains("frigate") or cfg_archetype_raw.contains("symbiont"):
		# Abyssal Symbiont Frigate: Twin-fuselage catamaran bio-cruiser
		width_mult = 1.95
		height_mult = 0.85
		tentacle_count = 6
		thruster_count = 4
	elif cfg_archetype_raw.contains("carrier") or cfg_archetype_raw.contains("colony") or cfg_archetype_raw.contains("viral"):
		# Viral Colony Carrier: Voluminous hive brood sacs & launch bays
		width_mult = 2.15
		height_mult = 1.85
		tentacle_count = 8
		thruster_count = 6
	else:
		# Apex Hive Leviathan: Elongated apex predator bio-dreadnought
		width_mult = 1.35
		height_mult = 1.25
		tentacle_count = 8
		thruster_count = 4

	# Surface Tools for separate mesh surfaces / materials
	var st_chitin := SurfaceTool.new()
	st_chitin.begin(Mesh.PRIMITIVE_TRIANGLES)
	if mat_chitin: st_chitin.set_material(mat_chitin)

	var st_bio := SurfaceTool.new()
	st_bio.begin(Mesh.PRIMITIVE_TRIANGLES)
	if mat_bio: st_bio.set_material(mat_bio)

	var st_thruster := SurfaceTool.new()
	st_thruster.begin(Mesh.PRIMITIVE_TRIANGLES)
	if mat_thruster: st_thruster.set_material(mat_thruster)

	var st_interior := SurfaceTool.new()
	st_interior.begin(Mesh.PRIMITIVE_TRIANGLES)
	if mat_interior: st_interior.set_material(mat_interior)

	var count_chitin: int = 0
	var count_bio: int = 0
	var count_thruster: int = 0
	var count_interior: int = 0

	# -------------------------------------------------------------------------
	# 1. VERTEBRAL SPINE COLUMN & RIBCAGE
	# -------------------------------------------------------------------------
	count_chitin += _build_vertebral_spine(st_chitin, cfg_segments, cfg_length, width_mult, height_mult)

	# -------------------------------------------------------------------------
	# 2. CHITIN CARAPACE ARMOR PLATES & LIVING INTERIOR MEMBRANE
	# -------------------------------------------------------------------------
	var carapace_counts := _build_chitin_carapace(st_chitin, st_interior, cfg_segments, cfg_length, width_mult, height_mult, cfg_chitin_density)
	count_chitin += carapace_counts[0]
	count_interior += carapace_counts[1]

	# -------------------------------------------------------------------------
	# 3. SIPHON EXHAUST VENT NOZZLES & THRUSTER PLUMES
	# -------------------------------------------------------------------------
	var siphon_counts := _build_siphon_thrusters(st_chitin, st_thruster, cfg_length, width_mult, thruster_count)
	count_chitin += siphon_counts[0]
	count_thruster += siphon_counts[1]

	# -------------------------------------------------------------------------
	# 4. MULTISPECTRAL EYE POD CLUSTERS
	# -------------------------------------------------------------------------
	var eye_counts := _build_eye_pod_clusters(st_chitin, st_bio, cfg_length, width_mult)
	count_chitin += eye_counts[0]
	count_bio += eye_counts[1]

	# -------------------------------------------------------------------------
	# 5. VASCULAR CONDUITS
	# -------------------------------------------------------------------------
	count_bio += _build_vascular_conduits(st_bio, cfg_segments, cfg_length, width_mult, height_mult)

	# -------------------------------------------------------------------------
	# 6. ARTICULATED TENTACLES / SPINES
	# -------------------------------------------------------------------------
	var tentacle_counts := _build_articulated_tentacles(st_chitin, st_bio, cfg_length, width_mult, tentacle_count)
	count_chitin += tentacle_counts[0]
	count_bio += tentacle_counts[1]

	# -------------------------------------------------------------------------
	# 7. BIOMECHANICAL COMMAND CENTER / CRANIAL COCKPIT (INTERIOR FPV BRIDGE)
	# -------------------------------------------------------------------------
	var bridge_counts := _build_command_center(st_chitin, st_bio, st_interior, cfg_length, width_mult, height_mult)
	count_chitin += bridge_counts[0]
	count_bio += bridge_counts[1]
	count_interior += bridge_counts[2]

	# Dynamically commit surfaces that contain vertices
	var array_mesh := ArrayMesh.new()
	array_mesh = _commit_surface_tool(st_chitin, mat_chitin, array_mesh, count_chitin)
	array_mesh = _commit_surface_tool(st_bio, mat_bio, array_mesh, count_bio)
	array_mesh = _commit_surface_tool(st_thruster, mat_thruster, array_mesh, count_thruster)
	array_mesh = _commit_surface_tool(st_interior, mat_interior, array_mesh, count_interior)

	self.mesh = array_mesh
	
	self.scale = Vector3.ONE * cfg_scale

	if auto_generate_collision:
		generate_collision()

## Query 3D coordinate of the cranial command center
func get_command_center_position() -> Vector3:
	return Vector3(0.0, 0.45, length * 0.28)

## Query 3D coordinate of the pilot eye viewpoint for First-Person View (FPV)
func get_pilot_eye_position() -> Vector3:
	return Vector3(0.0, 0.65, length * 0.28 - 0.15)

## Returns the exact 3D geometric center (centroid of AABB) of the procedural starship
func get_ship_geometric_center() -> Vector3:
	if mesh and mesh is ArrayMesh and mesh.get_surface_count() > 0:
		var aabb := mesh.get_aabb()
		return aabb.position + aabb.size * 0.5
	return Vector3(0.0, 0.0, 0.0)

## Safe helper to commit a SurfaceTool to ArrayMesh and bind its material
func _commit_surface_tool(st: SurfaceTool, mat: Material, target_mesh: ArrayMesh, vert_count: int) -> ArrayMesh:
	if vert_count <= 0:
		return target_mesh
	st.generate_normals()
	st.generate_tangents()
	target_mesh = st.commit(target_mesh)
	var surf_idx := target_mesh.get_surface_count() - 1
	if mat and surf_idx >= 0:
		target_mesh.surface_set_material(surf_idx, mat)
	return target_mesh

## Generates unified rigid collision shape covering the whole bio-ship as a single object
func generate_collision() -> void:
	if mesh == null or mesh.get_surface_count() == 0:
		return

	var parent_node := get_parent()
	var col_shape: CollisionShape3D = null

	# If parent is a CollisionObject3D (e.g. PlayerShip CharacterBody3D / RigidBody3D), attach directly
	if parent_node is CollisionObject3D:
		for child in parent_node.get_children():
			if child is CollisionShape3D:
				col_shape = child
				break
		if col_shape == null:
			col_shape = CollisionShape3D.new()
			col_shape.name = "UnifiedShipCollisionShape"
			if parent_node.is_inside_tree():
				parent_node.add_child.call_deferred(col_shape)
			else:
				parent_node.add_child(col_shape)
	else:
		# Standalone preview in editor / builder
		var static_body: StaticBody3D = null
		for child in get_children():
			if child is StaticBody3D and child.name == "BioMeshStaticBody":
				static_body = child
				break
		if static_body == null:
			static_body = StaticBody3D.new()
			static_body.name = "BioMeshStaticBody"
			add_child(static_body)
		
		for child in static_body.get_children():
			if child is CollisionShape3D:
				col_shape = child
				break
		if col_shape == null:
			col_shape = CollisionShape3D.new()
			col_shape.name = "BioMeshCollisionShape"
			static_body.add_child(col_shape)

	if col_shape:
		var convex_shape := mesh.create_convex_shape(true, true)
		if convex_shape:
			col_shape.shape = convex_shape
		else:
			var aabb := mesh.get_aabb()
			var box := BoxShape3D.new()
			box.size = Vector3(max(0.1, aabb.size.x), max(0.1, aabb.size.y), max(0.1, aabb.size.z))
			col_shape.shape = box

# =============================================================================
# GEOMETRY BUILDER HELPER PROCEDURES
# =============================================================================

# 1. Vertebral Spine & Ribcage Builder
func _build_vertebral_spine(st: SurfaceTool, seg_count: int, ship_len: float, w_mult: float, h_mult: float) -> int:
	if seg_count <= 0 or ship_len <= 0.0:
		return 0
	var z_start := ship_len * 0.5
	var z_end := -ship_len * 0.5
	var step_z := ship_len / float(seg_count)
	var vert_count := 0

	for i in range(seg_count):
		var t := float(i) / float(seg_count)
		var z = lerp(z_start, z_end, t)
		var profile_width := sin(t * PI) * 2.2 * w_mult + 0.4
		var profile_height := sin(t * PI) * 1.5 * h_mult + 0.3

		# Vertebra central joint box
		var center := Vector3(0, sin(t * PI * 0.5) * 0.3, z)
		vert_count += _add_box(st, center, Vector3(0.4, 0.4, step_z * 0.7))

		# Left and Right Rib Arches
		for side in [-1.0, 1.0]:
			var rib_pts: Array[Vector3] = []
			var rib_steps := 5
			for r in range(rib_steps + 1):
				var rt := float(r) / float(rib_steps)
				var rx = side * rt * profile_width
				var ry := center.y + sin(rt * PI) * profile_height * 0.6 - rt * profile_height * 0.8
				var rz = z + sin(rt * PI) * 0.2
				rib_pts.append(Vector3(rx, ry, rz))

			vert_count += _extrude_rib_tube(st, rib_pts, 0.12 * (1.0 - t * 0.3))

	return vert_count

# 2. Chitin Carapace Armor Plates & Living Interior Membrane
func _build_chitin_carapace(st_hull: SurfaceTool, st_inner: SurfaceTool, seg_count: int, ship_len: float, w_mult: float, h_mult: float, density: float) -> Array[int]:
	if seg_count <= 0 or ship_len <= 0.0 or density <= 0.0:
		return [0, 0]
	var z_start := ship_len * 0.5
	var z_end := -ship_len * 0.5
	var plate_count = max(1, int(seg_count * density))
	var _step_z := ship_len / float(plate_count)
	var hull_verts := 0
	var inner_verts := 0

	for i in range(plate_count):
		var t0 := float(i) / float(plate_count)
		var t1 := float(i + 1.2) / float(plate_count) # 20% overlap for armored scales
		var z0 = lerp(z_start, z_end, t0)
		var z1 = lerp(z_start, z_end, t1)

		var w0 := sin(t0 * PI) * 2.6 * w_mult + 0.5
		var w1 := sin(t1 * PI) * 2.6 * w_mult + 0.5

		var h0 := sin(t0 * PI) * 1.8 * h_mult + 0.4
		var h1 := sin(t1 * PI) * 1.8 * h_mult + 0.4

		# Dorsal Carapace Plate (Top armored shell + interior membrane)
		var dorsal_counts := _add_carapace_plate(st_hull, st_inner, z0, z1, w0, w1, h0, h1, 1.0)
		hull_verts += dorsal_counts[0]
		inner_verts += dorsal_counts[1]
		
		# Ventral Carapace Plate (Bottom hull armor + interior membrane)
		var ventral_counts := _add_carapace_plate(st_hull, st_inner, z0, z1, w0 * 0.8, w1 * 0.8, -h0 * 0.7, -h1 * 0.7, -1.0)
		hull_verts += ventral_counts[0]
		inner_verts += ventral_counts[1]

	return [hull_verts, inner_verts]

# 3. Caudal Siphon Exhaust Vent Nozzles & Thruster Plumes
func _build_siphon_thrusters(st_hull: SurfaceTool, st_jet: SurfaceTool, ship_len: float, w_mult: float, count: int) -> Array[int]:
	if count <= 0 or ship_len <= 0.0:
		return [0, 0]
	var z_rear := -ship_len * 0.5
	var offset_step := (1.8 * w_mult) / float(max(count - 1, 1))
	var hull_verts := 0
	var jet_verts := 0

	for i in range(count):
		var side_x := -0.9 * w_mult + i * offset_step if count > 1 else 0.0
		var pos := Vector3(side_x, 0.1, z_rear)

		# Flared Bio-Thruster Bell Nozzle (Hull Chitin)
		hull_verts += _add_thruster_nozzle_bell(st_hull, pos, 0.75, 0.5, 1.4)

		# Inner Plasma Jet Exhaust Plume (Plasma Thruster Shader)
		jet_verts += _add_thruster_jet_plume(st_jet, pos + Vector3(0, 0, -0.2), 0.45, 3.5)

	return [hull_verts, jet_verts]

# 4. Multispectral Eye Pod Clusters Builder
func _build_eye_pod_clusters(st_hull: SurfaceTool, st_bio: SurfaceTool, ship_len: float, w_mult: float) -> Array[int]:
	if ship_len <= 0.0:
		return [0, 0]
	var z_eye := ship_len * 0.32
	var eye_offsets := [
		Vector3(-1.2 * w_mult, 0.4, z_eye),
		Vector3(1.2 * w_mult, 0.4, z_eye),
	]
	var hull_verts := 0
	var bio_verts := 0

	for base_pos in eye_offsets:
		# Main Eye Orb (Bioluminescent Optic Pod)
		bio_verts += _add_icosphere(st_bio, base_pos, 0.42, 2)
		
		# Organic Chitin Socket Ring around main eye
		hull_verts += _add_torus_ring(st_hull, base_pos + Vector3(0, 0, -0.05), 0.46, 0.08)

		# Cluster of smaller secondary ommatidia optic nodes
		for j in range(4):
			var angle := j * (PI * 0.5) + 0.2
			var small_pos = base_pos + Vector3(cos(angle) * 0.38, sin(angle) * 0.38, 0.08)
			bio_verts += _add_icosphere(st_bio, small_pos, 0.16, 1)

	return [hull_verts, bio_verts]

# 5. Flank Vascular Conduits Builder
func _build_vascular_conduits(st_bio: SurfaceTool, seg_count: int, ship_len: float, w_mult: float, h_mult: float) -> int:
	if seg_count <= 0 or ship_len <= 0.0:
		return 0
	var bio_verts := 0
	for side in [-1.0, 1.0]:
		var conduit_pts: Array[Vector3] = []
		var steps = max(1, seg_count * 2)

		for i in range(steps + 1):
			var t := float(i) / float(steps)
			var z = lerp(ship_len * 0.45, -ship_len * 0.48, t)
			var w = (sin(t * PI) * 2.4 * w_mult + 0.55) * side
			var h := sin(t * PI * 1.5) * 0.5 * h_mult
			
			# Sine wave pulsation offset along hull surface
			var pulse_wave := sin(t * PI * 8.0) * 0.06
			conduit_pts.append(Vector3(w + side * pulse_wave, h, z))

		bio_verts += _extrude_rib_tube(st_bio, conduit_pts, 0.09)

	return bio_verts

# 6. Articulated Thoracic Tentacles & Spines Builder
func _build_articulated_tentacles(st_hull: SurfaceTool, st_bio: SurfaceTool, ship_len: float, w_mult: float, tentacle_count: int) -> Array[int]:
	if tentacle_count <= 0 or ship_len <= 0.0:
		return [0, 0]
	var pairs: int = int(float(tentacle_count) / 2.0)
	if pairs <= 0:
		return [0, 0]
	var z_start_thoracic := ship_len * 0.1
	var z_step := (ship_len * 0.35) / float(max(pairs, 1))
	var hull_verts := 0
	var bio_verts := 0

	for p in range(pairs):
		var z_base := z_start_thoracic - p * z_step
		for side in [-1.0, 1.0]:
			var tent_pts: Array[Vector3] = []
			var tent_seg := 7
			var root_pos := Vector3(side * 1.3 * w_mult, -0.4, z_base)

			for s in range(tent_seg + 1):
				var st := float(s) / float(tent_seg)
				var tx = root_pos.x + side * (st * 1.5 + sin(st * PI * 2.0) * 0.2)
				var ty := root_pos.y - st * 1.8 - pow(st, 2.0) * 0.8
				var tz := root_pos.z - st * 2.2 + cos(st * PI * 1.5) * 0.3
				tent_pts.append(Vector3(tx, ty, tz))

			hull_verts += _extrude_rib_tube(st_hull, tent_pts, 0.18 * (1.0 - float(p) * 0.1))
			
			# Glowing ganglion tip node at end of tentacle
			if tent_pts.size() > 0:
				bio_verts += _add_icosphere(st_bio, tent_pts[-1], 0.14, 1)

	return [hull_verts, bio_verts]

# =============================================================================
# MESH GEOMETRY PRIMITIVE HELPERS
# =============================================================================

func _add_box(st: SurfaceTool, center: Vector3, size: Vector3) -> int:
	var h := size * 0.5
	var verts := [
		center + Vector3(-h.x, -h.y,  h.z), center + Vector3( h.x, -h.y,  h.z),
		center + Vector3( h.x,  h.y,  h.z), center + Vector3(-h.x,  h.y,  h.z),
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3( h.x, -h.y, -h.z),
		center + Vector3( h.x,  h.y, -h.z), center + Vector3(-h.x,  h.y, -h.z)
	]
	var faces := [
		0,1,2, 0,2,3, # Front
		1,5,6, 1,6,2, # Right
		5,4,7, 5,7,6, # Back
		4,0,3, 4,3,7, # Left
		3,2,6, 3,6,7, # Top
		4,5,1, 4,1,0  # Bottom
	]
	for idx in faces:
		var v = verts[idx]
		st.set_uv(Vector2(v.x, v.y))
		var diff = v - center
		var norm = diff.normalized() if diff.length_squared() > 0.000001 else Vector3.UP
		st.set_normal(norm)
		st.add_vertex(v)
	return faces.size()

# 7. Biomechanical Command Center / Cranial Cockpit Builder
# 7. Biomechanical Command Center / Cranial Cockpit Builder
func _build_command_center(st_chitin: SurfaceTool, st_bio: SurfaceTool, st_inner: SurfaceTool, ship_len: float, w_mult: float, h_mult: float) -> Array[int]:
	if ship_len <= 0.0:
		return [0, 0, 0]

	var hull_verts := 0
	var bio_verts := 0
	var inner_verts := 0

	# Command center cranial position (forward dorsal quadrant)
	var z_bridge := ship_len * 0.28
	var bridge_center := Vector3(0.0, 0.45 * h_mult, z_bridge)

	# 1. Interior Cockpit Deck Floor & Side Bulkheads (Living Membrane)
	var deck_len := ship_len * 0.18
	var deck_w := 1.4 * w_mult
	var deck_z0 := z_bridge + deck_len * 0.5
	var deck_z1 := z_bridge - deck_len * 0.5
	var deck_y := bridge_center.y - 0.35

	# Living Deck Floor (Upward-facing normal)
	inner_verts += _add_quad_directed(
		st_inner,
		Vector3(-deck_w, deck_y, deck_z0),
		Vector3( deck_w, deck_y, deck_z0),
		Vector3( deck_w, deck_y, deck_z1),
		Vector3(-deck_w, deck_y, deck_z1),
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
		Vector3.UP
	)

	# 2. Pilot Neuro-Helm Cradle (Center living pilot throne)
	var seat_pos := bridge_center + Vector3(0.0, -0.15, -0.25)
	# Seat base
	inner_verts += _add_box(st_inner, seat_pos, Vector3(0.7, 0.25, 0.8))
	# Spine backrest
	inner_verts += _add_box(st_inner, seat_pos + Vector3(0, 0.4, -0.35), Vector3(0.55, 0.7, 0.18))
	# Headrest & Synaptic Coupler node
	inner_verts += _add_box(st_inner, seat_pos + Vector3(0, 0.85, -0.35), Vector3(0.35, 0.25, 0.18))
	bio_verts += _add_icosphere(st_bio, seat_pos + Vector3(0, 0.85, -0.24), 0.12, 1)

	# 3. Biomechanical Flight Console & Synaptic Control Ribbons
	var console_z := z_bridge + 0.55
	var console_pos := Vector3(0.0, bridge_center.y - 0.1, console_z)
	# Main dash console
	hull_verts += _add_box(st_chitin, console_pos, Vector3(1.2 * w_mult, 0.3, 0.4))
	# Glowing Holographic Telemetry Interfaces (Bioluminescent)
	bio_verts += _add_box(st_bio, console_pos + Vector3(0.0, 0.16, 0.05), Vector3(0.9 * w_mult, 0.05, 0.25))
	# Left and Right Auxiliary Tactile Pods
	bio_verts += _add_icosphere(st_bio, console_pos + Vector3(-0.45 * w_mult, 0.2, 0.0), 0.08, 1)
	bio_verts += _add_icosphere(st_bio, console_pos + Vector3( 0.45 * w_mult, 0.2, 0.0), 0.08, 1)

	# 4. Panoramic Ocular Canopy Framework (Arched Ribs framing the view)
	var canopy_steps := 8
	var canopy_radius := 1.35 * w_mult
	for side in [-1.0, 1.0]:
		var arch_pts: Array[Vector3] = []
		for s in range(canopy_steps + 1):
			var st := float(s) / float(canopy_steps)
			var angle := st * PI * 0.6 + 0.1
			var ax = side * cos(angle) * canopy_radius
			var ay := bridge_center.y + sin(angle) * canopy_radius * 0.8
			var az := z_bridge + sin(st * PI) * 0.4 + (st - 0.5) * 0.6
			arch_pts.append(Vector3(ax, ay, az))
		hull_verts += _extrude_rib_tube(st_chitin, arch_pts, 0.08)

	# 5. Overhead Synaptic Ganglion Core (Pulsing living cockpit chandelier)
	var core_pos := bridge_center + Vector3(0.0, 0.85 * h_mult, 0.0)
	bio_verts += _add_icosphere(st_bio, core_pos, 0.22, 2)
	# Vascular tentacles suspending the core
	for a_idx in range(4):
		var ang := a_idx * (PI * 0.5)
		var strut_pts: Array[Vector3] = [
			core_pos,
			core_pos + Vector3(cos(ang) * 0.6, 0.3, sin(ang) * 0.6)
		]
		bio_verts += _extrude_rib_tube(st_bio, strut_pts, 0.04)

	return [hull_verts, bio_verts, inner_verts]

func _add_carapace_plate(st_hull: SurfaceTool, st_inner: SurfaceTool, z0: float, z1: float, w0: float, w1: float, h0: float, h1: float, side_dir: float) -> Array[int]:
	var res_u := 8
	var hull_count := 0
	var inner_count := 0
	var thickness := 0.12 # Living hull shell thickness for interior faces
	for i in range(res_u):
		var u0 := float(i) / float(res_u)
		var u1 := float(i + 1) / float(res_u)

		# Helicoidal curved crest calculations
		var x0_a = lerp(-w0, w0, u0); var x0_b = lerp(-w0, w0, u1)
		var x1_a = lerp(-w1, w1, u0); var x1_b = lerp(-w1, w1, u1)

		var crest0_a := sin(u0 * PI) * h0 * 0.4; var crest0_b := sin(u1 * PI) * h0 * 0.4
		var crest1_a := sin(u0 * PI) * h1 * 0.4; var crest1_b := sin(u1 * PI) * h1 * 0.4

		var y0_a := h0 * sin(u0 * PI) + crest0_a; var y0_b := h0 * sin(u1 * PI) + crest0_b
		var y1_a := h1 * sin(u0 * PI) + crest1_a; var y1_b := h1 * sin(u1 * PI) + crest1_b

		# Outer shell points
		var p0 := Vector3(x0_a, y0_a, z0); var p1 := Vector3(x0_b, y0_b, z0)
		var p2 := Vector3(x1_b, y1_b, z1); var p3 := Vector3(x1_a, y1_a, z1)

		# Normal check: outward direction for dorsal is +Y (side_dir > 0), for ventral is -Y (side_dir < 0)
		var target_outward := Vector3(0, side_dir, 0).normalized()

		# Outer Carapace Quad (strictly outward-facing normals)
		hull_count += _add_quad_directed(st_hull, p0, p1, p2, p3, Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1), target_outward)

		# Inner Living Shell Quad (Offset inwards with inward-facing normal onto st_inner)
		var in_offset_0a := Vector3(x0_a * 0.94, y0_a - side_dir * thickness, z0)
		var in_offset_0b := Vector3(x0_b * 0.94, y0_b - side_dir * thickness, z0)
		var in_offset_1b := Vector3(x1_b * 0.94, y1_b - side_dir * thickness, z1)
		var in_offset_1a := Vector3(x1_a * 0.94, y1_a - side_dir * thickness, z1)

		inner_count += _add_quad_directed(st_inner, in_offset_0a, in_offset_0b, in_offset_1b, in_offset_1a, Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1), -target_outward)
	return [hull_count, inner_count]

func _add_thruster_nozzle_bell(st: SurfaceTool, center: Vector3, radius_front: float, radius_back: float, length_z: float) -> int:
	var sides := 12
	var count := 0
	for i in range(sides):
		var a0 := float(i) / float(sides) * TAU
		var a1 := float(i + 1) / float(sides) * TAU

		var v0 := center + Vector3(cos(a0) * radius_front, sin(a0) * radius_front, 0.0)
		var v1 := center + Vector3(cos(a1) * radius_front, sin(a1) * radius_front, 0.0)
		var v2 := center + Vector3(cos(a1) * radius_back, sin(a1) * radius_back, -length_z)
		var v3 := center + Vector3(cos(a0) * radius_back, sin(a0) * radius_back, -length_z)

		var out_norm := Vector3(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5), 0.2).normalized()
		count += _add_quad_directed(st, v0, v1, v2, v3, Vector2(a0 / TAU, 0), Vector2(a1 / TAU, 0), Vector2(a1 / TAU, 1), Vector2(a0 / TAU, 1), out_norm)
		# Inner nozzle bell wall
		var in_v0 := center + Vector3(cos(a0) * radius_front * 0.9, sin(a0) * radius_front * 0.9, 0.0)
		var in_v1 := center + Vector3(cos(a1) * radius_front * 0.9, sin(a1) * radius_front * 0.9, 0.0)
		var in_v2 := center + Vector3(cos(a1) * radius_back * 0.9, sin(a1) * radius_back * 0.9, -length_z)
		var in_v3 := center + Vector3(cos(a0) * radius_back * 0.9, sin(a0) * radius_back * 0.9, -length_z)
		count += _add_quad_directed(st, in_v0, in_v1, in_v2, in_v3, Vector2(a0 / TAU, 0), Vector2(a1 / TAU, 0), Vector2(a1 / TAU, 1), Vector2(a0 / TAU, 1), -out_norm)
	return count

func _add_thruster_jet_plume(st: SurfaceTool, center: Vector3, radius: float, length_z: float) -> int:
	if radius <= 0.0 or length_z <= 0.0:
		return 0
	var sides := 10
	var tip := center + Vector3(0, 0, -length_z)
	for i in range(sides):
		var a0 := float(i) / float(sides) * TAU
		var a1 := float(i + 1) / float(sides) * TAU

		var v0 := center + Vector3(cos(a0) * radius, sin(a0) * radius, 0.0)
		var v1 := center + Vector3(cos(a1) * radius, sin(a1) * radius, 0.0)

		var cross_vec := (v1 - v0).cross(tip - v0)
		var norm := cross_vec.normalized() if cross_vec.length_squared() > 0.000001 else Vector3.BACK

		st.set_uv(Vector2(a0 / TAU, 0.0)); st.set_normal(norm); st.add_vertex(v0)
		st.set_uv(Vector2(a1 / TAU, 0.0)); st.set_normal(norm); st.add_vertex(v1)
		st.set_uv(Vector2((a0 + a1) * 0.5 / TAU, 1.0)); st.set_normal(norm); st.add_vertex(tip)
	return sides * 3

func _add_icosphere(st: SurfaceTool, center: Vector3, radius: float, subdivisions: int) -> int:
	if radius <= 0.0:
		return 0
	var lat_lines := 6 * (subdivisions + 1)
	var lon_lines := 12 * (subdivisions + 1)
	var count := 0

	for i in range(lat_lines):
		var lat0 := (float(i) / float(lat_lines) - 0.5) * PI
		var lat1 := (float(i + 1) / float(lat_lines) - 0.5) * PI

		for j in range(lon_lines):
			var lon0 := float(j) / float(lon_lines) * TAU
			var lon1 := float(j + 1) / float(lon_lines) * TAU

			var p0 := center + Vector3(cos(lat0) * cos(lon0), sin(lat0), cos(lat0) * sin(lon0)) * radius
			var p1 := center + Vector3(cos(lat0) * cos(lon1), sin(lat0), cos(lat0) * sin(lon1)) * radius
			var p2 := center + Vector3(cos(lat1) * cos(lon1), sin(lat1), cos(lat1) * sin(lon1)) * radius
			var p3 := center + Vector3(cos(lat1) * cos(lon0), sin(lat1), cos(lat1) * sin(lon0)) * radius

			var uv0 := Vector2(float(j) / float(lon_lines), float(i) / float(lat_lines))
			var uv1 := Vector2(float(j + 1) / float(lon_lines), float(i) / float(lat_lines))
			var uv2 := Vector2(float(j + 1) / float(lon_lines), float(i + 1) / float(lat_lines))
			var uv3 := Vector2(float(j) / float(lon_lines), float(i + 1) / float(lat_lines))

			var sphere_norm := (p0 - center).normalized()
			count += _add_quad_directed(st, p0, p1, p2, p3, uv0, uv1, uv2, uv3, sphere_norm)
	return count

func _add_torus_ring(st: SurfaceTool, center: Vector3, major_r: float, minor_r: float) -> int:
	if major_r <= 0.0 or minor_r <= 0.0:
		return 0
	var major_seg := 12
	var minor_seg := 6
	var count := 0

	for i in range(major_seg):
		var a0 := float(i) / float(major_seg) * TAU
		var a1 := float(i + 1) / float(major_seg) * TAU

		for j in range(minor_seg):
			var b0 := float(j) / float(minor_seg) * TAU
			var b1 := float(j + 1) / float(minor_seg) * TAU

			var p0 := center + Vector3((major_r + cos(b0) * minor_r) * cos(a0), (major_r + cos(b0) * minor_r) * sin(a0), sin(b0) * minor_r)
			var p1 := center + Vector3((major_r + cos(b0) * minor_r) * cos(a1), (major_r + cos(b0) * minor_r) * sin(a1), sin(b0) * minor_r)
			var p2 := center + Vector3((major_r + cos(b1) * minor_r) * cos(a1), (major_r + cos(b1) * minor_r) * sin(a1), sin(b1) * minor_r)
			var p3 := center + Vector3((major_r + cos(b1) * minor_r) * cos(a0), (major_r + cos(b1) * minor_r) * sin(a0), sin(b1) * minor_r)

			count += _add_quad(st, p0, p1, p2, p3, Vector2(a0 / TAU, b0 / TAU), Vector2(a1 / TAU, b0 / TAU), Vector2(a1 / TAU, b1 / TAU), Vector2(a0 / TAU, b1 / TAU))
	return count

func _extrude_rib_tube(st: SurfaceTool, points: Array[Vector3], radius: float) -> int:
	if points.size() < 2 or radius <= 0.0:
		return 0

	var sides := 6
	var count := 0
	for i in range(points.size() - 1):
		var p0 := points[i]
		var p1 := points[i + 1]
		if p0.is_equal_approx(p1):
			continue

		var dir := (p1 - p0).normalized()

		# Construct perpendicular frame safely
		var up := Vector3.UP if abs(dir.y) < 0.9 else Vector3.RIGHT
		var side_vec := dir.cross(up)
		if side_vec.length_squared() < 0.000001:
			side_vec = Vector3.RIGHT if abs(dir.x) < 0.9 else Vector3.FORWARD
		var side := side_vec.normalized()
		var normal_up := side.cross(dir).normalized()

		for s in range(sides):
			var a0 := float(s) / float(sides) * TAU
			var a1 := float(s + 1) / float(sides) * TAU

			var offset0 := side * cos(a0) * radius + normal_up * sin(a0) * radius
			var offset1 := side * cos(a1) * radius + normal_up * sin(a1) * radius

			var v0 := p0 + offset0
			var v1 := p0 + offset1
			var v2 := p1 + offset1
			var v3 := p1 + offset0

			var tube_norm := (offset0 + offset1).normalized()
			count += _add_quad_directed(st, v0, v1, v2, v3, Vector2(a0 / TAU, 0), Vector2(a1 / TAU, 0), Vector2(a1 / TAU, 1), Vector2(a0 / TAU, 1), tube_norm)

	return count

func _add_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, uv0: Vector2, uv1: Vector2, uv2: Vector2, uv3: Vector2) -> int:
	return _add_quad_directed(st, v0, v1, v2, v3, uv0, uv1, uv2, uv3, Vector3.ZERO)

func _add_quad_directed(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, uv0: Vector2, uv1: Vector2, uv2: Vector2, uv3: Vector2, desired_norm: Vector3 = Vector3.ZERO) -> int:
	var cross_vec := (v1 - v0).cross(v2 - v0)
	var norm := cross_vec.normalized() if cross_vec.length_squared() > 0.000001 else Vector3.UP

	# If desired normal is specified and winding order faces the wrong way, invert winding
	if desired_norm.length_squared() > 0.001 and norm.dot(desired_norm) < 0.0:
		norm = -norm
		st.set_uv(uv0); st.set_normal(norm); st.add_vertex(v0)
		st.set_uv(uv2); st.set_normal(norm); st.add_vertex(v2)
		st.set_uv(uv1); st.set_normal(norm); st.add_vertex(v1)

		st.set_uv(uv0); st.set_normal(norm); st.add_vertex(v0)
		st.set_uv(uv3); st.set_normal(norm); st.add_vertex(v3)
		st.set_uv(uv2); st.set_normal(norm); st.add_vertex(v2)
	else:
		st.set_uv(uv0); st.set_normal(norm); st.add_vertex(v0)
		st.set_uv(uv1); st.set_normal(norm); st.add_vertex(v1)
		st.set_uv(uv2); st.set_normal(norm); st.add_vertex(v2)

		st.set_uv(uv0); st.set_normal(norm); st.add_vertex(v0)
		st.set_uv(uv2); st.set_normal(norm); st.add_vertex(v2)
		st.set_uv(uv3); st.set_normal(norm); st.add_vertex(v3)
	return 6

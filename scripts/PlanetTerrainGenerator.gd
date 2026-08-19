@tool
class_name PlanetTerrainGenerator
extends Node3D

## PlanetTerrainGenerator.gd
## GPU compute-shader driven planet terrain system for TRUE planetary scale.
## Uses a chunked cube-sphere (6 faces) with distance-based quadtree LOD and a
## floating origin so vertex precision stays high even at a 6,371,000 m radius.
##
## Terrain geometry (positions/normals/tangents) is generated entirely on the
## GPU via a GLSL compute shader (res://shaders/planet_terrain.glsl) dispatched
## through the RenderingDevice API. The compute output is read back once per
## chunk to assemble an ArrayMesh for a MeshInstance3D; rendering itself never
## reads back to the CPU.
##
## Floating origin: chunk vertices are stored relative to the player's current
## planet-local position, keeping all rendered coordinates near zero so float32
## jitter is eliminated at multi-megameter distances.

signal chunk_loaded(chunk_position: Vector3)
signal chunk_unloaded(chunk_position: Vector3)

const _SHADER_PATH: String = "res://shaders/planet_terrain.glsl"
const _VERTS_PER_CHUNK: int = 64
const _VEC4_BYTES: int = 16
const _PARAM_BYTES: int = 64
const _CHUNK_VERTEX_COUNT: int = _VERTS_PER_CHUNK * _VERTS_PER_CHUNK
const _MAX_CHUNKS_PER_UPDATE: int = 2
const _ORIGIN_SHIFT_THRESHOLD_M: float = 1.0

# Faces whose cube->sphere UV mapping produces inward-facing winding and so need
# flipped triangle indices to render with back-face culling.
const _FACE_WINDING_FLIP: Array[bool] = [false, true, true, false, false, true]

# --- Culling (ported from Procedural Planet Chunked LOD) ---------------------
# Frustum test results for quadtree traversal.
const _FRUSTUM_OUTSIDE: int = 0   ## Entirely outside the view — don't render
const _FRUSTUM_INTERSECT: int = 1 ## Partially inside — test children individually
const _FRUSTUM_INSIDE: int = 2    ## Fully inside — skip frustum test for children

# --- LOD hysteresis & split budget (ported from Chunked LOD) ------------------
# Merge threshold is _HYSTERESIS_FACTOR × the split threshold to prevent
# split/merge flickering at the distance boundary.
const _HYSTERESIS_FACTOR: float = 1.15
# Maximum chunk splits per frame. Limits expensive compute dispatches to avoid
# frame hitches when many chunks need refinement simultaneously.
const _SPLIT_BUDGET: int = 8

# --- Skirt generation (ported from Chunked LOD) ------------------------------
# Skirt depth as a fraction of the chunk's bounding sphere radius. Skirts hide
# gaps between adjacent chunks at different LOD levels.
const _SKIRT_DEPTH_FRACTION: float = 0.15
# Number of skirt vertices: one ring per edge (4 edges × _VERTS_PER_CHUNK).
const _SKIRT_VERTEX_COUNT: int = 4 * _VERTS_PER_CHUNK
const _TOTAL_VERTEX_COUNT: int = _CHUNK_VERTEX_COUNT + _SKIRT_VERTEX_COUNT

@export_group("Planet Configuration")
@export var planet_radius_m: float = 6371000.0:
	set(v):
		planet_radius_m = v
		_invalidate_all_chunks()

@export_range(8, 128, 8) var chunk_size: int = 64:
	set(v):
		chunk_size = v
		_invalidate_all_chunks()

@export_range(0, 10, 1) var max_lod: int = 8:
	set(v):
		max_lod = clampi(v, 0, 10)
		_invalidate_all_chunks()

@export_group("Terrain Generation")
@export var elevation_amplitude_m: float = 8000.0
@export var base_frequency: float = 2.5
@export var octaves_base: int = 4
@export var sea_level: float = 0.0
@export var auto_update_lod: bool = true

@export_group("Culling & LOD")
## Enable frustum culling — skips chunks outside the camera's view frustum.
@export var frustum_culling_enabled: bool = true
## Enable horizon culling — skips chunks hidden behind the planet's curvature.
@export var horizon_culling_enabled: bool = true
## Maximum chunk splits per frame (limits compute dispatches to avoid hitches).
@export_range(1, 32, 1) var split_budget: int = _SPLIT_BUDGET

var _planet_seed: int = 1337
var _archetype: int = 3
var _origin: Vector3 = Vector3.ZERO
var _chunks: Dictionary = {} # key(String) -> ChunkHandle
var _pending_generations: Array[Dictionary] = []
var _rd: RenderingDevice
var _shader_file: RDShaderFile
var _shader: RID
var _pipeline: RID
var _rd_initialized: bool = false

# --- Chunk pool (recycled MeshInstance3D nodes) ------------------------------
var _chunk_pool_container: Node3D = null
var _free_chunk_nodes: Array[MeshInstance3D] = []

class ChunkHandle:
	extends RefCounted
	var node: MeshInstance3D
	var face_id: int
	var chunk_x: int
	var chunk_y: int
	var lod: int
	var center_planet_local: Vector3
	# Bounding sphere for culling and LOD distance checks.
	var bounding_center: Vector3
	var bounding_radius: float
	var bounding_aabb: AABB
	# Horizon culling data (angular extent of the chunk on the sphere).
	var horizon_cos_alpha: float
	var horizon_sin_alpha: float
	# Current frustum test result (propagated down the quadtree).
	var frustum_state: int = _FRUSTUM_INTERSECT
	var is_visible: bool = true

	func _init(p_node: MeshInstance3D, p_face: int, p_x: int, p_y: int, p_lod: int, p_center: Vector3) -> void:
		node = p_node
		face_id = p_face
		chunk_x = p_x
		chunk_y = p_y
		lod = p_lod
		center_planet_local = p_center

func _ready() -> void:
	# Create container for pooled chunk nodes (keeps scene tree clean).
	_chunk_pool_container = Node3D.new()
	_chunk_pool_container.name = "ChunkPool"
	add_child(_chunk_pool_container)
	# Lazy init: RenderingDevice may be unavailable in headless/editor contexts.
	_ensure_rd_initialized()

func _process(_delta: float) -> void:
	if not auto_update_lod:
		return
	# Drain the pending generation queue a few chunks per frame to avoid hitches.
	_drain_pending_generations()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_release_rd_resources()

# ---------------------------------------------------------------------------
# PUBLIC API
# ---------------------------------------------------------------------------

## Configures the planet's seed, archetype and radius. Invalidates all chunks.
func set_planet_data(p_seed: int, p_archetype: int, p_radius_m: float) -> void:
	_planet_seed = p_seed
	_archetype = clampi(p_archetype, 0, 7)
	planet_radius_m = p_radius_m
	_invalidate_all_chunks()

## Generates a single terrain chunk at the given face / grid position / LOD.
func generate_chunk(face_id: int, chunk_x: int, chunk_y: int, lod: int) -> void:
	if not _ensure_rd_initialized():
		push_warning("PlanetTerrainGenerator: RenderingDevice unavailable; cannot generate chunk.")
		return
	if face_id < 0 or face_id > 5:
		push_warning("PlanetTerrainGenerator: face_id must be 0..5, got %d." % face_id)
		return
	var clamped_lod: int = clampi(lod, 0, max_lod)
	var key: String = _chunk_key(face_id, chunk_x, chunk_y, clamped_lod)
	if _chunks.has(key):
		return

	var center_dir: Vector3 = _chunk_center_dir(face_id, clamped_lod, chunk_x, chunk_y)
	var center_planet_local: Vector3 = center_dir * planet_radius_m

	var mesh: ArrayMesh = _dispatch_and_build_mesh(face_id, chunk_x, chunk_y, clamped_lod)
	if mesh == null:
		return

	# Acquire a pooled MeshInstance3D (recycled, not newly allocated).
	var mi: MeshInstance3D = _acquire_chunk_node()
	mi.name = "Chunk_%s" % key
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Vertices are stored relative to the floating origin; the node itself sits
	# at the accumulated origin delta (updated each frame in update_lod).
	mi.position = Vector3.ZERO
	mi.visible = true

	var handle: ChunkHandle = ChunkHandle.new(mi, face_id, chunk_x, chunk_y, clamped_lod, center_planet_local)
	# Compute bounding sphere and horizon culling data for this chunk.
	_compute_chunk_bounds(handle, face_id, clamped_lod, chunk_x, chunk_y)
	_chunks[key] = handle
	chunk_loaded.emit(center_planet_local)

## Recomputes LOD around the player and shifts the floating origin.
## Accepts an optional camera for frustum culling. When no camera is provided,
## frustum culling is skipped (all chunks are considered visible).
func update_lod(player_position: Vector3, camera: Camera3D = null) -> void:
	# Shift floating origin: translate every existing chunk node by the delta so
	# their already-baked vertices stay correct relative to the new origin.
	var delta: Vector3 = player_position - _origin
	if delta.length() > _ORIGIN_SHIFT_THRESHOLD_M:
		for key: String in _chunks:
			var handle: ChunkHandle = _chunks[key]
			if is_instance_valid(handle.node):
				handle.node.position -= delta
		_origin = player_position

	# Gather frustum planes for culling (transformed to planet-local space).
	var frustum_planes: Array[Plane] = []
	if frustum_culling_enabled and camera != null and is_instance_valid(camera):
		var planet_pos: Vector3 = global_position
		for p: Plane in camera.get_frustum():
			frustum_planes.append(Plane(p.normal, p.d - p.normal.dot(planet_pos)))

	# Shared split budget — limits expensive compute dispatches per frame.
	var remaining_splits: Array[int] = [split_budget]
	var desired: Array[Dictionary] = []
	for face: int in range(6):
		_refine_face_quadtree(face, 0, 0, 0, player_position, frustum_planes, _FRUSTUM_INTERSECT, remaining_splits, desired)

	var desired_keys: Dictionary = {}
	for d: Dictionary in desired:
		desired_keys[_chunk_key(int(d["face"]), int(d["x"]), int(d["y"]), int(d["lod"]))] = true

	# Unload chunks no longer desired.
	var to_unload: Array[String] = []
	for key: String in _chunks:
		if not desired_keys.has(key):
			to_unload.append(key)
	for key: String in to_unload:
		_unload_chunk(key)

	# Queue new chunks for staggered generation.
	for d: Dictionary in desired:
		var key: String = _chunk_key(int(d["face"]), int(d["x"]), int(d["y"]), int(d["lod"]))
		if not _chunks.has(key):
			_pending_generations.append(d)

	# Update visibility of existing chunks based on culling results.
	_update_chunk_visibility(frustum_planes)

# ---------------------------------------------------------------------------
# RD LIFECYCLE
# ---------------------------------------------------------------------------

func _ensure_rd_initialized() -> bool:
	if _rd_initialized:
		return _rd != null
	_rd_initialized = true
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return false
	_shader_file = load(_SHADER_PATH) as RDShaderFile
	if _shader_file == null:
		push_warning("PlanetTerrainGenerator: failed to load compute shader %s." % _SHADER_PATH)
		return false
	var spirv: RDShaderSPIRV = _shader_file.get_spirv()
	if spirv == null:
		push_warning("PlanetTerrainGenerator: compute shader SPIR-V compilation failed.")
		return false
	_shader = _rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		push_warning("PlanetTerrainGenerator: compute shader is invalid.")
		return false
	_pipeline = _rd.compute_pipeline_create(_shader)
	if not _rd.compute_pipeline_is_valid(_pipeline):
		push_warning("PlanetTerrainGenerator: compute pipeline is invalid.")
		return false
	return true

func _release_rd_resources() -> void:
	if _rd == null:
		return
	if _pipeline != RID():
		_rd.free_rid(_pipeline)
		_pipeline = RID()
	if _shader != RID():
		_rd.free_rid(_shader)
		_shader = RID()
	# _shader_file is a Resource reference; let GC handle it.
	_shader_file = null

# ---------------------------------------------------------------------------
# COMPUTE DISPATCH + MESH BUILD
# ---------------------------------------------------------------------------

func _dispatch_and_build_mesh(face_id: int, chunk_x: int, chunk_y: int, lod: int) -> ArrayMesh:
	var param_bytes: PackedByteArray = _pack_params(face_id, chunk_x, chunk_y, lod)
	var ubo: RID = _rd.uniform_buffer_create(param_bytes.size(), param_bytes)
	if ubo == RID():
		push_warning("PlanetTerrainGenerator: failed to create chunk param UBO.")
		return null

	var buffer_byte_size: int = _CHUNK_VERTEX_COUNT * _VEC4_BYTES
	var pos_buffer: RID = _rd.storage_buffer_create(buffer_byte_size)
	var nrm_buffer: RID = _rd.storage_buffer_create(buffer_byte_size)
	var tan_buffer: RID = _rd.storage_buffer_create(buffer_byte_size)
	if pos_buffer == RID() or nrm_buffer == RID() or tan_buffer == RID():
		push_warning("PlanetTerrainGenerator: failed to create terrain storage buffers.")
		_rd.free_rid(ubo)
		return null

	var uniforms: Array[RDUniform] = []
	var u_ubo: RDUniform = RDUniform.new()
	u_ubo.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u_ubo.binding = 0
	u_ubo.add_id(ubo)
	uniforms.append(u_ubo)

	var u_pos: RDUniform = RDUniform.new()
	u_pos.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_pos.binding = 1
	u_pos.add_id(pos_buffer)
	uniforms.append(u_pos)

	var u_nrm: RDUniform = RDUniform.new()
	u_nrm.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_nrm.binding = 2
	u_nrm.add_id(nrm_buffer)
	uniforms.append(u_nrm)

	var u_tan: RDUniform = RDUniform.new()
	u_tan.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_tan.binding = 3
	u_tan.add_id(tan_buffer)
	uniforms.append(u_tan)

	var uniform_set: RID = _rd.uniform_set_create(uniforms, _shader, 0)
	if not _rd.uniform_set_is_valid(uniform_set):
		push_warning("PlanetTerrainGenerator: failed to create uniform set.")
		_rd.free_rid(ubo)
		_rd.free_rid(pos_buffer)
		_rd.free_rid(nrm_buffer)
		_rd.free_rid(tan_buffer)
		return null

	var groups: int = maxi(int(_VERTS_PER_CHUNK / 4.0), 1)
	var cl: int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipeline)
	_rd.compute_list_bind_uniform_set(cl, uniform_set, 0)
	_rd.compute_list_dispatch(cl, groups, groups, 1)
	_rd.compute_list_end()

	# One-time readback to assemble the renderable ArrayMesh.
	var pos_data: PackedByteArray = _rd.buffer_get_data(pos_buffer)
	var nrm_data: PackedByteArray = _rd.buffer_get_data(nrm_buffer)
	var tan_data: PackedByteArray = _rd.buffer_get_data(tan_buffer)

	_rd.free_rid(ubo)
	_rd.free_rid(pos_buffer)
	_rd.free_rid(nrm_buffer)
	_rd.free_rid(tan_buffer)

	return _build_mesh_from_buffers(pos_data, nrm_data, tan_data, face_id)

func _pack_params(face_id: int, chunk_x: int, chunk_y: int, lod: int) -> PackedByteArray:
	var buf: PackedByteArray = []
	buf.resize(_PARAM_BYTES)
	# ivec4 face_chunk (16 bytes, offsets 0..15)
	buf.encode_s32(0, face_id)
	buf.encode_s32(4, chunk_x)
	buf.encode_s32(8, chunk_y)
	buf.encode_s32(12, lod)
	# uvec4 seed_arch (16 bytes, offsets 16..31)
	buf.encode_u32(16, _planet_seed & 0xFFFFFFFF)
	buf.encode_s32(20, _archetype)
	buf.encode_s32(24, octaves_base)
	buf.encode_s32(28, 0) # pad
	# vec4 geo (16 bytes, offsets 32..47)
	buf.encode_float(32, planet_radius_m)
	buf.encode_float(36, elevation_amplitude_m)
	buf.encode_float(40, base_frequency)
	buf.encode_float(44, sea_level)
	# vec4 warp (16 bytes, offsets 48..63) - deterministic per-seed warp offset
	var warp_seed: float = float(_planet_seed) * 0.013
	buf.encode_float(48, warp_seed)
	buf.encode_float(52, warp_seed * 1.7 + 0.3)
	buf.encode_float(56, warp_seed * 2.3 + 0.7)
	buf.encode_float(60, 0.0) # pad
	return buf

func _build_mesh_from_buffers(pos_data: PackedByteArray, nrm_data: PackedByteArray, tan_data: PackedByteArray, face_id: int) -> ArrayMesh:
	var positions: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var tangents: PackedFloat32Array = PackedFloat32Array()
	positions.resize(_TOTAL_VERTEX_COUNT)
	normals.resize(_TOTAL_VERTEX_COUNT)
	tangents.resize(_TOTAL_VERTEX_COUNT * 4)

	# --- Grid vertices (from compute shader output) ---
	for i: int in range(_CHUNK_VERTEX_COUNT):
		var off: int = i * _VEC4_BYTES
		# Subtract the floating origin so stored vertices are near zero.
		var raw_px: float = pos_data.decode_float(off)
		var raw_py: float = pos_data.decode_float(off + 4)
		var raw_pz: float = pos_data.decode_float(off + 8)
		positions[i] = Vector3(raw_px - _origin.x, raw_py - _origin.y, raw_pz - _origin.z)
		var nx: float = nrm_data.decode_float(off)
		var ny: float = nrm_data.decode_float(off + 4)
		var nz: float = nrm_data.decode_float(off + 8)
		normals[i] = Vector3(nx, ny, nz)
		var t_off: int = i * 4
		tangents[t_off + 0] = tan_data.decode_float(off)
		tangents[t_off + 1] = tan_data.decode_float(off + 4)
		tangents[t_off + 2] = tan_data.decode_float(off + 8)
		tangents[t_off + 3] = tan_data.decode_float(off + 12)

	# --- Skirt vertices (ported from Chunked LOD chunk.gd) ---
	# Duplicate each edge vertex, pushed toward planet center by skirt_depth.
	# Hides gaps between adjacent chunks at different LOD levels.
	_build_skirt_vertices(positions, normals, tangents, pos_data, nrm_data, tan_data)

	var indices: PackedInt32Array = _build_grid_indices(face_id)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _build_default_material())
	return mesh

## Builds skirt vertices: duplicates each edge vertex and pushes it toward the
## planet center by skirt_depth. 4 edges × _VERTS_PER_CHUNK vertices.
## Ported from the Procedural Planet Chunked LOD asset's chunk.gd.
func _build_skirt_vertices(positions: PackedVector3Array, normals: PackedVector3Array,
		tangents: PackedFloat32Array, pos_data: PackedByteArray,
		nrm_data: PackedByteArray, tan_data: PackedByteArray) -> void:
	var n: int = _VERTS_PER_CHUNK
	# Compute skirt depth from the chunk's approximate bounding radius.
	var center_dir: Vector3 = positions[0].normalized() # approximate
	# Use the average edge vertex distance from origin as bounding radius proxy.
	var edge_mid: Vector3 = positions[n / 2] # mid-top edge vertex
	var skirt_depth: float = maxf(edge_mid.length(), 1.0) * _SKIRT_DEPTH_FRACTION
	var idx: int = _CHUNK_VERTEX_COUNT

	# Top edge (y=0): vertices 0..n-1
	for x: int in range(n):
		idx = _write_skirt_vertex(idx, x, skirt_depth, positions, normals, tangents, pos_data, nrm_data, tan_data)
	# Right edge (x=n-1): vertices (n-1)..(n-1)+(n-1)*n
	for y: int in range(n):
		var grid_idx: int = (n - 1) + y * n
		idx = _write_skirt_vertex(idx, grid_idx, skirt_depth, positions, normals, tangents, pos_data, nrm_data, tan_data)
	# Bottom edge (y=n-1, reversed): vertices (n-1)+(n-1)*n down to 0+(n-1)*n
	for x: int in range(n):
		var grid_idx: int = (n - 1 - x) + (n - 1) * n
		idx = _write_skirt_vertex(idx, grid_idx, skirt_depth, positions, normals, tangents, pos_data, nrm_data, tan_data)
	# Left edge (x=0, reversed): vertices 0+(n-1)*n down to 0
	for y: int in range(n):
		var grid_idx: int = 0 + (n - 1 - y) * n
		idx = _write_skirt_vertex(idx, grid_idx, skirt_depth, positions, normals, tangents, pos_data, nrm_data, tan_data)

## Writes a single skirt vertex: duplicates the grid vertex at grid_idx and
## pushes it toward the planet center by skirt_depth.
func _write_skirt_vertex(idx: int, grid_idx: int, skirt_depth: float,
		positions: PackedVector3Array, normals: PackedVector3Array,
		tangents: PackedFloat32Array, pos_data: PackedByteArray,
		nrm_data: PackedByteArray, tan_data: PackedByteArray) -> int:
	# Use the raw (pre-origin) position to compute the inward direction.
	var off: int = grid_idx * _VEC4_BYTES
	var raw_px: float = pos_data.decode_float(off)
	var raw_py: float = pos_data.decode_float(off + 4)
	var raw_pz: float = pos_data.decode_float(off + 8)
	var raw_pos: Vector3 = Vector3(raw_px, raw_py, raw_pz)
	var inward_dir: Vector3 = raw_pos.normalized()
	# Push toward planet center.
	var skirt_pos: Vector3 = raw_pos - inward_dir * skirt_depth
	positions[idx] = Vector3(skirt_pos.x - _origin.x, skirt_pos.y - _origin.y, skirt_pos.z - _origin.z)
	# Copy normal and tangent from the grid vertex.
	normals[idx] = normals[grid_idx]
	var t_off: int = grid_idx * 4
	var s_t_off: int = idx * 4
	tangents[s_t_off + 0] = tangents[t_off + 0]
	tangents[s_t_off + 1] = tangents[t_off + 1]
	tangents[s_t_off + 2] = tangents[t_off + 2]
	tangents[s_t_off + 3] = tangents[t_off + 3]
	return idx + 1

## Builds the triangle index buffer for the grid + skirt. The grid connects
## the _VERTS_PER_CHUNK × _VERTS_PER_CHUNK vertices. The skirt connects each
## edge vertex to its lowered duplicate, hiding gaps between LOD levels.
func _build_grid_indices(face_id: int) -> PackedInt32Array:
	var indices: PackedInt32Array = PackedInt32Array()
	var n: int = _VERTS_PER_CHUNK
	# --- Grid triangles ---
	var cell_count: int = (n - 1) * (n - 1)
	indices.resize(cell_count * 6 + 4 * (n - 1) * 6)
	var flip: bool = _FACE_WINDING_FLIP[face_id]
	var w: int = 0
	for y: int in range(n - 1):
		for x: int in range(n - 1):
			var v00: int = y * n + x
			var v10: int = y * n + x + 1
			var v01: int = (y + 1) * n + x
			var v11: int = (y + 1) * n + x + 1
			if flip:
				indices[w + 0] = v00
				indices[w + 1] = v01
				indices[w + 2] = v11
				indices[w + 3] = v00
				indices[w + 4] = v11
				indices[w + 5] = v10
			else:
				indices[w + 0] = v00
				indices[w + 1] = v10
				indices[w + 2] = v11
				indices[w + 3] = v00
				indices[w + 4] = v11
				indices[w + 5] = v01
			w += 6

	# --- Skirt triangles (ported from Chunked LOD chunk.gd) ---
	# Connect each edge grid vertex to its skirt duplicate.
	# Skirt vertex base offsets: top=n², right=n²+n, bottom=n²+2n, left=n²+3n.
	var grid_vertex_count: int = n * n
	# Top edge (y=0): grid[x] → skirt_top[x]
	var skirt_base: int = grid_vertex_count
	for x: int in range(n - 1):
		var e0: int = x
		var e1: int = x + 1
		var s0: int = skirt_base + x
		var s1: int = skirt_base + x + 1
		indices[w + 0] = e0; indices[w + 1] = s0; indices[w + 2] = e1
		indices[w + 3] = s0; indices[w + 4] = s1; indices[w + 5] = e1
		w += 6
	# Right edge (x=n-1): grid[n-1 + y*n] → skirt_right[y]
	skirt_base = grid_vertex_count + n
	for y: int in range(n - 1):
		var e0: int = (n - 1) + y * n
		var e1: int = (n - 1) + (y + 1) * n
		var s0: int = skirt_base + y
		var s1: int = skirt_base + y + 1
		indices[w + 0] = e0; indices[w + 1] = s0; indices[w + 2] = e1
		indices[w + 3] = s0; indices[w + 4] = s1; indices[w + 5] = e1
		w += 6
	# Bottom edge (y=n-1, reversed): grid[(n-1-x) + (n-1)*n] → skirt_bottom[x]
	skirt_base = grid_vertex_count + 2 * n
	for x: int in range(n - 1):
		var e0: int = (n - 1 - x) + (n - 1) * n
		var e1: int = (n - 1 - x - 1) + (n - 1) * n
		var s0: int = skirt_base + x
		var s1: int = skirt_base + x + 1
		indices[w + 0] = e0; indices[w + 1] = s0; indices[w + 2] = e1
		indices[w + 3] = s0; indices[w + 4] = s1; indices[w + 5] = e1
		w += 6
	# Left edge (x=0, reversed): grid[0 + (n-1-y)*n] → skirt_left[y]
	skirt_base = grid_vertex_count + 3 * n
	for y: int in range(n - 1):
		var e0: int = 0 + (n - 1 - y) * n
		var e1: int = 0 + (n - 1 - y - 1) * n
		var s0: int = skirt_base + y
		var s1: int = skirt_base + y + 1
		indices[w + 0] = e0; indices[w + 1] = s0; indices[w + 2] = e1
		indices[w + 3] = s0; indices[w + 4] = s1; indices[w + 5] = e1
		w += 6

	return indices

func _build_default_material() -> Material:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.45, 0.30)
	mat.roughness = 0.85
	mat.metallic = 0.0
	mat.vertex_color_use_as_albedo = false
	return mat

# ---------------------------------------------------------------------------
# LOD SELECTION (per-face quadtree refined by distance + culling + hysteresis)
# ---------------------------------------------------------------------------

## Recursive quadtree refinement with frustum culling, horizon culling,
## LOD hysteresis, and a per-frame split budget. Ported from the Procedural
## Planet Chunked LOD asset and adapted for the compute-shader pipeline.
func _refine_face_quadtree(face: int, lod: int, cx: int, cy: int,
		player_position: Vector3, frustum_planes: Array[Plane],
		parent_frustum_state: int, remaining_splits: Array[int],
		out: Array[Dictionary]) -> void:
	var center_dir: Vector3 = _chunk_center_dir(face, lod, cx, cy)
	var center_pos: Vector3 = center_dir * planet_radius_m

	# --- Culling: is this chunk visible from the camera? ---
	var is_visible: bool = true
	var frustum_state: int = parent_frustum_state
	if frustum_culling_enabled and not frustum_planes.is_empty():
		if parent_frustum_state == _FRUSTUM_INSIDE:
			frustum_state = _FRUSTUM_INSIDE
		else:
			var chunk_aabb: AABB = _estimate_chunk_aabb(face, lod, cx, cy)
			frustum_state = _test_frustum(chunk_aabb, frustum_planes)
		is_visible = frustum_state != _FRUSTUM_OUTSIDE

	if horizon_culling_enabled and is_visible:
		is_visible = _is_above_horizon(center_dir, face, lod, cx, cy, player_position)

	# --- LOD decision with hysteresis ---
	var dist: float = player_position.distance_to(center_pos)
	var angular_size: float = (PI * 0.5) / float(1 << lod)
	var chunk_extent_m: float = angular_size * planet_radius_m
	var split_threshold: float = chunk_extent_m * 2.0
	var merge_threshold: float = split_threshold * _HYSTERESIS_FACTOR

	# Split when close enough and below max LOD (respecting the split budget).
	if lod < max_lod and dist < split_threshold and is_visible and remaining_splits[0] > 0:
		remaining_splits[0] -= 1
		_refine_face_quadtree(face, lod + 1, cx * 2 + 0, cy * 2 + 0, player_position, frustum_planes, frustum_state, remaining_splits, out)
		_refine_face_quadtree(face, lod + 1, cx * 2 + 1, cy * 2 + 0, player_position, frustum_planes, frustum_state, remaining_splits, out)
		_refine_face_quadtree(face, lod + 1, cx * 2 + 0, cy * 2 + 1, player_position, frustum_planes, frustum_state, remaining_splits, out)
		_refine_face_quadtree(face, lod + 1, cx * 2 + 1, cy * 2 + 1, player_position, frustum_planes, frustum_state, remaining_splits, out)
	elif lod > 0 and dist > merge_threshold and not is_visible:
		# Chunk is far away and not visible — don't include it (it will be unloaded).
		pass
	else:
		out.append({"face": face, "x": cx, "y": cy, "lod": lod})

# ---------------------------------------------------------------------------
# FRUSTUM CULLING (AABB vs frustum planes — ported from Chunked LOD quad.gd)
# ---------------------------------------------------------------------------

## Tests an AABB against camera frustum planes. Returns _FRUSTUM_OUTSIDE,
## _FRUSTUM_INTERSECT, or _FRUSTUM_INSIDE. Godot frustum planes have normals
## pointing outward; distance_to > 0 means outside.
func _test_frustum(aabb: AABB, planes: Array[Plane]) -> int:
	var fully_inside_count: int = 0
	var aabb_min: Vector3 = aabb.position
	var aabb_max: Vector3 = aabb.position + aabb.size
	for plane: Plane in planes:
		# n-vertex: corner most AGAINST the plane normal (closest to inside).
		var n_vertex := Vector3(
			aabb_min.x if plane.normal.x >= 0.0 else aabb_max.x,
			aabb_min.y if plane.normal.y >= 0.0 else aabb_max.y,
			aabb_min.z if plane.normal.z >= 0.0 else aabb_max.z
		)
		if plane.distance_to(n_vertex) > 0.0:
			return _FRUSTUM_OUTSIDE
		# p-vertex: corner most ALONG the plane normal (closest to outside).
		var p_vertex := Vector3(
			aabb_max.x if plane.normal.x >= 0.0 else aabb_min.x,
			aabb_max.y if plane.normal.y >= 0.0 else aabb_min.y,
			aabb_max.z if plane.normal.z >= 0.0 else aabb_min.z
		)
		if plane.distance_to(p_vertex) <= 0.0:
			fully_inside_count += 1
	if fully_inside_count == planes.size():
		return _FRUSTUM_INSIDE
	return _FRUSTUM_INTERSECT

# ---------------------------------------------------------------------------
# HORIZON CULLING (angular geometry on sphere — ported from Chunked LOD quad.gd)
# ---------------------------------------------------------------------------

## Tests whether a chunk is above the planet's curved horizon from the
## camera's viewpoint. Uses angular geometry: the camera's horizon angle
## (depends on altitude) combined with the chunk's angular extent. Mountains
## can peek above the geometric horizon via the terrain_height extension.
func _is_above_horizon(chunk_dir: Vector3, face: int, lod: int, cx: int, cy: int, camera_pos: Vector3) -> bool:
	var camera_distance: float = camera_pos.length()
	# Camera inside the planet — everything is visible.
	if camera_distance <= planet_radius_m:
		return true
	var camera_dir: Vector3 = camera_pos / camera_distance
	var cos_angle_to_chunk: float = camera_dir.dot(chunk_dir)

	# Compute the chunk's angular radius (half-angle subtended by the chunk).
	var angular_size: float = (PI * 0.5) / float(1 << lod)
	var chunk_half_angle: float = angular_size * 0.5
	var cos_chunk_half: float = cos(chunk_half_angle)
	var sin_chunk_half: float = sin(chunk_half_angle)

	# Camera is within the chunk's angular extent — always visible.
	if cos_angle_to_chunk >= cos_chunk_half:
		return true

	# Combined horizon angle: camera_horizon + terrain_extension.
	var cos_camera_horizon: float = planet_radius_m / camera_distance
	var sin_camera_horizon: float = sqrt(maxf(0.0, 1.0 - cos_camera_horizon * cos_camera_horizon))
	var cos_terrain_extend: float = planet_radius_m / (planet_radius_m + elevation_amplitude_m)
	var sin_terrain_extend: float = sqrt(maxf(0.0, 1.0 - cos_terrain_extend * cos_terrain_extend))
	# cos(a+b) = cos(a)cos(b) - sin(a)sin(b)
	var cos_total_horizon: float = cos_camera_horizon * cos_terrain_extend - sin_camera_horizon * sin_terrain_extend

	# Nearest edge of chunk (subtract chunk's angular radius from angle to center).
	# cos(a-b) = cos(a)cos(b) + sin(a)sin(b)
	var sin_angle_to_chunk: float = sqrt(maxf(0.0, 1.0 - cos_angle_to_chunk * cos_angle_to_chunk))
	var cos_nearest_edge: float = cos_angle_to_chunk * cos_chunk_half + sin_angle_to_chunk * sin_chunk_half
	return cos_nearest_edge > cos_total_horizon

## Estimates a chunk's AABB for frustum culling. Includes terrain displacement
## margin so shader-displaced vertices are never incorrectly culled.
func _estimate_chunk_aabb(face: int, lod: int, cx: int, cy: int) -> AABB:
	var center_dir: Vector3 = _chunk_center_dir(face, lod, cx, cy)
	var center_pos: Vector3 = center_dir * planet_radius_m
	var angular_size: float = (PI * 0.5) / float(1 << lod)
	var chunk_extent_m: float = angular_size * planet_radius_m
	# Bounding sphere radius: half the chunk extent + terrain amplitude margin.
	var radius: float = chunk_extent_m * 0.7 + elevation_amplitude_m
	var aabb_min: Vector3 = center_pos - Vector3(radius, radius, radius)
	var aabb_max: Vector3 = center_pos + Vector3(radius, radius, radius)
	return AABB(aabb_min, aabb_max - aabb_min)

## Computes precise bounding sphere and horizon culling data for a generated
## chunk. Called after the mesh is built so the bounds reflect actual geometry.
func _compute_chunk_bounds(handle: ChunkHandle, face: int, lod: int, cx: int, cy: int) -> void:
	var center_dir: Vector3 = _chunk_center_dir(face, lod, cx, cy)
	var center_pos: Vector3 = center_dir * planet_radius_m
	var angular_size: float = (PI * 0.5) / float(1 << lod)
	var chunk_extent_m: float = angular_size * planet_radius_m
	handle.bounding_center = center_pos
	handle.bounding_radius = chunk_extent_m * 0.7 + elevation_amplitude_m
	# AABB including terrain displacement margin.
	var r: float = handle.bounding_radius
	handle.bounding_aabb = AABB(center_pos - Vector3(r, r, r), Vector3(2.0 * r, 2.0 * r, 2.0 * r))
	# Horizon culling: angular half-extent of the chunk on the sphere.
	var chunk_half_angle: float = angular_size * 0.5
	handle.horizon_cos_alpha = cos(chunk_half_angle)
	handle.horizon_sin_alpha = sin(chunk_half_angle)

## Updates visibility flags on existing chunks based on current frustum/horizon
## culling. Hides invisible chunks to save draw calls without unloading them.
func _update_chunk_visibility(frustum_planes: Array[Plane]) -> void:
	for key: String in _chunks:
		var handle: ChunkHandle = _chunks[key]
		if not is_instance_valid(handle.node):
			continue
		var visible: bool = true
		if frustum_culling_enabled and not frustum_planes.is_empty():
			visible = _test_frustum(handle.bounding_aabb, frustum_planes) != _FRUSTUM_OUTSIDE
		if horizon_culling_enabled and visible:
			var camera_pos: Vector3 = _origin
			visible = _is_above_horizon(handle.bounding_center.normalized(),
					handle.face_id, handle.lod, handle.chunk_x, handle.chunk_y, camera_pos)
		handle.is_visible = visible
		handle.node.visible = visible

# ---------------------------------------------------------------------------
# CUBE-SPHERE MATH (mirrors the GLSL face_to_cube)
# ---------------------------------------------------------------------------

func _face_to_cube(face_id: int, uv: Vector2) -> Vector3:
	match face_id:
		0: return Vector3(1.0, uv.x, uv.y)
		1: return Vector3(-1.0, uv.x, uv.y)
		2: return Vector3(uv.x, 1.0, uv.y)
		3: return Vector3(uv.x, -1.0, uv.y)
		4: return Vector3(uv.x, uv.y, 1.0)
		5: return Vector3(uv.x, uv.y, -1.0)
		_: return Vector3(1.0, uv.x, uv.y)

func _chunk_center_dir(face_id: int, lod: int, chunk_x: int, chunk_y: int) -> Vector3:
	var extent: float = 2.0 / float(1 << lod)
	var u: float = -1.0 + (float(chunk_x) + 0.5) * extent
	var v: float = -1.0 + (float(chunk_y) + 0.5) * extent
	return _face_to_cube(face_id, Vector2(u, v)).normalized()

# ---------------------------------------------------------------------------
# CHUNK LIFECYCLE HELPERS
# ---------------------------------------------------------------------------

func _chunk_key(face_id: int, chunk_x: int, chunk_y: int, lod: int) -> String:
	return "%d_%d_%d_%d" % [face_id, chunk_x, chunk_y, lod]

func _unload_chunk(key: String) -> void:
	var handle: ChunkHandle = _chunks.get(key)
	if handle == null:
		return
	var center: Vector3 = handle.center_planet_local
	if is_instance_valid(handle.node):
		# Return the node to the pool for reuse (avoids allocation overhead).
		_release_chunk_node(handle.node)
	_chunks.erase(key)
	chunk_unloaded.emit(center)

func _invalidate_all_chunks() -> void:
	for key: String in _chunks.keys():
		_unload_chunk(key)
	_pending_generations.clear()

# ---------------------------------------------------------------------------
# CHUNK POOL (recycled MeshInstance3D nodes — ported from Chunked LOD planet.gd)
# ---------------------------------------------------------------------------

## Acquires a MeshInstance3D from the pool, creating one if the pool is empty.
func _acquire_chunk_node() -> MeshInstance3D:
	if _free_chunk_nodes.is_empty():
		var mi: MeshInstance3D = MeshInstance3D.new()
		_chunk_pool_container.add_child(mi)
		return mi
	return _free_chunk_nodes.pop_back()

## Releases a MeshInstance3D back to the pool. Hides it immediately.
func _release_chunk_node(node: MeshInstance3D) -> void:
	node.visible = false
	node.mesh = null
	_free_chunk_nodes.append(node)

## Removes all unused chunk nodes from the pool, freeing GPU memory.
func free_unused_pooled_chunks() -> void:
	for node: MeshInstance3D in _free_chunk_nodes:
		if is_instance_valid(node):
			_chunk_pool_container.remove_child(node)
			node.queue_free()
	_free_chunk_nodes.clear()

func _drain_pending_generations() -> void:
	if _pending_generations.is_empty():
		return
	if not _ensure_rd_initialized():
		return
	var generated: int = 0
	while generated < _MAX_CHUNKS_PER_UPDATE and not _pending_generations.is_empty():
		var d: Dictionary = _pending_generations.pop_front()
		var key: String = _chunk_key(int(d["face"]), int(d["x"]), int(d["y"]), int(d["lod"]))
		if not _chunks.has(key):
			generate_chunk(int(d["face"]), int(d["x"]), int(d["y"]), int(d["lod"]))
			generated += 1

# ---------------------------------------------------------------------------
# DEBUG / INSPECTION
# ---------------------------------------------------------------------------

func get_active_chunk_count() -> int:
	return _chunks.size()

func get_pending_chunk_count() -> int:
	return _pending_generations.size()

func get_floating_origin() -> Vector3:
	return _origin

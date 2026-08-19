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

class ChunkHandle:
	extends RefCounted
	var node: MeshInstance3D
	var face_id: int
	var chunk_x: int
	var chunk_y: int
	var lod: int
	var center_planet_local: Vector3

	func _init(p_node: MeshInstance3D, p_face: int, p_x: int, p_y: int, p_lod: int, p_center: Vector3) -> void:
		node = p_node
		face_id = p_face
		chunk_x = p_x
		chunk_y = p_y
		lod = p_lod
		center_planet_local = p_center

func _ready() -> void:
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

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Chunk_%s" % key
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Vertices are stored relative to the floating origin; the node itself sits
	# at the accumulated origin delta (updated each frame in update_lod).
	mi.position = Vector3.ZERO
	add_child(mi)

	var handle: ChunkHandle = ChunkHandle.new(mi, face_id, chunk_x, chunk_y, clamped_lod, center_planet_local)
	_chunks[key] = handle
	chunk_loaded.emit(center_planet_local)

## Recomputes LOD around the player and shifts the floating origin.
func update_lod(player_position: Vector3) -> void:
	# Shift floating origin: translate every existing chunk node by the delta so
	# their already-baked vertices stay correct relative to the new origin.
	var delta: Vector3 = player_position - _origin
	if delta.length() > _ORIGIN_SHIFT_THRESHOLD_M:
		for key: String in _chunks:
			var handle: ChunkHandle = _chunks[key]
			if is_instance_valid(handle.node):
				handle.node.position -= delta
		_origin = player_position

	var desired: Array[Dictionary] = _desired_chunks(player_position)
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
	positions.resize(_CHUNK_VERTEX_COUNT)
	normals.resize(_CHUNK_VERTEX_COUNT)
	tangents.resize(_CHUNK_VERTEX_COUNT * 4)

	for i: int in range(_CHUNK_VERTEX_COUNT):
		var off: int = i * _VEC4_BYTES
		# Subtract the floating origin so stored vertices are near zero.
		var px: float = pos_data.decode_float(off) - _origin.x
		var py: float = pos_data.decode_float(off + 4) - _origin.y
		var pz: float = pos_data.decode_float(off + 8) - _origin.z
		positions[i] = Vector3(px, py, pz)
		var nx: float = nrm_data.decode_float(off)
		var ny: float = nrm_data.decode_float(off + 4)
		var nz: float = nrm_data.decode_float(off + 8)
		normals[i] = Vector3(nx, ny, nz)
		var t_off: int = i * 4
		tangents[t_off + 0] = tan_data.decode_float(off)
		tangents[t_off + 1] = tan_data.decode_float(off + 4)
		tangents[t_off + 2] = tan_data.decode_float(off + 8)
		tangents[t_off + 3] = tan_data.decode_float(off + 12)

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

func _build_grid_indices(face_id: int) -> PackedInt32Array:
	var indices: PackedInt32Array = PackedInt32Array()
	var n: int = _VERTS_PER_CHUNK
	var cell_count: int = (n - 1) * (n - 1)
	indices.resize(cell_count * 6)
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
	return indices

func _build_default_material() -> Material:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.45, 0.30)
	mat.roughness = 0.85
	mat.metallic = 0.0
	mat.vertex_color_use_as_albedo = false
	return mat

# ---------------------------------------------------------------------------
# LOD SELECTION (per-face quadtree refined by distance to player)
# ---------------------------------------------------------------------------

func _desired_chunks(player_position: Vector3) -> Array[Dictionary]:
	var desired: Array[Dictionary] = []
	for face: int in range(6):
		_refine_face_quadtree(face, 0, 0, 0, player_position, desired)
	return desired

func _refine_face_quadtree(face: int, lod: int, cx: int, cy: int, player_position: Vector3, out: Array[Dictionary]) -> void:
	var center_dir: Vector3 = _chunk_center_dir(face, lod, cx, cy)
	var center_pos: Vector3 = center_dir * planet_radius_m
	var dist: float = player_position.distance_to(center_pos)
	# Approximate chunk linear extent on the sphere surface.
	var angular_size: float = (PI * 0.5) / float(1 << lod)
	var chunk_extent_m: float = angular_size * planet_radius_m
	# Split when the player is within ~2 chunk extents and below max LOD.
	if lod < max_lod and dist < chunk_extent_m * 2.0:
		_refine_face_quadtree(face, lod + 1, cx * 2 + 0, cy * 2 + 0, player_position, out)
		_refine_face_quadtree(face, lod + 1, cx * 2 + 1, cy * 2 + 0, player_position, out)
		_refine_face_quadtree(face, lod + 1, cx * 2 + 0, cy * 2 + 1, player_position, out)
		_refine_face_quadtree(face, lod + 1, cx * 2 + 1, cy * 2 + 1, player_position, out)
	else:
		out.append({"face": face, "x": cx, "y": cy, "lod": lod})

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
		remove_child(handle.node)
		handle.node.queue_free()
	_chunks.erase(key)
	chunk_unloaded.emit(center)

func _invalidate_all_chunks() -> void:
	for key: String in _chunks.keys():
		_unload_chunk(key)
	_pending_generations.clear()

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

# res://scripts/GPUComputeManager.gd
# ==============================================================================
# BioGenesis-X — Reusable GPU Compute Manager (Autoload)
# ==============================================================================
# Centralizes RenderingDevice access and compute-pipeline lifecycle so that
# multiple systems (NeuralRegen, fluid dynamics, terrain erosion, particle
# simulation) can share the same GPU compute infrastructure without each
# re-implementing RenderingDevice boilerplate.
#
#   - Caches the RenderingDevice (fetched once from RenderingServer).
#   - Compiles GLSL SPIR-V shaders into compute pipelines (cached by name).
#   - Creates storage / uniform buffers with full RID tracking for cleanup.
#   - Provides a single dispatch_compute() entry point.
#   - Null-safe: every method returns an empty RID / no-op when no RD exists.
# ==============================================================================

extends Node

# ------------------------------------------------------------------------------
# Internal State
# ------------------------------------------------------------------------------

## Cached RenderingDevice (fetched once from RenderingServer).
var _rendering_device: RenderingDevice = null
## All RIDs allocated through this manager, tracked for bulk cleanup.
var _tracked_rids: Array = []
## Compute pipelines cached by name (shader_name -> RID).
var _pipeline_cache: Dictionary = {}
## Shader RIDs cached by name (shader_name -> RID), needed for uniform sets.
var _shader_cache: Dictionary = {}

# ------------------------------------------------------------------------------
# RenderingDevice Access
# ------------------------------------------------------------------------------

## Returns the cached RenderingDevice, fetching it from RenderingServer on
## first access. Returns null if GPU compute is unavailable (headless mode).
func get_rendering_device() -> RenderingDevice:
	if _rendering_device == null:
		_rendering_device = RenderingServer.get_rendering_device()
	return _rendering_device

## Returns true if a RenderingDevice is available for GPU compute.
func is_available() -> bool:
	return get_rendering_device() != null

# ------------------------------------------------------------------------------
# Pipeline Creation
# ------------------------------------------------------------------------------

## Compiles GLSL SPIR-V (from an RDShaderFile source path or raw GLSL) and
## creates a compute pipeline. Caches the pipeline by shader_name when provided.
## Returns an empty RID if the RD is unavailable or compilation fails.
func create_compute_pipeline(shader_source: String, shader_name: String = "") -> RID:
	var rd: RenderingDevice = get_rendering_device()
	if rd == null:
		return RID()
	# Load the RDShaderFile resource from the given path.
	var shader_file: RDShaderFile = load(shader_source) as RDShaderFile
	if shader_file == null:
		return RID()
	var spirv: RDShaderSPIRV = shader_file.get_spirv()
	if spirv == null:
		return RID()
	var shader_rid: RID = rd.shader_create_from_spirv(spirv)
	if not shader_rid.is_valid():
		return RID()
	_track_rid(shader_rid)
	var pipeline: RID = rd.compute_pipeline_create(shader_rid)
	if not rd.compute_pipeline_is_valid(pipeline):
		rd.free_rid(shader_rid)
		_untrack_rid(shader_rid)
		return RID()
	_track_rid(pipeline)
	if shader_name != "":
		_pipeline_cache[shader_name] = pipeline
		_shader_cache[shader_name] = shader_rid
	return pipeline

## Returns the cached shader RID for a previously created compute pipeline.
func get_shader_rid(shader_name: String) -> RID:
	if _shader_cache.has(shader_name):
		return _shader_cache[shader_name]
	return RID()

# ------------------------------------------------------------------------------
# Buffer Creation
# ------------------------------------------------------------------------------

## Creates a storage buffer of the given size (bytes) initialized with data.
## Returns an empty RID if the RD is unavailable or creation fails.
func create_storage_buffer(data: PackedByteArray, name: String = "") -> RID:
	var rd: RenderingDevice = get_rendering_device()
	if rd == null:
		return RID()
	var buffer: RID = rd.storage_buffer_create(data.size(), data)
	if buffer == RID():
		return RID()
	_track_rid(buffer)
	return buffer

## Creates a uniform buffer of the given size (bytes) initialized with data.
## Returns an empty RID if the RD is unavailable or creation fails.
func create_uniform_buffer(data: PackedByteArray, name: String = "") -> RID:
	var rd: RenderingDevice = get_rendering_device()
	if rd == null:
		return RID()
	var buffer: RID = rd.uniform_buffer_create(data.size(), data)
	if buffer == RID():
		return RID()
	_track_rid(buffer)
	return buffer

# ------------------------------------------------------------------------------
# Buffer Update
# ------------------------------------------------------------------------------

## Updates a region of a buffer with new data starting at offset.
func update_buffer(buffer: RID, offset: int, data: PackedByteArray) -> void:
	var rd: RenderingDevice = get_rendering_device()
	if rd == null:
		return
	if not buffer.is_valid():
		return
	rd.buffer_update(buffer, offset, data.size(), data)

# ------------------------------------------------------------------------------
# Uniform Set Creation
# ------------------------------------------------------------------------------

## Creates a uniform set from an array of RDUniform objects bound to the given
## shader RID at the specified set index. Returns an empty RID on failure.
func create_uniform_set(uniforms: Array, shader_rid: RID, set_index: int) -> RID:
	var rd: RenderingDevice = get_rendering_device()
	if rd == null:
		return RID()
	var uniform_set: RID = rd.uniform_set_create(uniforms, shader_rid, set_index)
	if uniform_set == RID():
		return RID()
	_track_rid(uniform_set)
	return uniform_set

# ------------------------------------------------------------------------------
# Compute Dispatch
# ------------------------------------------------------------------------------

## Runs a compute dispatch on the given pipeline with the given uniform set.
## The workgroup counts (groups_x/y/z) define the dispatch dimensions.
func dispatch_compute(pipeline: RID, uniform_set: RID, groups_x: int, groups_y: int, groups_z: int) -> void:
	var rd: RenderingDevice = get_rendering_device()
	if rd == null:
		return
	if not pipeline.is_valid():
		return
	var cl: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, pipeline)
	rd.compute_list_bind_uniform_set(cl, uniform_set, 0)
	rd.compute_list_dispatch(cl, groups_x, groups_y, groups_z)
	rd.compute_list_end()

# ------------------------------------------------------------------------------
# RID Cleanup
# ------------------------------------------------------------------------------

## Frees a single tracked RID and removes it from the tracking list.
func free_rid(rid: RID) -> void:
	var rd: RenderingDevice = get_rendering_device()
	if rd == null:
		return
	if not rid.is_valid():
		return
	rd.free_rid(rid)
	_untrack_rid(rid)

## Frees all tracked RIDs allocated through this manager.
func free_all() -> void:
	var rd: RenderingDevice = get_rendering_device()
	if rd == null:
		_tracked_rids.clear()
		_pipeline_cache.clear()
		_shader_cache.clear()
		return
	for rid in _tracked_rids:
		if rid is RID and rid.is_valid():
			rd.free_rid(rid)
	_tracked_rids.clear()
	_pipeline_cache.clear()
	_shader_cache.clear()

func _exit_tree() -> void:
	free_all()

# ------------------------------------------------------------------------------
# Internal Tracking
# ------------------------------------------------------------------------------

## Adds a RID to the tracking list.
func _track_rid(rid: RID) -> void:
	_tracked_rids.append(rid)

## Removes a RID from the tracking list (does not free it).
func _untrack_rid(rid: RID) -> void:
	_tracked_rids.erase(rid)

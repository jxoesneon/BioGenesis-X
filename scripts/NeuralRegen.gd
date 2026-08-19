# res://scripts/NeuralRegen.gd
# ==============================================================================
# BioGenesis-X — NeuralRegen GPU Compute Self-Healing System (Autoload)
# ==============================================================================
# Custom-built replacement for the NeuralRegen asset (repo returned 404).
# Provides biological self-healing/regeneration for Void-Fauna living starships:
#
#   1. Hull regeneration  — organic hull slowly knits itself when not under fire.
#   2. Shield regeneration — bio-shield recharges after a post-damage delay.
#   3. Organ healing      — damaged organ nodes recover while at rest.
#   4. GPU compute shader — reaction-diffusion (Gray-Scott) healing simulation
#                           over a damage map, executed on the GPU when available.
#   5. Visual feedback    — bioluminescent regen pulse shader on the ship mesh.
#
# The system is fully headless-safe: the compute shader and visual shader are
# only instantiated when a RenderingDevice is present. In headless/test mode the
# CPU-side regeneration logic still runs so all gameplay tests pass.
# ==============================================================================

extends Node

# ------------------------------------------------------------------------------
# Signals
# ------------------------------------------------------------------------------

## Emitted when hull or organ regeneration begins (after the rest threshold).
signal regeneration_started(component: String)
## Emitted when a component reaches full health / completes a regen cycle.
signal regeneration_complete(component: String)
## Emitted when bio-shield regeneration resumes after the damage delay expires.
signal shield_regen_started
## Emitted when the GPU compute healing pass completes a step.
signal compute_heal_step(completed: bool)

# ------------------------------------------------------------------------------
# Tunable Exposed Parameters
# ------------------------------------------------------------------------------

## Base hull regeneration rate (hull points / second) at full organ health.
@export var hull_regen_rate: float = 1.5
## Base shield regeneration rate (shield points / second) when out of combat.
@export var shield_regen_rate: float = 12.0
## Seconds after taking damage before shield regeneration resumes.
@export var shield_regen_delay: float = 3.0
## Seconds after taking damage before hull regeneration resumes.
@export var hull_regen_delay: float = 5.0
## Base organ healing rate (health points / second) while at rest.
@export var organ_heal_rate: float = 0.8
## Seconds of no damage before the ship is considered "at rest" for organ healing.
@export var rest_threshold: float = 4.0
## Multiplier applied to all regen rates when organ health is low (0 = no regen).
@export var min_organ_health_mult: float = 0.25
## Maximum hull integrity (mirrors FlightController hull ceiling).
@export var max_hull: float = 100.0
## Maximum bio-shield (mirrors FlightController bio_shield_max).
@export var max_shield: float = 100.0

# ------------------------------------------------------------------------------
# Internal State
# ------------------------------------------------------------------------------

## Time since the ship last took damage.
var _time_since_damage: float = 999.0
## Countdown timer for shield regen delay.
var _shield_regen_timer: float = 0.0
## Countdown timer for hull regen delay.
var _hull_regen_timer: float = 0.0
## Whether hull regeneration is currently active.
var _hull_regen_active: bool = false
## Whether shield regeneration is currently active.
var _shield_regen_active: bool = false
## Current regeneration activity intensity [0-1] for the visual shader.
var regen_visual_intensity: float = 0.0
## Cached reference to the active FlightController (player ship).
var _flight_controller: Node = null
## Cached reference to OrganTelemetry autoload.
var _organ_telemetry: Node = null

# ------------------------------------------------------------------------------
# GPU Compute Shader State (reaction-diffusion healing map)
# ------------------------------------------------------------------------------

const _COMPUTE_SHADER_PATH: String = "res://shaders/regen_compute.glsl"
const _REGEN_SHADER_PATH: String = "res://shaders/bio_regen.gdshader"
const _GRID_SIZE: int = 64  # 64x64 damage map grid

var _rendering_device: RenderingDevice = null
var _compute_pipeline: RID = RID()
var _compute_shader_rid: RID = RID()
var _uniform_set: RID = RID()
var _buffer_damage: RID = RID()   # Current damage map (R=damage, G=heal_chemical)
var _buffer_next: RID = RID()     # Next-frame damage map
var _buffer_params: RID = RID()   # Simulation parameters
var _compute_available: bool = false
var _compute_step_accumulator: float = 0.0
const _COMPUTE_STEP_INTERVAL: float = 0.1  # 10 Hz GPU sim updates

# Visual regen shader material (available for external overlay application).
var _regen_material: ShaderMaterial = null

# Damage map CPU mirror (for headless fallback & testing).
var _damage_map: PackedFloat32Array = PackedFloat32Array()
var _heal_map: PackedFloat32Array = PackedFloat32Array()

# ------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------

func _ready() -> void:
	_damage_map.resize(_GRID_SIZE * _GRID_SIZE)
	_heal_map.resize(_GRID_SIZE * _GRID_SIZE)
	_damage_map.fill(0.0)
	_heal_map.fill(1.0)  # Healthy tissue produces heal chemical
	_init_compute_shader()
	_init_visual_shader()

func _exit_tree() -> void:
	_free_gpu_resources()

## Frees all GPU RIDs to prevent resource leaks on exit or scene transition.
func _free_gpu_resources() -> void:
	if _rendering_device == null:
		return
	if _uniform_set.is_valid():
		_rendering_device.free_rid(_uniform_set)
		_uniform_set = RID()
	if _buffer_params.is_valid():
		_rendering_device.free_rid(_buffer_params)
		_buffer_params = RID()
	if _buffer_next.is_valid():
		_rendering_device.free_rid(_buffer_next)
		_buffer_next = RID()
	if _buffer_damage.is_valid():
		_rendering_device.free_rid(_buffer_damage)
		_buffer_damage = RID()
	if _compute_pipeline.is_valid():
		_rendering_device.free_rid(_compute_pipeline)
		_compute_pipeline = RID()
	if _compute_shader_rid.is_valid():
		_rendering_device.free_rid(_compute_shader_rid)
		_compute_shader_rid = RID()
	_compute_available = false

func _process(delta: float) -> void:
	# Guard against running during scene teardown after _exit_tree freed resources.
	if not is_inside_tree():
		return
	_time_since_damage += delta

	# Decay the visual pulse intensity over time.
	regen_visual_intensity = move_toward(regen_visual_intensity, 0.0, delta * 0.8)
	if is_instance_valid(_regen_material):
		_regen_material.set_shader_parameter("regen_intensity", regen_visual_intensity)

	# Run the GPU compute healing step on a throttled interval.
	if _compute_available:
		_compute_step_accumulator += delta
		if _compute_step_accumulator >= _COMPUTE_STEP_INTERVAL:
			_compute_step_accumulator = 0.0
			_run_compute_step()
	else:
		# CPU fallback: simplified diffusion of the damage map.
		_cpu_heal_step(delta)

# ------------------------------------------------------------------------------
# Public API — called by FlightController
# ------------------------------------------------------------------------------

## Called by FlightController.take_damage() whenever the ship is hit.
func on_damage_taken(amount: float) -> void:
	_time_since_damage = 0.0
	_shield_regen_timer = shield_regen_delay
	_hull_regen_timer = hull_regen_delay
	# Inject damage into the compute damage map (clustered around center).
	_inject_damage_into_map(amount)
	# Spike the visual regen pulse (damage flash → red-orange).
	regen_visual_intensity = clampf(regen_visual_intensity + amount / 50.0, 0.0, 1.0)
	if _regen_material != null:
		_regen_material.set_shader_parameter("damage_flash", clampf(amount / 40.0, 0.0, 1.0))
	# Cancel active regen states.
	if _hull_regen_active:
		_hull_regen_active = false
	if _shield_regen_active:
		_shield_regen_active = false
	# Damage interrupts all organ healing — notify OrganTelemetry so the HUD
	# clears the healing indicators immediately.
	if _organ_telemetry == null:
		_organ_telemetry = _get_organ_telemetry()
	if _organ_telemetry != null and _organ_telemetry.has_method("clear_all_organ_healing"):
		_organ_telemetry.clear_all_organ_healing()

## Called by FlightController._process() each frame to drive regeneration.
## The FlightController is passed so NeuralRegen can read/write hull & shield.
func process_regeneration(delta: float, fc: Node = null) -> void:
	if fc == null:
		fc = _get_flight_controller()
	if fc == null:
		return
	_flight_controller = fc

	# Tick delay timers.
	if _shield_regen_timer > 0.0:
		_shield_regen_timer = maxf(0.0, _shield_regen_timer - delta)
	if _hull_regen_timer > 0.0:
		_hull_regen_timer = maxf(0.0, _hull_regen_timer - delta)

	var organ_mult: float = _get_organ_health_multiplier()

	# --- Shield regeneration ---
	var shield: float = float(fc.get("bio_shield"))
	var shield_max: float = float(fc.get("bio_shield_max"))
	if shield < shield_max and _shield_regen_timer <= 0.0:
		if not _shield_regen_active:
			_shield_regen_active = true
			shield_regen_started.emit()
		var regen_amount: float = shield_regen_rate * organ_mult * delta
		var new_shield: float = minf(shield_max, shield + regen_amount)
		fc.set("bio_shield", new_shield)
		regen_visual_intensity = maxf(regen_visual_intensity, 0.25)
		if new_shield >= shield_max:
			_shield_regen_active = false
			regeneration_complete.emit("bio_shield")
	else:
		_shield_regen_active = false

	# --- Hull regeneration ---
	var hull: float = float(fc.get("hull_integrity"))
	if hull < max_hull and _hull_regen_timer <= 0.0:
		if not _hull_regen_active:
			_hull_regen_active = true
			regeneration_started.emit("hull")
		var regen_amount: float = hull_regen_rate * organ_mult * delta
		var new_hull: float = minf(max_hull, hull + regen_amount)
		fc.set("hull_integrity", new_hull)
		regen_visual_intensity = maxf(regen_visual_intensity, 0.35)
		if new_hull >= max_hull:
			_hull_regen_active = false
			regeneration_complete.emit("hull")
	else:
		_hull_regen_active = false

	# --- Organ healing (at rest) ---
	if _time_since_damage >= rest_threshold:
		_heal_organs(delta, organ_mult)

	# Update the visual shader intensity (material is applied on-demand, not
	# auto-overlaid, to preserve the ship's existing bioluminescence shader).
	_update_visual_shader()

## Returns a normalized [0-1] overall regeneration activity level for HUD use.
func get_regen_activity() -> float:
	return clampf(regen_visual_intensity, 0.0, 1.0)

## Returns true if hull regeneration is currently active.
func is_hull_regen_active() -> bool:
	return _hull_regen_active

## Returns true if shield regeneration is currently active.
func is_shield_regen_active() -> bool:
	return _shield_regen_active

## Returns the CPU-mirrored damage map (for testing / debugging).
func get_damage_map() -> PackedFloat32Array:
	return _damage_map

## Returns the CPU-mirrored heal-chemical map (for testing / debugging).
func get_heal_map() -> PackedFloat32Array:
	return _heal_map

## Returns true if the GPU compute shader is available and running.
func is_compute_available() -> bool:
	return _compute_available

## Manually injects damage into the damage map at a grid cell (for testing).
func inject_damage_at(cell_x: int, cell_y: int, amount: float) -> void:
	if cell_x < 0 or cell_x >= _GRID_SIZE or cell_y < 0 or cell_y >= _GRID_SIZE:
		return
	var idx: int = cell_y * _GRID_SIZE + cell_x
	_damage_map[idx] = clampf(_damage_map[idx] + amount, 0.0, 1.0)
	_heal_map[idx] = maxf(0.0, _heal_map[idx] - amount * 0.5)

# ------------------------------------------------------------------------------
# Organ Health Integration
# ------------------------------------------------------------------------------

## Computes a multiplier [min_organ_health_mult, 1.0] based on average organ
## health from OrganTelemetry. Healthier organs → faster regeneration. Uses
## OrganTelemetry.get_organ_health_multiplier() (which reads the BioManager
## organ topology) when available, falling back to the neural_sync_rate proxy.
func _get_organ_health_multiplier() -> float:
	if _organ_telemetry == null:
		_organ_telemetry = _get_organ_telemetry()
	if _organ_telemetry == null:
		return 1.0  # No telemetry → assume healthy
	# Prefer the dedicated organ-health multiplier (reads BioManager topology).
	if _organ_telemetry.has_method("get_organ_health_multiplier"):
		var raw: float = float(_organ_telemetry.get_organ_health_multiplier())
		# Map 0..1 into [min_organ_health_mult, 1.0] so low-health organs still
		# allow a minimum of regen rather than zeroing it out entirely.
		return clampf(lerp(min_organ_health_mult, 1.0, raw), min_organ_health_mult, 1.0)
	# Fallback: neural sync rate proxy (95-100% = healthy).
	var sync: float = 1.0
	if _organ_telemetry.has_method("get_telemetry_snapshot"):
		var snap: Dictionary = _organ_telemetry.get_telemetry_snapshot()
		sync = float(snap.get("neural_sync_rate", 98.4)) / 100.0
	var mult: float = clampf((sync - 0.945) / (0.999 - 0.945), min_organ_health_mult, 1.0)
	return mult

## Heals damaged organ nodes in the BioManager topology while at rest.
func _heal_organs(delta: float, organ_mult: float) -> void:
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree) or not ml.root:
		return
	var bm: Node = ml.root.get_node_or_null("BioManager")
	if bm == null or not bm.has_method("get_ship_config"):
		return
	var cfg: Dictionary = bm.get_ship_config()
	if not cfg.has("organ_node_topology"):
		return
	var topology: Dictionary = cfg["organ_node_topology"]
	var healed_any: bool = false
	# Resolve OrganTelemetry for per-organ healing state tracking + signals.
	if _organ_telemetry == null:
		_organ_telemetry = _get_organ_telemetry()
	for pipeline_id in topology:
		var pipeline: Dictionary = topology[pipeline_id]
		if not pipeline.has("nodes"):
			continue
		var nodes: Array = pipeline["nodes"]
		for node in nodes:
			var organ_id: String = str(node.get("id", "organ"))
			var health: float = float(node.get("health", 100.0))
			if health < 100.0:
				var new_health: float = minf(100.0, health + organ_heal_rate * organ_mult * delta)
				node["health"] = new_health
				healed_any = true
				# Notify OrganTelemetry that this organ is actively healing.
				if _organ_telemetry != null and _organ_telemetry.has_method("set_organ_healing"):
					_organ_telemetry.set_organ_healing(organ_id, true)
				if new_health >= 100.0:
					regeneration_complete.emit(organ_id)
					# Organ fully healed — stop healing state.
					if _organ_telemetry != null and _organ_telemetry.has_method("set_organ_healing"):
						_organ_telemetry.set_organ_healing(organ_id, false)
			else:
				# Organ at full health — ensure healing state is cleared.
				if _organ_telemetry != null and _organ_telemetry.has_method("set_organ_healing"):
					_organ_telemetry.set_organ_healing(organ_id, false)
	if healed_any:
		regen_visual_intensity = maxf(regen_visual_intensity, 0.2)

# ------------------------------------------------------------------------------
# GPU Compute Shader (Reaction-Diffusion Healing)
# ------------------------------------------------------------------------------

## Attempts to initialize the GPU compute shader. Falls back gracefully if
## no RenderingDevice is available (headless mode).
func _init_compute_shader() -> void:
	_rendering_device = RenderingServer.get_rendering_device()
	if _rendering_device == null:
		_compute_available = false
		return
	# Load the GLSL compute shader as an RDShaderFile resource (same pattern as
	# PlanetTerrainGenerator.gd).
	var shader_file: RDShaderFile = load(_COMPUTE_SHADER_PATH) as RDShaderFile
	if shader_file == null:
		_compute_available = false
		return
	var spirv: RDShaderSPIRV = shader_file.get_spirv()
	if spirv == null:
		_compute_available = false
		return
	_compute_shader_rid = _rendering_device.shader_create_from_spirv(spirv)
	if not _compute_shader_rid.is_valid():
		_compute_available = false
		return
	_compute_pipeline = _rendering_device.compute_pipeline_create(_compute_shader_rid)
	if not _rendering_device.compute_pipeline_is_valid(_compute_pipeline):
		_compute_available = false
		return
	# Allocate buffers: damage map + heal map (interleaved) + params.
	var cell_count: int = _GRID_SIZE * _GRID_SIZE
	# Each cell: vec2 (damage, heal_chemical) = 8 bytes. Two buffers (current/next).
	var map_bytes: int = cell_count * 8
	_buffer_damage = _rendering_device.storage_buffer_create(map_bytes)
	_buffer_next = _rendering_device.storage_buffer_create(map_bytes)
	if _buffer_damage == RID() or _buffer_next == RID():
		_compute_available = false
		return
	# Upload initial data to the damage buffer.
	var packed_data: PackedByteArray = _pack_map_to_bytes(_damage_map, _heal_map)
	_rendering_device.buffer_update(_buffer_damage, 0, packed_data.size(), packed_data)
	# Params: feed_rate, kill_rate, diffusion_rate, delta_time (16 bytes).
	var params: PackedFloat32Array = PackedFloat32Array([0.055, 0.062, 1.0, 0.1])
	var params_bytes: PackedByteArray = params.to_byte_array()
	# binding 2 is declared as `uniform SimParams` (std140) in the shader,
	# so we must create a UniformBuffer — not a StorageBuffer — for it.
	_buffer_params = _rendering_device.uniform_buffer_create(params_bytes.size(), params_bytes)
	# Build uniform set: binding 0 = damage, 1 = next, 2 = params.
	_uniform_set = _create_uniform_set(_buffer_damage, _buffer_next, _buffer_params)
	_compute_available = true

## Creates the uniform set for the compute shader with the given buffer IDs.
func _create_uniform_set(buf_damage: RID, buf_next: RID, buf_params: RID) -> RID:
	var uniforms: Array[RDUniform] = []
	var u_damage := RDUniform.new()
	u_damage.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_damage.binding = 0
	u_damage.add_id(buf_damage)
	uniforms.append(u_damage)
	var u_next := RDUniform.new()
	u_next.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_next.binding = 1
	u_next.add_id(buf_next)
	uniforms.append(u_next)
	var u_params := RDUniform.new()
	u_params.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u_params.binding = 2
	u_params.add_id(buf_params)
	uniforms.append(u_params)
	return _rendering_device.uniform_set_create(uniforms, _compute_shader_rid, 0)

## Runs one GPU compute step of the reaction-diffusion healing simulation.
func _run_compute_step() -> void:
	if not _compute_available or _rendering_device == null:
		return
	if not _rendering_device.compute_pipeline_is_valid(_compute_pipeline):
		return
	# Dispatch: 64x64 grid / 8x8 workgroup = 8x8 groups.
	@warning_ignore("integer_division")
	var groups_x: int = _GRID_SIZE / 8
	@warning_ignore("integer_division")
	var groups_y: int = _GRID_SIZE / 8
	var cl: int = _rendering_device.compute_list_begin()
	_rendering_device.compute_list_bind_compute_pipeline(cl, _compute_pipeline)
	_rendering_device.compute_list_bind_uniform_set(cl, _uniform_set, 0)
	_rendering_device.compute_list_dispatch(cl, groups_x, groups_y, 1)
	_rendering_device.compute_list_end()
	# Swap buffers: next becomes current for the next step.
	var tmp: RID = _buffer_damage
	_buffer_damage = _buffer_next
	_buffer_next = tmp
	# Rebuild uniform set with swapped buffers.
	_uniform_set = _create_uniform_set(_buffer_damage, _buffer_next, _buffer_params)
	compute_heal_step.emit(true)

## CPU fallback healing step (simplified diffusion). Used in headless mode.
func _cpu_heal_step(delta: float) -> void:
	var dt: float = minf(delta, 0.1)
	var diffusion: float = 0.2
	# Simple diffusion: each cell averages with neighbors, heal chemical reduces damage.
	var new_damage := _damage_map.duplicate()
	var new_heal := _heal_map.duplicate()
	for y in range(_GRID_SIZE):
		for x in range(_GRID_SIZE):
			var idx: int = y * _GRID_SIZE + x
			# Sample 4-neighbors with wraparound.
			var left: int = (x - 1 + _GRID_SIZE) % _GRID_SIZE + y * _GRID_SIZE
			var right: int = (x + 1) % _GRID_SIZE + y * _GRID_SIZE
			var up: int = idx - _GRID_SIZE if y > 0 else (_GRID_SIZE - 1) * _GRID_SIZE + x
			var down: int = idx + _GRID_SIZE if y < _GRID_SIZE - 1 else x
			var avg_dmg: float = (_damage_map[left] + _damage_map[right] + _damage_map[up] + _damage_map[down]) * 0.25
			var avg_heal: float = (_heal_map[left] + _heal_map[right] + _heal_map[up] + _heal_map[down]) * 0.25
			# Diffusion.
			new_damage[idx] = _damage_map[idx] + (avg_dmg - _damage_map[idx]) * diffusion * dt * 10.0
			new_heal[idx] = _heal_map[idx] + (avg_heal - _heal_map[idx]) * diffusion * dt * 10.0
			# Reaction: heal chemical reduces damage, damage consumes heal chemical.
			var reaction: float = new_heal[idx] * new_damage[idx] * 0.5 * dt * 10.0
			new_damage[idx] = maxf(0.0, new_damage[idx] - reaction)
			new_heal[idx] = maxf(0.0, new_heal[idx] - reaction * 0.3)
			# Heal chemical slowly regenerates in healthy tissue.
			if new_damage[idx] < 0.1:
				new_heal[idx] = minf(1.0, new_heal[idx] + 0.05 * dt * 10.0)
	_damage_map = new_damage
	_heal_map = new_heal

## Injects damage into the center of the damage map (simulates a hit).
func _inject_damage_into_map(amount: float) -> void:
	@warning_ignore("integer_division")
	var cx: int = _GRID_SIZE / 2
	@warning_ignore("integer_division")
	var cy: int = _GRID_SIZE / 2
	var radius: int = 3
	var dmg: float = clampf(amount / 50.0, 0.1, 1.0)
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x: int = cx + dx
			var y: int = cy + dy
			if x < 0 or x >= _GRID_SIZE or y < 0 or y >= _GRID_SIZE:
				continue
			var dist: float = sqrt(float(dx * dx + dy * dy))
			if dist > float(radius):
				continue
			var falloff: float = 1.0 - dist / float(radius)
			var idx: int = y * _GRID_SIZE + x
			_damage_map[idx] = clampf(_damage_map[idx] + dmg * falloff, 0.0, 1.0)
			_heal_map[idx] = maxf(0.0, _heal_map[idx] - dmg * falloff * 0.5)

## Packs the damage and heal maps into a byte array for GPU upload (vec2 per cell).
func _pack_map_to_bytes(damage: PackedFloat32Array, heal: PackedFloat32Array) -> PackedByteArray:
	var interleaved: PackedFloat32Array = PackedFloat32Array()
	interleaved.resize(damage.size() * 2)
	for i in range(damage.size()):
		interleaved[i * 2] = damage[i]
		interleaved[i * 2 + 1] = heal[i]
	return interleaved.to_byte_array()

# ------------------------------------------------------------------------------
# Visual Regen Shader
# ------------------------------------------------------------------------------

## Loads and prepares the bioluminescent regen visual shader material.
func _init_visual_shader() -> void:
	var shader_res: Shader = load(_REGEN_SHADER_PATH) as Shader
	if shader_res == null:
		return
	_regen_material = ShaderMaterial.new()
	_regen_material.shader = shader_res
	_regen_material.set_shader_parameter("regen_intensity", 0.0)
	_regen_material.set_shader_parameter("damage_flash", 0.0)

## Updates the visual shader uniforms. The material is NOT auto-applied to the
## ship mesh to avoid clobbering the existing bioluminescence shader. Call
## get_regen_material() to retrieve the material and apply it manually if desired.
func _update_visual_shader() -> void:
	if _regen_material == null:
		return
	_regen_material.set_shader_parameter("regen_intensity", regen_visual_intensity)
	# Decay the damage flash over time.
	var flash: float = float(_regen_material.get_shader_parameter("damage_flash"))
	flash = maxf(0.0, flash - 0.5 * get_process_delta_time())
	_regen_material.set_shader_parameter("damage_flash", flash)

## Returns the regen ShaderMaterial for external application (e.g. as an overlay
## pass on a secondary mesh). Does not modify the ship's primary material.
func get_regen_material() -> ShaderMaterial:
	return _regen_material

# ------------------------------------------------------------------------------
# Helper Lookups
# ------------------------------------------------------------------------------

## Finds the active FlightController in the scene tree.
func _get_flight_controller() -> Node:
	if _flight_controller != null and is_instance_valid(_flight_controller):
		return _flight_controller
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree) or not ml.root:
		return null
	var tree: SceneTree = ml as SceneTree
	var nodes: Array = tree.get_nodes_in_group("flight_controller")
	if nodes.size() > 0:
		_flight_controller = nodes[0]
		return _flight_controller
	# Fallback: search by class name.
	for child in ml.root.get_children():
		if child is FlightController:
			_flight_controller = child
			return _flight_controller
	return null

## Finds the OrganTelemetry autoload.
func _get_organ_telemetry() -> Node:
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree) or not ml.root:
		return null
	return ml.root.get_node_or_null("OrganTelemetry")

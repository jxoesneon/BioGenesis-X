# res://scripts/GameplayDistributionManager.gd
# ==============================================================================
# BioGenesis-X Engine Architecture
# GameplayDistributionManager.gd — Noise-Driven Gameplay Element Distribution
# ==============================================================================
# Bridges SystemNoiseField channels to actual gameplay systems:
#   - RESOURCES → Asteroid composition (mineral-rich vs barren)
#   - ENEMIES   → Void-Fauna drone spawn density and aggression
#   - ANOMALIES → Anomaly marker spawn points (derelicts, ruins, signals)
#   - HAZARDS   → Hazard zone creation (radiation, gravity wells)
#
# This manager queries the SystemNoiseField at world positions and applies
# the values to gameplay objects. It does NOT modify astrophysical formulas.
#
# The manager runs after the AsteroidField and UniverseManager have finished
# their initialization, then tags/adjusts gameplay elements accordingly.
# ==============================================================================

extends Node

const SystemNoiseFieldClass: GDScript = preload("res://scripts/SystemNoiseField.gd")

var _noise_field: Node = null
var _asteroid_field: Node = null
var _chunk_stream_manager: Node = null
var _is_distributed: bool = false

# --- Resource composition tiers ---
enum ResourceTier {
	BARREN,       # 0.0 - 0.3 — low-value, common
	CARBONACEOUS, # 0.3 - 0.5 — carbon, organics
	SILICATE,     # 0.5 - 0.7 — silicon, metals
	METALLIC,     # 0.7 - 0.85 — rare metals, heavy elements
	EXOTIC,       # 0.85 - 1.0 — void-matter, bio-crystals
}

const RESOURCE_TIER_NAMES: Dictionary = {
	ResourceTier.BARREN: "barren",
	ResourceTier.CARBONACEOUS: "carbonaceous",
	ResourceTier.SILICATE: "silicate",
	ResourceTier.METALLIC: "metallic",
	ResourceTier.EXOTIC: "exotic",
}

const RESOURCE_TIER_COLORS: Dictionary = {
	ResourceTier.BARREN: Color(0.4, 0.4, 0.4),
	ResourceTier.CARBONACEOUS: Color(0.3, 0.25, 0.2),
	ResourceTier.SILICATE: Color(0.6, 0.5, 0.3),
	ResourceTier.METALLIC: Color(0.7, 0.7, 0.8),
	ResourceTier.EXOTIC: Color(0.5, 0.2, 0.8),
}

# --- Anomaly types ---
enum AnomalyType {
	DERELICT_SHIP,
	ANCIENT_RUIN,
	DISTRESS_SIGNAL,
	VOID_RIFT,
	ENERGY_ANOMALY,
}

# --- Hazard types ---
enum HazardType {
	RADIATION_ZONE,
	GRAVITY_WELL,
	SOLAR_FLARE_PATH,
	DEBRIS_STORM,
}

signal distribution_complete(stats: Dictionary)

func _ready() -> void:
	# Wait for the scene tree to be ready before finding nodes
	call_deferred("_initialize")

func _initialize() -> void:
	# Find sibling nodes under SpaceFlight
	_noise_field = get_node_or_null("../SystemNoiseField")
	_asteroid_field = get_node_or_null("../AsteroidField")
	_chunk_stream_manager = get_node_or_null("../ChunkStreamManager")

	# Connect to noise field generation
	if _noise_field and _noise_field.has_signal("grids_generated"):
		_noise_field.grids_generated.connect(_on_grids_ready)

	# If noise is already generated, distribute now
	if _noise_field and _noise_field.is_generated():
		_on_grids_ready()

func _on_grids_ready() -> void:
	if _is_distributed:
		return
	# Wait one frame to ensure asteroid field is fully populated
	call_deferred("_distribute_gameplay_elements")

func _distribute_gameplay_elements() -> void:
	if _is_distributed:
		return
	if not _noise_field or not _noise_field.is_generated():
		return

	var stats: Dictionary = {
		"asteroids_tagged": 0,
		"drones_adjusted": 0,
		"anomalies_spawned": 0,
		"hazards_spawned": 0,
		"streaming_delegated": false,
	}

	# 1. Tag existing AsteroidField asteroids with resource composition
	# (AsteroidField is NOT modified — we only tag its existing output)
	_tag_asteroid_resources(stats)

	# 2. Adjust existing AsteroidField drones with aggression
	_adjust_drone_density(stats)

	# 3. ChunkStreamManager handles all streaming (anomalies, hazards,
	#    streamed asteroids, streamed enemies) via dual-scale chunks.
	#    It runs continuously in _process, not as a one-shot.
	if _chunk_stream_manager:
		stats["streaming_delegated"] = true
		print("[GameplayDistribution] Streaming delegated to ChunkStreamManager")

	_is_distributed = true
	distribution_complete.emit(stats)
	print("[GameplayDistribution] Initial distribution complete: %s" % str(stats))

# --- Resource distribution: tag asteroids with composition ---
func _tag_asteroid_resources(stats: Dictionary) -> void:
	if not _asteroid_field:
		return

	var asteroids: Array = _asteroid_field.get("instantiated_asteroids")
	if asteroids.is_empty():
		return

	for body in asteroids:
		if not is_instance_valid(body):
			continue

		var world_pos: Vector3 = body.global_position
		var resource_value: float = _noise_field.sample_channel(SystemNoiseFieldClass.Channel.RESOURCES, world_pos)
		var tier: int = _resource_value_to_tier(resource_value)

		# Tag the asteroid with its resource composition
		body.set_meta("resource_tier", tier)
		body.set_meta("resource_tier_name", RESOURCE_TIER_NAMES[tier])
		body.set_meta("resource_value", resource_value)

		# Adjust visual tint based on resource tier
		_apply_resource_tint(body, tier)

		stats["asteroids_tagged"] = int(stats["asteroids_tagged"]) + 1

func _resource_value_to_tier(value: float) -> int:
	if value < 0.3:
		return ResourceTier.BARREN
	elif value < 0.5:
		return ResourceTier.CARBONACEOUS
	elif value < 0.7:
		return ResourceTier.SILICATE
	elif value < 0.85:
		return ResourceTier.METALLIC
	else:
		return ResourceTier.EXOTIC

func _apply_resource_tint(body: Node3D, tier: int) -> void:
	var mesh_inst: MeshInstance3D = null
	# Search for MeshInstance3D in children
	for child in body.get_children():
		if child is MeshInstance3D:
			mesh_inst = child
			break
	if not mesh_inst:
		return

	var mat := mesh_inst.material_override as StandardMaterial3D
	if not mat:
		mat = StandardMaterial3D.new()
		mesh_inst.material_override = mat

	# Slightly tint the asteroid based on resource tier
	var tint: Color = RESOURCE_TIER_COLORS[tier]
	var original_albedo: Color = mat.albedo_color if mat.albedo_color != Color.BLACK else Color(0.5, 0.5, 0.5)
	mat.albedo_color = original_albedo.lerp(tint, 0.3)

	# Exotic asteroids get emission glow
	if tier == ResourceTier.EXOTIC:
		mat.emission_enabled = true
		mat.emission = tint
		mat.emission_energy_multiplier = 0.5

# --- Enemy distribution: adjust drone density and aggression ---
func _adjust_drone_density(stats: Dictionary) -> void:
	if not _asteroid_field:
		return

	var drones: Array = _asteroid_field.get("target_drones")
	if drones.is_empty():
		return

	for drone in drones:
		if not is_instance_valid(drone):
			continue

		var world_pos: Vector3 = drone.global_position
		var enemy_value: float = _noise_field.sample_channel(SystemNoiseFieldClass.Channel.ENEMIES, world_pos)

		# Tag drone with aggression level based on enemy noise
		drone.set_meta("enemy_density", enemy_value)
		drone.set_meta("aggression", enemy_value)  # 0.0 = passive, 1.0 = hostile

		# Adjust drone emission intensity based on aggression
		var mesh_inst: MeshInstance3D = null
		for child in drone.get_children():
			if child is MeshInstance3D:
				mesh_inst = child
				break
		if mesh_inst:
			var mat := mesh_inst.material_override as StandardMaterial3D
			if mat and mat.emission_enabled:
				mat.emission_energy_multiplier = 1.0 + enemy_value * 2.0

		stats["drones_adjusted"] = int(stats["drones_adjusted"]) + 1

# --- Anomaly and Hazard spawning is now handled by ChunkStreamManager ---
# The old one-shot _spawn_anomalies() and _spawn_hazards() methods have been
# removed. ChunkStreamManager streams anomalies and hazards per-chunk based
# on noise density, with proper spawn/despawn lifecycle around the player.
# This avoids spawning elements at 50 AU that are invisible/useless when the
# ship is at 1 AU, and enables predictive loading along the ship's flight path.

# --- Public API ---
## Returns the resource tier at a given world position.
func get_resource_tier_at(world_pos_m: Vector3) -> int:
	if not _noise_field or not _noise_field.is_generated():
		return ResourceTier.BARREN
	var value: float = _noise_field.sample_channel(SystemNoiseFieldClass.Channel.RESOURCES, world_pos_m)
	return _resource_value_to_tier(value)

## Returns the enemy density at a given world position [0.0, 1.0].
func get_enemy_density_at(world_pos_m: Vector3) -> float:
	if not _noise_field or not _noise_field.is_generated():
		return 0.0
	return _noise_field.sample_channel(SystemNoiseFieldClass.Channel.ENEMIES, world_pos_m)

## Returns the anomaly probability at a given world position [0.0, 1.0].
func get_anomaly_probability_at(world_pos_m: Vector3) -> float:
	if not _noise_field or not _noise_field.is_generated():
		return 0.0
	return _noise_field.sample_channel(SystemNoiseFieldClass.Channel.ANOMALIES, world_pos_m)

## Returns the hazard intensity at a given world position [0.0, 1.0].
func get_hazard_intensity_at(world_pos_m: Vector3) -> float:
	if not _noise_field or not _noise_field.is_generated():
		return 0.0
	return _noise_field.sample_channel(SystemNoiseFieldClass.Channel.HAZARDS, world_pos_m)

## Returns all gameplay distribution values at a position.
func get_distribution_at(world_pos_m: Vector3) -> Dictionary:
	return {
		"resource_tier": get_resource_tier_at(world_pos_m),
		"resource_tier_name": RESOURCE_TIER_NAMES[get_resource_tier_at(world_pos_m)],
		"enemy_density": get_enemy_density_at(world_pos_m),
		"anomaly_probability": get_anomaly_probability_at(world_pos_m),
		"hazard_intensity": get_hazard_intensity_at(world_pos_m),
	}

func is_distributed() -> bool:
	return _is_distributed

## Returns streaming stats from ChunkStreamManager (active chunks, queue sizes).
func get_streaming_stats() -> Dictionary:
	if _chunk_stream_manager and _chunk_stream_manager.has_method("get_streaming_stats"):
		return _chunk_stream_manager.get_streaming_stats()
	return {}

## Returns total streamed element counts across all active chunks.
func get_total_streamed_elements() -> Dictionary:
	if _chunk_stream_manager and _chunk_stream_manager.has_method("get_total_streamed_elements"):
		return _chunk_stream_manager.get_total_streamed_elements()
	return {"asteroids": 0, "enemies": 0, "anomalies": 0, "hazards": 0}

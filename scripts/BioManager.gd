@tool
# class_name BioManager (removed due to autoload conflict)
extends Node

# ==============================================================================
# BioGenesis-X Engine Architecture
# BioManager.gd - Central Ship Configuration & Game State Autoload Singleton
# ==============================================================================
# Manages active game modes (BUILDER, FLIGHT, INSPECTOR), maintains current
# living starship parameters (archetype, seed, length, segment count, armor,
# chitin density, eye pods, organ topology), and provides standard preset
# archetypes according to BioGenesis-X lore (LORE.md).
# ==============================================================================


## Signal emitted when any aspect of the ship configuration is modified
signal ship_configuration_changed(config: Dictionary)

## Signal emitted when the global game state / mode changes
signal game_mode_changed(new_mode: int)

## Signal emitted when an individual organ node state or property is updated
signal organ_state_updated(organ_id: String, state_data: Dictionary)

## Game Modes supported by BioGenesis-X
enum GameMode {
	BUILDER_MODE,   ## Interactive 3D biological ship synthesis & organ node editing
	FLIGHT_MODE,    ## Active flight simulation, propulsion, & combat telemetry
	INSPECTOR_MODE  ## Deep anatomical breakdown, X-ray vascular viewing & telemetry inspection
}

## Canonical Standard Ship Archetypes from LORE.md
const ARCHETYPE_APEX_HIVE_LEVIATHAN: String = "Apex Hive Leviathan"
const ARCHETYPE_NEURO_SPORE_INTERCEPTOR: String = "Neuro-Spore Interceptor"
const ARCHETYPE_CHITINOUS_VOID_HARVESTER: String = "Chitinous Void Harvester"
const ARCHETYPE_ABYSSAL_SYMBIONT_FRIGATE: String = "Abyssal Symbiont Frigate"
const ARCHETYPE_VIRAL_COLONY_CARRIER: String = "Viral Colony Carrier"

## Current Active Game Mode
var current_mode: GameMode = GameMode.BUILDER_MODE

## Active Ship Configuration Dictionary
var current_ship_config: Dictionary = {}

## Catalog of Standard Ship Archetype Definitions
var archetype_catalog: Dictionary = {}

func _init() -> void:
	_initialize_archetype_catalog()
	# Default to Apex Hive Leviathan archetype on boot
	load_archetype(ARCHETYPE_APEX_HIVE_LEVIATHAN)

# ------------------------------------------------------------------------------
# Game State Management
# ------------------------------------------------------------------------------

func set_game_mode(new_mode: GameMode) -> void:
	if current_mode != new_mode:
		current_mode = new_mode as GameMode
		game_mode_changed.emit(current_mode)

func get_game_mode() -> GameMode:
	return current_mode

func get_game_mode_name() -> String:
	match current_mode:
		GameMode.BUILDER_MODE: return "BUILDER_MODE"
		GameMode.FLIGHT_MODE: return "FLIGHT_MODE"
		GameMode.INSPECTOR_MODE: return "INSPECTOR_MODE"
		_: return "UNKNOWN_MODE"

# ------------------------------------------------------------------------------
# Archetype & Configuration Management
# ------------------------------------------------------------------------------

## Initialize preset archetypes based on BioGenesis LORE.md & ORGAN_SYSTEMS.md
func _initialize_archetype_catalog() -> void:
	archetype_catalog = {
		ARCHETYPE_APEX_HIVE_LEVIATHAN: {
			"archetype_id": "apex_hive_leviathan",
			"archetype_name": ARCHETYPE_APEX_HIVE_LEVIATHAN,
			"classification": "Abyssocetus apex",
			"class_type": "Titan-Class Habitat Carrier",
			"seed": 10928374,
			"length": 28.0,
			"segment_count": 16,
			"armor_thickness": 4.5,
			"chitin_density": 0.95,
			"eye_pod_count": 8,
			"tentacle_pairs": 10,
			"bio_thrusters": 5,
			"cross_section": "pentamerous",
			"description": "Deep-space mobile colony carrier housing up to 50 human crew members. Features thick pentamerous radial carapace, massive vascular conduits, and heavy dorsal spiracles.",
			"organ_node_topology": _build_default_organ_topology("apex_hive_leviathan")
		},
		ARCHETYPE_NEURO_SPORE_INTERCEPTOR: {
			"archetype_id": "neuro_spore_interceptor",
			"archetype_name": ARCHETYPE_NEURO_SPORE_INTERCEPTOR,
			"classification": "Neuro-Spore interceptor",
			"class_type": "Vanguard-Class Strike Symbiont",
			"seed": 4829103,
			"length": 8.0,
			"segment_count": 4,
			"armor_thickness": 1.2,
			"chitin_density": 0.65,
			"eye_pod_count": 4,
			"tentacle_pairs": 2,
			"bio_thrusters": 2,
			"cross_section": "streamlined",
			"description": "High-speed, agile strike symbiont bonded with a single fighter pilot via direct graphene neuro-plug. 2.8 spinal arch, electro-receptive eye pods.",
			"organ_node_topology": _build_default_organ_topology("neuro_spore_interceptor")
		},
		ARCHETYPE_CHITINOUS_VOID_HARVESTER: {
			"archetype_id": "chitinous_void_harvester",
			"archetype_name": ARCHETYPE_CHITINOUS_VOID_HARVESTER,
			"classification": "Harvester chitinous",
			"class_type": "Heavy Ore Mining Dreadnought",
			"seed": 8837192,
			"length": 18.0,
			"segment_count": 10,
			"armor_thickness": 5.0,
			"chitin_density": 1.0,
			"eye_pod_count": 6,
			"tentacle_pairs": 4,
			"bio_thrusters": 3,
			"cross_section": "star",
			"spore_sacs": 12,
			"description": "Mineral-processing dreadnought designed to crush and refine asteroid belt minerals. 100% plate coverage, 16 plate overlap density, star-flanged shell.",
			"organ_node_topology": _build_default_organ_topology("chitinous_void_harvester")
		},
		ARCHETYPE_ABYSSAL_SYMBIONT_FRIGATE: {
			"archetype_id": "abyssal_symbiont_frigate",
			"archetype_name": ARCHETYPE_ABYSSAL_SYMBIONT_FRIGATE,
			"classification": "Symbiont abyssalis",
			"class_type": "Stealth Reconnaissance Vessel",
			"seed": 2938471,
			"length": 14.0,
			"segment_count": 8,
			"armor_thickness": 2.2,
			"chitin_density": 0.75,
			"eye_pod_count": 12,
			"tentacle_pairs": 12,
			"bio_thrusters": 4,
			"cross_section": "elliptical",
			"description": "Deep-space stealth infiltrator utilizing active chromatophore camouflage and thermal spiracle dampening. High fluid wobble (2.8), bioluminescent sensory tendrils.",
			"organ_node_topology": _build_default_organ_topology("abyssal_symbiont_frigate")
		},
		ARCHETYPE_VIRAL_COLONY_CARRIER: {
			"archetype_id": "viral_colony_carrier",
			"archetype_name": ARCHETYPE_VIRAL_COLONY_CARRIER,
			"classification": "Colony carrier-spore",
			"class_type": "Brood-Mother Fleet Support",
			"seed": 7712940,
			"length": 15.0,
			"segment_count": 12,
			"armor_thickness": 3.0,
			"chitin_density": 0.80,
			"eye_pod_count": 6,
			"tentacle_pairs": 6,
			"bio_thrusters": 4,
			"cross_section": "circular",
			"spore_sacs": 12,
			"description": "Mobile repair and bio-drone carrier deploying defensive spore clouds and nanite repair swarms to damaged fleet vessels.",
			"organ_node_topology": _build_default_organ_topology("viral_colony_carrier")
		}
	}

## Load an archetype by its name, id, or classification
func load_archetype(archetype_key: String) -> bool:
	var target_archetype: Dictionary = {}
	if archetype_catalog.has(archetype_key):
		target_archetype = archetype_catalog[archetype_key]
	else:
		for key in archetype_catalog:
			var arch: Dictionary = archetype_catalog[key]
			if arch.get("archetype_id") == archetype_key or arch.get("classification") == archetype_key:
				target_archetype = arch
				break

	if target_archetype.is_empty():
		push_error("BioManager: Archetype '%s' not found." % archetype_key)
		return false

	current_ship_config = target_archetype.duplicate(true)
	ship_configuration_changed.emit(current_ship_config)
	return true

## Update a specific ship configuration parameter
func update_ship_parameter(param_name: String, value: Variant) -> void:
	current_ship_config[param_name] = value
	ship_configuration_changed.emit(current_ship_config)

## Update an individual organ node in the topology
func update_organ_state(organ_id: String, state_data: Dictionary) -> void:
	if organ_id.is_empty():
		return
	if not current_ship_config.has("organ_node_topology"):
		current_ship_config["organ_node_topology"] = {}
	
	var topology: Dictionary = current_ship_config["organ_node_topology"]
	if not topology.has(organ_id):
		topology[organ_id] = {}
	
	for key in state_data:
		topology[organ_id][key] = state_data[key]
	
	organ_state_updated.emit(organ_id, topology[organ_id])
	ship_configuration_changed.emit(current_ship_config)

## Randomize ship seed and re-emit configuration
func randomize_seed(new_seed: int = -1) -> int:
	if new_seed < 0:
		new_seed = randi()
	current_ship_config["seed"] = new_seed
	ship_configuration_changed.emit(current_ship_config)
	return new_seed

## Get current ship configuration
func get_ship_config() -> Dictionary:
	return current_ship_config

## Get available archetype names
func get_archetype_names() -> Array[String]:
	var names: Array[String] = []
	for key in archetype_catalog:
		names.append(key)
	return names

## Reset configuration to default (Apex Hive Leviathan)
func reset_to_default_archetype() -> void:
	load_archetype(ARCHETYPE_APEX_HIVE_LEVIATHAN)

## Serialization support for saving ship designs
func serialize_config() -> Dictionary:
	return current_ship_config.duplicate(true)

## Deserialization support for loading ship designs
func deserialize_config(data: Dictionary) -> bool:
	if data.is_empty() or not data.has("archetype_name"):
		push_error("BioManager: Invalid configuration data for deserialization.")
		return false
	current_ship_config = data.duplicate(true)
	ship_configuration_changed.emit(current_ship_config)
	return true

# ------------------------------------------------------------------------------
# Default Closed-Loop Organ Topology Constructor (ORGAN_SYSTEMS.md)
# ------------------------------------------------------------------------------

func _build_default_organ_topology(_archetype_id: String) -> Dictionary:
	return {
		"pipelines": {
			"bio_plasma": {
				"name": "Bio-Plasma Power & Propulsion",
				"nodes": [
					{
						"id": "plasma_gland",
						"name": "Bio-Plasma Electrolysis Gland",
						"role": "GENERATION",
						"position": Vector3(0, -1.2, 4.0),
						"layer": "organs",
						"output": "850 kW Electrolysis",
						"downstream": ["plasma_bladder"]
					},
					{
						"id": "plasma_bladder",
						"name": "Muscular Plasma Bladder",
						"role": "STORAGE",
						"position": Vector3(0, -0.8, 1.5),
						"layer": "organs",
						"output": "140 Bar Fuel Buffer",
						"upstream": "plasma_gland",
						"downstream": ["plasma_trunk"]
					},
					{
						"id": "plasma_trunk",
						"name": "Primary Plasma Trunk Highway",
						"role": "DISTRIBUTION",
						"position": Vector3(0, -0.5, -2.0),
						"layer": "vascular",
						"output": "2,400 L/min Flow",
						"upstream": "plasma_bladder",
						"downstream": ["caudal_manifold", "disruptor_glands"]
					},
					{
						"id": "caudal_manifold",
						"name": "Caudal Manifold Trunk",
						"role": "DISTRIBUTION",
						"position": Vector3(0, 0, -6.5),
						"layer": "vascular",
						"output": "Hydrodynamic Splitting",
						"upstream": "plasma_trunk",
						"downstream": ["siphon_nozzles"]
					},
					{
						"id": "siphon_nozzles",
						"name": "Bio-Plasma Vent Nozzles",
						"role": "EFFECTOR",
						"position": Vector3(0, -0.4, -9.0),
						"layer": "exoskeleton",
						"output": "1,700 kN Hydro-Pulse",
						"upstream": "caudal_manifold"
					},
					{
						"id": "disruptor_glands",
						"name": "Bio-Plasma Disruptor Glands",
						"role": "EFFECTOR",
						"position": Vector3(0, 1.2, 3.5),
						"layer": "organs",
						"output": "450 MW Thermal Burst",
						"upstream": "plasma_trunk"
					}
				]
			},
			"hemolymph": {
				"name": "Hemolymph Circulation & Thermal Regulation",
				"nodes": [
					{
						"id": "heart_core",
						"name": "Aorta Central Heart Core",
						"role": "GENERATION",
						"position": Vector3(0, 0.2, 0.5),
						"layer": "vascular",
						"output": "68 BPM Systolic Stroke",
						"downstream": ["hemolymph_atrium"]
					},
					{
						"id": "hemolymph_atrium",
						"name": "Hemolymph Atrium Reservoir",
						"role": "STORAGE",
						"position": Vector3(0, 0.6, 1.2),
						"layer": "vascular",
						"output": "18.5 Bar Antifreeze Buffer",
						"upstream": "heart_core",
						"downstream": ["central_aorta"]
					},
					{
						"id": "central_aorta",
						"name": "Central Aorta Highway",
						"role": "DISTRIBUTION",
						"position": Vector3(0, 0, 0),
						"layer": "vascular",
						"output": "Murray's Law Branching",
						"upstream": "hemolymph_atrium",
						"downstream": ["flank_arteries", "spiracle_vents"]
					},
					{
						"id": "flank_arteries",
						"name": "Luminescent Flank Arteries",
						"role": "DISTRIBUTION",
						"position": Vector3(1.5, 0, 0),
						"layer": "vascular",
						"output": "Capillary Delivery",
						"upstream": "central_aorta"
					},
					{
						"id": "spiracle_vents",
						"name": "Respiratory Spiracle Vents",
						"role": "EFFECTOR",
						"position": Vector3(0, 1.5, 0),
						"layer": "exoskeleton",
						"output": "820 W/m² IR Radiation",
						"upstream": "central_aorta"
					}
				]
			},
			"nervous": {
				"name": "Nervous & Cybernetic Synaptic System",
				"nodes": [
					{
						"id": "ganglion_brain",
						"name": "Primary Ganglion Brain Core",
						"role": "GENERATION",
						"position": Vector3(0, 0.8, 5.5),
						"layer": "organs",
						"output": "98.4% Synaptic Coherence",
						"downstream": ["neurolink_pod"]
					},
					{
						"id": "neurolink_pod",
						"name": "Human Neuro-Link Interface",
						"role": "INTERFACE",
						"position": Vector3(0, 0.4, 4.8),
						"layer": "organs",
						"output": "Graphene Fiber Plug",
						"upstream": "ganglion_brain",
						"downstream": ["spinal_axon"]
					},
					{
						"id": "spinal_axon",
						"name": "Spinal Axon Cord Highway",
						"role": "DISTRIBUTION",
						"position": Vector3(0, 0.5, 0),
						"layer": "muscular",
						"output": "120 m/s Nerve Impulse",
						"upstream": "neurolink_pod",
						"downstream": ["eye_pods", "muscle_tendons"]
					},
					{
						"id": "eye_pods",
						"name": "Ocular Beam Stalk Pods",
						"role": "EFFECTOR",
						"position": Vector3(0, 1.0, 6.2),
						"layer": "exoskeleton",
						"output": "Multispectral Vision",
						"upstream": "spinal_axon"
					},
					{
						"id": "muscle_tendons",
						"name": "Biomechanical Muscle Tendons",
						"role": "EFFECTOR",
						"position": Vector3(1.0, 0, 0),
						"layer": "muscular",
						"output": "FABRIK IK Actuation",
						"upstream": "spinal_axon"
					}
				]
			},
			"life_support": {
				"name": "Endosymbiotic Life Support & Metabolism",
				"nodes": [
					{
						"id": "ingestion_gizzard",
						"name": "Comet Ingestion Gizzard",
						"role": "GENERATION",
						"position": Vector3(0, -1.5, 6.0),
						"layer": "organs",
						"output": "12.5 kg/min Mineral Ore",
						"downstream": ["biomoss_bed"]
					},
					{
						"id": "biomoss_bed",
						"name": "Photosynthetic Bio-Moss Bed",
						"role": "STORAGE",
						"position": Vector3(0, 0, 0),
						"layer": "organs",
						"output": "420 L/min O₂ Output",
						"upstream": "ingestion_gizzard",
						"downstream": ["habitat_chambers"]
					},
					{
						"id": "habitat_chambers",
						"name": "Human Habitat Chambers",
						"role": "SOCIETAL",
						"position": Vector3(0, 0, 0),
						"layer": "organs",
						"output": "1.0 atm / 12 Crew",
						"upstream": "biomoss_bed",
						"downstream": ["stomata_valves"]
					},
					{
						"id": "stomata_valves",
						"name": "Cyber-Airlock Stomata Valves",
						"role": "EFFECTOR",
						"position": Vector3(1.2, 0.2, 0),
						"layer": "exoskeleton",
						"output": "Pressure Seal (0-1 atm)",
						"upstream": "habitat_chambers"
					}
				]
			},
			"armor_defense": {
				"name": "Exoskeleton, Armor & Shield Defense",
				"nodes": [
					{
						"id": "bone_vertebrae",
						"name": "Chitinous Bone Vertebrae",
						"role": "STRUCTURAL",
						"position": Vector3(0, 0, 0),
						"layer": "exoskeleton",
						"output": "C3 NURBS Structural Load",
						"downstream": ["carapace_plates"]
					},
					{
						"id": "carapace_plates",
						"name": "Overlapping Carapace Plates",
						"role": "DEFENSE",
						"position": Vector3(0, 0, 0),
						"layer": "exoskeleton",
						"output": "85 Gy/hr Gamma Shield",
						"upstream": "bone_vertebrae",
						"downstream": ["nanite_bed"]
					},
					{
						"id": "nanite_bed",
						"name": "Bio-Nanite Coagulation Bed",
						"role": "REPAIR",
						"position": Vector3(0, 0, 0),
						"layer": "vascular",
						"output": "1.2 m³/s Breach Clotting",
						"upstream": "carapace_plates",
						"downstream": ["shield_emitters"]
					},
					{
						"id": "shield_emitters",
						"name": "Repulsion Shield Emitters",
						"role": "EFFECTOR",
						"position": Vector3(0, 0, 0),
						"layer": "exoskeleton",
						"output": "450 MW Kinetic Deflection",
						"upstream": "nanite_bed"
					}
				]
			}
		}
	}

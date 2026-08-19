# res://scripts/ShaderRegistry.gd
# ==============================================================================
# BioGenesis-X — Cherry-Picked Shader Registry
# ==============================================================================
# Central registry for all shaders cherry-picked & adapted from the
# godotshaders.com library (via the Godot Shaders Library addon) for the
# BioGenesis-X biopunk aesthetic.
#
# All shaders here are MIT or CC0 licensed (verified per-shader) and adapted
# with organic/biological color palettes (cyan-green, magenta, amber) and
# procedural noise-based patterns. They are floating-origin safe (model-space
# or UV + TIME only — no world-space dependency).
#
# Usage:
#   var shader := ShaderRegistry.get_shader("bio_impact_burn")
#   var mat := ShaderMaterial.new()
#   mat.shader = shader
# ==============================================================================
class_name ShaderRegistry
extends RefCounted

# ------------------------------------------------------------------------------
# Shader IDs — use these strings with get_shader()
# ------------------------------------------------------------------------------
const ID_IMPACT_BURN := "bio_impact_burn"           # Weapon impact scorch + energy discharge
const ID_WORMHOLE_VORTEX := "bio_wormhole_vortex"   # Swirling energy vortex (wormhole/jump point)
const ID_SCAN_HOLOGRAM := "bio_scan_hologram"       # Bio-scan holographic grid overlay
const ID_DISSOLVE := "bio_dissolve"                 # Organic disintegration / teleport dissolve
const ID_CONTAINMENT_FIELD := "bio_containment_field" # Containment / stasis energy field
const ID_CAUSTIC_FLUID := "bio_caustic_fluid"       # Organic fluid caustics (amniotic/bio-pools)

# ------------------------------------------------------------------------------
# Preloaded shader table (loaded once at first access)
# ------------------------------------------------------------------------------
static var _shaders: Dictionary = {}
static var _initialized: bool = false

# ------------------------------------------------------------------------------
# Preload paths — keyed by shader id
# ------------------------------------------------------------------------------
const _PATHS := {
	ID_IMPACT_BURN: "res://shaders/bio_impact_burn.gdshader",
	ID_WORMHOLE_VORTEX: "res://shaders/bio_wormhole_vortex.gdshader",
	ID_SCAN_HOLOGRAM: "res://shaders/bio_scan_hologram.gdshader",
	ID_DISSOLVE: "res://shaders/bio_dissolve.gdshader",
	ID_CONTAINMENT_FIELD: "res://shaders/bio_containment_field.gdshader",
	ID_CAUSTIC_FLUID: "res://shaders/bio_caustic_fluid.gdshader",
}

# ------------------------------------------------------------------------------
# Human-readable documentation for each shader
# ------------------------------------------------------------------------------
const _DOCS := {
	ID_IMPACT_BURN:
		"Weapon impact scorch + radial energy discharge ripple on ship hull. " +
		"Driven by impact_point (object space), impact_age, impact_strength. " +
		"COMBAT USEFUL — stack per-hit via decals or multi-pass.",
	ID_WORMHOLE_VORTEX:
		"Swirling bioluminescent energy vortex for wormholes / jump points. " +
		"Multi-arm spiral with procedural turbulence + inward radial flow. " +
		"SPACE USEFUL — apply to a disc/cylinder mesh face-on to camera.",
	ID_SCAN_HOLOGRAM:
		"Bio-scan holographic overlay: sweeping scan line + organic wireframe " +
		"grid + fresnel rim with flicker. Cyan-green diagnostic aesthetic. " +
		"BIOPUNK USEFUL — organ inspector, bio-scan targeting, diagnostics.",
	ID_DISSOLVE:
		"Organic disintegration / teleport dissolve. Noise-driven threshold " +
		"with glowing bioluminescent edge (emerald -> magenta). " +
		"COMBAT/BIOPUNK USEFUL — ship death, spore dispersal, teleport.",
	ID_CONTAINMENT_FIELD:
		"Containment / stasis energy field bubble. Hexagonal voronoi mesh + " +
		"organic flow pulse + fresnel rim + intersection highlight. " +
		"BIOPUNK USEFUL — containment bubbles, stasis fields, bio-barriers.",
	ID_CAUSTIC_FLUID:
		"Animated organic fluid caustics for amniotic tanks / bio-fluid " +
		"surfaces / bio-oceans. Layered procedural caustic light + fresnel. " +
		"BIOPUNK USEFUL — amniotic tanks, bio-reactors, planet bio-oceans.",
}

# ------------------------------------------------------------------------------
# Initialize the registry (loads & caches all shaders). Called once lazily.
# ------------------------------------------------------------------------------
static func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_shaders.clear()
	for id in _PATHS.keys():
		var path: String = _PATHS[id]
		var shader: Shader = load(path) as Shader
		if shader == null:
			push_warning("ShaderRegistry: failed to load shader '%s' from %s" % [id, path])
			continue
		_shaders[id] = shader

# ------------------------------------------------------------------------------
# Retrieve a shader by id. Returns null (with a warning) if not found.
# ------------------------------------------------------------------------------
static func get_shader(id: String) -> Shader:
	_ensure_initialized()
	if not _shaders.has(id):
		push_warning("ShaderRegistry: unknown shader id '%s'" % id)
		return null
	return _shaders[id]

# ------------------------------------------------------------------------------
# List all registered shader ids.
# ------------------------------------------------------------------------------
static func get_shader_ids() -> PackedStringArray:
	_ensure_initialized()
	var ids: PackedStringArray = PackedStringArray()
	for id in _shaders.keys():
		ids.append(id)
	return ids

# ------------------------------------------------------------------------------
# Get the documentation string for a shader id.
# ------------------------------------------------------------------------------
static func get_shader_doc(id: String) -> String:
	if _DOCS.has(id):
		return _DOCS[id]
	return ""

# ------------------------------------------------------------------------------
# Preload all shaders now (call at startup to warm the cache).
# ------------------------------------------------------------------------------
static func preload_all() -> void:
	_ensure_initialized()

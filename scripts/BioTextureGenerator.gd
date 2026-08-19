@tool
class_name BioTextureGenerator
extends RefCounted

# ============================================================================
# BIO TEXTURE GENERATOR - BioGenesis-X
# Pumilio Studios - Runtime Procedural Biopunk Texture Synthesis
# ============================================================================
# Standalone procedural texture generator using Godot's native Image API
# (FastNoiseLite, gradients, cellular patterns). Generates organic biopunk
# surface textures at runtime for ships, planets, and asteroids.
#
# The Procedural Texture Designer addon (addons/procedural_textures/) is an
# editor-only EditorPlugin that builds shader node-graphs for the editor
# designer UI. Its runtime render path (ShaderTexture) depends on the render
# loop (`await RenderingServer.frame_post_draw`) and programmatic node-graph
# construction, which is too editor-coupled and complex for reliable runtime
# use. This class therefore provides a lightweight, synchronous, cache-backed
# alternative that works identically in @tool and exported builds.
# ============================================================================

const DEFAULT_TEXTURE_SIZE: int = 512

# Planet archetype constants (mirror ProceduralPlanet.gd archetype indices).
const PLANET_MOLTEN: int = 0
const PLANET_METALLIC_BARREN: int = 1
const PLANET_TERRAN_OCEANIC: int = 3
const PLANET_ICE_WORLD: int = 4
const PLANET_JOVIAN_GAS_GIANT: int = 5
const PLANET_ICE_GIANT: int = 6
const PLANET_RADIOTROPHIC_BIO: int = 7

# Asteroid archetype constants (mirror ProceduralAsteroidMesh.AsteroidArchetype).
const ASTEROID_CARBONACEOUS: int = 0
const ASTEROID_SILICATE: int = 1
const ASTEROID_CONTACT_BINARY: int = 2
const ASTEROID_RUBBLE_REGOLITH: int = 3
const ASTEROID_JAGGED_SHRAPNEL: int = 4

# Texture cache: key = "method:seed:args:size" -> ImageTexture
# Bounded LRU cache — evicts oldest entries when MAX_CACHE_SIZE is reached.
const MAX_CACHE_SIZE: int = 64
static var _cache: Dictionary = {}
static var _cache_order: Array[String] = []
static var _default_size: int = DEFAULT_TEXTURE_SIZE
static var _profiles: Dictionary = {}


# =============================================================================
# PUBLIC API
# =============================================================================

## Generates an organic biopunk hull texture (veins, bioluminescent spots,
## plate boundaries). The result doubles as an albedo accent map and an
## emission map: bioluminescent veins/spots are encoded bright so that when
## bound to the emission sampler they glow, while the dark organic base tints
## the albedo blend without over-emitting.
static func generate_hull_texture(seed_value: int, damage_level: float = 0.0, size: int = -1) -> ImageTexture:
	var sz := _resolve_size(size)
	var profile := _make_hull_profile(seed_value, clampf(damage_level, 0.0, 1.0), sz)
	return generate_from_profile(profile)


## Generates a planet-specific surface texture for the given archetype index
## (see PLANET_* constants). Produces a color/albedo map tailored to the
## celestial body type (molten lava cracks, barren regolith, oceanic landmass,
## ice fissures, gas-giant bands, radiotrophic bio-veins, etc.).
static func generate_planet_texture(archetype: int, seed_value: int, size: int = -1) -> ImageTexture:
	var sz := _resolve_size(size)
	var profile := _make_planet_profile(archetype, seed_value, sz)
	return generate_from_profile(profile)


## Generates an asteroid surface texture (rocky / metallic / crystalline) for
## the given asteroid type index (see ASTEROID_* constants). Produces an albedo
## map with mineral variation, regolith grain, and bio-crystal veins.
static func generate_asteroid_texture(type: int, seed_value: int, size: int = -1) -> ImageTexture:
	var sz := _resolve_size(size)
	var profile := _make_asteroid_profile(type, seed_value, sz)
	return generate_from_profile(profile)


## Generates a texture from a data-driven TextureProfile. The profile supplies
## the palette, noise parameters, and layer flags; this method builds the
## image, caches it by the profile's cache key, and returns an ImageTexture.
static func generate_from_profile(profile: TextureProfile) -> ImageTexture:
	if profile == null:
		return null
	var key := profile.get_cache_key()
	if _cache.has(key):
		return _cache[key]
	var img: Image
	match profile.texture_type:
		"planet":
			img = _build_planet_image(profile)
		"asteroid":
			img = _build_asteroid_image(profile)
		_:
			img = _build_hull_image(profile)
	var tex := ImageTexture.create_from_image(img)
	_cache_insert(key, tex)
	return tex


## Registers a TextureProfile in the profile registry under its profile_id.
static func register_profile(profile: TextureProfile) -> void:
	if profile == null or profile.profile_id.is_empty():
		return
	_profiles[profile.profile_id] = profile


## Returns a previously registered TextureProfile by id, or null if absent.
static func get_profile(id: String) -> TextureProfile:
	return _profiles.get(id, null) as TextureProfile


## Clears the entire texture cache. Call under memory pressure or on scene
## transitions where procedural assets are no longer needed.
static func clear_cache() -> void:
	_cache.clear()
	_cache_order.clear()


## Clears a single cached entry by its logical key components.
static func clear_cached_hull(seed_value: int, damage_level: float = 0.0, size: int = -1) -> void:
	var sz := _resolve_size(size)
	var key := "hull:%d:%.4f:%d" % [seed_value, clampf(damage_level, 0.0, 1.0), sz]
	_cache.erase(key)
	_cache_order.erase(key)


static func clear_cached_planet(archetype: int, seed_value: int, size: int = -1) -> void:
	var sz := _resolve_size(size)
	var key := "planet:%d:%d:%d" % [archetype, seed_value, sz]
	_cache.erase(key)
	_cache_order.erase(key)


static func clear_cached_asteroid(type: int, seed_value: int, size: int = -1) -> void:
	var sz := _resolve_size(size)
	var key := "asteroid:%d:%d:%d" % [type, seed_value, sz]
	_cache.erase(key)
	_cache_order.erase(key)


## Clears the texture cache if its size exceeds half of MAX_CACHE_SIZE.
static func clear_cache_if_needed() -> void:
	if _cache.size() > MAX_CACHE_SIZE / 2:
		_cache.clear()
		_cache_order.clear()


## Sets the default texture resolution for subsequent generations.
static func set_default_size(size: int) -> void:
	_default_size = maxi(32, size)


## Returns the current default texture resolution.
static func get_default_size() -> int:
	return _default_size


## Returns the number of textures currently held in the cache.
static func get_cache_count() -> int:
	return _cache.size()


# =============================================================================
# INTERNAL HELPERS
# =============================================================================

static func _resolve_size(size: int) -> int:
	return size if size > 0 else _default_size


## Inserts a texture into the cache with LRU eviction. When the cache exceeds
## MAX_CACHE_SIZE, the oldest entry is removed.
static func _cache_insert(key: String, tex: ImageTexture) -> void:
	if _cache.has(key):
		# Move to end (most recently used).
		_cache_order.erase(key)
	else:
		# Evict oldest if at capacity.
		while _cache_order.size() >= MAX_CACHE_SIZE:
			var oldest: String = _cache_order.pop_front()
			_cache.erase(oldest)
	_cache[key] = tex
	_cache_order.append(key)


static func _make_noise(seed_value: int, type: int, freq: float, octaves: int = 4, fractal: int = FastNoiseLite.FRACTAL_FBM) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	@warning_ignore("int_as_enum_without_cast")
	n.noise_type = type
	n.frequency = freq
	@warning_ignore("int_as_enum_without_cast")
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	return n


static func _make_cellular(seed_value: int, freq: float, return_type: int = FastNoiseLite.RETURN_DISTANCE) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	@warning_ignore("int_as_enum_without_cast")
	n.cellular_return_type = return_type
	n.frequency = freq
	return n


static func _pcolor(arr: Array[Color], idx: int, fallback: Color) -> Color:
	if idx >= 0 and idx < arr.size():
		return arr[idx]
	return fallback


# -----------------------------------------------------------------------------
# PROFILE FACTORIES
# -----------------------------------------------------------------------------

static func _make_hull_profile(seed_value: int, damage_level: float, sz: int) -> TextureProfile:
	var p := TextureProfile.new()
	p.profile_id = "hull:%d:%.4f:%d" % [seed_value, damage_level, sz]
	p.texture_type = "hull"
	p.archetype_id = 0
	p.seed_value = seed_value
	p.size = sz
	p.damage_level = damage_level
	p.frequency = 0.008
	p.octaves = 5
	p.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	p.fractal_type = FastNoiseLite.FRACTAL_FBM
	p.base_colors = [Color(0.035, 0.065, 0.055, 1.0)]
	p.mid_colors = [Color(0.10, 0.15, 0.115, 1.0)]
	p.high_colors = [Color(0.0, 0.95, 0.85, 1.0), Color(0.45, 1.0, 0.9, 1.0)]
	p.accent_colors = [Color(0.015, 0.025, 0.02, 1.0), Color(0.012, 0.012, 0.012, 1.0)]
	p.enable_plates = true
	p.enable_veins = true
	p.enable_spots = true
	p.enable_damage = true
	return p


static func _make_planet_profile(archetype: int, seed_value: int, sz: int) -> TextureProfile:
	var p := TextureProfile.new()
	p.profile_id = "planet:%d:%d:%d" % [archetype, seed_value, sz]
	p.texture_type = "planet"
	p.archetype_id = archetype
	p.seed_value = seed_value
	p.size = sz
	p.damage_level = 0.0
	p.frequency = 0.006
	p.octaves = 5
	p.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	p.fractal_type = FastNoiseLite.FRACTAL_FBM
	# Palette per archetype
	p.base_colors = [Color(0.05, 0.05, 0.08, 1.0)]
	p.high_colors = [Color(0.5, 0.5, 0.5, 1.0)]
	p.accent_colors = [Color(1.0, 0.4, 0.1, 1.0)]
	match archetype:
		PLANET_MOLTEN:
			p.base_colors = [Color(0.08, 0.02, 0.0, 1.0)]
			p.high_colors = [Color(0.9, 0.25, 0.05, 1.0)]
			p.accent_colors = [Color(1.0, 0.85, 0.2, 1.0)]
			p.enable_cracks = true
		PLANET_METALLIC_BARREN:
			p.base_colors = [Color(0.12, 0.12, 0.14, 1.0)]
			p.high_colors = [Color(0.45, 0.43, 0.40, 1.0)]
			p.accent_colors = [Color(0.7, 0.6, 0.4, 1.0)]
		PLANET_TERRAN_OCEANIC:
			p.base_colors = [Color(0.02, 0.10, 0.30, 1.0)]
			p.high_colors = [Color(0.18, 0.55, 0.25, 1.0)]
			p.accent_colors = [Color(0.85, 0.78, 0.55, 1.0)]
		PLANET_ICE_WORLD:
			p.base_colors = [Color(0.10, 0.18, 0.28, 1.0)]
			p.high_colors = [Color(0.85, 0.92, 0.98, 1.0)]
			p.accent_colors = [Color(0.6, 0.8, 1.0, 1.0)]
			p.enable_cracks = true
		PLANET_JOVIAN_GAS_GIANT:
			p.base_colors = [Color(0.35, 0.22, 0.12, 1.0)]
			p.high_colors = [Color(0.85, 0.65, 0.40, 1.0)]
			p.accent_colors = [Color(0.95, 0.80, 0.55, 1.0)]
			p.enable_bands = true
		PLANET_ICE_GIANT:
			p.base_colors = [Color(0.10, 0.30, 0.45, 1.0)]
			p.high_colors = [Color(0.55, 0.80, 0.95, 1.0)]
			p.accent_colors = [Color(0.70, 0.90, 1.0, 1.0)]
			p.enable_bands = true
		PLANET_RADIOTROPHIC_BIO:
			p.base_colors = [Color(0.02, 0.08, 0.06, 1.0)]
			p.high_colors = [Color(0.10, 0.35, 0.20, 1.0)]
			p.accent_colors = [Color(0.0, 0.95, 0.70, 1.0)]
			p.enable_veins = true
		_:
			p.base_colors = [Color(0.10, 0.10, 0.12, 1.0)]
			p.high_colors = [Color(0.40, 0.40, 0.42, 1.0)]
			p.accent_colors = [Color(0.6, 0.6, 0.6, 1.0)]
	return p


static func _make_asteroid_profile(type: int, seed_value: int, sz: int) -> TextureProfile:
	var p := TextureProfile.new()
	p.profile_id = "asteroid:%d:%d:%d" % [type, seed_value, sz]
	p.texture_type = "asteroid"
	p.archetype_id = type
	p.seed_value = seed_value
	p.size = sz
	p.damage_level = 0.0
	p.frequency = 0.01
	p.octaves = 5
	p.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	p.fractal_type = FastNoiseLite.FRACTAL_FBM
	# Palette per asteroid type
	p.base_colors = [Color(0.05, 0.05, 0.06, 1.0)]
	p.high_colors = [Color(0.20, 0.20, 0.22, 1.0)]
	p.accent_colors = [Color(0.0, 0.92, 0.78, 1.0)]
	match type:
		ASTEROID_CARBONACEOUS:
			p.base_colors = [Color(0.03, 0.035, 0.045, 1.0)]
			p.high_colors = [Color(0.10, 0.11, 0.13, 1.0)]
			p.accent_colors = [Color(0.0, 0.95, 0.80, 1.0)]
		ASTEROID_SILICATE:
			p.base_colors = [Color(0.10, 0.10, 0.12, 1.0)]
			p.high_colors = [Color(0.30, 0.28, 0.26, 1.0)]
			p.accent_colors = [Color(0.95, 0.40, 0.20, 1.0)]
		ASTEROID_CONTACT_BINARY:
			p.base_colors = [Color(0.06, 0.07, 0.09, 1.0)]
			p.high_colors = [Color(0.16, 0.17, 0.20, 1.0)]
			p.accent_colors = [Color(0.85, 0.20, 0.60, 1.0)]
		ASTEROID_RUBBLE_REGOLITH:
			p.base_colors = [Color(0.08, 0.09, 0.11, 1.0)]
			p.high_colors = [Color(0.22, 0.23, 0.25, 1.0)]
			p.accent_colors = [Color(0.20, 0.80, 1.0, 1.0)]
		ASTEROID_JAGGED_SHRAPNEL:
			p.base_colors = [Color(0.10, 0.11, 0.13, 1.0)]
			p.high_colors = [Color(0.35, 0.36, 0.40, 1.0)]
			p.accent_colors = [Color(1.0, 0.20, 0.40, 1.0)]
		_:
			p.base_colors = [Color(0.07, 0.07, 0.08, 1.0)]
			p.high_colors = [Color(0.20, 0.20, 0.22, 1.0)]
			p.accent_colors = [Color(0.5, 0.5, 0.5, 1.0)]
	p.enable_grain = true
	p.enable_veins = true
	p.enable_craters = true
	return p


# -----------------------------------------------------------------------------
# HULL TEXTURE
# -----------------------------------------------------------------------------

static func _build_hull_image(p: TextureProfile) -> Image:
	var sz := p.size
	var seed_value := p.seed_value
	var damage_level := clampf(p.damage_level, 0.0, 1.0)
	var img := Image.create_empty(sz, sz, false, Image.FORMAT_RGBA8)

	var n_base := _make_noise(seed_value, p.noise_type, p.frequency, p.octaves, p.fractal_type)
	var n_plates := _make_cellular(seed_value ^ 0x5A5A, 0.045, FastNoiseLite.RETURN_DISTANCE)
	var n_veins := _make_noise(seed_value ^ 0xA5A5, FastNoiseLite.TYPE_SIMPLEX, 0.018, 4, FastNoiseLite.FRACTAL_RIDGED)
	var n_spots := _make_cellular(seed_value ^ 0x1234, 0.09, FastNoiseLite.RETURN_CELL_VALUE)
	var n_damage := _make_noise(seed_value ^ 0xDEAD, FastNoiseLite.TYPE_SIMPLEX, 0.06, 3, FastNoiseLite.FRACTAL_RIDGED)

	var bio_color := _pcolor(p.high_colors, 0, Color(0.0, 0.95, 0.85, 1.0))        # bioluminescent cyan-green
	var bio_hot := _pcolor(p.high_colors, 1, Color(0.45, 1.0, 0.9, 1.0))           # brighter vein core
	var chitin_dark := _pcolor(p.base_colors, 0, Color(0.035, 0.065, 0.055, 1.0))
	var chitin_mid := _pcolor(p.mid_colors, 0, Color(0.10, 0.15, 0.115, 1.0))
	var plate_line := _pcolor(p.accent_colors, 0, Color(0.015, 0.025, 0.02, 1.0))
	var scorch_col := _pcolor(p.accent_colors, 1, Color(0.012, 0.012, 0.012, 1.0))

	for y in sz:
		var fy := float(y)
		for x in sz:
			var fx := float(x)

			# 1. Base organic pigmentation (broad melanin variation)
			var b := n_base.get_noise_2d(fx, fy) * 0.5 + 0.5
			var col := chitin_dark.lerp(chitin_mid, b)

			# 2. Plate boundaries (cellular distance edges -> dark seams)
			if p.enable_plates:
				var pd := n_plates.get_noise_2d(fx, fy)
				var edge: float = clamp(abs(pd) * 3.5, 0.0, 1.0)
				col = col.lerp(plate_line, (1.0 - edge) * 0.65)

			# 3. Vascular veins (ridged noise -> bioluminescent filaments)
			if p.enable_veins:
				var v := n_veins.get_noise_2d(fx, fy)
				var vein_mask := pow(clamp(1.0 - abs(v), 0.0, 1.0), 3.0)
				col = col.lerp(bio_color, vein_mask * 0.8)
				# Hot vein cores
				var vein_core := pow(vein_mask, 4.0)
				col = col.lerp(bio_hot, vein_core * 0.6)

			# 4. Bioluminescent spots (cellular cell-value clusters)
			if p.enable_spots:
				var s := n_spots.get_noise_2d(fx, fy) * 0.5 + 0.5
				var spot_mask: float = smoothstep(0.80, 0.96, s)
				col = col.lerp(bio_hot, spot_mask * 0.9)

			# 5. Damage (scorching + scratches) scaled by damage_level
			if p.enable_damage and damage_level > 0.001:
				var d := n_damage.get_noise_2d(fx, fy)
				var scorch := pow(clamp(1.0 - abs(d), 0.0, 1.0), 2.0) * damage_level
				col = col.lerp(scorch_col, scorch * 0.75)
				var scratch: float = smoothstep(0.92, 0.995, abs(d)) * damage_level
				col = col.lerp(scorch_col, scratch * 0.5)

			img.set_pixel(x, y, col)

	img.generate_mipmaps()
	return img


# -----------------------------------------------------------------------------
# PLANET TEXTURE
# -----------------------------------------------------------------------------

static func _build_planet_image(p: TextureProfile) -> Image:
	var sz := p.size
	var seed_value := p.seed_value
	var img := Image.create_empty(sz, sz, false, Image.FORMAT_RGBA8)

	var n_base := _make_noise(seed_value, p.noise_type, p.frequency, p.octaves, p.fractal_type)
	var n_detail := _make_noise(seed_value ^ 0x7777, FastNoiseLite.TYPE_SIMPLEX, 0.03, 4)
	var n_bands := _make_noise(seed_value ^ 0xBEEF, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.004, 3)
	var n_cracks := _make_noise(seed_value ^ 0xC0DE, FastNoiseLite.TYPE_SIMPLEX, 0.02, 4, FastNoiseLite.FRACTAL_RIDGED)
	var n_veins := _make_cellular(seed_value ^ 0x9999, 0.05, FastNoiseLite.RETURN_CELL_VALUE)

	# Palette per archetype
	var col_low := _pcolor(p.base_colors, 0, Color(0.05, 0.05, 0.08, 1.0))
	var col_high := _pcolor(p.high_colors, 0, Color(0.5, 0.5, 0.5, 1.0))
	var accent := _pcolor(p.accent_colors, 0, Color(1.0, 0.4, 0.1, 1.0))

	for y in sz:
		var fy := float(y)
		var band_t := float(y) / float(sz)
		for x in sz:
			var fx := float(x)

			var b := n_base.get_noise_2d(fx, fy) * 0.5 + 0.5
			var det := n_detail.get_noise_2d(fx, fy) * 0.5 + 0.5
			var col := col_low.lerp(col_high, clamp(b * 0.7 + det * 0.3, 0.0, 1.0))

			if p.enable_bands:
				# Horizontal latitudinal storm bands (gas giants)
				var band_noise := n_bands.get_noise_2d(fx * 0.2, fy) * 0.5 + 0.5
				var band: float = smoothstep(0.35, 0.65, sin(band_t * PI * 8.0 + band_noise * 3.0) * 0.5 + 0.5)
				col = col.lerp(accent, band * 0.35)

			if p.enable_cracks:
				var c := n_cracks.get_noise_2d(fx, fy)
				var crack_mask := pow(clamp(1.0 - abs(c), 0.0, 1.0), 4.0)
				col = col.lerp(accent, crack_mask * 0.7)

			if p.enable_veins:
				var v := n_veins.get_noise_2d(fx, fy) * 0.5 + 0.5
				var vein_mask: float = smoothstep(0.78, 0.95, v)
				col = col.lerp(accent, vein_mask * 0.85)

			img.set_pixel(x, y, col)

	img.generate_mipmaps()
	return img


# -----------------------------------------------------------------------------
# ASTEROID TEXTURE
# -----------------------------------------------------------------------------

static func _build_asteroid_image(p: TextureProfile) -> Image:
	var sz := p.size
	var seed_value := p.seed_value
	var img := Image.create_empty(sz, sz, false, Image.FORMAT_RGBA8)

	var n_base := _make_noise(seed_value, p.noise_type, p.frequency, p.octaves, p.fractal_type)
	var n_grain := _make_noise(seed_value ^ 0x4242, FastNoiseLite.TYPE_SIMPLEX, 0.06, 3)
	var n_veins := _make_noise(seed_value ^ 0x8BAD, FastNoiseLite.TYPE_SIMPLEX, 0.025, 4, FastNoiseLite.FRACTAL_RIDGED)
	var n_craters := _make_cellular(seed_value ^ 0xF00D, 0.04, FastNoiseLite.RETURN_DISTANCE)

	# Palette per asteroid type
	var col_low := _pcolor(p.base_colors, 0, Color(0.05, 0.05, 0.06, 1.0))
	var col_high := _pcolor(p.high_colors, 0, Color(0.20, 0.20, 0.22, 1.0))
	var vein_color := _pcolor(p.accent_colors, 0, Color(0.0, 0.92, 0.78, 1.0))
	var metallic := p.archetype_id == ASTEROID_SILICATE
	var crystalline := p.archetype_id == ASTEROID_JAGGED_SHRAPNEL

	for y in sz:
		var fy := float(y)
		for x in sz:
			var fx := float(x)

			var b := n_base.get_noise_2d(fx, fy) * 0.5 + 0.5
			var g := n_grain.get_noise_2d(fx, fy) * 0.5 + 0.5
			var blend: float = b * 0.75
			if p.enable_grain:
				blend += g * 0.25
			var col := col_low.lerp(col_high, clamp(blend, 0.0, 1.0))

			# Mineral crystalline shimmer for metallic/crystalline types
			if metallic:
				var sheen: float = smoothstep(0.55, 0.75, b)
				col = col.lerp(col_high.lightened(0.4), sheen * 0.4)
			if crystalline:
				var facet: float = smoothstep(0.60, 0.80, g)
				col = col.lerp(vein_color.lightened(0.3), facet * 0.3)

			# Bio-crystal veins (ridged noise filaments)
			if p.enable_veins:
				var v := n_veins.get_noise_2d(fx, fy)
				var vein_mask := pow(clamp(1.0 - abs(v), 0.0, 1.0), 3.0)
				col = col.lerp(vein_color, vein_mask * 0.75)

			# Regolith crater darkening (cellular distance)
			if p.enable_craters:
				var cd := n_craters.get_noise_2d(fx, fy)
				var crater: float = clamp(1.0 - abs(cd) * 2.5, 0.0, 1.0)
				col = col.darkened(crater * 0.35)

			img.set_pixel(x, y, col)

	img.generate_mipmaps()
	return img

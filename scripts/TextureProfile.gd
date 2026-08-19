@tool
class_name TextureProfile
extends Resource

@export var profile_id: String = ""
@export var texture_type: String = "hull"
@export var archetype_id: int = 0
@export var seed_value: int = 0
@export var size: int = 512
@export var damage_level: float = 0.0

@export var base_colors: Array[Color] = []
@export var mid_colors: Array[Color] = []
@export var high_colors: Array[Color] = []
@export var accent_colors: Array[Color] = []

@export var frequency: float = 0.008
@export var octaves: int = 5
@export var noise_type: int = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
@export var fractal_type: int = FastNoiseLite.FRACTAL_FBM

@export var enable_veins: bool = false
@export var enable_plates: bool = false
@export var enable_spots: bool = false
@export var enable_damage: bool = false
@export var enable_bands: bool = false
@export var enable_cracks: bool = false
@export var enable_craters: bool = false
@export var enable_grain: bool = false


func get_cache_key() -> String:
	var sz := size if size > 0 else 512
	var dmg := clampf(damage_level, 0.0, 1.0)
	match texture_type:
		"hull":
			return "hull:%d:%.4f:%d" % [seed_value, dmg, sz]
		"planet":
			return "planet:%d:%d:%d" % [archetype_id, seed_value, sz]
		"asteroid":
			return "asteroid:%d:%d:%d" % [archetype_id, seed_value, sz]
		_:
			return "%s:%d:%d:%d:%.4f" % [texture_type, archetype_id, seed_value, sz, dmg]

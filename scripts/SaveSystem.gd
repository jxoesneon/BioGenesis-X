extends Node
class_name SaveSystemManager

const SAVE_FILE_PATH = "user://save_game.json"

var current_save_data: Dictionary = {}

func _ready() -> void:
	load_save()
	if not current_save_data.has("profile_name"):
		create_debug_player()

func create_debug_player() -> void:
	current_save_data = {
		"profile_name": "DEBUGPLAYER",
		"upgrades": {
			"jump_range": 50000.0, # Access to the whole galaxy
			"max_speed": 600.0,
			"forward_thrust_force": 25000000.0,
			"primary_damage": 9999.0, # One shot kill
			"max_heat": 900.0,
			"heat_dissipation_rate": 300.0
		},
		"inventory": {
			"credits": 9999999,
			"bio_matter": 9999
		}
	}
	save_game()

func save_game() -> void:
	var file := FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(current_save_data, "\t"))
		file.close()
		print("SaveSystem: Game saved to ", SAVE_FILE_PATH)
	else:
		print("SaveSystem: Failed to save game!")

func load_save() -> void:
	if FileAccess.file_exists(SAVE_FILE_PATH):
		var file := FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
		if file:
			var content := file.get_as_text()
			var json := JSON.new()
			var err := json.parse(content)
			if err == OK:
				current_save_data = json.data
				print("SaveSystem: Loaded save profile: ", current_save_data.get("profile_name", "Unknown"))
				return
	
	print("SaveSystem: No valid save found.")

func get_upgrade(upgrade_name: String, default_value: float) -> float:
	if current_save_data.has("upgrades") and current_save_data["upgrades"].has(upgrade_name):
		return float(current_save_data["upgrades"][upgrade_name])
	return default_value

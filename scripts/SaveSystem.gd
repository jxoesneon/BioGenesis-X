extends Node
class_name SaveSystemManager

## ============================================================================
## BioGenesis-X Save System
## ----------------------------------------------------------------------------
## Unified save architecture combining the best of three systems:
##   1. Original SaveSystem   — simple JSON player profile (preserved API)
##   2. SaveState addon        — atomic writes, backup rotation, schema migration
##   3. SaverLoader (Voyager)  — procedural node-tree / object-graph persistence
##
## Architecture:
##   - Player profile + galaxy state  → JSON (human-readable, atomic, versioned)
##   - Procedural scene/object graph  → binary .bin via SaverLoader
##
## The JSON envelope stores:
##   schema_version, profile_name, upgrades, inventory, galaxy, procedural_seeds
## The binary file stores the full procedural node tree (SaverLoader format).
##
## Public API (unchanged, backwards compatible):
##   save_game(), load_save(), get_upgrade(), current_save_data
## New API:
##   save_galaxy_state(), load_galaxy_state(), save_procedural_state(),
##   load_procedural_state(), get_galaxy_state(), set_galaxy_state()
## ============================================================================

const SAVE_FILE_PATH := "user://save_game.json"
const PROCEDURAL_FILE_PATH := "user://save_procedural.bin"
const CURRENT_SCHEMA_VERSION := 2
const MAX_BACKUPS := 3

## Emitted just before the save data is serialized to disk. Connected systems
## (e.g. QuestManager) use this to inject their state into current_save_data.
signal about_to_save

# --- SaverLoader integration ---
var _saver_loader: SaverLoader

# --- Migration pipeline (Callable(index) -> mutates Dictionary in place) ---
var _schema_migrations: Array = []

# --- Runtime state ---
var current_save_data: Dictionary = {}

# --- Galaxy state cache (mirrors current_save_data["galaxy"]) ---
var _galaxy_state: Dictionary = {}


func _ready() -> void:
	_saver_loader = SaverLoader.new()
	_register_default_migrations()
	load_save()
	if not current_save_data.has("profile_name"):
		create_debug_player()


# ===========================================================================
# DEFAULT MIGRATIONS
# ===========================================================================

func _register_default_migrations() -> void:
	# v1 -> v2: add galaxy + procedural_seeds sections to legacy saves.
	_schema_migrations = [
		Callable(self, "_migrate_v1_to_v2"),
	]


## v1 saves only had: profile_name, upgrades, inventory.
## v2 adds: galaxy {}, procedural_seeds {}.
func _migrate_v1_to_v2(inner: Dictionary) -> void:
	if not inner.has("galaxy"):
		inner["galaxy"] = _default_galaxy_state()
	if not inner.has("procedural_seeds"):
		inner["procedural_seeds"] = {
			"planet_seeds": [],
			"planet_seed_map": {},
			"explored_systems": [],
		}
	else:
		var ps: Dictionary = inner["procedural_seeds"]
		if not ps.has("planet_seed_map"):
			ps["planet_seed_map"] = {}
			inner["procedural_seeds"] = ps


# ===========================================================================
# DEBUG / DEFAULT DATA
# ===========================================================================

func create_debug_player() -> void:
	current_save_data = {
		"schema_version": CURRENT_SCHEMA_VERSION,
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
		},
		"galaxy": _default_galaxy_state(),
		"procedural_seeds": {
			"planet_seeds": [],
			"planet_seed_map": {},
			"explored_systems": [],
		},
		"quest_weaver": {},
	}
	_galaxy_state = current_save_data["galaxy"].duplicate(true)
	save_game()


func _default_galaxy_state() -> Dictionary:
	return {
		"current_system": {},
		"current_system_name": "",
		"visited_systems": [],       # Array of system name Strings
		"discovered_pois": [],       # Array of POI dictionaries {name, system, type}
		"player_position": [0.0, 0.0, 0.0],  # Stored as array for JSON safety
		"player_system_index": 0,
	}


# ===========================================================================
# PUBLIC API — SAVE / LOAD (backwards compatible)
# ===========================================================================

## Save the current player profile + galaxy state to disk atomically.
## Writes to a .tmp file, verifies, rotates backups, then commits via rename.
func save_game() -> void:
	# Sync galaxy cache into save data before writing
	current_save_data["galaxy"] = _galaxy_state.duplicate(true)
	current_save_data["schema_version"] = CURRENT_SCHEMA_VERSION

	# Notify connected systems to inject their state before serialization.
	about_to_save.emit()

	var json_text := JSON.stringify(current_save_data, "\t")
	var bytes := json_text.to_utf8_buffer()

	var err := _write_atomic(SAVE_FILE_PATH, bytes, true)
	if err == OK:
		print("SaveSystem: Game saved atomically to ", SAVE_FILE_PATH)
	else:
		push_error("SaveSystem: Atomic save failed (error %d)!" % err)


## Load the player profile from disk. Runs schema migration if needed.
## Falls back to backup files if the primary save is corrupt.
func load_save() -> void:
	var data: Variant = _read_and_parse(SAVE_FILE_PATH)
	if data == null:
		# Try rotating backups (newest first)
		for i in range(1, MAX_BACKUPS + 1):
			var bak_path := SAVE_FILE_PATH + ".bak" + str(i)
			if FileAccess.file_exists(bak_path):
				print("SaveSystem: Primary save unreadable, trying backup ", i)
				data = _read_and_parse(bak_path)
				if data != null:
					break
	if data == null:
		print("SaveSystem: No valid save found.")
		return

	# Schema migration
	var file_schema: int = int(data.get("schema_version", 1))
	var migrated := false
	if file_schema < CURRENT_SCHEMA_VERSION:
		print("SaveSystem: Migrating save from schema v%d to v%d" % [file_schema, CURRENT_SCHEMA_VERSION])
		_run_schema_migration(data, file_schema)
		data["schema_version"] = CURRENT_SCHEMA_VERSION
		migrated = true

	# Deep-merge defaults so new fields appear in old saves
	data = _deep_merge_defaults(data)

	current_save_data = data
	_galaxy_state = (data.get("galaxy") as Dictionary).duplicate(true) if data.has("galaxy") else _default_galaxy_state()
	print("SaveSystem: Loaded save profile: ", current_save_data.get("profile_name", "Unknown"))

	# Persist the migrated data so disk reflects the new schema immediately
	if migrated:
		save_game()


## Get an upgrade value by name with a fallback default. (Backwards compatible)
func get_upgrade(upgrade_name: String, default_value: float) -> float:
	if current_save_data.has("upgrades") and current_save_data["upgrades"].has(upgrade_name):
		return float(current_save_data["upgrades"][upgrade_name])
	return default_value


# ===========================================================================
# PUBLIC API — GALAXY STATE
# ===========================================================================

## Returns the current galaxy state dictionary (current system, visited, POIs).
func get_galaxy_state() -> Dictionary:
	return _galaxy_state


## Replace the entire galaxy state cache. Call save_game() to persist.
func set_galaxy_state(state: Dictionary) -> void:
	_galaxy_state = state.duplicate(true)


## Persist the current galaxy state to disk immediately (atomic).
func save_galaxy_state() -> void:
	current_save_data["galaxy"] = _galaxy_state.duplicate(true)
	save_game()


## Reload galaxy state from disk without reloading the full profile.
func load_galaxy_state() -> Dictionary:
	load_save()
	return _galaxy_state


## Mark a system as visited (deduplicated by name).
func mark_system_visited(system_name: String) -> void:
	if system_name.is_empty():
		return
	var visited: Array = _galaxy_state.get("visited_systems", [])
	if not visited.has(system_name):
		visited.append(system_name)
		_galaxy_state["visited_systems"] = visited


## Set the current system the player is in.
func set_current_system(system: Dictionary) -> void:
	_galaxy_state["current_system"] = system.duplicate(true)
	_galaxy_state["current_system_name"] = system.get("name", "")
	mark_system_visited(_galaxy_state["current_system_name"])


## Record a discovered POI (deduplicated by name).
func discover_poi(poi: Dictionary) -> void:
	var pois: Array = _galaxy_state.get("discovered_pois", [])
	var poi_name: String = poi.get("name", "")
	for existing in pois:
		if existing is Dictionary and existing.get("name", "") == poi_name:
			return
	pois.append(poi.duplicate(true))
	_galaxy_state["discovered_pois"] = pois


## Set the player's world position (stored as array for JSON serialization).
func set_player_position(pos: Vector3) -> void:
	_galaxy_state["player_position"] = [pos.x, pos.y, pos.z]


## Get the player's stored world position.
func get_player_position() -> Vector3:
	var arr: Array = _galaxy_state.get("player_position", [0.0, 0.0, 0.0])
	if arr.size() >= 3:
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3.ZERO


## Returns true if a non-zero player position has been recorded.
func has_player_position() -> bool:
	var arr: Array = _galaxy_state.get("player_position", [0.0, 0.0, 0.0])
	if arr.size() < 3:
		return false
	return float(arr[0]) != 0.0 or float(arr[1]) != 0.0 or float(arr[2]) != 0.0


## Returns the current system dictionary the player is in (empty if unset).
func get_current_system() -> Dictionary:
	return _galaxy_state.get("current_system", {})


## Returns the name of the current system (empty string if unset).
func get_current_system_name() -> String:
	return _galaxy_state.get("current_system_name", "")


## Returns the list of visited system name Strings.
func get_visited_systems() -> Array:
	return _galaxy_state.get("visited_systems", [])


## Alias for mark_system_visited — mark a system as visited by name.
func add_visited_system(system_name: String) -> void:
	mark_system_visited(system_name)


## Returns true if the system has been visited before.
func is_system_visited(system_name: String) -> bool:
	return get_visited_systems().has(system_name)


## Returns the list of discovered POI dictionaries.
func get_discovered_pois() -> Array:
	return _galaxy_state.get("discovered_pois", [])


## Alias for discover_poi — record a discovered POI by dictionary.
func add_discovered_poi(poi: Dictionary) -> void:
	discover_poi(poi)


## Record a discovered POI by its component fields (convenience overload).
func add_discovered_poi_fields(poi_name: String, system: String, poi_type: String, extra: Dictionary = {}) -> void:
	var poi: Dictionary = {"name": poi_name, "system": system, "type": poi_type}
	for key in extra:
		poi[key] = extra[key]
	discover_poi(poi)


# ===========================================================================
# PUBLIC API — PROCEDURAL SEEDS
# ===========================================================================

## Add a planet seed to the persistent list (deduplicated).
func add_planet_seed(seed_value: int) -> void:
	var seeds_dict: Dictionary = current_save_data.get("procedural_seeds", {})
	var planet_seeds: Array = seeds_dict.get("planet_seeds", [])
	if not planet_seeds.has(seed_value):
		planet_seeds.append(seed_value)
		seeds_dict["planet_seeds"] = planet_seeds
		current_save_data["procedural_seeds"] = seeds_dict


## Returns the persistent list of planet seeds (Array of int).
func get_planet_seeds() -> Array:
	var seeds_dict: Dictionary = current_save_data.get("procedural_seeds", {})
	return seeds_dict.get("planet_seeds", [])


## Store a planet seed keyed by a stable planet identifier (planet name).
## Maintains a name→seed map alongside the flat seed list for fast lookup.
## Also appends the raw seed to the flat list so legacy callers keep working.
func set_planet_seed(planet_id: String, seed_value: int) -> void:
	if planet_id.is_empty():
		return
	var seeds_dict: Dictionary = current_save_data.get("procedural_seeds", {})
	var seed_map: Dictionary = seeds_dict.get("planet_seed_map", {})
	seed_map[planet_id] = seed_value
	seeds_dict["planet_seed_map"] = seed_map
	current_save_data["procedural_seeds"] = seeds_dict
	# Keep the flat list in sync for backwards-compatible callers.
	add_planet_seed(seed_value)


## Retrieve a planet seed by its stable planet identifier.
## Returns -1 if the planet has no recorded seed.
func get_planet_seed(planet_id: String) -> int:
	var seeds_dict: Dictionary = current_save_data.get("procedural_seeds", {})
	var seed_map: Dictionary = seeds_dict.get("planet_seed_map", {})
	if seed_map.has(planet_id):
		return int(seed_map[planet_id])
	return -1


## Returns true if a planet seed has been recorded for the given identifier.
func has_planet_seed(planet_id: String) -> bool:
	var seeds_dict: Dictionary = current_save_data.get("procedural_seeds", {})
	var seed_map: Dictionary = seeds_dict.get("planet_seed_map", {})
	return seed_map.has(planet_id)


## Mark a system as explored (procedural generation has been run for it).
func mark_system_explored(system_name: String) -> void:
	var seeds_dict: Dictionary = current_save_data.get("procedural_seeds", {})
	var explored: Array = seeds_dict.get("explored_systems", [])
	if not explored.has(system_name):
		explored.append(system_name)
		seeds_dict["explored_systems"] = explored
		current_save_data["procedural_seeds"] = seeds_dict


## Alias for mark_system_explored — mark a system as fully explored.
func add_explored_system(system_name: String) -> void:
	mark_system_explored(system_name)


## Returns the list of explored system name Strings.
func get_explored_systems() -> Array:
	var seeds_dict: Dictionary = current_save_data.get("procedural_seeds", {})
	return seeds_dict.get("explored_systems", [])


## Check if a system has been explored (procedural gen already run).
func is_system_explored(system_name: String) -> bool:
	var seeds_dict: Dictionary = current_save_data.get("procedural_seeds", {})
	var explored: Array = seeds_dict.get("explored_systems", [])
	return explored.has(system_name)


# ===========================================================================
# PUBLIC API — PROCEDURAL NODE-TREE PERSISTENCE (via SaverLoader)
# ===========================================================================

## Save the procedural node tree (planets, generated objects) to a binary file.
## Uses SaverLoader to serialize all nodes tagged with PERSIST_AS_PROCEDURAL_OBJECT.
## Returns OK on success, or an error code.
func save_procedural_state() -> int:
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		push_warning("SaveSystem: No profile save — skipping procedural save.")
		return ERR_FILE_NOT_FOUND

	var tree := get_tree()
	if tree == null:
		push_error("SaveSystem: No SceneTree available for procedural save.")
		return FAILED

	# Atomic write: SaverLoader writes to .tmp, then we commit via rename.
	var tmp_path := PROCEDURAL_FILE_PATH + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: Failed to open procedural temp file for write.")
		return FileAccess.get_open_error()

	_saver_loader.save_game(file, tree)
	await _saver_loader.finished

	# Verify the temp file was written
	if not FileAccess.file_exists(tmp_path):
		push_error("SaveSystem: Procedural temp file missing after SaverLoader write.")
		return ERR_FILE_CORRUPT

	# Rotate backups and commit
	_rotate_backups(PROCEDURAL_FILE_PATH)
	var rename_err := DirAccess.rename_absolute(tmp_path, PROCEDURAL_FILE_PATH)
	if rename_err != OK:
		push_error("SaveSystem: Failed to commit procedural save (rename error %d)." % rename_err)
		_try_remove_file(tmp_path)
		return rename_err

	print("SaveSystem: Procedural state saved to ", PROCEDURAL_FILE_PATH)
	return OK


## Load the procedural node tree from the binary file and rebuild the scene.
## Frees existing procedural nodes, then reconstructs from saved data.
## Returns OK on success, or an error code.
func load_procedural_state() -> int:
	if not FileAccess.file_exists(PROCEDURAL_FILE_PATH):
		print("SaveSystem: No procedural save found — starting fresh.")
		return ERR_FILE_NOT_FOUND

	var tree := get_tree()
	if tree == null:
		push_error("SaveSystem: No SceneTree available for procedural load.")
		return FAILED

	var file := FileAccess.open(PROCEDURAL_FILE_PATH, FileAccess.READ)
	if file == null:
		# Try backup
		for i in range(1, MAX_BACKUPS + 1):
			var bak := PROCEDURAL_FILE_PATH + ".bak" + str(i)
			if FileAccess.file_exists(bak):
				file = FileAccess.open(bak, FileAccess.READ)
				if file != null:
					print("SaveSystem: Loading procedural backup ", i)
					break
		if file == null:
			push_error("SaveSystem: Failed to open procedural save file.")
			return FileAccess.get_open_error()

	_saver_loader.load_game(file, tree)
	await _saver_loader.finished

	print("SaveSystem: Procedural state loaded from ", PROCEDURAL_FILE_PATH)
	return OK


# ===========================================================================
# ATOMIC WRITE (ported from SaveState's AtomicWriter)
# ===========================================================================

## Write bytes to destination_path + ".tmp", verify, rotate backups, then
## commit via atomic rename. If [param rotate_backups] is true, keeps up to
## MAX_BACKUPS rolling copies (.bak1 = newest, .bak3 = oldest).
func _write_atomic(destination_path: String, data: PackedByteArray, rotate_backups: bool) -> int:
	if destination_path.is_empty():
		return ERR_INVALID_PARAMETER

	var tmp_path := destination_path + ".tmp"

	# 1. Write to temp file
	var err := _write_all_bytes(tmp_path, data)
	if err != OK:
		_try_remove_file(tmp_path)
		return err

	# 2. Verify read-back matches (catches disk-full / partial writes)
	err = _verify_read_matches(tmp_path, data)
	if err != OK:
		_try_remove_file(tmp_path)
		return err

	# 3. Rotate backups
	if rotate_backups:
		_rotate_backups(destination_path)
	else:
		# Just remove the old file
		if FileAccess.file_exists(destination_path):
			DirAccess.remove_absolute(destination_path)

	# 4. Commit via rename
	err = DirAccess.rename_absolute(tmp_path, destination_path)
	if err != OK:
		_try_remove_file(tmp_path)
		return err
	return OK


func _write_all_bytes(path: String, data: PackedByteArray) -> int:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(data)
	file.flush()
	var close_err := file.get_error()
	file.close()
	if close_err != OK:
		return close_err
	return OK


func _verify_read_matches(path: String, expected: PackedByteArray) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var length: int = int(file.get_length())
	if length != expected.size():
		file.close()
		return ERR_FILE_CORRUPT
	var got := file.get_buffer(length)
	file.close()
	if got != expected:
		return ERR_FILE_CORRUPT
	return OK


## Rotate backup files: .bak(MAX-1) -> .bak(MAX), ..., .bak1 -> .bak2,
## current -> .bak1. Keeps the last MAX_BACKUPS copies.
func _rotate_backups(base_path: String) -> void:
	# Shift older backups down: bak2 -> bak3, bak1 -> bak2
	for i in range(MAX_BACKUPS - 1, 0, -1):
		var src := base_path + ".bak" + str(i)
		var dst := base_path + ".bak" + str(i + 1)
		if FileAccess.file_exists(src):
			if FileAccess.file_exists(dst):
				DirAccess.remove_absolute(dst)
			DirAccess.rename_absolute(src, dst)
	# Move current to .bak1
	if FileAccess.file_exists(base_path):
		var bak1 := base_path + ".bak1"
		if FileAccess.file_exists(bak1):
			DirAccess.remove_absolute(bak1)
		DirAccess.rename_absolute(base_path, bak1)


func _try_remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# ===========================================================================
# READ / PARSE / MIGRATE
# ===========================================================================

## Read a JSON save file and parse it. Returns the Dictionary or null on failure.
func _read_and_parse(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var content := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(content)
	if err == OK and json.data is Dictionary:
		return json.data
	push_warning("SaveSystem: Failed to parse %s (error at line %d)" % [path, json.get_error_line()])
	return null


## Run the ordered migration pipeline from file_schema up to CURRENT_SCHEMA_VERSION.
func _run_schema_migration(inner: Dictionary, file_schema: int) -> void:
	var from_schema := maxi(1, file_schema)
	if from_schema >= CURRENT_SCHEMA_VERSION:
		return
	for ver in range(from_schema, CURRENT_SCHEMA_VERSION):
		var idx := ver - 1
		if idx < 0 or idx >= _schema_migrations.size():
			if idx >= 0:
				push_warning("SaveSystem: Missing migration step for schema %d → %d" % [ver, ver + 1])
			continue
		var c: Variant = _schema_migrations[idx]
		if c is Callable and (c as Callable).is_valid():
			(c as Callable).call(inner)


## Deep-merge default fields into loaded data so new schema fields appear
## in older saves without overwriting existing values. (Ported from SaveMigrator)
func _deep_merge_defaults(data: Dictionary) -> Dictionary:
	var defaults := {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"profile_name": "Unknown",
		"upgrades": {},
		"inventory": {"credits": 0, "bio_matter": 0},
		"galaxy": _default_galaxy_state(),
		"procedural_seeds": {"planet_seeds": [], "planet_seed_map": {}, "explored_systems": []},
		"quest_weaver": {},
	}
	return _deep_merge(data, defaults)


## Deep-merge: missing keys from [param defaults] are filled without
## overwriting existing nested keys from [param current]. (From SaveMigrator)
func _deep_merge(current: Dictionary, defaults: Dictionary) -> Dictionary:
	var out := current.duplicate(true)
	for key in defaults:
		var dv: Variant = defaults[key]
		if not out.has(key):
			out[key] = _duplicate_value(dv)
			continue
		var cv: Variant = out[key]
		if typeof(dv) == TYPE_DICTIONARY and typeof(cv) == TYPE_DICTIONARY:
			out[key] = _deep_merge(cv, dv)
	return out


func _duplicate_value(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			return (v as Dictionary).duplicate(true)
		TYPE_ARRAY:
			return (v as Array).duplicate(true)
		_:
			return v

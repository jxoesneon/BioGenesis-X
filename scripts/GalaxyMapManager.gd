extends Node
class_name GalaxyMapManager

## ============================================================================
## AAA+ Streaming Galaxy Map Manager
## Elite Dangerous / NMS-Grade Architecture:
##   - Instant overview cloud (~3000 stars, synchronous, <100ms)
##   - Threaded sector streaming via WorkerThreadPool
##   - LRU sector cache (revisiting is instant)
##   - Concentric ring loading around camera
##   - Automatic sector unloading beyond render distance
## ============================================================================

@export var camera: GalaxyMapCamera
const MAP_SCALE = 0.01

# --- Signals (preserved for galaxy_map.tscn connections) ---
signal stars_updated(stars)
signal system_selected(system_data)
signal current_system_changed(system_data)
signal route_plotted(path_points)

# --- Navigation ---
var current_system: Dictionary = {}
var astar: AStar3D
@export var ship_jump_range: float = 800.0
var current_route_path: PackedVector3Array
var current_route_names: PackedStringArray
var current_route_seeds: Array[int] = []

# --- Streaming State ---
const SECTOR_SIZE_LY: float = 2500.0       # Size of each streaming sector
const MAX_SECTORS_PER_FRAME: int = 4        # Max new sector requests per update
const SECTOR_RENDER_DIST_LY: float = 8000.0 # Distance to keep sectors loaded
const SECTOR_UNLOAD_DIST_LY: float = 12000.0 # Distance to unload sectors
# Predictive loading: request sectors ahead of the camera's predicted position
const PREDICT_TIME: float = 2.0             # Seconds ahead to predict
const PREDICT_RENDER_DIST_LY: float = 5000.0 # Smaller radius for predictive requests

var all_stars: Array[Dictionary] = []       # All currently loaded stars
var sector_cache: Dictionary = {}           # Vector3i -> Array[Dictionary] (generated star data)
var active_sectors: Dictionary = {}         # Vector3i -> true (sectors currently in scene)
var in_flight_sectors: Dictionary = {}      # Vector3i -> true (sectors being generated)
var completed_queue: Array = []             # Thread-safe results queue
var queue_mutex: Mutex = Mutex.new()
var overview_generated: bool = false

# --- SaveSystem galaxy-state caches (loaded once on ready) ---
var visited_system_names: Array = []        # Array of system name Strings
var discovered_pois: Array = []             # Array of POI dictionaries
var explored_system_names: Array = []       # Array of explored system name Strings
var _save_system: Node = null

func _ready():
	_save_system = get_tree().root.get_node_or_null("SaveSystem")
	if _save_system and _save_system.has_method("get_upgrade"):
		ship_jump_range = _save_system.get_upgrade("jump_range", ship_jump_range)
	# Load persisted galaxy state for map highlighting.
	_load_galaxy_state_from_save()
			
	var ui := get_node_or_null("../UI/GalaxyMapUI")
	if ui:
		ui.connect("refocus_current_system", Callable(self, "refocus_on_current"))
		
	var visuals := get_node_or_null("../GalaxyMapVisuals")
	if visuals:
		self.connect("system_selected", Callable(visuals, "set_selected_system"))
	
	# Generate the instant overview cloud synchronously (< 100ms)
	call_deferred("_generate_overview_cloud")

func refocus_on_current():
	if camera and current_system and current_system.has("position"):
		camera.focus_on_system(current_system["position"] * MAP_SCALE)

# ==========================================================================
# SAVE SYSTEM INTEGRATION
# ==========================================================================

## Loads persisted galaxy state (visited systems, discovered POIs, explored
## systems) from SaveSystem so the map can highlight them.
func _load_galaxy_state_from_save() -> void:
	if _save_system == null:
		return
	if _save_system.has_method("get_visited_systems"):
		visited_system_names = _save_system.call("get_visited_systems")
	if _save_system.has_method("get_discovered_pois"):
		discovered_pois = _save_system.call("get_discovered_pois")
	if _save_system.has_method("get_explored_systems"):
		explored_system_names = _save_system.call("get_explored_systems")
	print("GalaxyMapManager: Loaded galaxy state — visited:", visited_system_names.size(),
		" POIs:", discovered_pois.size(), " explored:", explored_system_names.size())

## Returns true if the given system name has been visited before.
func is_system_visited(system_name: String) -> bool:
	return visited_system_names.has(system_name)

## Returns true if the given system name has been fully explored.
func is_system_explored(system_name: String) -> bool:
	return explored_system_names.has(system_name)

## Returns the list of discovered POIs (dictionaries with name/system/type).
func get_discovered_pois() -> Array:
	return discovered_pois

## Persists the given system as the current system in SaveSystem (called when
## the player selects a system to travel to).
func save_current_system(system_data: Dictionary) -> void:
	if _save_system == null or not _save_system.has_method("set_current_system"):
		return
	_save_system.call("set_current_system", system_data)
	var sys_name: String = system_data.get("name", "")
	if not sys_name.is_empty() and not visited_system_names.has(sys_name):
		visited_system_names.append(sys_name)

# ==========================================================================
# OVERVIEW CLOUD: Instant galaxy shape on map open (~3000 stars, <100ms)
# ==========================================================================
func _generate_overview_cloud():
	var t_start := Time.get_ticks_msec()
	var overview_stars: Array[Dictionary] = []
	var max_overview := 3000
	var attempts := 0
	var max_attempts := 60000
	
	# Use a fixed seed for determinism
	var rng := RandomNumberGenerator.new()
	rng.seed = ProceduralGalaxy.GALAXY_SEED
	
	while overview_stars.size() < max_overview and attempts < max_attempts:
		attempts += 1
		var r := sqrt(rng.randf()) * ProceduralGalaxy.GALAXY_RADIUS_LY
		var theta := rng.randf() * TAU
		var z := (rng.randf() - 0.5) * ProceduralGalaxy.GALAXY_THICKNESS_LY * 2.0
		var pos_ly := Vector3(r * cos(theta), z, r * sin(theta))
		var density := ProceduralGalaxy.get_stellar_density(pos_ly)
		
		if rng.randf() < density:
			var star_seed := rng.randi()
			overview_stars.append({
				"index": overview_stars.size(),
				"position": pos_ly,
				"spectral_idx": rng.randf(),
				"luminosity": rng.randf() * 0.8 + 0.2,
				"name": "BIO-%04d" % (star_seed % 9999),
				"galactic_pos": pos_ly,
				"seed": star_seed
			})
	
	all_stars = overview_stars
	_build_navigation_graph()
	emit_signal("stars_updated", overview_stars)
	
	overview_generated = true
	var elapsed := Time.get_ticks_msec() - t_start
	print("Overview cloud: ", overview_stars.size(), " stars in ", elapsed, "ms")

	# Set current system and trigger intro zoom.
	# Prefer the persisted current system from SaveSystem if available.
	var saved_system: Dictionary = {}
	if _save_system != null and _save_system.has_method("get_current_system"):
		saved_system = _save_system.call("get_current_system")
	if not saved_system.is_empty() and saved_system.has("galactic_position_ly"):
		current_system = saved_system.duplicate(true)
		# Ensure the saved system has a valid index for navigation lookups.
		if not current_system.has("index"):
			current_system["index"] = 0
		if not current_system.has("position"):
			current_system["position"] = current_system.get("galactic_position_ly", Vector3.ZERO)
		emit_signal("current_system_changed", current_system)
		if camera and current_system.has("position"):
			camera.intro_zoom(current_system["position"] * MAP_SCALE)
		print("GalaxyMapManager: Restored current system '", current_system.get("name", "Unknown"), "' from save.")
	elif not overview_stars.is_empty():
		current_system = overview_stars[0]
		current_system["name"] = "Current System"
		emit_signal("current_system_changed", current_system)
		if camera and current_system.has("position"):
			camera.intro_zoom(current_system["position"] * MAP_SCALE)

	# Predictive: immediately request sectors at the destination AND along the sweep path
	# The camera sweeps from (0, 1200, 0) to the current system over several seconds.
	# Request sectors at the destination now so they're ready when the camera arrives.
	if camera and current_system and current_system.has("position"):
		var dest_ly: Vector3 = current_system["position"]
		_update_streaming_sectors(dest_ly)
		# Also request along the sweep path (sample 3 intermediate points)
		var start_ly := Vector3(0, 1200.0 / MAP_SCALE, 0)
		for i in range(1, 4):
			var t: float = float(i) / 4.0
			var path_pos := start_ly.lerp(dest_ly, t)
			_request_sectors_near(path_pos, PREDICT_RENDER_DIST_LY)
		_sector_update_timer = 0.0

	# Highlight visited systems on the map using persisted SaveSystem state.
	_update_visited_highlights()

## Computes the galactic positions of all loaded stars whose names appear in the
## visited-systems list and asks the visuals to highlight them.
func _update_visited_highlights() -> void:
	if visited_system_names.is_empty():
		return
	var visuals := get_node_or_null("../GalaxyMapVisuals")
	if visuals == null or not visuals.has_method("highlight_visited_systems"):
		return
	var positions: Array = []
	for star in all_stars:
		var sname: String = star.get("name", "")
		if not sname.is_empty() and visited_system_names.has(sname):
			positions.append(star.get("galactic_pos", star.get("position", Vector3.ZERO)))
	visuals.call("highlight_visited_systems", positions)

# ==========================================================================
# STREAMING: Per-frame sector management
# ==========================================================================
var _sector_update_timer: float = 0.0
const SECTOR_UPDATE_INTERVAL: float = 0.5 # Only check sectors every 0.5s
var _nav_rebuild_pending: bool = false
var _nav_rebuild_timer: float = 0.0
const NAV_REBUILD_DELAY: float = 2.0 # Wait 2s after last sector change before rebuilding

func _process(delta: float):
	if not camera or not overview_generated:
		return

	# 1. Process completed sector generation results (up to 2 per frame)
	_process_completed_sectors()

	# 2. Throttled sector streaming update (every 0.5s, not every frame)
	_sector_update_timer += delta
	if _sector_update_timer >= SECTOR_UPDATE_INTERVAL:
		_sector_update_timer = 0.0
		var cam_pos_ly := camera.global_position / MAP_SCALE
		_update_streaming_sectors(cam_pos_ly)

		# Predictive: also request sectors at the camera's predicted future position
		# This pre-loads sectors the camera will enter, eliminating pop-in during movement
		var cam_velocity: Vector3 = camera.velocity if "velocity" in camera else Vector3.ZERO
		if cam_velocity.length() > 1.0:
			var predicted_pos_ly := cam_pos_ly + (cam_velocity / MAP_SCALE) * PREDICT_TIME
			_request_sectors_near(predicted_pos_ly, PREDICT_RENDER_DIST_LY)
	
	# 3. Deferred navigation graph rebuild (wait for sector loading to settle)
	if _nav_rebuild_pending:
		_nav_rebuild_timer += delta
		if _nav_rebuild_timer >= NAV_REBUILD_DELAY:
			_nav_rebuild_pending = false
			_nav_rebuild_timer = 0.0
			_build_navigation_graph()

func _process_completed_sectors():
	var results_this_frame: Array = []
	queue_mutex.lock()
	# Drain up to 2 results per frame to mount sectors faster
	var max_results: int = mini(completed_queue.size(), 2)
	for i in range(max_results):
		results_this_frame.append(completed_queue.pop_front())
	queue_mutex.unlock()
	
	for result in results_this_frame:
		var sec_key: Vector3i = result["sector_key"]
		var stars: Array[Dictionary] = result["stars"]
		
		in_flight_sectors.erase(sec_key)
		sector_cache[sec_key] = stars
		
		if not stars.is_empty():
			_mount_sector(sec_key, stars)

func _update_streaming_sectors(cam_pos_ly: Vector3):
	var cam_sec := _pos_to_sector(cam_pos_ly)
	
	# Calculate how many sectors to check in each direction
	var check_radius := ceili(SECTOR_RENDER_DIST_LY / SECTOR_SIZE_LY)
	check_radius = mini(check_radius, 3) # Cap to 7x3x7 = 147 max
	
	var requested_this_frame := 0
	var mounted_this_frame := 0
	
	# Request sectors in a spiral outward from camera (closest first)
	var needed_sectors: Array[Vector3i] = []
	for dx in range(-check_radius, check_radius + 1):
		for dy in range(-1, 2): # Galaxy is thin, only check ±1 vertically
			for dz in range(-check_radius, check_radius + 1):
				var sec := Vector3i(cam_sec.x + dx, cam_sec.y + dy, cam_sec.z + dz)
				var sec_center_ly := (Vector3(sec) + Vector3(0.5, 0.5, 0.5)) * SECTOR_SIZE_LY
				var dist := cam_pos_ly.distance_to(sec_center_ly)
				
				if dist < SECTOR_RENDER_DIST_LY:
					if not active_sectors.has(sec) and not in_flight_sectors.has(sec):
						if sector_cache.has(sec):
							# Cache hit - mount instantly but limit per-update
							if mounted_this_frame < 2:
								_mount_sector(sec, sector_cache[sec])
								mounted_this_frame += 1
						else:
							needed_sectors.append(sec)
	
	# Sort needed sectors by distance to camera (closest first)
	needed_sectors.sort_custom(func(a, b):
		var da := (Vector3(a) * SECTOR_SIZE_LY).distance_squared_to(cam_pos_ly)
		var db := (Vector3(b) * SECTOR_SIZE_LY).distance_squared_to(cam_pos_ly)
		return da < db
	)
	
	# Dispatch up to MAX_SECTORS_PER_FRAME generation tasks
	for sec in needed_sectors:
		if requested_this_frame >= MAX_SECTORS_PER_FRAME:
			break
		_request_sector_generation(sec)
		requested_this_frame += 1
	
	# Unload distant sectors
	var to_unload: Array[Vector3i] = []
	for sec_key in active_sectors.keys():
		var sec_center_ly := (Vector3(sec_key) + Vector3(0.5, 0.5, 0.5)) * SECTOR_SIZE_LY
		if cam_pos_ly.distance_to(sec_center_ly) > SECTOR_UNLOAD_DIST_LY:
			to_unload.append(sec_key)
	
	for sec_key in to_unload:
		_unmount_sector(sec_key)

func _pos_to_sector(pos_ly: Vector3) -> Vector3i:
	return Vector3i(
		floori(pos_ly.x / SECTOR_SIZE_LY),
		floori(pos_ly.y / SECTOR_SIZE_LY),
		floori(pos_ly.z / SECTOR_SIZE_LY)
	)

## Request generation of all ungenerated sectors within `radius_ly` of `pos_ly`.
## Does NOT mount sectors — just dispatches worker threads so data is ready
## when the camera eventually arrives. Mounted sectors are skipped.
func _request_sectors_near(pos_ly: Vector3, radius_ly: float) -> void:
	var center_sec := _pos_to_sector(pos_ly)
	var check_radius := ceili(radius_ly / SECTOR_SIZE_LY)
	check_radius = mini(check_radius, 3)  # Cap to prevent runaway requests

	var needed: Array[Vector3i] = []
	for dx in range(-check_radius, check_radius + 1):
		for dy in range(-1, 2):
			for dz in range(-check_radius, check_radius + 1):
				var sec := Vector3i(center_sec.x + dx, center_sec.y + dy, center_sec.z + dz)
				var sec_center_ly := (Vector3(sec) + Vector3(0.5, 0.5, 0.5)) * SECTOR_SIZE_LY
				var dist := pos_ly.distance_to(sec_center_ly)
				if dist < radius_ly:
					if not active_sectors.has(sec) and not in_flight_sectors.has(sec) and not sector_cache.has(sec):
						needed.append(sec)

	# Sort by distance (closest first)
	needed.sort_custom(func(a, b):
		var da := (Vector3(a) + Vector3(0.5, 0.5, 0.5)) * SECTOR_SIZE_LY
		var db := (Vector3(b) + Vector3(0.5, 0.5, 0.5)) * SECTOR_SIZE_LY
		return da.distance_squared_to(pos_ly) < db.distance_squared_to(pos_ly)
	)

	var requested: int = 0
	for sec in needed:
		if requested >= MAX_SECTORS_PER_FRAME:
			break
		_request_sector_generation(sec)
		requested += 1

# ==========================================================================
# THREADED GENERATION
# ==========================================================================
func _request_sector_generation(sec_key: Vector3i):
	in_flight_sectors[sec_key] = true
	var params := {
		"sec_x": sec_key.x,
		"sec_y": sec_key.y,
		"sec_z": sec_key.z,
		"sector_size": SECTOR_SIZE_LY
	}
	WorkerThreadPool.add_task(Callable(self, "_worker_generate_sector").bind(params))

func _worker_generate_sector(params: Dictionary):
	## Runs entirely on a background thread. No scene tree access!
	var sec_x: int = params["sec_x"]
	var sec_y: int = params["sec_y"]
	var sec_z: int = params["sec_z"]
	var sector_size: float = params["sector_size"]
	var sec_key := Vector3i(sec_x, sec_y, sec_z)
	
	var stars: Array[Dictionary] = ProceduralGalaxy.generate_sector_stars(
		sec_x, sec_y, sec_z, sector_size, 600
	)
	
	# Push result to thread-safe queue
	queue_mutex.lock()
	completed_queue.append({
		"sector_key": sec_key,
		"stars": stars
	})
	queue_mutex.unlock()

# ==========================================================================
# SECTOR MOUNT / UNMOUNT
# ==========================================================================
func _mount_sector(sec_key: Vector3i, stars: Array[Dictionary]):
	if active_sectors.has(sec_key):
		return
	active_sectors[sec_key] = true

	# Add stars to the global list and update indices
	var base_idx := all_stars.size()
	for i in range(stars.size()):
		var star := stars[i].duplicate()
		star["index"] = base_idx + i
		star["sector_key"] = sec_key
		all_stars.append(star)

	# Notify visuals to render this sector chunk
	var visuals := get_node_or_null("../GalaxyMapVisuals")
	if visuals and visuals.has_method("mount_sector_chunk"):
		visuals.mount_sector_chunk(sec_key, stars)

	# Refresh visited-system highlights now that new stars are available.
	_update_visited_highlights()

	#print("[SECTOR] t=%.2fs Mounted %s with %d stars (total active: %d)" % [Time.get_ticks_msec() / 1000.0, sec_key, stars.size(), active_sectors.size()])

	_nav_rebuild_pending = true
	_nav_rebuild_timer = 0.0

func _unmount_sector(sec_key: Vector3i):
	if not active_sectors.has(sec_key):
		return
	active_sectors.erase(sec_key)
	
	# Remove stars belonging to this sector from all_stars
	all_stars = all_stars.filter(func(s): return s.get("sector_key", Vector3i(-99999,-99999,-99999)) != sec_key)
	# Re-index
	for i in range(all_stars.size()):
		all_stars[i]["index"] = i
	
	# Tell visuals to remove the chunk
	var visuals := get_node_or_null("../GalaxyMapVisuals")
	if visuals and visuals.has_method("unmount_sector_chunk"):
		visuals.unmount_sector_chunk(sec_key)
	
	_nav_rebuild_pending = true
	_nav_rebuild_timer = 0.0

# ==========================================================================
# NAVIGATION GRAPH (AStar3D)
# ==========================================================================
func _build_navigation_graph():
	astar = AStar3D.new()
	if all_stars.is_empty():
		return
		
	var cell_size := ship_jump_range
	var grid := {}
	
	for i in range(all_stars.size()):
		astar.add_point(i, all_stars[i]["galactic_pos"])
		var pos = all_stars[i]["galactic_pos"]
		var cell := Vector3i(floori(pos.x / cell_size), floori(pos.y / cell_size), floori(pos.z / cell_size))
		if not grid.has(cell): grid[cell] = []
		grid[cell].append(i)
		
	var range_sq := ship_jump_range * ship_jump_range
	for i in range(all_stars.size()):
		var pos = all_stars[i]["galactic_pos"]
		var cell := Vector3i(floori(pos.x / cell_size), floori(pos.y / cell_size), floori(pos.z / cell_size))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var neighbor_cell := cell + Vector3i(dx, dy, dz)
					if grid.has(neighbor_cell):
						for j in grid[neighbor_cell]:
							if j > i:
								if pos.distance_squared_to(all_stars[j]["galactic_pos"]) <= range_sq:
									astar.connect_points(i, j)

# ==========================================================================
# STAR SELECTION & ROUTING (preserved interface)
# ==========================================================================
func select_system(system_data: Dictionary):
	if not current_system.is_empty() and system_data.has("galactic_pos") and current_system.has("galactic_pos"):
		var dist = current_system["galactic_pos"].distance_to(system_data["galactic_pos"])
		system_data["distance_from_current"] = dist
		
		if astar and astar.get_point_count() > 0:
			var path := astar.get_point_path(current_system["index"], system_data["index"])
			current_route_path = path
			current_route_names = PackedStringArray()
			current_route_seeds.clear()
			for i in range(path.size()):
				for s in all_stars:
					if s["galactic_pos"].is_equal_approx(path[i]):
						current_route_names.append(s["name"])
						current_route_seeds.append(s["seed"])
						break
			
			if path.size() > 0:
				system_data["jumps"] = path.size() - 1
				emit_signal("route_plotted", path)
			else:
				system_data["jumps"] = -1
				emit_signal("route_plotted", PackedVector3Array())
		else:
			system_data["jumps"] = -1
			emit_signal("route_plotted", PackedVector3Array())
	else:
		system_data["distance_from_current"] = 0.0
		system_data["jumps"] = 0
		emit_signal("route_plotted", PackedVector3Array())

	emit_signal("system_selected", system_data)
	if camera and system_data.has("position"):
		camera.focus_on_system(system_data["position"] * MAP_SCALE)

func _on_wave_ride_engaged(system_data: Dictionary):
	print("GalaxyMapManager: OVERCHARGE WAVE DRIVE requested to ", system_data.get("name", "Unknown"))
	if not current_route_path or current_route_path.size() < 2:
		print("GalaxyMapManager: No valid route. Jump aborted.")
		return
	# Persist the destination as the new current system in SaveSystem.
	save_current_system(system_data)
	print("GalaxyMapManager: Passing jump execution to FlightHUDUI / FlightController...")

func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not camera or all_stars.is_empty(): return
		
		var ray_origin := camera.project_ray_origin(event.position)
		var ray_dir := camera.project_ray_normal(event.position)
		
		var closest_star = null
		var closest_dist := 5.0
		
		for star in all_stars:
			var pos_scaled = star.get("position", Vector3.ZERO) * MAP_SCALE
			var vec_to_star = pos_scaled - ray_origin
			var projection = vec_to_star.project(ray_dir)
			if projection.dot(ray_dir) > 0:
				var dist_to_ray = (vec_to_star - projection).length()
				if dist_to_ray < closest_dist:
					closest_dist = dist_to_ray
					closest_star = star
					
		if closest_star:
			select_system(closest_star)

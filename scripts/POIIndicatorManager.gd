# res://scripts/POIIndicatorManager.gd
# ==============================================================================
# BioGenesis-X: Points of Interest Indicator System
# ==============================================================================
# Elite Dangerous-style in-space HUD markers for celestial bodies and
# nearby star systems.
#
# Features:
#   - On-screen markers for bodies within the camera frustum (bracket + name + distance)
#   - Off-screen edge indicators pointing toward bodies behind/around you
#   - Color-coded by body type (star=yellow, gas_giant=orange, terrestrial=green, etc.)
#   - Nearest body highlighted
#   - Distance updates in real-time
#   - Nearby star systems shown with a distinct diamond icon + "HyperWave Jump Required"
#   - Inter-system distance shown in light-years
#
# The markers are 2D Control nodes projected from 3D world positions.
# In-system planets use 3D world positions. Nearby star systems use a
# directional projection from the ship's current galactic coordinates.
# ==============================================================================

extends CanvasLayer

const POI_LAYER: int = 100

# Colors by archetype
const COLOR_STAR: Color = Color(1.0, 0.85, 0.2, 1.0)
const COLOR_GAS_GIANT: Color = Color(1.0, 0.5, 0.2, 1.0)
const COLOR_TERRESTRIAL: Color = Color(0.3, 0.9, 0.4, 1.0)
const COLOR_WATER: Color = Color(0.2, 0.6, 1.0, 1.0)
const COLOR_ICE: Color = Color(0.6, 0.8, 1.0, 1.0)
const COLOR_LAVA: Color = Color(1.0, 0.3, 0.1, 1.0)
const COLOR_BARREN: Color = Color(0.6, 0.6, 0.6, 1.0)
const COLOR_DEFAULT: Color = Color(0.8, 0.8, 0.8, 1.0)
const COLOR_NEAREST: Color = Color(0.0, 1.0, 1.0, 1.0)  # Cyan for nearest body
const COLOR_HYPERWAVE: Color = Color(0.7, 0.3, 1.0, 1.0)  # Purple for nearby star systems

# How far to scan for nearby star systems (light-years) — default fallback.
# Actual value is read from SettingsSystem at runtime.
const DEFAULT_SCAN_RADIUS_LY: float = 80.0
# 1 light-year in meters (for reference)
const LY_METERS: float = 9.461e15

var _camera: Camera3D = null
var _viewport_size: Vector2 = Vector2(1920, 1080)
var _indicators: Dictionary = {}  # planet_node -> Dictionary{bracket, label, dist_label, edge_arrow, color}
var _system_indicators: Array[Dictionary] = []  # Nearby star system markers
var _container: Control = null
var _nearest_planet: Node3D = null
var _universe_manager: Node = null

func _ready() -> void:
	layer = POI_LAYER

	# Create a full-screen container for HUD elements
	_container = Control.new()
	_container.name = "POIContainer"
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)

	# Find the main camera
	call_deferred("_find_camera")

func _find_camera() -> void:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return
	# Look for the chase camera
	_camera = tree.root.get_node_or_null("SpaceFlight/PlayerShip/CameraPivot/SpringArm3D/Camera3D")
	if _camera == null:
		_camera = tree.root.get_node_or_null("SpaceFlight/PlayerShip/CommandCenterFPVCamera")
	if _camera == null:
		# Search for any current Camera3D
		_camera = _search_for_camera(tree.root)
	if _camera == null:
		get_tree().create_timer(1.0).timeout.connect(_find_camera)
		return
	print("[POI] Camera found: %s" % _camera.name)
	# Find the UniverseManager autoload
	_universe_manager = tree.root.get_node_or_null("SpaceFlight/UniverseManager")
	if _universe_manager == null:
		_universe_manager = tree.root.get_node_or_null("UniverseManager")
	# Build indicators for all existing celestial bodies
	_build_indicators()
	# Build nearby star system indicators
	_build_nearby_system_indicators()
	# Listen for new bodies
	tree.node_added.connect(_on_node_added)
	# Listen for settings changes to rebuild POI indicators
	var settings := _get_settings_system()
	if settings and settings.has_signal("setting_changed"):
		settings.setting_changed.connect(_on_setting_changed)

func _search_for_camera(root: Node) -> Camera3D:
	if root is Camera3D and (root as Camera3D).current:
		return root
	for child: Node in root.get_children():
		var result: Camera3D = _search_for_camera(child)
		if result != null:
			return result
	return null

func _on_node_added(node: Node) -> void:
	if node is ProceduralPlanet:
		call_deferred("_add_indicator", node)

func _on_setting_changed(section: String, key: String, _value: Variant) -> void:
	if section == "gameplay" and (key == "poi_scan_radius_ly" or key == "poi_max_indicators"):
		call_deferred("rebuild_nearby_system_indicators")

func _build_indicators() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	for body: Node in tree.get_nodes_in_group("celestial_bodies"):
		if body is ProceduralPlanet:
			_add_indicator(body)

# ------------------------------------------------------------------------------
# Settings-driven POI parameters
# ------------------------------------------------------------------------------
func _get_poi_scan_radius() -> float:
	var settings := _get_settings_system()
	if settings and settings.has_method("get_setting"):
		return float(settings.get_setting("gameplay", "poi_scan_radius_ly", DEFAULT_SCAN_RADIUS_LY))
	return DEFAULT_SCAN_RADIUS_LY

func _get_poi_max_indicators() -> int:
	var settings := _get_settings_system()
	if settings and settings.has_method("get_setting"):
		return int(settings.get_setting("gameplay", "poi_max_indicators", 0))
	return 0

func _get_settings_system() -> Node:
	var tree: SceneTree = get_tree()
	if tree and tree.root and tree.root.has_node("SettingsSystem"):
		return tree.root.get_node("SettingsSystem")
	return null

## Rebuilds nearby system indicators when POI settings change.
func rebuild_nearby_system_indicators() -> void:
	# Clear existing system indicators
	for sys_data: Dictionary in _system_indicators:
		var marker: Control = sys_data.get("marker", null)
		if marker and is_instance_valid(marker):
			marker.queue_free()
		var edge: Line2D = sys_data.get("edge_diamond", null)
		if edge and is_instance_valid(edge):
			edge.queue_free()
	_system_indicators.clear()
	_build_nearby_system_indicators()

# ------------------------------------------------------------------------------
# Nearby Star System Indicators (HyperWave Jump targets)
# ------------------------------------------------------------------------------
func _build_nearby_system_indicators() -> void:
	if _universe_manager == null or not is_instance_valid(_universe_manager):
		print("[POI] UniverseManager not found — skipping nearby system indicators")
		return
	if not _universe_manager.has_method("get_nearby_systems"):
		return

	var scan_radius_ly: float = _get_poi_scan_radius()
	var max_indicators: int = _get_poi_max_indicators()
	var nearby: Array[Dictionary] = _universe_manager.get_nearby_systems(scan_radius_ly)
	var current_seed: int = _universe_manager.current_system_seed

	for sys_data: Dictionary in nearby:
		var sys_seed: int = sys_data.get("seed", 0)
		if sys_seed == current_seed:
			continue  # Skip the current system

		# Limit the number of indicators to avoid clutter (0 = unlimited)
		if max_indicators > 0 and _system_indicators.size() >= max_indicators:
			break

		var sys_name: String = sys_data.get("name", "Unknown System")
		var dist_ly: float = sys_data.get("distance_from_vessel_ly", 0.0)
		var galactic_pos: Vector3 = sys_data.get("galactic_position_ly", Vector3.ZERO)
		var star_color: Color = sys_data.get("star_color", COLOR_HYPERWAVE)
		# spectral_class is stored as an int index — convert to letter
		var spec_idx: int = int(sys_data.get("spectral_class", 0))
		var spectral_class: String = _spectral_class_letter(spec_idx)

		# Create a diamond-shaped marker for the star system
		var marker: Control = Control.new()
		marker.name = "POI_System_" + sys_name.replace(" ", "_")
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Diamond shape (4 lines forming a rotated square)
		var diamond: Line2D = Line2D.new()
		diamond.width = 2.5
		diamond.default_color = COLOR_HYPERWAVE
		diamond.closed = true
		diamond.add_point(Vector2(0, -18))
		diamond.add_point(Vector2(18, 0))
		diamond.add_point(Vector2(0, 18))
		diamond.add_point(Vector2(-18, 0))
		marker.add_child(diamond)

		# Inner dot
		var dot: Line2D = Line2D.new()
		dot.width = 4.0
		dot.default_color = star_color
		dot.add_point(Vector2(0, 0))
		dot.add_point(Vector2(0.1, 0))
		marker.add_child(dot)

		# System name label
		var label: Label = Label.new()
		label.name = "Label"
		label.text = sys_name + " [" + spectral_class + "]"
		label.add_theme_color_override("font_color", COLOR_HYPERWAVE)
		label.add_theme_font_size_override("font_size", 13)
		label.position = Vector2(25, -18)
		label.size = Vector2(250, 18)
		marker.add_child(label)

		# Distance + HyperWave label
		var dist_label: Label = Label.new()
		dist_label.name = "Distance"
		dist_label.text = "%.1f LY — HyperWave Jump Required" % dist_ly
		dist_label.add_theme_color_override("font_color", COLOR_HYPERWAVE * 0.8)
		dist_label.add_theme_font_size_override("font_size", 11)
		dist_label.position = Vector2(25, 2)
		dist_label.size = Vector2(250, 16)
		marker.add_child(dist_label)

		marker.visible = false
		_container.add_child(marker)

		# Off-screen edge indicator (diamond outline)
		var edge_diamond: Line2D = Line2D.new()
		edge_diamond.name = "EdgeDiamond_" + sys_name.replace(" ", "_")
		edge_diamond.width = 3.0
		edge_diamond.default_color = COLOR_HYPERWAVE
		edge_diamond.closed = true
		edge_diamond.visible = false
		edge_diamond.add_point(Vector2(-10, 0))
		edge_diamond.add_point(Vector2(0, -10))
		edge_diamond.add_point(Vector2(10, 0))
		edge_diamond.add_point(Vector2(0, 10))
		_container.add_child(edge_diamond)

		_system_indicators.append({
			"marker": marker,
			"label": label,
			"dist_label": dist_label,
			"edge_diamond": edge_diamond,
			"galactic_pos": galactic_pos,
			"sys_name": sys_name,
			"sys_seed": sys_seed,
			"dist_ly": dist_ly,
			"star_color": star_color,
		})

	print("[POI] Added %d nearby star system indicators (HyperWave Jump targets)" % _system_indicators.size())

func _add_indicator(planet: ProceduralPlanet) -> void:
	if planet == null or not is_instance_valid(planet):
		return
	if _indicators.has(planet):
		return

	var color: Color = _get_color_for_planet(planet)

	# On-screen bracket marker (4 corner brackets + label)
	var bracket: Control = Control.new()
	bracket.name = "POI_" + planet.planet_name
	bracket.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Top-left bracket
	var tl: Line2D = Line2D.new()
	tl.width = 2.0
	tl.default_color = color
	tl.add_point(Vector2(-20, 0))
	tl.add_point(Vector2(-20, -20))
	tl.add_point(Vector2(0, -20))
	bracket.add_child(tl)

	# Top-right bracket
	var tr_bracket: Line2D = Line2D.new()
	tr_bracket.width = 2.0
	tr_bracket.default_color = color
	tr_bracket.add_point(Vector2(20, 0))
	tr_bracket.add_point(Vector2(20, -20))
	tr_bracket.add_point(Vector2(0, -20))
	bracket.add_child(tr_bracket)

	# Bottom-left bracket
	var bl: Line2D = Line2D.new()
	bl.width = 2.0
	bl.default_color = color
	bl.add_point(Vector2(-20, 0))
	bl.add_point(Vector2(-20, 20))
	bl.add_point(Vector2(0, 20))
	bracket.add_child(bl)

	# Bottom-right bracket
	var br: Line2D = Line2D.new()
	br.width = 2.0
	br.default_color = color
	br.add_point(Vector2(20, 0))
	br.add_point(Vector2(20, 20))
	br.add_point(Vector2(0, 20))
	bracket.add_child(br)

	# Name label
	var label: Label = Label.new()
	label.name = "Label"
	label.text = planet.planet_name
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 14)
	label.position = Vector2(25, -10)
	label.size = Vector2(200, 20)
	bracket.add_child(label)

	# Distance label
	var dist_label: Label = Label.new()
	dist_label.name = "Distance"
	dist_label.text = "---"
	dist_label.add_theme_color_override("font_color", color * 0.8)
	dist_label.add_theme_font_size_override("font_size", 12)
	dist_label.position = Vector2(25, 8)
	dist_label.size = Vector2(200, 16)
	bracket.add_child(dist_label)

	bracket.visible = false
	_container.add_child(bracket)

	# Off-screen edge arrow
	var edge_arrow: Line2D = Line2D.new()
	edge_arrow.name = "EdgeArrow_" + planet.planet_name
	edge_arrow.width = 3.0
	edge_arrow.default_color = color
	edge_arrow.visible = false
	_container.add_child(edge_arrow)

	_indicators[planet] = {
		"bracket": bracket,
		"label": label,
		"dist_label": dist_label,
		"edge_arrow": edge_arrow,
		"color": color,
	}
	print("[POI] Added indicator for %s" % planet.planet_name)

func _get_color_for_planet(planet: ProceduralPlanet) -> Color:
	# Archetypes from ProceduralPlanet.gd:
	# 0=Molten, 1=Metallic Barren, 2=?, 3=Terran Oceanic, 4=Ice World,
	# 5=Jovian Gas Giant, 6=Ice Giant, 7=Radiotrophic Bio
	var archetype: int = planet.archetype
	match archetype:
		0: return COLOR_LAVA        # Molten
		1: return COLOR_BARREN      # Metallic Barren
		3: return COLOR_WATER       # Terran Oceanic
		4: return COLOR_ICE         # Ice World
		5: return COLOR_GAS_GIANT   # Jovian Gas Giant
		6: return COLOR_ICE         # Ice Giant
		7: return COLOR_TERRESTRIAL # Radiotrophic Bio
		_:
			# Fallback: detect by radius
			if planet.radius_m > 500000000.0:
				return COLOR_STAR
			elif planet.radius_m > 50000000.0:
				return COLOR_GAS_GIANT
			else:
				return COLOR_DEFAULT

func _process(_delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	if _container == null:
		return

	# Hide POI indicators when the galaxy map is open. The galaxy map is
	# instantiated as a child of the space_flight scene (not a scene change),
	# so our cached _camera reference still points at the flight camera.
	# Check the viewport's actual current camera instead.
	var viewport_cam: Camera3D = get_viewport().get_camera_3d()
	if viewport_cam and viewport_cam is GalaxyMapCamera:
		if _container.visible:
			_container.visible = false
		return
	# Also hide during dialogue so markers don't clutter the conversation.
	if _is_dialogue_active():
		if _container.visible:
			_container.visible = false
		return
	# Re-enable if previously hidden
	if not _container.visible:
		_container.visible = true

	_viewport_size = get_viewport().get_visible_rect().size
	var margin: float = 60.0

	# Find nearest planet
	var nearest: Node3D = null
	var nearest_dist: float = INF
	var ship: Node3D = _camera.get_parent()
	if ship == null:
		ship = _camera

	# Update each indicator
	for planet: Node in _indicators:
		if not is_instance_valid(planet):
			continue
		var data: Dictionary = _indicators[planet]
		var bracket: Control = data["bracket"]
		var _label: Label = data["label"]
		var dist_label: Label = data["dist_label"]
		var edge_arrow: Line2D = data["edge_arrow"]
		var _base_color: Color = data["color"]

		var planet_3d: Node3D = planet as Node3D
		var world_pos: Vector3 = planet_3d.global_position
		var dist: float = ship.global_position.distance_to(world_pos)

		# Track nearest
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = planet_3d

		# Format distance
		dist_label.text = _format_distance(dist)

		# Project to screen space
		var screen_pos: Vector2 = _camera.unproject_position(world_pos)
		var on_screen: bool = _camera.is_position_behind(world_pos) == false

		# Check if the projected position is within the viewport
		var in_viewport: bool = on_screen and \
			screen_pos.x > 0 and screen_pos.x < _viewport_size.x and \
			screen_pos.y > 0 and screen_pos.y < _viewport_size.y

		if in_viewport:
			# Show bracket marker at projected position
			bracket.visible = true
			bracket.position = Vector2(screen_pos.x, screen_pos.y)
			edge_arrow.visible = false

			# Scale brackets based on distance (closer = bigger)
			var scale_factor: float = clampf(2000.0 / maxf(dist, 1.0), 0.5, 3.0)
			bracket.scale = Vector2(scale_factor, scale_factor)
		else:
			# Show edge arrow pointing toward the body
			bracket.visible = false
			edge_arrow.visible = true

			# Calculate direction to body in screen space
			var dir_2d: Vector2
			if on_screen:
				# On screen but outside viewport bounds — clamp to edge
				dir_2d = Vector2(screen_pos.x, screen_pos.y) - _viewport_size * 0.5
			else:
				# Behind camera — project direction from camera forward
				var cam_to_planet: Vector3 = (world_pos - _camera.global_position).normalized()
				var cam_right: Vector3 = _camera.global_transform.basis.x
				var cam_up: Vector3 = _camera.global_transform.basis.y
				dir_2d = Vector2(
					cam_to_planet.dot(cam_right),
					-cam_to_planet.dot(cam_up)  # Y is flipped in screen space
				)

			if dir_2d.length() < 0.01:
				dir_2d = Vector2(0, -1)  # Default up

			dir_2d = dir_2d.normalized()

			# Position arrow at screen edge
			var center: Vector2 = _viewport_size * 0.5
			var half_size: Vector2 = _viewport_size * 0.5 - Vector2(margin, margin)

			# Find intersection with screen edge
			var t_x: float = half_size.x / absf(dir_2d.x) if absf(dir_2d.x) > 0.001 else INF
			var t_y: float = half_size.y / absf(dir_2d.y) if absf(dir_2d.y) > 0.001 else INF
			var t: float = minf(t_x, t_y)

			var arrow_pos: Vector2 = center + dir_2d * t

			# Draw arrow pointing in dir_2d
			arrow_pos = arrow_pos.round()
			var tip: Vector2 = arrow_pos + dir_2d * 15.0
			var left: Vector2 = arrow_pos + dir_2d.rotated(2.5) * 10.0
			var right: Vector2 = arrow_pos + dir_2d.rotated(-2.5) * 10.0

			edge_arrow.clear_points()
			edge_arrow.add_point(left)
			edge_arrow.add_point(tip)
			edge_arrow.add_point(right)

			# Add name label as a child of the arrow (reposition)
			edge_arrow.position = Vector2.ZERO

	# Highlight nearest planet
	if nearest != null and nearest != _nearest_planet:
		_nearest_planet = nearest
		# Update all indicator colors
		for planet: Node in _indicators:
			if not is_instance_valid(planet):
				continue
			var data: Dictionary = _indicators[planet]
			var color: Color = data["color"]
			if planet == nearest:
				color = COLOR_NEAREST
			_update_indicator_color(data, color)

	# Update nearby star system indicators
	_update_nearby_system_indicators(ship)

# ------------------------------------------------------------------------------
# Nearby Star System Indicator Updates
# ------------------------------------------------------------------------------
func _update_nearby_system_indicators(_ship: Node3D) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var margin: float = 80.0
	var center: Vector2 = _viewport_size * 0.5

	# Get current galactic position from UniverseManager
	var current_galactic_pos: Vector3 = Vector3.ZERO
	if _universe_manager != null and is_instance_valid(_universe_manager):
		current_galactic_pos = _universe_manager.galactic_coordinates_ly

	for sys_data: Dictionary in _system_indicators:
		var marker: Control = sys_data["marker"]
		var dist_label: Label = sys_data["dist_label"]
		var edge_diamond: Line2D = sys_data["edge_diamond"]
		var galactic_pos: Vector3 = sys_data["galactic_pos"]

		# Direction from current system to nearby system in galactic coordinates (light-years)
		var dir_ly: Vector3 = galactic_pos - current_galactic_pos
		var dist_ly: float = dir_ly.length()

		# Update distance label
		dist_label.text = "%.1f LY — HyperWave Jump Required" % dist_ly

		# Project the direction onto the camera's view plane.
		# Since nearby systems are light-years away (not in the 3D scene),
		# we use the camera's basis to project the galactic direction onto screen space.
		var cam_right: Vector3 = _camera.global_transform.basis.x
		var cam_up: Vector3 = _camera.global_transform.basis.y
		var cam_fwd: Vector3 = -_camera.global_transform.basis.z

		# Project galactic direction onto camera axes
		var screen_x: float = dir_ly.dot(cam_right)
		var screen_y: float = -dir_ly.dot(cam_up)  # Y flipped in screen space
		var screen_z: float = dir_ly.dot(cam_fwd)  # Positive = in front

		var dir_2d: Vector2 = Vector2(screen_x, screen_y)
		if dir_2d.length() < 0.001:
			dir_2d = Vector2(0, -1)
		dir_2d = dir_2d.normalized()

		if screen_z > 0 and dir_2d.length() > 0.01:
			# System is in front of the camera — check if in viewport
			# Map direction to screen position (scaled to place near screen edge for distant objects)
			var half_size: Vector2 = _viewport_size * 0.5 - Vector2(margin, margin)

			# For on-screen display, place the marker at a proportional position
			# Use a large virtual distance so the marker appears at a fixed screen position
			# based on the direction only (since all nearby systems are "infinitely" far away)
			var t_x: float = half_size.x / absf(dir_2d.x) if absf(dir_2d.x) > 0.001 else INF
			var t_y: float = half_size.y / absf(dir_2d.y) if absf(dir_2d.y) > 0.001 else INF
			var t: float = minf(t_x, t_y) * 0.7  # Place at 70% toward edge

			var marker_pos: Vector2 = center + dir_2d * t

			# Check if within viewport bounds (with some margin)
			if marker_pos.x > 20 and marker_pos.x < _viewport_size.x - 20 and \
			   marker_pos.y > 20 and marker_pos.y < _viewport_size.y - 20:
				# Show on-screen diamond marker
				marker.visible = true
				marker.position = marker_pos
				edge_diamond.visible = false
			else:
				# Show edge indicator
				marker.visible = false
				edge_diamond.visible = true
				var edge_pos: Vector2 = center + dir_2d * minf(t_x, t_y)
				edge_diamond.position = edge_pos
		else:
			# System is behind camera — show edge indicator
			marker.visible = false
			edge_diamond.visible = true
			# Flip direction for behind-camera indicators
			var behind_dir: Vector2 = -dir_2d
			var t_x: float = (_viewport_size.x * 0.5 - margin) / absf(behind_dir.x) if absf(behind_dir.x) > 0.001 else INF
			var t_y: float = (_viewport_size.y * 0.5 - margin) / absf(behind_dir.y) if absf(behind_dir.y) > 0.001 else INF
			var t: float = minf(t_x, t_y)
			var edge_pos: Vector2 = center + behind_dir * t
			edge_diamond.position = edge_pos

func _spectral_class_letter(idx: int) -> String:
	# O B A F G K M (stellar classification, hot to cool)
	var letters: Array[String] = ["O", "B", "A", "F", "G", "K", "M"]
	if idx >= 0 and idx < letters.size():
		return letters[idx]
	return "?"

func _update_indicator_color(data: Dictionary, color: Color) -> void:
	var bracket: Control = data["bracket"]
	for child: Node in bracket.get_children():
		if child is Line2D:
			(child as Line2D).default_color = color
		elif child is Label:
			(child as Label).add_theme_color_override("font_color", color)
	var edge_arrow: Line2D = data["edge_arrow"]
	edge_arrow.default_color = color

func _format_distance(dist: float) -> String:
	if dist < 1000.0:
		return "%.0f m" % dist
	elif dist < 1000000.0:
		return "%.1f km" % (dist / 1000.0)
	elif dist < 149597870700.0:
		return "%.1f Mm" % (dist / 1000000.0)
	else:
		return "%.2f AU" % (dist / 149597870700.0)

func _exit_tree() -> void:
	# Stop processing during cleanup
	set_process(false)
	# Clean up planet indicators
	for planet: Node in _indicators:
		var data: Dictionary = _indicators[planet]
		var bracket: Control = data["bracket"]
		var edge_arrow: Line2D = data["edge_arrow"]
		if is_instance_valid(bracket):
			bracket.queue_free()
		if is_instance_valid(edge_arrow):
			edge_arrow.queue_free()
	_indicators.clear()
	# Clean up nearby star system indicators
	for sys_data: Dictionary in _system_indicators:
		var marker: Control = sys_data["marker"]
		var edge_diamond: Line2D = sys_data["edge_diamond"]
		if is_instance_valid(marker):
			marker.queue_free()
		if is_instance_valid(edge_diamond):
			edge_diamond.queue_free()
	_system_indicators.clear()

## Returns true if a DialogueUI is currently active (conversation in progress).
func _is_dialogue_active() -> bool:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root:
		for child in ml.root.get_children():
			if child is DialogueUI and child.is_active():
				return true
	return false

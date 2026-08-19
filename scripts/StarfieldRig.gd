# res://scripts/StarfieldRig.gd
# ==============================================================================
# BioGenesis-X: Starlight Addon Integration Rig (Floating-Origin Compatible)
# ==============================================================================
# Wraps the Starlight `StarGenerator` node and keeps it centered on the active
# camera every frame so the procedural PSF starfield behaves as an
# infinite-distance skybox:
#
#   * Stars never parallax against the ship (they "follow" the camera).
#   * The star MultiMesh instances stay near the world origin where float32
#     precision is highest, so the floating-origin shift in FlightController
#     never degrades star rendering precision.
#
# Visibility is automatically disabled while a planet descent / surface
# sequence is active (PlanetEntryManager.is_descent_active()), so the starfield
# only renders during space flight and is hidden on planet surfaces.
#
# The actual StarGenerator node is placed as a child ("StarGenerator") in the
# space_flight scene so its PSF shader parameters are editable in the inspector.
# ==============================================================================

class_name StarfieldRig
extends Node3D

## If true, the rig re-centers itself on the active camera every frame so the
## starfield acts as an infinite-distance skybox (floating-origin safe).
@export var follow_camera: bool = true

## If true, the starfield remains visible even while a planet descent/surface
## sequence is active. Default false — stars are hidden on planet surfaces.
@export var visible_during_descent: bool = false

var _star_generator: Node3D = null
var _camera: Camera3D = null


func _ready() -> void:
	_star_generator = get_node_or_null("StarGenerator")
	_refresh_camera()


func _refresh_camera() -> void:
	var vp: Viewport = get_viewport()
	if vp != null:
		_camera = vp.get_camera_3d()


func _process(_delta: float) -> void:
	if follow_camera:
		if _camera == null or not is_instance_valid(_camera):
			_refresh_camera()
		if _camera != null and is_instance_valid(_camera):
			# Track the camera's global position so the star sphere (radius
			# `size` around the generator origin) always surrounds the viewer.
			# This is the key floating-origin adaptation: the rig never drifts
			# away from the camera, so star instance transforms stay near (0,0,0)
			# where float32 precision is highest.
			global_position = _camera.global_position
	visible = _compute_visibility()


## Returns whether the starfield should currently render. Hidden during active
## planet descent/surface mode unless `visible_during_descent` is set.
func _compute_visibility() -> bool:
	if visible_during_descent:
		return true
	if not is_inside_tree() or get_tree() == null or get_tree().root == null:
		return true
	var pem: Node = get_tree().root.get_node_or_null("/root/PlanetEntryManager")
	if pem != null and pem.has_method("is_descent_active"):
		if pem.call("is_descent_active") == true:
			return false
	return true


## Returns the Starlight StarGenerator child node (or null if not present).
func get_star_generator() -> Node3D:
	return _star_generator

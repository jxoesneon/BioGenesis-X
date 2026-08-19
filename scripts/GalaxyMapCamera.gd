extends Camera3D
class_name GalaxyMapCamera

@export var fly_speed_base: float = 100.0
@export var look_sensitivity: float = 0.003
@export var sweep_speed: float = 3.0
@export var focus_distance: float = 15.0

var pitch: float = 0.0
var yaw: float = 0.0
var target_pitch: float = 0.0
var target_yaw: float = 0.0

var target_position: Vector3
var is_mouse_looking: bool = false

# Velocity for predictive sector loading (world units/sec)
var velocity: Vector3 = Vector3.ZERO
var _prev_global_position: Vector3 = Vector3.ZERO

# Debug: track if zoom was requested
var _zoom_debug_counter: int = 0

enum CameraMode { FREE_FLY, SWEEPING_TO_NODE, FOCUSED }
var current_mode: CameraMode = CameraMode.FREE_FLY

func _ready():
	# Physics interpolation is enabled globally (common/physics_interpolation=true).
	# The camera must either:
	#   A) Move in _physics_process() (interpolation works automatically), OR
	#   B) Move in _process() with physics_interpolation_mode = OFF + top_level = true
	#
	# We use approach A: move in _physics_process(). This is the Godot-recommended
	# approach and avoids the "Interpolated Camera3D triggered from outside physics
	# process" warning.
	#
	# See: https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/using_physics_interpolation.html

	# Make the camera independent of its parent's transform so that
	# parent physics interpolation doesn't affect the camera's global transform.
	# See: https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/advanced_physics_interpolation.html
	top_level = true

	# Also reset interpolation state to avoid streaking from the initial position
	reset_physics_interpolation()

	target_position = global_position
	# Look down from top right
	pitch = -PI / 4.0
	yaw = PI / 4.0
	target_pitch = pitch
	target_yaw = yaw

	transform.basis = Basis()
	rotate_object_local(Vector3.UP, yaw)
	rotate_object_local(Vector3.RIGHT, pitch)

# ==========================================================================
# INPUT — handle in both _input AND _unhandled_input for maximum reliability.
# _input fires first (before GUI), _unhandled_input fires last (after GUI).
# Using both ensures scroll events are caught regardless of GUI interception.
#
# Three input types are handled for zoom:
#   1. InputEventMouseButton (MOUSE_BUTTON_WHEEL_UP/DOWN) — regular mouse
#   2. InputEventPanGesture — macOS trackpad two-finger scroll
#   3. InputEventMagnifyGesture — macOS trackpad pinch-to-zoom
#
# On macOS, trackpads do NOT emit MOUSE_BUTTON_WHEEL_UP/DOWN events.
# They emit InputEventPanGesture with a delta vector instead.
# See: https://forum.godotengine.org/t/mouse-wheel-detection-not-working-in-os-x/9038
# ==========================================================================
func _input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				is_mouse_looking = true
				if current_mode == CameraMode.FOCUSED:
					unfocus()
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				is_mouse_looking = false

		# Scroll to Zoom — regular mouse wheel
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_handle_zoom(-1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_handle_zoom(1.0)

	elif event is InputEventMouseMotion and is_mouse_looking:
		target_yaw -= event.relative.x * look_sensitivity
		target_pitch -= event.relative.y * look_sensitivity
		target_pitch = clamp(target_pitch, -PI/2.1, PI/2.1)

	# macOS trackpad two-finger scroll → InputEventPanGesture
	# delta.y > 0 = scroll up (zoom in), delta.y < 0 = scroll down (zoom out)
	elif event is InputEventPanGesture:
		var pan_delta: float = event.delta.y
		if abs(pan_delta) > 0.01:
			# Normalize to a zoom direction: positive delta = zoom in
			_handle_zoom_continuous(-pan_delta)

	# macOS trackpad pinch-to-zoom → InputEventMagnifyGesture
	# factor > 1.0 = zoom in, factor < 1.0 = zoom out
	# Negate so that positive magnitude = zoom in (matching pan gesture convention)
	elif event is InputEventMagnifyGesture:
		var mag_factor: float = event.factor
		if abs(mag_factor - 1.0) > 0.01:
			_handle_zoom_continuous(-(mag_factor - 1.0))

# Fallback: _unhandled_input catches scroll events that _input might miss
# if a Control is somehow intercepting them in _gui_input.
func _unhandled_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_handle_zoom(-1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_handle_zoom(1.0)
	elif event is InputEventPanGesture:
		var pan_delta: float = event.delta.y
		if abs(pan_delta) > 0.01:
			_handle_zoom_continuous(-pan_delta)
	elif event is InputEventMagnifyGesture:
		var mag_factor: float = event.factor
		if abs(mag_factor - 1.0) > 0.01:
			_handle_zoom_continuous(-(mag_factor - 1.0))

# ==========================================================================
# CAMERA MOVEMENT — in _physics_process() for physics interpolation compatibility.
# _input() stores zoom/orbit requests; _physics_process() applies them.
# ==========================================================================
func _physics_process(delta: float):
	# Handle Rotations
	yaw = lerp_angle(yaw, target_yaw, delta * 15.0)
	pitch = lerp_angle(pitch, target_pitch, delta * 15.0)

	transform.basis = Basis()
	rotate_object_local(Vector3.UP, yaw)
	rotate_object_local(Vector3.RIGHT, pitch)

	var forward := -transform.basis.z.normalized()
	var right := transform.basis.x.normalized()
	var up := transform.basis.y.normalized()

	# Handle Translations
	if current_mode == CameraMode.FREE_FLY:
		var input_dir := Vector2.ZERO
		if Input.is_key_pressed(KEY_A): input_dir.x -= 1.0
		if Input.is_key_pressed(KEY_D): input_dir.x += 1.0
		if Input.is_key_pressed(KEY_W): input_dir.y += 1.0
		if Input.is_key_pressed(KEY_S): input_dir.y -= 1.0

		var vertical := 0.0
		if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE):
			vertical += 1.0
		if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL):
			vertical -= 1.0

		var fly_speed := fly_speed_base
		if Input.is_key_pressed(KEY_SHIFT):
			fly_speed *= 5.0

		var move_dir := (right * input_dir.x + forward * input_dir.y + up * vertical).normalized()

		if move_dir.length() > 0:
			target_position += move_dir * fly_speed * delta

			if target_position.length() > ProceduralGalaxy.GALAXY_RADIUS_LY:
				target_position = target_position.normalized() * ProceduralGalaxy.GALAXY_RADIUS_LY

		global_position = global_position.lerp(target_position, delta * 5.0)

	elif current_mode == CameraMode.SWEEPING_TO_NODE or current_mode == CameraMode.FOCUSED:
		var dist = global_position.distance_to(target_position)

		# Exponential smooth-damp style lerp. Slower when far away for the grand overview, faster near the end to snap.
		var t = delta * sweep_speed * 0.4
		global_position = global_position.lerp(target_position, clamp(t, 0.0, 1.0))

		if current_mode == CameraMode.SWEEPING_TO_NODE and dist < 2.0:
			current_mode = CameraMode.FOCUSED

	# Track velocity for predictive sector loading
	if delta > 0.0:
		velocity = (global_position - _prev_global_position) / delta
	_prev_global_position = global_position

# Continuous zoom for trackpad gestures (pan/magnify).
# magnitude > 0 = zoom in, magnitude < 0 = zoom out.
# The magnitude scales the zoom step proportionally.
func _handle_zoom_continuous(magnitude: float) -> void:
	var forward := -transform.basis.z.normalized()
	var zoom_amount: float = clampf(abs(magnitude), 0.1, 5.0)
	var direction: float = sign(magnitude) # -1 = zoom in, +1 = zoom out

	if current_mode == CameraMode.FREE_FLY:
		var dist_to_center := global_position.length()
		var zoom_step := maxf(fly_speed_base * 0.5, dist_to_center * 0.1) * zoom_amount * 0.3
		if Input.is_key_pressed(KEY_SHIFT):
			zoom_step *= 5.0
		target_position += forward * direction * zoom_step

	elif current_mode == CameraMode.FOCUSED:
		var look_at_point := target_position + forward * focus_distance
		var zoom_step := maxf(focus_distance * 0.15, 2.0) * zoom_amount * 0.3
		focus_distance = clampf(focus_distance + direction * zoom_step, 2.0, 800.0)
		target_position = look_at_point - forward * focus_distance

	elif current_mode == CameraMode.SWEEPING_TO_NODE:
		var dist_to_target := global_position.distance_to(target_position)
		var zoom_step := maxf(dist_to_target * 0.12, 5.0) * zoom_amount * 0.3
		target_position += forward * direction * zoom_step
		focus_distance = clampf(focus_distance + direction * zoom_step * 0.5, 2.0, 800.0)

	_zoom_debug_counter += 1
	if _zoom_debug_counter <= 3:
		print("[GalaxyMapCamera] Trackpad zoom #%d: mode=%s mag=%.2f focus_distance=%.1f" % [
			_zoom_debug_counter, current_mode, magnitude, focus_distance])

func _handle_zoom(direction: float) -> void:
	# direction: -1 = zoom in (wheel up), +1 = zoom out (wheel down)
	var forward := -transform.basis.z.normalized()

	if current_mode == CameraMode.FREE_FLY:
		# Free-fly: move target position along view direction.
		# Step is proportional to current distance from galaxy center
		# so zoom feels consistent at any scale.
		var dist_to_center := global_position.length()
		var zoom_step := maxf(fly_speed_base * 0.5, dist_to_center * 0.1)
		if Input.is_key_pressed(KEY_SHIFT):
			zoom_step *= 5.0
		target_position += forward * direction * zoom_step

	elif current_mode == CameraMode.FOCUSED:
		# Focused: keep the same look-at point, move camera closer/farther.
		# Step is proportional to current focus_distance so zoom feels
		# consistent whether you're 5 units or 200 units from the target.
		var look_at_point := target_position + forward * focus_distance
		var zoom_step := maxf(focus_distance * 0.15, 2.0)
		focus_distance = clampf(focus_distance + direction * zoom_step, 2.0, 800.0)
		target_position = look_at_point - forward * focus_distance

	elif current_mode == CameraMode.SWEEPING_TO_NODE:
		# Still sweeping — adjust both focus_distance AND target_position
		# so the zoom takes effect immediately, not just after arrival.
		var dist_to_target := global_position.distance_to(target_position)
		var zoom_step := maxf(dist_to_target * 0.12, 5.0)
		# Move target_position closer/farther along the view direction
		target_position += forward * direction * zoom_step
		# Also adjust focus_distance for when we arrive
		focus_distance = clampf(focus_distance + direction * zoom_step * 0.5, 2.0, 800.0)

	# Debug: increment counter to verify zoom is being called
	_zoom_debug_counter += 1
	if _zoom_debug_counter <= 3:
		print("[GalaxyMapCamera] Zoom #%d: mode=%s dir=%.0f focus_distance=%.1f target=%s" % [
			_zoom_debug_counter, current_mode, direction, focus_distance, target_position])

func focus_on_system(pos: Vector3):
	current_mode = CameraMode.SWEEPING_TO_NODE

	# NMS jump: Position the camera near the star looking slightly off-center
	# Maintain current view direction to make it continuous
	var view_dir := -transform.basis.z.normalized()
	target_position = pos - view_dir * focus_distance

func intro_zoom(pos: Vector3):
	current_mode = CameraMode.SWEEPING_TO_NODE

	# Start extremely high above the galactic center to view the entire galaxy map
	global_position = Vector3(0, 1200.0, 0)
	pitch = -PI / 2.0
	yaw = PI / 4.0
	target_pitch = -PI / 6.0 # Flatten out as we zoom in
	target_yaw = PI / 4.0

	transform.basis = Basis()
	rotate_object_local(Vector3.UP, yaw)
	rotate_object_local(Vector3.RIGHT, pitch)

	# Reset interpolation after teleporting to avoid streaking
	reset_physics_interpolation()

	var final_basis := Basis()
	final_basis = final_basis.rotated(Vector3.UP, target_yaw)
	final_basis = final_basis.rotated(Vector3.RIGHT, target_pitch)
	var final_view_dir := -final_basis.z.normalized()

	target_position = pos - final_view_dir * focus_distance

func unfocus():
	current_mode = CameraMode.FREE_FLY

# Helper for GalaxyMapManager to fetch sectors based on where the camera is looking
func get_focal_point() -> Vector3:
	if current_mode == CameraMode.FREE_FLY:
		# Look ahead into the depth to load stars we are flying towards
		var forward := -transform.basis.z.normalized()
		return global_position + forward * 50.0
	else:
		return target_position + transform.basis.z.normalized() * focus_distance

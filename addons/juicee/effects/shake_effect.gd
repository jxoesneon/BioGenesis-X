@tool
class_name JuiceeShakeEffect
extends JuiceeEffect

## Maximum shake displacement in pixels.
@export_range(0.0, 100.0, 0.5) var intensity: float = 8.0
## Total shake duration in seconds.
@export_range(0.05, 5.0, 0.05) var duration: float = 0.3
## Shake oscillations per second.
@export_range(1.0, 60.0, 0.5) var frequency: float = 15.0
## How quickly the shake amplitude falls off. 0 = constant, higher = faster decay.
@export_range(0.0, 5.0, 0.01) var decay: float = 0.8
## If true, uses smooth Perlin noise. If false, uses random offsets (jittery).
@export var use_noise: bool = true

func get_accessibility_tag() -> int: return JuiceeAccessibility.TAG_SCREENSHAKE
func get_category_color() -> Color:
	return Color(0.72, 0.28, 0.95)

func _apply(context: Node, intensity_mult: float) -> void:
	if not context or not context.is_inside_tree():
		return
	var cam: Camera2D = context.get_viewport().get_camera_2d()
	if not cam:
		push_warning("JuiceeShakeEffect: no Camera2D in viewport")
		return

	# Directional juicee: if caller passed {"hit_direction": Vector2.LEFT}, bias the shake
	# in that direction so the camera "recoils" away from the hit.
	var hit_direction: Vector2 = _runtime_params.get("hit_direction", Vector2.ZERO)
	var has_direction: bool = hit_direction != Vector2.ZERO
	if has_direction:
		hit_direction = hit_direction.normalized()

	var noise: FastNoiseLite
	if use_noise:
		noise = FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_PERLIN
		noise.seed = randi()

	var effective_intensity := intensity * intensity_mult
	# Ref-counted state — handles concurrent shakes correctly.
	var original_offset: Vector2 = _capture_state(cam, "offset")
	var elapsed: float = 0.0
	var step: float = 1.0 / frequency
	var noise_offset: float = 0.0
	var tree := context.get_tree()

	while elapsed < duration and is_instance_valid(cam) and not _cancelled:
		var progress: float = elapsed / duration
		var current_intensity: float = effective_intensity * pow(1.0 - progress, decay * 2.0)
		var offset: Vector2
		if use_noise:
			noise_offset += step * 10.0
			offset = Vector2(
				noise.get_noise_1d(noise_offset) * current_intensity,
				noise.get_noise_1d(noise_offset + 100.0) * current_intensity
			)
		else:
			offset = Vector2(
				randf_range(-current_intensity, current_intensity),
				randf_range(-current_intensity, current_intensity)
			)
		# Add directional bias on top of the random noise (recoil away from hit).
		if has_direction:
			var directional_pulse: float = current_intensity * 0.6 * sin(elapsed * frequency * TAU)
			offset += hit_direction * directional_pulse
		cam.offset = original_offset + offset
		await tree.create_timer(step, true, false, false).timeout
		elapsed += step

	_release_state(cam, "offset")

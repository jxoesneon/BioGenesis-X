## Multi-color particle burst for celebrations / level-ups.
## Like JuiceeBurstEffect but with randomized colors per-particle.
@tool
class_name JuiceeConfettiEffect
extends JuiceeEffect

## Number of confetti particles.
@export_range(8, 256, 1) var amount: int = 40
## Average particle speed (randomized 0.5×–1.5×).
@export_range(0.0, 800.0, 5.0) var speed: float = 200.0
## Spread angle in degrees (360 = burst in all directions, 180 = hemisphere).
@export_range(0.0, 360.0, 1.0) var spread: float = 180.0
## Particle lifetime in seconds.
@export_range(0.1, 5.0, 0.05) var lifetime: float = 1.2
## Gravity per second. Default falls down for celebratory rain.
@export var gravity: Vector2 = Vector2(0, 250)
## Color palette — each particle picks a color along this gradient.
@export var colors: PackedColorArray = PackedColorArray([
	Color(1.0, 0.3, 0.3),
	Color(1.0, 0.8, 0.3),
	Color(0.3, 1.0, 0.4),
	Color(0.3, 0.6, 1.0),
	Color(0.9, 0.4, 1.0),
])

func get_category_color() -> Color:
	return Color(0.22, 0.58, 1.00)

func _apply(context: Node, intensity_mult: float) -> void:
	# Particles render in editor preview — no global side effects on the editor.
	var origin: Node2D = context as Node2D
	if not origin or not origin.is_inside_tree():
		push_warning("JuiceeConfettiEffect: context is not a Node2D")
		return

	var effective_amount := max(1, int(amount * intensity_mult))
	var color_ramp := Gradient.new()
	if colors.size() > 0:
		color_ramp.colors = colors
		var offsets := PackedFloat32Array()
		for i in colors.size():
			offsets.append(float(i) / max(1, colors.size() - 1))
		color_ramp.offsets = offsets

	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = effective_amount
	p.lifetime = lifetime
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed * 1.5
	p.spread = spread
	p.gravity = gravity
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.color_ramp = color_ramp
	p.global_position = origin.global_position
	# current_scene is null in autoload / added-to-root contexts — fall back to origin.
	var spawn_parent: Node = origin.get_tree().current_scene
	if not spawn_parent:
		spawn_parent = origin
	spawn_parent.add_child(p)
	p.emitting = true
	await origin.get_tree().create_timer(lifetime + 0.2, true, false, false).timeout
	if is_instance_valid(p):
		p.queue_free()

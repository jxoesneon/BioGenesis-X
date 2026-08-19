## Cycle a CanvasItem's modulate through the HSV color wheel.
##
## Use for: powerup glow ("RAINBOW MODE"), party/celebration sequences,
## boss "phase 2" warning, victory screens, easter eggs. Combine with
## a `JuiceeFlashEffect` at the start to sell the moment.
@tool
class_name JuiceeColorCycleEffect
extends JuiceeEffect

## Number of full hue revolutions across the duration.
@export_range(0.5, 16.0, 0.5) var cycles: float = 2.0
## Total duration of the cycling.
@export_range(0.1, 30.0, 0.1) var duration: float = 1.5
## Saturation of the cycled hue (0 = grayscale, 1 = full color).
@export_range(0.0, 1.0, 0.01) var saturation: float = 1.0
## Value/brightness of the cycled hue (1 = full bright).
@export_range(0.0, 2.0, 0.01) var value: float = 1.0
## If true, alpha is preserved from the original modulate. If false, fully opaque.
@export var preserve_alpha: bool = true
## If true, cycle forever (until stop()). `duration` still sets the cycle SPEED
## (cycles per duration), it just no longer ends the effect. Great for a persistent
## "RAINBOW MODE" glow on a title, powerup, or victory banner.
@export var loop: bool = false

func get_category_color() -> Color:
	return Color(0.22, 0.58, 1.00)

func get_category_name() -> String:
	return "Object"

func _apply(context: Node, intensity_mult: float) -> void:
	var target: CanvasItem = context as CanvasItem
	if not target or not target.is_inside_tree():
		push_warning("JuiceeColorCycleEffect: context is not a CanvasItem")
		return

	var original_modulate: Color = _capture_state(target, "modulate")
	var tree := target.get_tree()
	if not tree:
		_release_state(target, "modulate")
		return

	var elapsed := 0.0
	var effective_sat: float = clamp(saturation * intensity_mult, 0.0, 1.0)
	while (loop or elapsed < duration) and not _cancelled and is_instance_valid(target):
		var hue: float = fposmod(elapsed / duration * cycles, 1.0)
		var c := Color.from_hsv(hue, effective_sat, value, 1.0)
		if preserve_alpha:
			c.a = original_modulate.a
		target.modulate = c
		await tree.process_frame
		elapsed += tree.root.get_process_delta_time()

	if is_instance_valid(target):
		target.modulate = original_modulate
	_release_state(target, "modulate")

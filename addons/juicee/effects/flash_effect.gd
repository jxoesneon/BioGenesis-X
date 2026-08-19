@tool
class_name JuiceeFlashEffect
extends JuiceeEffect

## Color to flash to. White = bright flash, red = damage, etc.
@export var flash_color: Color = Color.WHITE
## Total duration spread across all flashes.
@export_range(0.05, 2.0, 0.05) var duration: float = 0.15
## Number of flashes to perform. 1 = single, 3 = blink three times.
@export_range(1, 10, 1) var flash_count: int = 1

func get_accessibility_tag() -> int: return JuiceeAccessibility.TAG_FLASH
func get_category_color() -> Color:
	return Color(0.22, 0.58, 1.00)

func _apply(context: Node, intensity_mult: float) -> void:
	var target: CanvasItem = context as CanvasItem
	if not target or not target.is_inside_tree():
		push_warning("JuiceeFlashEffect: context is not a CanvasItem in the tree")
		return

	var original_modulate: Color = _capture_state(target, "modulate")
	var effective_color := flash_color
	if intensity_mult != 1.0:
		effective_color = original_modulate.lerp(flash_color, clamp(intensity_mult, 0.0, 1.0))
	var single_duration: float = duration / float(flash_count * 2)
	var tween := _track(target.create_tween())

	for i in flash_count:
		tween.tween_property(target, "modulate", effective_color, single_duration)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(target, "modulate", original_modulate, single_duration)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	await tween.finished
	_release_state(target, "modulate")

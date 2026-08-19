# res://scripts/BioSporeCloud.gd
# ==============================================================================
# BioGenesis-X - Area-of-Effect Defensive Bio-Spore Cloud (AAA+ Jolt Physics)
# ==============================================================================
@tool
class_name BioSporeCloud
extends Area3D

var duration: float = 6.0
var dps: float = 15.0
var radius: float = 5.0

## Initialize the spore cloud with parameters. Called by WeaponSystem after instantiation.
func setup(p_radius: float, p_dps: float, p_duration: float) -> void:
	radius = p_radius
	dps = p_dps
	duration = p_duration
	# Set collision shape radius if present
	for child in get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is SphereShape3D:
			((child as CollisionShape3D).shape as SphereShape3D).radius = radius

func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	if is_queued_for_deletion():
		return

	duration -= delta
	if duration <= 0.0:
		queue_free()
		return

	# Tick-aligned area damage on overlapping bodies
	for body: Node3D in get_overlapping_bodies():
		if is_instance_valid(body) and not body.is_queued_for_deletion() and body != self:
			if body.has_method("take_damage"):
				body.call("take_damage", dps * delta)
			elif is_instance_valid(body.get_parent()) and body.get_parent().has_method("take_damage"):
				body.get_parent().call("take_damage", dps * delta)

	# Tick-aligned area damage on overlapping areas
	for area: Area3D in get_overlapping_areas():
		if is_instance_valid(area) and not area.is_queued_for_deletion() and area != self:
			if area.has_method("take_damage"):
				area.call("take_damage", dps * delta)
			elif is_instance_valid(area.get_parent()) and area.get_parent().has_method("take_damage"):
				area.get_parent().call("take_damage", dps * delta)

func _on_body_entered(body: Node) -> void:
	if is_instance_valid(body):
		if body.has_method("apply_spore_slow"):
			body.call("apply_spore_slow", 0.5, duration)
		elif is_instance_valid(body.get_parent()) and body.get_parent().has_method("apply_spore_slow"):
			body.get_parent().call("apply_spore_slow", 0.5, duration)

func _on_area_entered(area: Area3D) -> void:
	if is_instance_valid(area) and area != self:
		if area.has_method("apply_spore_slow"):
			area.call("apply_spore_slow", 0.5, duration)
		elif is_instance_valid(area.get_parent()) and area.get_parent().has_method("apply_spore_slow"):
			area.get_parent().call("apply_spore_slow", 0.5, duration)

## Backward compatibility alias for _on_body_entered
func _on_ent(body: Node) -> void:
	_on_body_entered(body)

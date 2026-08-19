# res://scripts/VoidFaunaDrone.gd
# ==============================================================================
# BioGenesis-X - Void-Fauna Target Drone (AAA+ Jolt Physics Integrated)
# ==============================================================================
@tool
class_name VoidFaunaDrone
extends CharacterBody3D

var health: float = 80.0
var base_position: Vector3 = Vector3.ZERO
var orbit_angle: float = 0.0
var orbit_speed: float = 0.3
var move_radius: float = 25.0
var external_velocity: Vector3 = Vector3.ZERO

func _ready() -> void:
	base_position = global_position
	orbit_angle = randf_range(0.0, TAU)
	add_to_group("void_fauna")
	add_to_group("targets")

func _physics_process(delta: float) -> void:
	orbit_angle += orbit_speed * delta
	var target_pos: Vector3 = base_position + Vector3(
		cos(orbit_angle) * move_radius,
		sin(orbit_angle * 2.0) * 8.0,
		sin(orbit_angle) * move_radius
	)
	
	if not global_position.is_equal_approx(target_pos):
		var dir: Vector3 = (target_pos - global_position).normalized()
		if abs(dir.dot(Vector3.UP)) < 0.99:
			look_at(target_pos, Vector3.UP)

	# Calculate kinematic patrol velocity towards target orbit position
	var desired_step: Vector3 = (target_pos - global_position)
	var patrol_velocity: Vector3 = desired_step * 2.0

	# Dampen external recoil impulse
	external_velocity = external_velocity.lerp(Vector3.ZERO, delta * 4.0)

	velocity = patrol_velocity + external_velocity
	move_and_slide()

	# AI Agro & Player Targeting Detection
	if is_inside_tree() and get_tree():
		var ml := Engine.get_main_loop()
		if ml is SceneTree and ml.root:
			var ws := ml.root.find_child("WeaponSystem", true, false) as WeaponSystem
			var fc := ml.root.find_child("FlightController", true, false) as Node3D
			if fc and is_instance_valid(fc) and ws and is_instance_valid(ws):
				var dist := global_position.distance_to(fc.global_position)
				if dist < 85.0:
					ws.set_targeted_by_enemy(self, true)
				elif dist > 140.0:
					ws.set_targeted_by_enemy(self, false)

func apply_impulse(impulse: Vector3, _pos: Vector3 = Vector3.ZERO) -> void:
	# Assume mass of drone ~1500 kg
	external_velocity += impulse / 1500.0

func take_damage(amount: float) -> void:
	health -= amount
	_flash_hit()

	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root:
		if ml.root.has_node("BioAudioSynth"):
			ml.root.get_node("BioAudioSynth").play_creature_vocalization(1.8)
		var ws := ml.root.find_child("WeaponSystem", true, false) as WeaponSystem
		if ws and is_instance_valid(ws):
			ws.notify_enemy_hit(self)

	if health <= 0.0:
		_on_destroyed()

func apply_spore_slow(_factor: float, _duration: float) -> void:
	orbit_speed = 0.15

func _flash_hit() -> void:
	var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh and mesh.material_override:
		var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
		mat.emission_energy_multiplier = 8.0
		if is_inside_tree() and get_tree():
			await get_tree().create_timer(0.1).timeout
			if is_instance_valid(self) and is_instance_valid(mat):
				mat.emission_energy_multiplier = 2.0

func _on_destroyed() -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root:
		if ml.root.has_node("BioAudioSynth"):
			var audio = ml.root.get_node("BioAudioSynth")
			audio.play_shield_impact()
			audio.play_creature_vocalization(0.6)
		var ws := ml.root.find_child("WeaponSystem", true, false) as WeaponSystem
		if ws and is_instance_valid(ws):
			ws.set_targeted_by_enemy(self, false)
	queue_free()

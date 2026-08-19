@tool
class_name HyperWaveAutopilot
extends Node

signal jump_sequence_started
signal jump_sequence_finished(aborted: bool)
signal jump_segment_started(target_name: String)
signal jump_segment_finished(target_name: String)

enum State { IDLE, ALIGNING, CHARGING, TRANSIT, DROPOUT, COOLDOWN }

var state: State = State.IDLE
var route: PackedVector3Array
var route_names: PackedStringArray
var route_seeds: Array[int] = []
var system_loaded: bool = false
var drop_start_pos: Vector3 = Vector3.ZERO
var drop_end_pos: Vector3 = Vector3.ZERO
var universe_fade_sphere: MeshInstance3D = null
var current_waypoint_index: int = 0

var flight_controller: Node3D
var universe_manager: Node

@export var audio_synth: Node

var warp_tunnel_mesh: MeshInstance3D
var jump_particles: GPUParticles3D
var flash_light: OmniLight3D
var spool_grid_mesh: MeshInstance3D

var timer: float = 0.0
var aborted: bool = false
var original_fov: float = 75.0

func start_jump_sequence(ship: Node3D, universe: Node, path: PackedVector3Array, names: PackedStringArray, seeds: Array[int] = []) -> void:
	flight_controller = ship
	universe_manager = universe
	route = path
	route_names = names
	route_seeds = seeds
	
	current_waypoint_index = 0
	aborted = false
	
	if route.size() < 2:
		return
		
	current_waypoint_index = 1
	state = State.ALIGNING
	
	if flight_controller:
		if flight_controller.has_method("set_physics_process"):
			flight_controller.set_physics_process(false) # Disable manual Newtonian flight
		if "camera_node" in flight_controller and flight_controller.camera_node:
			original_fov = flight_controller.camera_node.fov
			
	jump_sequence_started.emit()
	_get_audio_synth()
	_begin_alignment()

func _get_audio_synth() -> Node:
	if audio_synth and is_instance_valid(audio_synth):
		return audio_synth
	var ml := Engine.get_main_loop()
	if ml is SceneTree and ml.root and ml.root.has_node("BioAudioSynth"):
		audio_synth = ml.root.get_node("BioAudioSynth")
		return audio_synth
	return null

func _process(delta: float) -> void:
	if state == State.IDLE:
		return
		
	# Manual abort handling (can abort at any intermediate star between transits, or during transit)
	if Input.is_key_pressed(KEY_BACKSPACE) or Input.is_key_pressed(KEY_ESCAPE):
		if state != State.DROPOUT and state != State.COOLDOWN:
			_abort_sequence()
			
	match state:
		State.ALIGNING:
			_process_alignment(delta)
		State.CHARGING:
			timer -= delta
			var ratio := clampf(1.0 - (timer / 3.0), 0.0, 1.0)
			
			if not spool_grid_mesh:
				_spawn_spool_grid()
				
			if spool_grid_mesh and is_instance_valid(spool_grid_mesh) and spool_grid_mesh.material_override:
				spool_grid_mesh.material_override.set_shader_parameter("charge_ratio", ratio)
				
			if flight_controller and "wave_charge_timer" in flight_controller:
				flight_controller.wave_charge_timer = timer
				if flight_controller.has_signal("wave_state_changed"):
					flight_controller.emit_signal("wave_state_changed", 1, ratio)
					
			# Shake builds up as it charges
			if flight_controller and "camera_node" in flight_controller and flight_controller.camera_node:
				var cam = flight_controller.camera_node
				var intensity := ratio * 0.15
				cam.h_offset = (randf() - 0.5) * intensity
				cam.v_offset = (randf() - 0.5) * intensity
				
			if timer <= 0.0:
				_despawn_spool_grid()
				_enter_transit()
		State.TRANSIT:
			timer -= delta
			
			if universe_fade_sphere and is_instance_valid(universe_fade_sphere):
				var fade_out_ratio := clampf((15.0 - timer) / 3.0, 0.0, 1.0)
				universe_fade_sphere.material_override.albedo_color.a = fade_out_ratio
			
			if timer <= 5.0 and not system_loaded:
				system_loaded = true
				if universe_manager and route_seeds.size() > current_waypoint_index:
					print("HyperWave Autopilot: Physically jumping to target system...")
					var target_seed := route_seeds[current_waypoint_index]
					# Call the actual load function which replaces the environment
					universe_manager.hyperjump_to_system(target_seed)
					
					# Calculate safe distance based on the star's visual size
					var sys_data = universe_manager.current_system_data
					var rad_norm := clampf(sys_data.get("radius_km", 696340.0) / 8500000.0, 0.001, 1.0)
					var star_visual_radius := 800.0 + rad_norm * 11200.0
					var safe_distance := star_visual_radius * 4.0 # 4x radius to account for corona and heat
					
					# Randomize approach angle
					var angle := randf() * TAU
					var dir := Vector3(cos(angle), (randf() - 0.5) * 0.5, sin(angle)).normalized()
					
					drop_end_pos = dir * safe_distance
					drop_start_pos = dir * (safe_distance + 30000.0) # Start 30km back
					
					# Warp the ship back to the start pos for the new system
					if flight_controller:
						flight_controller.global_transform.origin = drop_start_pos
						flight_controller.look_at(Vector3.ZERO, Vector3.UP)
						
			# Flash light fade
			if flash_light and is_instance_valid(flash_light):
				flash_light.light_energy = lerp(flash_light.light_energy, 0.0, delta * 3.0)
				
			if flight_controller:
				if "wave_eta_seconds" in flight_controller:
					flight_controller.wave_eta_seconds = timer
					
				# Move ship rapidly forward for visual effect ONLY before jumping physically
				if not system_loaded:
					flight_controller.global_transform.origin += -flight_controller.global_transform.basis.z * 5000.0 * delta
				
				# FX: Camera Shake & FOV Stretch
				if "camera_node" in flight_controller and flight_controller.camera_node:
					var cam = flight_controller.camera_node
					cam.fov = lerp(cam.fov, 115.0, delta * 4.0)
					cam.h_offset = (randf() - 0.5) * 0.2
					cam.v_offset = (randf() - 0.5) * 0.2
					
			if timer <= 0.0:
				_enter_dropout()
		State.DROPOUT:
			timer -= delta
			
			if universe_fade_sphere and is_instance_valid(universe_fade_sphere):
				var fade_in_ratio := clampf((2.0 - timer) / 1.0, 0.0, 1.0)
				universe_fade_sphere.material_override.albedo_color.a = 1.0 - fade_in_ratio
			
			# Fade particles rapidly
			if jump_particles and is_instance_valid(jump_particles):
				jump_particles.amount_ratio = max(0.0, timer / 2.0)
				
			# Inverse grid animation: Starts fully deformed, flattens out
			var ratio := clampf(timer / 2.0, 0.0, 1.0)
			if spool_grid_mesh and is_instance_valid(spool_grid_mesh) and spool_grid_mesh.material_override:
				spool_grid_mesh.material_override.set_shader_parameter("charge_ratio", ratio)
				
			if flight_controller:
				# Interpolate position to ease out towards the star
				var progress := 1.0 - (timer / 2.0)
				var ease_out := 1.0 - pow(1.0 - progress, 3.0) # Cubic ease out
				flight_controller.global_transform.origin = drop_start_pos.lerp(drop_end_pos, ease_out)
				
				# FX: Restore Camera
				if "camera_node" in flight_controller and flight_controller.camera_node:
					var cam = flight_controller.camera_node
					cam.fov = lerp(cam.fov, original_fov, delta * 5.0)
					cam.h_offset = lerp(cam.h_offset, 0.0, delta * 10.0)
					cam.v_offset = lerp(cam.v_offset, 0.0, delta * 10.0)
					
			if timer <= 0.0:
				_finish_segment()
		State.COOLDOWN:
			timer -= delta
			if timer <= 0.0:
				if current_waypoint_index < route.size():
					_begin_alignment()
				else:
					_finish_sequence()

func _begin_alignment() -> void:
	print("HyperWave Autopilot: Aligning for jump ", current_waypoint_index, "/", route.size() - 1)
	state = State.ALIGNING
	
	if flight_controller:
		if "wave_state" in flight_controller:
			flight_controller.wave_state = 1 # CHARGING
			flight_controller.wave_charge_timer = 3.0
			flight_controller.wave_charge_duration = 3.0
		if flight_controller.has_signal("wave_state_changed"):
			flight_controller.emit_signal("wave_state_changed", 1, 0.0)
	
func _process_alignment(delta: float) -> void:
	if not flight_controller: return
	
	# Calculate direction to target in macroscopic map coordinates
	var current_pos := route[current_waypoint_index - 1]
	var target_pos := route[current_waypoint_index]
	var dir_to_target := (target_pos - current_pos).normalized()
	
	# We want to align flight_controller's -Z axis to dir_to_target
	var fwd := -flight_controller.global_transform.basis.z.normalized()
	var dot := fwd.dot(dir_to_target)
	
	if dot < 0.999:
		# Slerp basis
		var target_basis := Basis.looking_at(dir_to_target, Vector3.UP)
		var q_curr := flight_controller.global_transform.basis.get_rotation_quaternion()
		var q_targ := target_basis.get_rotation_quaternion()
		flight_controller.global_transform.basis = Basis(q_curr.slerp(q_targ, delta * 2.0))
	else:
		# Aligned
		state = State.CHARGING
		timer = 3.0 # 3 seconds charge up
		print("HyperWave Autopilot: Aligned. Charging HyperWave...")
		
		var snd_charge := _get_audio_synth()
		if snd_charge and snd_charge.has_method("play_hyperwave_charge"):
			snd_charge.play_hyperwave_charge()

func _enter_transit() -> void:
	state = State.TRANSIT
	timer = 15.0 # 15 seconds transit time (Elite Dangerous style)
	system_loaded = false
	var target_name := "System"
	if route_names.size() > current_waypoint_index:
		target_name = route_names[current_waypoint_index]
	
	if flight_controller:
		if "wave_state" in flight_controller:
			flight_controller.wave_state = 2 # ENGAGED
			flight_controller.wave_target_name = target_name
		if flight_controller.has_signal("wave_state_changed"):
			flight_controller.emit_signal("wave_state_changed", 2, 1.0)
			
	# Spawn a 2500m inverted black sphere to hide the old universe geometry without hiding the tunnel effects
	if flight_controller:
		universe_fade_sphere = MeshInstance3D.new()
		var s_mesh := SphereMesh.new()
		s_mesh.radius = 2500.0
		s_mesh.height = 5000.0
		universe_fade_sphere.mesh = s_mesh
		
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_FRONT # Inside-out
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0, 0, 0, 0.0) # Starts transparent
		universe_fade_sphere.material_override = mat
		
		flight_controller.add_child(universe_fade_sphere)
			
	jump_segment_started.emit(target_name)
	print("HyperWave Autopilot: Entering Transit to ", target_name)
	
	var snd_transit := _get_audio_synth()
	if snd_transit:
		if snd_transit.has_method("play_hyperwave_boom"):
			snd_transit.play_hyperwave_boom()
		if snd_transit.has_method("set_hyperwave_tunnel"):
			snd_transit.set_hyperwave_tunnel(true)
	
	_spawn_warp_tunnel()
	
	# Spawn a massive flash when entering transit
	if flight_controller:
		flash_light = OmniLight3D.new()
		flash_light.light_color = Color(0.8, 0.9, 1.0)
		flash_light.light_energy = 100.0
		flash_light.omni_range = 500.0
		flight_controller.add_child(flash_light)

func _enter_dropout() -> void:
	state = State.DROPOUT
	timer = 2.0
	if flight_controller:
		if "wave_state" in flight_controller:
			flight_controller.wave_state = 3 # DISENGAGING
		if flight_controller.has_signal("wave_state_changed"):
			flight_controller.emit_signal("wave_state_changed", 3, 0.0)
			
	print("HyperWave Autopilot: Dropping out of warp...")
	
	var snd_drop := _get_audio_synth()
	if snd_drop:
		if snd_drop.has_method("play_hyperwave_boom"):
			snd_drop.play_hyperwave_boom()
		if snd_drop.has_method("set_hyperwave_tunnel"):
			snd_drop.set_hyperwave_tunnel(false)
		
	# Only destroy the tunnel, leave particles to fade out
	if warp_tunnel_mesh and is_instance_valid(warp_tunnel_mesh):
		warp_tunnel_mesh.queue_free()
	warp_tunnel_mesh = null
	
	_spawn_spool_grid()

func _finish_segment() -> void:
	_despawn_warp_tunnel() # Cleans up particles
	_despawn_spool_grid()
	
	var target_name := "System"
	if route_names.size() > current_waypoint_index:
		target_name = route_names[current_waypoint_index]
	jump_segment_finished.emit(target_name)
	print("HyperWave Autopilot: Arrived at ", target_name)
	
	# Fully load the intermediate star system
	if universe_manager and universe_manager.has_method("hyperjump_to_system"):
		# We can just hash the position to generate a deterministic seed
		var pos := route[current_waypoint_index]
		var seed_val := hash(str(pos.x) + str(pos.y) + str(pos.z))
		universe_manager.hyperjump_to_system(seed_val)
		
	current_waypoint_index += 1
	
	if current_waypoint_index < route.size():
		state = State.COOLDOWN
		timer = 3.0 # Wait 3 seconds before next jump
	else:
		_finish_sequence()

func _finish_sequence() -> void:
	state = State.IDLE
	
	if universe_fade_sphere and is_instance_valid(universe_fade_sphere):
		universe_fade_sphere.queue_free()
		universe_fade_sphere = null
		
	if flight_controller:
		if "wave_state" in flight_controller:
			flight_controller.wave_state = 0 # OFF
			flight_controller.wave_target_name = ""
		if flight_controller.has_signal("wave_state_changed"):
			flight_controller.emit_signal("wave_state_changed", 0, 0.0)
		if flight_controller.has_method("set_physics_process"):
			flight_controller.set_physics_process(true)
		if "camera_node" in flight_controller and flight_controller.camera_node:
			flight_controller.camera_node.fov = original_fov
			flight_controller.camera_node.h_offset = 0.0
			flight_controller.camera_node.v_offset = 0.0
			
	if flash_light and is_instance_valid(flash_light):
		flash_light.queue_free()
			
	jump_sequence_finished.emit(aborted)
	print("HyperWave Autopilot: Route Complete.")
	queue_free()

func _abort_sequence() -> void:
	print("HyperWave Autopilot: JUMP SEQUENCE ABORTED BY USER.")
	aborted = true
	_despawn_warp_tunnel()
	_despawn_spool_grid()
	
	var snd_abort := _get_audio_synth()
	if snd_abort and snd_abort.has_method("set_hyperwave_tunnel"):
		snd_abort.set_hyperwave_tunnel(false)
	
	if flash_light and is_instance_valid(flash_light):
		flash_light.queue_free()
	
	# If in transit, instantly drop out
	if state == State.TRANSIT:
		_enter_dropout()
	else:
		_finish_sequence()

func _spawn_warp_tunnel() -> void:
	if warp_tunnel_mesh:
		_despawn_warp_tunnel()
		
	warp_tunnel_mesh = MeshInstance3D.new()
	
	# Cylinder mesh for the tunnel
	var cyl := CylinderMesh.new()
	cyl.height = 800.0
	cyl.top_radius = 25.0
	cyl.bottom_radius = 25.0
	cyl.radial_segments = 32
	cyl.rings = 32
	cyl.cap_top = false
	cyl.cap_bottom = false
	warp_tunnel_mesh.mesh = cyl
	
	# Rotate cylinder so it points forward along Z
	warp_tunnel_mesh.rotation_degrees.x = 90
	
	var shader := load("res://shaders/hyperwave_tunnel.gdshader")
	var mat := ShaderMaterial.new()
	if shader:
		mat.shader = shader
		# We can tweak uniforms here if we want
		mat.set_shader_parameter("scroll_speed", 15.0)
		mat.set_shader_parameter("intensity_multiplier", 2.5)
		
	warp_tunnel_mesh.material_override = mat
	
	if flight_controller:
		flight_controller.add_child(warp_tunnel_mesh)
		
		# Add high-speed star streak particles
		jump_particles = GPUParticles3D.new()
		jump_particles.amount = 150
		jump_particles.lifetime = 1.0
		jump_particles.randomness = 0.5
		jump_particles.visibility_aabb = AABB(Vector3(-100, -100, -400), Vector3(200, 200, 800))
		
		var pmat := ParticleProcessMaterial.new()
		pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		# Emit from a box far ahead of the ship
		pmat.emission_box_extents = Vector3(40, 40, 20)
		pmat.direction = Vector3(0, 0, 1) # Move backwards towards ship
		pmat.spread = 0.0
		pmat.initial_velocity_min = 400.0
		pmat.initial_velocity_max = 800.0
		jump_particles.process_material = pmat
		
		var pmesh := BoxMesh.new()
		pmesh.size = Vector3(0.2, 0.2, 40.0) # long streaks
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(1.0, 1.0, 1.0, 0.8)
		smat.emission_enabled = true
		smat.emission = Color(0.8, 0.9, 1.0)
		smat.emission_energy_multiplier = 8.0
		pmesh.material = smat
		jump_particles.draw_pass_1 = pmesh
		
		# Position particles 300 units ahead
		jump_particles.position.z = -300.0
		flight_controller.add_child(jump_particles)

func _despawn_warp_tunnel() -> void:
	if warp_tunnel_mesh and is_instance_valid(warp_tunnel_mesh):
		warp_tunnel_mesh.queue_free()
	warp_tunnel_mesh = null
	
	if jump_particles and is_instance_valid(jump_particles):
		jump_particles.queue_free()
	jump_particles = null

func _spawn_spool_grid() -> void:
	if spool_grid_mesh: return
	
	spool_grid_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(800.0, 800.0)
	plane.subdivide_width = 48
	plane.subdivide_depth = 48
	spool_grid_mesh.mesh = plane
	
	# Rotate so +Y points forward, local XZ is parallel to screen
	spool_grid_mesh.rotation_degrees.x = 90
	spool_grid_mesh.position.z = -100.0
	
	var shader := load("res://shaders/hyperwave_grid.gdshader")
	var mat := ShaderMaterial.new()
	if shader:
		mat.shader = shader
	spool_grid_mesh.material_override = mat
	
	if flight_controller:
		flight_controller.add_child(spool_grid_mesh)

func _despawn_spool_grid() -> void:
	if spool_grid_mesh and is_instance_valid(spool_grid_mesh):
		spool_grid_mesh.queue_free()
	spool_grid_mesh = null

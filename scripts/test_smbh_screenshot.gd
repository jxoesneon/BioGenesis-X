extends SceneTree

## Renders the SMBH raymarch shader to a PNG for visual verification.

var frame_count := 0
var cam: Camera3D

func _init():
	var root_node := Node3D.new()
	root_node.name = "SMBHTest"
	get_root().add_child(root_node)

	# Environment with glow (same as galaxy map)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.02)
	env.glow_enabled = true
	env.glow_intensity = 1.5
	env.glow_bloom = 0.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.environment = env
	root_node.add_child(we)

	# SMBH sphere with raymarch shader (mirrors GalaxyMapVisuals settings)
	var bh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 500.0
	sphere.height = 1000.0
	sphere.radial_segments = 32
	sphere.rings = 16
	bh.mesh = sphere
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/smbh_raymarch.gdshader")
	mat.set_shader_parameter("schwarzschild_radius", 30.0)
	mat.set_shader_parameter("photon_sphere_radius", 45.0)
	mat.set_shader_parameter("disk_inner_radius", 38.0)
	mat.set_shader_parameter("disk_outer_radius", 160.0)
	mat.set_shader_parameter("disk_thickness", 8.0)
	mat.set_shader_parameter("ray_bend_strength", 1.0)
	mat.set_shader_parameter("doppler_boost", 1.5)
	mat.set_shader_parameter("gravitational_redshift", 0.8)
	mat.set_shader_parameter("disk_rotation_speed", 2.0)
	mat.set_shader_parameter("ray_steps", 160)
	mat.set_shader_parameter("brightness", 1.0)
	mat.set_shader_parameter("temperature_inner", 8000.0)
	mat.set_shader_parameter("temperature_outer", 2500.0)
	mat.set_shader_parameter("noise_scale", 6.0)
	mat.set_shader_parameter("noise_speed", 0.5)
	mat.set_shader_parameter("disk_tilt_x", 0.5)
	mat.set_shader_parameter("disk_tilt_z", -0.13)
	mat.set_shader_parameter("background_enabled", 0.0)
	mat.set_shader_parameter("bounding_radius", 500.0)
	mat.set_shader_parameter("debug_mode", 0)
	bh.material_override = mat
	root_node.add_child(bh)

	# Shadow sphere removed for testing — shader should create its own shadow

	# Camera slightly above disk plane, like Gargantua view
	cam = Camera3D.new()
	cam.position = Vector3(0, 120, 600)
	cam.look_at_from_position(cam.position, Vector3.ZERO, Vector3.UP)
	cam.far = 5000.0
	root_node.add_child(cam)
	cam.current = true

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count == 30:
		var img := get_root().get_texture().get_image()
		img.save_png("/tmp/smbh_test.png")
		print("SCREENSHOT_SAVED: /tmp/smbh_test.png size=%s" % img.get_size())
		quit(0)
	return false

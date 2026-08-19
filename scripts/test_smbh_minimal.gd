extends SceneTree

## Absolute minimal test: constant-color shader on a sphere

func _init():
	var root_node := Node3D.new()
	get_root().add_child(root_node)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 800)
	cam.far = 5000.0
	root_node.add_child(cam)
	cam.current = true

	# Simple red sphere
	var bh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 500.0
	sphere.height = 1000.0
	bh.mesh = sphere

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/smbh_raymarch.gdshader")
	mat.set_shader_parameter("bounding_radius", 500.0)
	mat.set_shader_parameter("debug_mode", 1)
	bh.material_override = mat
	root_node.add_child(bh)

	# Also add a plain red sphere for comparison
	var ref := MeshInstance3D.new()
	var ref_sphere := SphereMesh.new()
	ref_sphere.radius = 100.0
	ref_sphere.height = 200.0
	ref.mesh = ref_sphere
	ref.position = Vector3(800, 0, 0)
	var ref_mat := StandardMaterial3D.new()
	ref_mat.albedo_color = Color(1, 0, 0)
	ref_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	ref_mat.emission_enabled = true
	ref_mat.emission = Color(1, 0, 0)
	ref.material_override = ref_mat
	root_node.add_child(ref)

	call_deferred("_take_shot")

func _take_shot() -> void:
	await process_frame
	await process_frame
	await process_frame
	var img := get_root().get_texture().get_image()
	img.save_png("/tmp/smbh_minimal.png")

	var img2 := Image.load_from_file("/tmp/smbh_minimal.png")
	var w := img2.get_width()
	var h := img2.get_height()

	# Check center (should be SMBH shader output)
	var cx := w / 2
	var cy := h / 2
	var center := img2.get_pixel(cx, cy)
	print("CENTER: r=%.3f g=%.3f b=%.3f" % [center.r, center.g, center.b])

	# Check right side (should be red reference sphere)
	var right := img2.get_pixel(w - 100, cy)
	print("RIGHT_REF: r=%.3f g=%.3f b=%.3f" % [right.r, right.g, right.b])

	# Scan for any non-black pixels
	var bright := 0
	var max_b := 0.0
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			var p := img2.get_pixel(x, y)
			var b := (p.r + p.g + p.b) / 3.0
			if b > 0.05:
				bright += 1
				if b > max_b: max_b = b
	print("BRIGHT: %d  max=%.3f" % [bright, max_b])

	quit(0)

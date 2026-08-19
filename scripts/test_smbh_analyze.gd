extends SceneTree

## Analyzes the saved SMBH screenshot by sampling pixel values.

func _init():
	var img := Image.load_from_file("/tmp/smbh_test.png")
	if img == null:
		print("LOAD_ERROR: failed to load /tmp/smbh_test.png")
		quit(1)
		return

	var w := img.get_width()
	var h := img.get_height()
	print("IMAGE_SIZE: %dx%d" % [w, h])

	# Sample center region (where SMBH should be)
	var cx := w / 2
	var cy := h / 2

	# Center pixel (should be black shadow)
	var center := img.get_pixel(cx, cy)
	print("CENTER_PIXEL: r=%.3f g=%.3f b=%.3f" % [center.r, center.g, center.b])

	# Sample a grid of pixels across the image
	print("--- HORIZONTAL SWEEP (middle row) ---")
	for x in range(0, w, w / 20):
		var p := img.get_pixel(x, cy)
		var brightness := (p.r + p.g + p.b) / 3.0
		var marker := "  "
		if brightness > 0.01: marker = ". "
		if brightness > 0.1: marker = ": "
		if brightness > 0.3: marker = "* "
		if brightness > 0.6: marker = "# "
		print("x=%4d  bright=%.3f  %s r=%.2f g=%.2f b=%.2f" % [x, brightness, marker, p.r, p.g, p.b])

	print("--- VERTICAL SWEEP (middle col) ---")
	for y in range(0, h, h / 20):
		var p := img.get_pixel(cx, y)
		var brightness := (p.r + p.g + p.b) / 3.0
		var marker := "  "
		if brightness > 0.01: marker = ". "
		if brightness > 0.1: marker = ": "
		if brightness > 0.3: marker = "* "
		if brightness > 0.6: marker = "# "
		print("y=%4d  bright=%.3f  %s r=%.2f g=%.2f b=%.2f" % [y, brightness, marker, p.r, p.g, p.b])

	# Find the bounding box of non-black pixels
	var min_x := w
	var max_x := 0
	var min_y := h
	var max_y := 0
	var bright_count := 0
	var max_brightness := 0.0
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var p := img.get_pixel(x, y)
			var b := (p.r + p.g + p.b) / 3.0
			if b > 0.02:
				bright_count += 1
				if x < min_x: min_x = x
				if x > max_x: max_x = x
				if y < min_y: min_y = y
				if y > max_y: max_y = y
				if b > max_brightness: max_brightness = b

	print("--- BRIGHT PIXEL STATS ---")
	print("bright_count: %d (of %d sampled)" % [bright_count, (w/2)*(h/2)])
	print("bright_bbox: x=[%d,%d] y=[%d,%d]" % [min_x, max_x, min_y, max_y])
	print("max_brightness: %.3f" % max_brightness)

	# Check for color variation (disk should have orange/yellow/white hues)
	var hue_samples := []
	for y in range(0, h, 8):
		for x in range(0, w, 8):
			var p := img.get_pixel(x, y)
			var b := (p.r + p.g + p.b) / 3.0
			if b > 0.1:
				hue_samples.append(p)
	print("colored_samples: %d" % hue_samples.size())
	if hue_samples.size() > 0:
		var avg_r := 0.0
		var avg_g := 0.0
		var avg_b := 0.0
		for c in hue_samples:
			avg_r += c.r
			avg_g += c.g
			avg_b += c.b
		avg_r /= hue_samples.size()
		avg_g /= hue_samples.size()
		avg_b /= hue_samples.size()
		print("AVG_COLOR: r=%.3f g=%.3f b=%.3f" % [avg_r, avg_g, avg_b])
		# Disk should be warm (r > b)
		if avg_r > avg_b:
			print("WARM_TINT: YES (disk-like)")
		else:
			print("WARM_TINT: NO (blue/neutral - disk not visible)")

	quit(0)

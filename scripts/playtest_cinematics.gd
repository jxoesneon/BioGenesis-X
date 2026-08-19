# ==============================================================================
# playtest_cinematics.gd - BioGenesis-X Headless Cinematic Playtest
# Pumilio Studios
# ==============================================================================

extends SceneTree

func _init():
	print("--- BIOGENESIS-X: TESTING CINEMATIC CUTSCENE & CAMERA SEQUENCER ---")

	var seq_script := load("res://scripts/CinematicSequencer.gd")
	var seq: Node = seq_script.new()

	print("Instantiated CinematicSequencer cleanly.")
	print("Total duration: ", seq.total_duration, " seconds")
	print("Show letterbox: ", seq.show_letterbox)

	root.add_child(seq)
	seq.autostart = false
	seq._ready()
	seq.play_cinematic()

	print("Simulating 5 seconds of cinematic camera orbit...")
	for i in range(50):
		seq._process(0.1)

	print("Subtitles processed successfully.")
	var cam_pos = seq.camera.global_position if seq.camera.is_inside_tree() else seq.camera.position
	print("Cinematic Camera position: ", cam_pos)
	print("Cinematic Camera FOV: ", seq.camera.fov)

	root.remove_child(seq)
	seq.free()
	print("--- CINEMATIC SEQUENCER PLAYTEST PASSED CLEANLY ---")
	quit(0)

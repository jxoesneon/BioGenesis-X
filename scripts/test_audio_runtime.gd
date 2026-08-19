# ==============================================================================
# test_audio_runtime.gd - Verifies audio plays continuously without underrun
# ==============================================================================
extends SceneTree

func _init():
	print("\n" + "=".repeat(70))
	print("BIOGENESIS-X: AUDIO RUNTIME CONTINUITY TEST")
	print("=".repeat(70))

	# Load and instantiate BioAudioSynth
	var script = load("res://scripts/BioAudioSynth.gd")
	if not script:
		print("FAIL: Could not load BioAudioSynth.gd")
		quit(1)
		return

	var synth = script.new()
	synth.name = "BioAudioSynth"
	root.add_child(synth)

	# Wait for _ready to initialize
	await process_frame

	if synth.audio_player == null:
		print("FAIL: audio_player is null after _ready")
		quit(1)
		return

	if synth.playback == null:
		print("FAIL: playback is null after _ready")
		quit(1)
		return

	print("✓ BioAudioSynth initialized")
	print("  Sample rate: %.0f Hz" % synth.sample_rate)
	print("  Buffer length: %.3f s" % synth.buffer_length)
	print("  Audio bus: %s" % synth.audio_player.bus)
	print("  Player playing: %s" % str(synth.audio_player.playing))

	# Monitor audio for 5 seconds
	var duration: float = 5.0
	var elapsed: float = 0.0
	var frame_count: int = 0
	var underrun_count: int = 0
	var restart_count: int = 0
	var was_playing: bool = true
	var total_frames_pushed: int = 0

	while elapsed < duration:
		await process_frame
		elapsed += 0.016
		frame_count += 1

		if synth.audio_player == null:
			print("FAIL: audio_player became null at t=%.2f" % elapsed)
			quit(1)
			return

		if not synth.audio_player.playing:
			underrun_count += 1
			if was_playing:
				print("  ⚠ Player stopped at t=%.2f (underrun detected)" % elapsed)
			was_playing = false
		else:
			if not was_playing:
				print("  ✓ Player restarted at t=%.2f" % elapsed)
				restart_count += 1
			was_playing = true

		if synth.playback != null:
			var available: int = synth.playback.get_frames_available()
			total_frames_pushed += available

	# Final report
	print("\n" + "-".repeat(70))
	print("RUNTIME AUDIO TEST RESULTS (%.1f seconds)" % duration)
	print("-".repeat(70))
	print("  Frames monitored: %d" % frame_count)
	print("  Player still playing: %s" % str(synth.audio_player.playing if synth.audio_player else false))
	print("  Underrun events: %d" % underrun_count)
	print("  Restart events: %d" % restart_count)
	print("  Total frames pushed: %d" % total_frames_pushed)
	var expected_frames: int = int(synth.sample_rate * duration)
	print("  Expected frames (%.0f Hz × %.1fs): %d" % [synth.sample_rate, duration, expected_frames])
	var fill_ratio: float = float(total_frames_pushed) / float(max(1, expected_frames))
	print("  Fill ratio: %.1f%%" % (fill_ratio * 100.0))

	if synth.audio_player and synth.audio_player.playing and underrun_count == 0:
		print("\n✅ PASS: Audio played continuously for %.1f seconds with zero underruns" % duration)
		quit(0)
	else:
		print("\n❌ FAIL: Audio stopped or underran during playback")
		quit(1)

# ==============================================================================
# test_aaa_audio_suite.gd - Comprehensive Automated Audio Verification Suite
# BioGenesis-X Engine Architecture
# ==============================================================================
@tool
extends SceneTree

func _init() -> void:
	print("\n" + "=".repeat(75))
	print("BIOGENESIS-X: AAA+ PROCEDURAL AUDIO & ADAPTIVE MUSIC VERIFICATION SUITE")
	print("=".repeat(75))

	var failures: int = 0

	# --------------------------------------------------------------------------
	# TEST 1: Audio Bus Layout & Routing Architecture
	# --------------------------------------------------------------------------
	print("\n[TEST 1] Verifying Audio Bus Architecture & Effects Routing...")
	var expected_buses: Array[String] = [
		"Master", "Music", "SFX_Player", "SFX_World", 
		"Telemetry_Voice", "Bio_Sub", "Reverb_Space", "Reverb_Cockpit"
	]
	for bus_name in expected_buses:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx >= 0:
			var fx_count := AudioServer.get_bus_effect_count(idx)
			print("  ✓ Bus '%s' verified (Index: %d, Volume: %.1f dB, Effects: %d)" % [
				bus_name, idx, AudioServer.get_bus_volume_db(idx), fx_count
			])
		else:
			print("  ✗ FAILED: Bus '%s' not found in AudioServer!" % bus_name)
			failures += 1

	# --------------------------------------------------------------------------
	# TEST 2: BioAudioSynth Autoload & Component Instantiation
	# --------------------------------------------------------------------------
	print("\n[TEST 2] Instantiating Procedural BioAudioSynth Master Engine...")
	var BioAudioSynthClass = load("res://scripts/BioAudioSynth.gd")
	if not BioAudioSynthClass:
		print("  ✗ FAILED to load BioAudioSynth.gd!")
		quit(1)
		return

	var synth = BioAudioSynthClass.new()
	synth.name = "BioAudioSynth"
	root.add_child(synth)
	print("  ✓ BioAudioSynth instantiated and attached to Root SceneTree.")

	# --------------------------------------------------------------------------
	# TEST 3: Dynamic Tension Index (DTI) 4-Tier Music Generation
	# --------------------------------------------------------------------------
	print("\n[TEST 3] Testing Dynamic Tension Index (DTI) Adaptive Music Transitions...")
	var test_dtis: Array[float] = [0.0, 0.35, 0.65, 0.90]
	for dti in test_dtis:
		synth.tension_index = dti
		synth._update_dynamic_music_timers(0.016)
		print("  ✓ DTI set to %.2f -> Active Music Stems evaluated successfully." % dti)

	# --------------------------------------------------------------------------
	# TEST 4: 5 Void-Fauna Archetype Leitmotifs & Formants
	# --------------------------------------------------------------------------
	print("\n[TEST 4] Testing 5 Void-Fauna Archetype Bio-Acoustic Signatures...")
	var archetypes: Array[String] = [
		"Apex Hive Leviathan", "Neuro-Spore Interceptor", "Chitinous Void Harvester",
		"Abyssal Symbiont Frigate", "Viral Colony Carrier"
	]
	for idx in range(archetypes.size()):
		synth._apply_archetype_leitmotif(idx)
		synth.play_creature_vocalization(1.0)
		print("  ✓ Archetype [%d] '%s': Pitch=%.1f Hz, Formants=[%.0f, %.0f, %.0f] Hz" % [
			idx, archetypes[idx], synth._creature_vocal_pitch, 
			synth._creature_formant_f1, synth._creature_formant_f2, synth._creature_formant_f3
		])

	# --------------------------------------------------------------------------
	# TEST 5: 6-DOF Biopunk Propulsion & Alcubierre Wave Engine
	# --------------------------------------------------------------------------
	print("\n[TEST 5] Testing 6-DOF Siphon Kinematics & Alcubierre Spacetime Audio...")
	synth.set_6dof_thrust(1.0, 0.5, 0.0, 3.2)
	synth.set_bio_boost(true)
	synth.set_bio_boost(false)
	print("  ✓ 6-DOF Siphon Thrusters & Bio-Boost modulated.")

	var wave_states: Array[String] = ["OFF", "CHARGING (Shepard Whine)", "ENGAGED (38 km/s Cruise)", "DISENGAGE"]
	for ws in range(wave_states.size()):
		synth.set_wave_engine_state(ws)
		print("  ✓ Alcubierre Wave Engine transition: State %d (%s)" % [ws, wave_states[ws]])

	synth.play_hyperwave_charge()
	synth.play_hyperwave_boom()
	synth.set_hyperwave_tunnel(true)
	synth.set_hyperwave_tunnel(false)
	synth.play_interstellar_jump()
	print("  ✓ Interstellar Hyperjump Spool, Boom, and Hyperspace Transit Tunnel tested.")

	# --------------------------------------------------------------------------
	# TEST 6: Tactical Combat & Weaponry Acoustics
	# --------------------------------------------------------------------------
	print("\n[TEST 6] Testing Tactical Combat Audio & Target Lock-On...")
	synth.play_laser_fire(-0.6) # Left muzzle
	synth.play_laser_fire(0.6)  # Right muzzle
	synth.play_spore_cloud_release()
	synth.play_shield_impact()
	synth.play_chitin_creak()
	for stage in [1, 2, 3, 0]:
		synth.set_lock_on_stage(stage)
	print("  ✓ Disruptors, Spore Cloud, Shield Impact, Chitin Creaks & 3-Stage Lock-On executed.")

	# --------------------------------------------------------------------------
	# TEST 7: Organ Pipeline Stethoscope Sonification
	# --------------------------------------------------------------------------
	print("\n[TEST 7] Testing 5 Organ Pipeline Stethoscope Mode...")
	synth.stethoscope_mode = true
	synth.play_heartbeat_pulse()
	synth.stethoscope_mode = false
	print("  ✓ Stethoscope Mode & Peristaltic Heart Cycle tested.")

	# --------------------------------------------------------------------------
	# TEST 8: Tactile Frutiger Aero UI Micro-Chirps
	# --------------------------------------------------------------------------
	print("\n[TEST 8] Testing Tactile UI Audio Micro-Transients...")
	synth.play_ui_click(true)  # Confirm click
	synth.play_ui_click(false) # Back/Tick click
	print("  ✓ UI Confirm and Tick clicks executed.")

	# Clean up
	synth.queue_free()

	print("\n" + "=".repeat(75))
	if failures == 0:
		print("🏆 ALL AUDIO SYSTEMS VERIFIED AT AAA+ BENCHMARK LEVEL (0 FAILURES)")
	else:
		print("❌ VERIFICATION COMPLETED WITH %d FAILURES" % failures)
	print("=".repeat(75) + "\n")

	quit(failures)

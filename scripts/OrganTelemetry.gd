# res://scripts/OrganTelemetry.gd
# ==============================================================================
# BioGenesis-X Engine Architecture
# OrganTelemetry.gd - Real-time Live Organ System Telemetry & ECG Autoload Singleton
# ==============================================================================
# Simulates live biological & physiological metrics for the 5 closed-loop organ
# pipelines from ORGAN_SYSTEMS.md. Emits telemetry updates frame-by-frame or per
# second, calculates heart rate dynamics based on flight speed & G-forces, and
# generates real-time synthetic ECG waveform samples for UI line graph rendering.
# ==============================================================================

@tool
extends Node
# class_name OrganTelemetry (removed due to autoload conflict)

## Signal emitted when live telemetry data metrics are updated
signal telemetry_updated(data: Dictionary)

## Signal emitted per ECG waveform sample tick for real-time line graph drawing
signal ecg_pulse(waveform_sample: float)

## Signal emitted when an organ starts or stops healing. [param organ_id] is the
## organ node id, [param is_healing] is true when healing begins, false when it
## stops (full health or regen interrupted by damage).
signal organ_healing(organ_id: String, is_healing: bool)

# ------------------------------------------------------------------------------
# Core Telemetry State & Operating Ranges (ORGAN_SYSTEMS.md & LORE.md)
# ------------------------------------------------------------------------------

## Heart Rate (BPM): Base 68 BPM, scales up to ~180 BPM during high speed / G-force
## WHY 68: this IS the Peristaltic Heart Core's canonical resting rate from
## LORE.md (Hemolymph & Thermal Radiator pipeline: "Peristaltic Heart Core
## (68 BPM)"). The Void-Fauna's copper-hemocyanin hemolymph is more viscous
## than human blood, so a slower pump rate maintains the same oxygen-transport
## efficiency. 68 BPM is the resting rate of a large active deep-sea organism
## — fast for a leviathan (sperm whale ~10 BPM, giant squid ~20 BPM) but the
## Void-Fauna is warm-blooded and active, hence the higher rate.
var heart_rate_bpm: float = 68.0

## Oxygenation Yield (L/min): Endosymbiotic bio-moss photosynthetic yield (250 - 650 L/min)
## WHY 420: canonical from LORE.md (Photosynthetic Bio-Moss Carpet @ 420 L/min
## O₂, Endosymbiotic Life Support pipeline). The bio-moss must sustain a human
## crew of up to 50 (Apex Hive Leviathan capacity): 420 L/min ÷ 50 crew =
## 8.4 L/min per person — slightly above human resting O₂ consumption (~6
## L/min) with margin for exertion, so the crew never suffocates at baseline.
var oxygenation_yield_lpm: float = 420.0

## Hemolymph Pressure (Bar): Peristaltic copper-hemocyanin hydraulic pressure (12.0 - 18.0 Bar)
## WHY 15.5: canonical mid-range from LORE.md (12–18 bar). The Peristaltic
## Heart Core (68 BPM) pumps copper-hemocyanin hemolymph at high pressure to
## overcome the viscosity of copper-based oxygen transport — far higher than a
## human's ~0.13 bar blood pressure. 15.5 bar is healthy but not maxed, leaving
## headroom for G-force / exertion spikes without rupturing the Atrium buffer
## (rated 18.5 bar, ORGAN_SYSTEMS.md §2.2).
var hemolymph_pressure_bar: float = 15.5

## Nanite Repair Rate (m³/s): Bio-nanite armor breach coagulation speed (0.8 - 2.5 m³/s)
## WHY 1.2: this IS the Sub-Dermal Bio-Nanite Bed's canonical clotting velocity
## from LORE.md (Exoskeleton & Nanite Defense pipeline: "Sub-Dermal Bio-Nanite
## Bed (1.2 m³/s)"). It is the baseline healthy repair rate; damage_stress
## drives it up toward 2.5 as nanite swarms mobilize to seal hull breaches.
var nanite_repair_rate: float = 1.2

## Radiotrophic Absorption (Gy/hr): Conversion of cosmic/gamma radiation to metabolic energy (20 - 80 Gy/hr)
## WHY 45: canonical mid-range from LORE.md (20–80 Gy/hr). The chitin carapace
## converts gamma/cosmic radiation directly into metabolic energy (LORE.md
## §"Immaculate Radiation Protection") — the same armor that shields the crew
## also feeds the ship. 45 Gy/hr is sufficient to sustain low-power survival
## mode indefinitely on ambient radiation alone, per LORE.md §"Near
## Self-Sufficiency". Mid-range leaves margin for radiation-rich environments.
var radiotrophic_absorption_gy_hr: float = 45.0

## Neural Sync Rate (%): Pilot-to-ganglion neuro-link coherence (95.0% - 99.9%)
## WHY 98.4: canonical from LORE.md range (95–99.9%). The graphene neuro-link
## between pilot and ganglion brain is near-perfect, but biological noise
## (ganglion firing variance, hemolymph pressure fluctuations) prevents 100%.
## Below 95% the ship becomes unresponsive (pilot intent lost in noise);
## 99.9% is the theoretical maximum. 98.4% is high-but-imperfect — healthy and
## responsive, with headroom to degrade under G-force / damage stress.
var neural_sync_rate: float = 98.4

# Extended System Parameters
# WHY 1250 kN: canonical mid-range thrust from LORE.md (680–2550 kN) for the
# Peristaltic Hydro-Pulse Siphons (Bio-Plasma Power & Propulsion pipeline).
# Mid-range at rest leaves headroom to spike toward 2550 kN under full throttle.
var hydro_pulse_thrust_kn: float = 1250.0   # 680 - 2550 kN
# WHY 140 bar: this IS the Muscular Plasma Bladder's canonical operating
# pressure from LORE.md (Bio-Plasma pipeline: "Muscular Plasma Bladder
# (140 Bar)"). The bladder buffers electrolyzed plasma from the Bio-Plasma
# Gland before distributing it to the siphon nozzles and disruptor glands.
var plasma_bladder_pressure_bar: float = 140.0 # 120 - 160 Bar
var habitat_pressure_atm: float = 1.0        # 0.95 - 1.05 atm
var shield_output_mw: float = 450.0          # 300 - 500 MW

# Flight / Kinematic Inputs
var current_speed: float = 0.0              # m/s
var current_g_force: float = 1.0            # Gs
var damage_stress: float = 0.0              # 0.0 to 1.0

# ------------------------------------------------------------------------------
# ECG Waveform Generator State
# WHY a PQRST-style waveform: the ECG line graph represents the Peristaltic
# Heart Core's pressure cycle, NOT a human cardiac ECG. The Void-Fauna's heart
# is peristaltic (wave-like contraction along the aorta), so the true waveform
# is sinusoidal rather than the human PQRST complex. We render a PQRST-shaped
# curve here because it is the universally readable "vital signs" glyph on a
# HUD — players instantly recognize it as a heartbeat. Lore accuracy is
# preserved by the BPM (68) and pressure (15.5 bar) values; the waveform shape
# is an interface-layer affordance (docs/DESIGN_DIRECTION.md §1 Interface
# Layer: skeuomorphic UI the player understands at a glance).
# ------------------------------------------------------------------------------
var ecg_time_accumulator: float = 0.0
var ecg_buffer_max_size: int = 300
var ecg_history: PackedFloat32Array = PackedFloat32Array()
var current_ecg_sample: float = 0.0

# Telemetry emit timer interval
var telemetry_timer: float = 0.0
# WHY 10 Hz (0.1s): sufficient for smooth ECG-style waveform visualization on
# the HUD without flooding the signal bus with redundant updates. The ECG
# waveform itself is sampled every frame (see _generate_ecg_sample), but the
# full telemetry snapshot dict is only emitted at 10 Hz — human eye/HUD
# refresh can't meaningfully distinguish faster numeric updates, and 10 Hz
# keeps the telemetry_updated signal subscribers cheap.
const TELEMETRY_EMIT_INTERVAL: float = 0.1 # 10 Hz updates

# ------------------------------------------------------------------------------
# Per-Organ Healing State (NeuralRegen integration)
# ------------------------------------------------------------------------------

## Tracks the current healing state of each organ node id (true = healing).
## Updated by NeuralRegen._heal_organs() via set_organ_healing(). Consumed by
## the HUD organ inspector for bioluminescent healing feedback.
var _organ_healing_states: Dictionary = {}

func _ready() -> void:
	ecg_history.resize(ecg_buffer_max_size)
	ecg_history.fill(0.0)

func _process(delta: float) -> void:
	_update_kinematic_dynamics(delta)
	_update_telemetry_metrics(delta)
	_generate_ecg_sample(delta)
	
	telemetry_timer += delta
	if telemetry_timer >= TELEMETRY_EMIT_INTERVAL:
		telemetry_timer = 0.0
		telemetry_updated.emit(get_telemetry_snapshot())

# ------------------------------------------------------------------------------
# Kinematics & Dynamic Adjustments
# ------------------------------------------------------------------------------

## Updates current ship kinematics (called by flight controller or simulated)
func set_ship_kinematics(speed: float, g_force: float, damage: float = 0.0) -> void:
	current_speed = max(0.0, speed)
	current_g_force = max(1.0, g_force)
	damage_stress = clamp(damage, 0.0, 1.0)

## Callback for G-force changes from FlightController
func on_g_force_changed(g_force: float, _delta: float = 0.0) -> void:
	current_g_force = max(1.0, g_force)

## Alternative telemetry entry point for G-force recording
func record_g_force(g_force: float) -> void:
	current_g_force = max(1.0, g_force)

## Adjust physiological parameters based on stress, speed, and G-force
func _update_kinematic_dynamics(delta: float) -> void:
	# Target heart rate formula: Base 68 + speed scaling + G-force scaling + damage stress
	var target_bpm: float = 68.0 + (current_speed * 0.15) + ((current_g_force - 1.0) * 12.0) + (damage_stress * 40.0)
	target_bpm = clamp(target_bpm, 55.0, 185.0)
	
	# Smoothly interpolate heart rate
	heart_rate_bpm = lerp(heart_rate_bpm, target_bpm, delta * 2.0)
	
	# Hemolymph pressure correlates with heart rate
	var target_pressure: float = 12.0 + ((heart_rate_bpm - 55.0) / 130.0) * 6.0
	target_pressure += sin(Time.get_ticks_msec() * 0.003) * 0.2
	hemolymph_pressure_bar = clamp(target_pressure, 11.5, 18.5)
	
	# Oxygenation yield fluctuates based on metabolic load
	var target_o2: float = 250.0 + ((heart_rate_bpm - 55.0) / 130.0) * 400.0
	target_o2 += sin(Time.get_ticks_msec() * 0.001) * 15.0
	oxygenation_yield_lpm = clamp(target_o2, 240.0, 660.0)
	
	# Nanite repair rate increases when damaged
	var target_nanite: float = 0.8 + (damage_stress * 1.7) + (randf() * 0.05 - 0.025)
	nanite_repair_rate = clamp(target_nanite, 0.75, 2.55)
	
	# Radiotrophic absorption fluctuates with cosmic background
	radiotrophic_absorption_gy_hr = 45.0 + sin(Time.get_ticks_msec() * 0.0005) * 25.0 + (randf() * 2.0 - 1.0)
	radiotrophic_absorption_gy_hr = clamp(radiotrophic_absorption_gy_hr, 20.0, 80.0)
	
	# Neural sync rate degrades slightly under severe G-force or damage stress
	var target_sync: float = 99.9 - ((current_g_force - 1.0) * 0.4) - (damage_stress * 3.5)
	target_sync += (randf() * 0.2 - 0.1)
	neural_sync_rate = clamp(target_sync, 94.5, 99.9)

func _update_telemetry_metrics(_delta: float) -> void:
	# Hydro-pulse thrust correlates with speed
	hydro_pulse_thrust_kn = 680.0 + (current_speed * 4.5) + (randf() * 20.0 - 10.0)
	hydro_pulse_thrust_kn = clamp(hydro_pulse_thrust_kn, 650.0, 2600.0)
	
	# Plasma bladder pressure
	plasma_bladder_pressure_bar = 140.0 + sin(Time.get_ticks_msec() * 0.002) * 8.0
	
	# Habitat pressure stability
	habitat_pressure_atm = 1.0 + (randf() * 0.004 - 0.002)

# ------------------------------------------------------------------------------
# Synthetic Physiological ECG Waveform Generator
# ------------------------------------------------------------------------------

## Synthesizes real-time physiological P-QRS-T ECG signal points
func _generate_ecg_sample(delta: float) -> void:
	# Cycle period T in seconds based on current heart_rate_bpm
	var beat_period: float = 60.0 / max(heart_rate_bpm, 30.0)
	ecg_time_accumulator += delta
	
	var phase: float = fmod(ecg_time_accumulator, beat_period) / beat_period # normalized [0, 1]
	
	var sample: float = 0.0
	
	# P wave: Atrial depolarization (phase ~ 0.12 to 0.22)
	if phase >= 0.12 and phase <= 0.22:
		var p_phase: float = (phase - 0.17) / 0.05
		sample += 0.15 * exp(-p_phase * p_phase * 4.0)
	
	# QRS Complex: Ventricular depolarization (phase ~ 0.32 to 0.44)
	# Q wave dip
	if phase >= 0.32 and phase <= 0.35:
		var q_phase: float = (phase - 0.335) / 0.015
		sample -= 0.18 * exp(-q_phase * q_phase * 6.0)
	# R wave peak
	elif phase >= 0.35 and phase <= 0.41:
		var r_phase: float = (phase - 0.38) / 0.03
		sample += 1.10 * exp(-r_phase * r_phase * 8.0)
	# S wave dip
	elif phase >= 0.41 and phase <= 0.45:
		var s_phase: float = (phase - 0.43) / 0.02
		sample -= 0.35 * exp(-s_phase * s_phase * 6.0)
	
	# T wave: Ventricular repolarization (phase ~ 0.58 to 0.75)
	if phase >= 0.58 and phase <= 0.75:
		var t_phase: float = (phase - 0.665) / 0.085
		sample += 0.32 * exp(-t_phase * t_phase * 3.5)
	
	# Add slight bio-baseline noise (0.01 amplitude)
	sample += (randf() * 0.02 - 0.01)
	
	current_ecg_sample = sample
	
	# Append to circular/sliding buffer with strict size bound
	if ecg_buffer_max_size <= 0:
		ecg_buffer_max_size = 300
	while ecg_history.size() >= ecg_buffer_max_size:
		ecg_history.remove_at(0)
	ecg_history.append(sample)
	
	ecg_pulse.emit(sample)

# ------------------------------------------------------------------------------
# Data Queries & Telemetry API
# ------------------------------------------------------------------------------

## Returns full dictionary snapshot of current telemetry metrics
func get_telemetry_snapshot() -> Dictionary:
	return {
		"heart_rate_bpm": round(heart_rate_bpm * 10.0) / 10.0,
		"oxygenation_yield_lpm": round(oxygenation_yield_lpm * 10.0) / 10.0,
		"hemolymph_pressure_bar": round(hemolymph_pressure_bar * 100.0) / 100.0,
		"nanite_repair_rate": round(nanite_repair_rate * 100.0) / 100.0,
		"radiotrophic_absorption_gy_hr": round(radiotrophic_absorption_gy_hr * 10.0) / 10.0,
		"neural_sync_rate": round(neural_sync_rate * 100.0) / 100.0,
		"hydro_pulse_thrust_kn": round(hydro_pulse_thrust_kn * 10.0) / 10.0,
		"plasma_bladder_pressure_bar": round(plasma_bladder_pressure_bar * 10.0) / 10.0,
		"habitat_pressure_atm": round(habitat_pressure_atm * 1000.0) / 1000.0,
		"shield_output_mw": round(shield_output_mw * 10.0) / 10.0,
		"current_speed": round(current_speed * 10.0) / 10.0,
		"current_g_force": round(current_g_force * 100.0) / 100.0,
		"damage_stress": round(damage_stress * 100.0) / 100.0,
		"current_ecg_sample": current_ecg_sample,
		"timestamp_ms": Time.get_ticks_msec()
	}

## Returns the array of recent ECG waveform samples for UI rendering
func get_ecg_buffer() -> PackedFloat32Array:
	return ecg_history

## Get closed-loop telemetry for a specific pipeline (from ORGAN_SYSTEMS.md)
func get_pipeline_telemetry(pipeline_id: String) -> Dictionary:
	match pipeline_id:
		"bio_plasma", "1":
			return {
				"pipeline_name": "Bio-Plasma Propulsion",
				"bladder_pressure": plasma_bladder_pressure_bar,
				"thrust_kn": hydro_pulse_thrust_kn,
				"flow_rate_lpm": 2400.0
			}
		"hemolymph", "2":
			return {
				"pipeline_name": "Hemolymph Circulation",
				"heart_rate_bpm": heart_rate_bpm,
				"pressure_bar": hemolymph_pressure_bar,
				"spiracle_radiation_w_m2": 820.0
			}
		"nervous", "3":
			return {
				"pipeline_name": "Nervous Cyber-Synaptic",
				"neural_sync_rate": neural_sync_rate,
				"axon_conduction_m_s": 120.0
			}
		"life_support", "4":
			return {
				"pipeline_name": "Life Support Metabolism",
				"oxygen_yield_lpm": oxygenation_yield_lpm,
				"habitat_pressure_atm": habitat_pressure_atm
			}
		"armor_defense", "5":
			return {
				"pipeline_name": "Armor & Shielding",
				"nanite_repair_rate": nanite_repair_rate,
				"gamma_absorption_gy_hr": radiotrophic_absorption_gy_hr,
				"shield_output_mw": shield_output_mw
			}
		_:
			return get_telemetry_snapshot()

# ------------------------------------------------------------------------------
# NeuralRegen Organ Health Integration
# ------------------------------------------------------------------------------

## Returns a normalized [0..1] multiplier based on average organ health across
## the BioManager topology. Used by NeuralRegen to scale hull/shield/organ
## regeneration rates — healthier organs → faster regen. Falls back to the
## neural_sync_rate proxy (0.945..0.999 → 0..1) when no organ topology is
## available (e.g. headless tests, no BioManager).
func get_organ_health_multiplier() -> float:
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree) or not ml.root:
		return 1.0
	var bm: Node = ml.root.get_node_or_null("BioManager")
	if bm == null or not bm.has_method("get_ship_config"):
		# No BioManager — use neural sync rate as a health proxy.
		var sync: float = clampf(neural_sync_rate / 100.0, 0.0, 1.0)
		return clampf((sync - 0.945) / (0.999 - 0.945), 0.0, 1.0)
	var cfg: Dictionary = bm.get_ship_config()
	if not cfg.has("organ_node_topology"):
		var sync2: float = clampf(neural_sync_rate / 100.0, 0.0, 1.0)
		return clampf((sync2 - 0.945) / (0.999 - 0.945), 0.0, 1.0)
	var topology: Dictionary = cfg["organ_node_topology"]
	var total_health: float = 0.0
	var organ_count: int = 0
	for pipeline_id in topology:
		var pipeline: Dictionary = topology[pipeline_id]
		if not pipeline.has("nodes"):
			continue
		for node in pipeline["nodes"]:
			total_health += float(node.get("health", 100.0))
			organ_count += 1
	if organ_count == 0:
		return 1.0
	var avg: float = total_health / float(organ_count)
	return clampf(avg / 100.0, 0.0, 1.0)

## Records the healing state of a specific organ node and emits organ_healing
## when the state transitions. Called by NeuralRegen._heal_organs().
func set_organ_healing(organ_id: String, is_healing: bool) -> void:
	var prev: bool = bool(_organ_healing_states.get(organ_id, false))
	if prev != is_healing:
		_organ_healing_states[organ_id] = is_healing
		organ_healing.emit(organ_id, is_healing)

## Clears all organ healing states (e.g. when the ship takes damage and all
## healing is interrupted). Emits organ_healing(false) for each previously
## healing organ so the HUD updates immediately.
func clear_all_organ_healing() -> void:
	for organ_id in _organ_healing_states.keys():
		if bool(_organ_healing_states[organ_id]):
			organ_healing.emit(str(organ_id), false)
	_organ_healing_states.clear()

## Returns a copy of the per-organ healing state dictionary (organ_id → bool).
## Consumed by the HUD organ inspector for visual feedback.
func get_organ_healing_states() -> Dictionary:
	return _organ_healing_states.duplicate()

## Returns true if any organ is currently healing.
func is_any_organ_healing() -> bool:
	for organ_id in _organ_healing_states:
		if bool(_organ_healing_states[organ_id]):
			return true
	return false

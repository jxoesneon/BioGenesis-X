# ==============================================================================
# BioAudioSynth.gd - BioGenesis-X AAA+ Clean Biopunk Procedural Audio Synthesizer
# Pumilio Studios & Ciel Audio Architecture Division
# ==============================================================================
# Masterwork real-time procedural audio synthesizer and dynamic music director
# engineered specifically for the living Void-Fauna starships of BioGenesis-X.
#
# AESTHETIC DIRECTIVE: CLEAN BIOPUNK (FRUTIGER AERO & MAJESTIC BIO-HARMONY)
# - Sleek, luminous, hydrodynamic soundscapes (Subnautica Seamoth / Living Oceanic Leviathans).
# - ZERO grotesque body-horror / wet gore. Replaced by vital, healthy, athletic biology:
#   * Rhythmic cardiovascular thud (calm, powerful, resonant bio-engine).
#   * Crystalline bioluminescent harps, pure sinusoidal sub-bass, and smooth laminar pulse jets.
#   * Pristine glassy Frutiger Aero micro-transients for tactile UI feedback.
#   * Majestic, oceanic leviathan vocal calls (whale-like acoustic harmonics and singing organ formants).
#
# AAA+ UPGRADES (v3.0 — NMS-Inspired Layered Soundscapes):
# - Wavetable oscillator (sine/saw/square/triangle) replacing raw sines for harmonic richness
# - Detuned supersaw pad voices (5 detuned saws through resonant lowpass) for lush pads
# - 3-band filtered noise texture bed (sub-rumble, mid-wind, high-hiss) for atmospheric depth
# - Harmonic additive synthesis (5 harmonics, 1/n decay) for crystalline bells/chimes
# - Sub-bass octave layering below drone for cinematic weight
# - Stereo widening via channel detuning + Haas effect
# - Resonant lowpass filter with slow envelope sweeps on pad voices
# - Granular cloud texture for cosmic ambience
#
# v2.0:
# - 7 Psychoacoustic Humanization Laws (1/f jitter, anti-machine-gun, thermal drift, triode warmth)
# - Biometric Exertion & Trauma Engine (HR/RR/stamina → formant shifts, tinnitus filter)
# - Bar/Beat Quantum Transition Queue with reverb-tail preservation
# - 3-Band Crossover Dynamic Sidechain Matrix for combat ducking
# - Incommensurate Prime Loop Clocks + 2nd-Order Markov harmonic transitions
# - Harmonic Drone Anchoring for seamless stem crossfading
# - Proper bus routing (Music, SFX_World, Bio_Sub, Reverb sends)
# ==============================================================================

@tool
extends Node

# ------------------------------------------------------------------------------
# Exported Inspector Parameters
# ------------------------------------------------------------------------------
@export_group("Audio Engine Setup")
## Sampling rate for procedural audio generation (Hz)
## 22050 is recommended for GDScript — 44100 causes buffer underruns with layered synthesis
@export_range(22050.0, 96000.0, 100.0) var sample_rate: float = 22050.0
## Generator buffer length in seconds (lower values reduce latency)
@export_range(0.02, 0.5, 0.01) var buffer_length: float = 0.15
## Master output volume attenuation (dB)
@export_range(-80.0, 12.0, 0.5) var master_volume_db: float = 3.0
## Automatically start audio generation on ready
@export var autoplay: bool = true

@export_group("Dynamic Music & Ambience")
## Master Dynamic Tension Index [0.0 = Serene Exploration, 1.0 = Climax Combat]
@export_range(0.0, 1.0, 0.01) var tension_index: float = 0.0
## Current game musical tempo in BPM
@export_range(60.0, 180.0, 1.0) var music_bpm: float = 112.0
## Music theme selection — each theme has its own scale, chords, and arpeggio character
enum MusicTheme { EXPLORATION, MENU, CINEMATIC }
@export var music_theme: MusicTheme = MusicTheme.EXPLORATION
## Stethoscope Mode (Internal Organ Auditory Inspection)
@export var stethoscope_mode: bool = false
## Ship Hull Health % [Heartbeat is ONLY audible when health < 40% or in stethoscope mode]
@export_range(0.0, 100.0, 0.5) var ship_health_pct: float = 100.0

@export_group("Biometric Engine")
## Pilot stamina [0.0 = Exhausted, 1.0 = Full]
@export_range(0.0, 1.0, 0.01) var pilot_stamina: float = 1.0
## Damage flash intensity [0.0 = None, 1.0 = Critical] (transient, decays automatically)
@export_range(0.0, 1.0, 0.01) var damage_flash: float = 0.0
## Tinnitus ringing intensity [0.0 = None, 1.0 = Severe] (derived from damage)
@export_range(0.0, 1.0, 0.01) var tinnitus_intensity: float = 0.0

@export_group("Humanization")
## Enable 1/f pink noise micro-timing jitter on all events
@export var enable_timing_jitter: bool = true
## Enable anti-machine-gun spectral perturbation
@export var enable_anti_machine_gun: bool = true
## Enable thermal VCO analog drift simulation
@export var enable_thermal_drift: bool = true
## Enable triode warmth saturation on output
@export var enable_triode_warmth: bool = true

# ------------------------------------------------------------------------------
# Private Audio Component References
# ------------------------------------------------------------------------------
var audio_player: AudioStreamPlayer
var generator: AudioStreamGenerator
var playback: AudioStreamGeneratorPlayback

# ------------------------------------------------------------------------------
# DSP Constants & Step Timing
# ------------------------------------------------------------------------------
var _sample_step: float = 1.0 / 44100.0
const TWO_PI: float = TAU

# ------------------------------------------------------------------------------
# 1/f PINK NOISE JITTER ENGINE (Voss-McCartney)
# ------------------------------------------------------------------------------
var _pink_octaves: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _pink_counter: int = 0
var _pink_stride: int = 0

# ------------------------------------------------------------------------------
# THERMAL VCO DRIFT STATE
# ------------------------------------------------------------------------------
var _thermal_phase: float = 0.0
var _wow_phase: float = 0.0
var _thermal_cents: float = 0.0
var _wow_cents: float = 0.0

# ------------------------------------------------------------------------------
# ANTI-MACHINE-GUN STATE MEMORY
# ------------------------------------------------------------------------------
var _last_trigger_gain: float = 0.0
var _last_trigger_cutoff: float = 0.0
var _last_trigger_attack: float = 0.0
var _trigger_count: int = 0

# ------------------------------------------------------------------------------
# TRIODE WARMTH SATURATION STATE
# ------------------------------------------------------------------------------
var _triode_dc: float = 0.0

# ------------------------------------------------------------------------------
# Sound Engine State Variables
# ------------------------------------------------------------------------------
# --- 1. Dynamic Tension & Music Stems ---
var _music_phase_drone: float = 0.0
var _music_phase_arp: float = 0.0
var _music_arp_step: int = 0
var _music_arp_timer: float = 0.0
var _music_beat_timer: float = 0.0
var _music_beat_count: int = 0
var _music_perc_active: bool = false
var _music_perc_time: float = 0.0
var _music_lead_phase: float = 0.0

# --- 1e. ARPEGGIO VARIATION ENGINE (ported from Godot Synth MusicTheme techniques) ---
# Applies probabilistic octave displacement, neighbor tone ornamentation, and
# rhythmic rests to the static arpeggio patterns, making them evolve over time.
# Variation probability scales with tension_index for dramatic effect.
# Techniques adapted from MusicTheme.generate_variation(): octave displacement,
# neighbor tone ornamentation, and rhythmic displacement — but integrated into
# the real-time procedural synthesis pipeline rather than pre-computed note arrays.
var _arp_octave_shift: int = 0         # semitone offset from octave displacement (-12, 0, +12)
var _arp_neighbor_shift: int = 0       # semitone offset from neighbor tone (-1, 0, +1)
var _arp_rest_active: bool = false     # suppress arpeggio for this step (rhythmic rest)

# --- 1a. Bar/Beat Quantum Transition Queue ---
var _stem_transition_queue: Array[Dictionary] = []
var _current_stem_set: int = 0  # 0=calm, 1=exploration, 2=tension, 3=combat, 4=climax
var _pending_stem_set: int = -1
var _stem_crossfade: float = 1.0  # 1.0 = fully transitioned, 0.0 = starting
var _reverb_tail_time: float = 0.0
var _reverb_tail_active: bool = false

# --- 1b. Incommensurate Prime Loop Clocks (Brian Eno Ambient Automata) ---
# Each loop runs at a prime-numbered beat length, creating non-repeating overlaps
var _prime_loops: Array[Dictionary] = []
const PRIME_LENGTHS: Array[int] = [3, 5, 7, 11, 13]

# --- 1c. 2nd-Order Markov Harmonic Transition Matrix ---
# D Dorian → probabilistic chord movement (i, VII, VI, v, iv)
# States: 0=Dm(i), 1=C(VII), 2=Bb(VI), 3=Am(v), 4=Gm(iv)
var _current_harmonic_state: int = 0
var _prev_harmonic_state: int = 0
const MARKOV_MATRIX: Array[Array] = [
	[0.20, 0.30, 0.20, 0.20, 0.10],  # From Dm
	[0.35, 0.15, 0.25, 0.15, 0.10],  # From C
	[0.30, 0.20, 0.15, 0.25, 0.10],  # From Bb
	[0.25, 0.20, 0.20, 0.15, 0.20],  # From Am
	[0.30, 0.25, 0.20, 0.15, 0.10],  # From Gm
]
const CHORD_ROOTS: Array[int] = [50, 48, 46, 45, 43]  # D3, C3, Bb2, A2, G2

# --- 1c-extras. PER-THEME MUSICAL DATA ---
# Each theme defines: scale pitches (MIDI pitch classes), chord roots, Markov matrix,
# arpeggio pattern, drone anchor, and whether percussion/lead are allowed.

# EXPLORATION (Flight): D Dorian — modal, exploratory, tension-driven
const EXPLORATION_SCALE: Array[int] = [0, 2, 3, 5, 7, 9, 10]  # D Dorian pitch classes
const EXPLORATION_ARP_FREQS: Array[float] = [146.83, 164.81, 174.61, 196.00, 220.00, 246.94, 261.63, 293.66]
const EXPLORATION_CHORD_ROOTS: Array[int] = [50, 48, 46, 45, 43]  # D3, C3, Bb2, A2, G2
const EXPLORATION_MARKOV: Array[Array] = [
	[0.20, 0.30, 0.20, 0.20, 0.10],
	[0.35, 0.15, 0.25, 0.15, 0.10],
	[0.30, 0.20, 0.15, 0.25, 0.10],
	[0.25, 0.20, 0.20, 0.15, 0.20],
	[0.30, 0.25, 0.20, 0.15, 0.10],
]
const EXPLORATION_DRONE_ANCHOR: float = 73.42  # D2
const EXPLORATION_LEAD_FREQ: float = 587.33  # D5
const EXPLORATION_ALLOWS_PERC: bool = true
const EXPLORATION_ALLOWS_LEAD: bool = true

# MENU: A Aeolian (natural minor) — mysterious, oceanic, biopunk title screen
# Chord progression: Am - F - C - G (vi - IV - I - V in C major)
# Slower, wider arpeggios, no percussion, no lead climax
const MENU_SCALE: Array[int] = [9, 11, 0, 2, 4, 5, 7]  # A Aeolian pitch classes (A B C D E F G)
const MENU_ARP_FREQS: Array[float] = [220.00, 261.63, 293.66, 329.63, 392.00, 440.00, 523.25, 587.33]
const MENU_CHORD_ROOTS: Array[int] = [57, 53, 60, 55]  # A3, F3, C4, G3
const MENU_MARKOV: Array[Array] = [
	[0.10, 0.40, 0.30, 0.20],  # From Am → F, C, G
	[0.35, 0.10, 0.35, 0.20],  # From F  → Am, C, G
	[0.30, 0.25, 0.10, 0.35],  # From C  → Am, F, G
	[0.45, 0.25, 0.30, 0.00],  # From G  → Am, F, C (resolves back)
]
const MENU_DRONE_ANCHOR: float = 110.00  # A2 — higher than flight's D2, more ethereal
const MENU_LEAD_FREQ: float = 440.00  # A4
const MENU_ALLOWS_PERC: bool = false
const MENU_ALLOWS_LEAD: bool = false

# CINEMATIC: D Dorian with dramatic shifts — same scale as exploration but different voicings
const CINEMATIC_SCALE: Array[int] = [0, 2, 3, 5, 7, 9, 10]
const CINEMATIC_ARP_FREQS: Array[float] = [146.83, 174.61, 196.00, 220.00, 261.63, 293.66, 329.63, 392.00]
const CINEMATIC_CHORD_ROOTS: Array[int] = [50, 45, 43, 48]  # D3, A2, G2, C3
const CINEMATIC_MARKOV: Array[Array] = [
	[0.15, 0.35, 0.30, 0.20],
	[0.40, 0.10, 0.25, 0.25],
	[0.30, 0.25, 0.10, 0.35],
	[0.35, 0.30, 0.25, 0.10],
]
const CINEMATIC_DRONE_ANCHOR: float = 73.42  # D2
const CINEMATIC_LEAD_FREQ: float = 587.33  # D5
const CINEMATIC_ALLOWS_PERC: bool = true
const CINEMATIC_ALLOWS_LEAD: bool = true

# --- 1d. Harmonic Drone Anchoring ---
var _drone_anchor_phase: float = 0.0
var _drone_anchor_freq: float = 73.42  # D2

# --- 2. Cardiovascular & Heartbeat State ---
var _heart_timer: float = 0.0
var _lub_active: bool = false
var _lub_time: float = 0.0
var _dub_active: bool = false
var _dub_time: float = 0.0
var _heart_rate_bpm: float = 68.0
var _cardiac_arrhythmia: float = 0.0  # [0.0=normal, 1.0=severe arrhythmia]
var _respiration_rate: float = 14.0  # breaths per minute
var _respiration_phase: float = 0.0
var _exertion_level: float = 0.0  # derived from stamina + throttle

# --- 2a. Tinnitus / Trauma Filter ---
var _tinnitus_phase: float = 0.0
var _tinnitus_freq: float = 7200.0
var _tinnitus_envelope: float = 0.0

# --- 3. Siphon Thrust Engine & Flight Kinematics ---
var _throttle_forward: float = 0.0
var _throttle_strafe: float = 0.0
var _throttle_retro: float = 0.0
var _bio_boost: bool = false
var _g_force_stress: float = 0.0
var _engine_brown_noise: float = 0.0
var _engine_lpf_state: float = 0.0
var _engine_rumble_phase: float = 0.0
var _engine_lfo_phase: float = 0.0

# --- 4. Alcubierre Wave Engine & Interstellar Jump State ---
var _wave_state: int = 0 # 0=OFF, 1=CHARGING, 2=ENGAGED, 3=DISENGAGING, 4=INHIBITED
var _wave_time: float = 0.0
var _wave_shepard_phase1: float = 0.0
var _wave_shepard_phase2: float = 0.0
var _wave_cruise_phase: float = 0.0
var _wave_sub_boom_active: bool = false
var _wave_sub_boom_time: float = 0.0
var _hyper_tunnel_active: bool = false
var _hyper_tunnel_time: float = 0.0
var _hyper_tunnel_noise_state: float = 0.0
var _hyper_tunnel_phase: float = 0.0
var _hyper_tunnel_lfo_phase: float = 0.0

# --- 5. Chitin Acoustic Tension ---
var _chitin_active: bool = false
var _chitin_time: float = 0.0
var _chitin_freq_seed: float = 4200.0

# --- 6. Tactical Weapons & Combat ---
var _laser_active: bool = false
var _laser_time: float = 0.0
var _laser_pan: float = 0.0
var _laser_carrier_phase: float = 0.0
var _laser_mod_phase: float = 0.0

var _lock_on_stage: int = 0
var _lock_on_phase: float = 0.0
var _lock_on_timer: float = 0.0

var _spore_active: bool = false
var _spore_time: float = 0.0

var _shield_impact_active: bool = false
var _shield_impact_time: float = 0.0

# --- 6a. 3-Band Crossover Sidechain Matrix ---
var _sidechain_trigger: float = 0.0  # decays from 1.0
var _sidechain_band_sub: float = 1.0  # < 120 Hz (preserved)
var _sidechain_band_mid: float = 1.0  # 250 Hz - 4.5 kHz (ducked)
var _sidechain_band_high: float = 1.0  # > 4.5 kHz (shepard risers)

# --- 7. Oceanic VocAlien Formants (Majestic Oceanic Bio-Acoustics) ---
var _creature_vocal_active: bool = false
var _creature_vocal_time: float = 0.0
var _creature_vocal_pitch: float = 85.0
var _creature_formant_f1: float = 380.0
var _creature_formant_f2: float = 1100.0
var _creature_formant_f3: float = 2300.0
var _creature_glottal_phase: float = 0.0

# --- 8. Frutiger Aero Glass UI Micro-Transients ---
var _ui_chirp_active: bool = false
var _ui_chirp_time: float = 0.0
var _ui_chirp_freq_start: float = 3200.0
var _ui_chirp_freq_end: float = 5800.0
var _ui_chirp_duration: float = 0.035
var _ui_chirp_phase: float = 0.0

# --- 9. WAVETABLE OSCILLATOR (precomputed for performance) ---
const WAVETABLE_SIZE: int = 2048
var _wt_sine_tbl: PackedFloat32Array
var _wt_saw_tbl: PackedFloat32Array
var _wt_square_tbl: PackedFloat32Array
var _wt_triangle_tbl: PackedFloat32Array
var _wt_initialized: bool = false

# --- 10. DETUNED SUPERSAW PAD VOICES ---
# 5 detuned sawtooth oscillators through a shared one-pole lowpass filter
const PAD_VOICE_COUNT: int = 5
var _pad_phases: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _pad_detune_cents: Array[float] = [-7.0, -3.0, 0.0, 4.0, 8.0]  # cents offset per voice
var _pad_lpf_state: float = 0.0
var _pad_lpf_coef: float = 0.0  # precomputed filter coefficient
var _pad_cutoff: float = 800.0
var _pad_cutoff_target: float = 800.0
var _pad_sweep_lfo: float = 0.0
var _pad_amp: float = 0.0  # smoothly fades in/out

# --- 10a. SECOND PAD LAYER (higher octave, softer) ---
var _pad2_phases: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _pad2_lpf_state: float = 0.0
var _pad2_lpf_coef: float = 0.0
var _pad2_amp: float = 0.0

# --- 11. SUB-BASS OCTAVE LAYER ---
var _sub_bass_phase: float = 0.0
var _sub_bass_amp: float = 0.0

# --- 12. 3-BAND NOISE TEXTURE BED (atmospheric depth) ---
var _noise_sub_state: float = 0.0    # < 80 Hz rumble
var _noise_mid_state: float = 0.0    # 200-2000 Hz wind
var _noise_high_state: float = 0.0   # 4000+ Hz hiss
var _noise_sub_amp: float = 0.0
var _noise_mid_amp: float = 0.0
var _noise_high_amp: float = 0.0
var _noise_lfo: float = 0.0

# --- 13. GRANULAR CLOUD TEXTURE (cosmic ambience) ---
var _grain_pool: Array[Dictionary] = []
const GRAIN_POOL_SIZE: int = 8
var _grain_spawn_timer: float = 0.0

# --- 14. STEREO WIDENER STATE ---
# Stereo widening is now handled per-voice via channel detuning in the render loop

# --- 15. DIAGNOSTIC STATE ---
var _diag_restart_count: int = 0

# --- 16. SYSTEM SOUNDSCAPE (star-type-driven ambient layers) ---
# Mirrors ProceduralGalaxy.SpectralClass enum values
enum StarType {
	CLASS_O,       # 0 — Blue Hypergiant: intense radiation, high-energy shimmer
	CLASS_B,       # 1 — Blue-White Giant: bright, energetic
	CLASS_A,       # 2 — White Main Sequence: clean, neutral
	CLASS_F,       # 3 — Yellow-White: warm, golden
	CLASS_G,       # 4 — Sol-Type: familiar, balanced, "home"
	CLASS_K,       # 5 — Orange Dwarf: warm, amber, melancholic
	CLASS_M,       # 6 — Red Dwarf: deep, dark, ominous
	NEUTRON_STAR,  # 7 — Pulsar: rhythmic pulsing beep + magnetic hum
	BLACK_HOLE,    # 8 — Singularity: gravitational drone, time-dilation pitch bend
	WOLF_RAYET     # 9 — Variable: chaotic, mass-loss wind
}
# Current star type (set by BioAudioDirector when entering a system)
var _current_star_type: int = StarType.CLASS_G
# Star-type-specific ambient parameters
var _star_radiation_freq: float = 0.0      # radiation hum carrier frequency
var _star_radiation_amp: float = 0.0       # radiation hum amplitude
var _star_radiation_phase: float = 0.0
var _star_gravity_drone_freq: float = 0.0  # gravitational drone frequency
var _star_gravity_drone_amp: float = 0.0   # gravitational drone amplitude
var _star_gravity_phase: float = 0.0
var _star_shimmer_amp: float = 0.0         # high-frequency shimmer (hot stars)
var _star_shimmer_phase: float = 0.0
var _pulsar_pulse_active: bool = false     # neutron star pulsing
var _pulsar_pulse_timer: float = 0.0
var _pulsar_pulse_period: float = 0.714    # seconds between pulses (~1.4 Hz)
var _pulsar_pulse_phase: float = 0.0
var _black_hole_time_dilation: float = 0.0 # pitch bend depth for black holes
var _black_hole_drone_phase: float = 0.0

# --- 16a. PLANET PROXIMITY SOUNDSCAPE ---
# Mirrors ProceduralGalaxy.PlanetArchetype enum values
enum PlanetType {
	MOLTEN,            # 0 — Volcanic rumble, crackling
	METALLIC_BARREN,   # 1 — Metallic resonance, empty echo
	DESERT_ARID,       # 2 — Wind sweeps, sand particle hiss
	TERRAN_OCEANIC,    # 3 — Ocean waves, bio-chorus
	ICE_WORLD,         # 4 — Crystal tones, frozen chimes
	GAS_GIANT_JOVIAN,  # 5 — Massive storm turbulence
	GAS_GIANT_ICE,     # 6 — Methane wind, higher-pitched storms
	RADIOTROPHIC_BIO   # 7 — Bioluminescent spore ambience, organic pulses
}
var _current_planet_type: int = -1  # -1 = no planet nearby
var _planet_proximity: float = 0.0  # 0.0 = far, 1.0 = very close
var _planet_ambient_amp: float = 0.0
var _planet_ambient_phase: float = 0.0
var _planet_ambient_freq: float = 0.0
var _planet_wind_amp: float = 0.0
var _planet_wind_state: float = 0.0
var _planet_wind_freq: float = 0.0

# --- 16b. ENVIRONMENT EVENT SYSTEM (extensible for future features) ---
# Each environment event modulates the soundscape layers
enum EnvironmentEvent {
	NONE,               # 0 — normal space
	NEBULA,             # 1 — diffuse, filtered, swirling (HII region)
	ASTEROID_FIELD,     # 2 — proximity pings, debris texture
	BLACK_HOLE_PROX,    # 3 — extreme gravitational drone
	SUPERNOVA_REMNANT,  # 4 — radioactive crackle
	MOLECULAR_CLOUD,    # 5 — dense, muffled, deep
	# --- Fully implemented environment events (AAA+ multi-layered DSP) ---
	ANOMALY,            # 6 — unknown/strange harmonics
	DISCOVERY,          # 7 — wonder stinger + uplift
	DOCKING,            # 8 — mechanical approach sequence
	DERELICT,           # 9 — eerie, abandoned ship ambience
	DISTRESS_SIGNAL,    # 10 — emergency beacon pulse
	COMBAT_AMBUSH,      # 11 — sudden combat tension spike
	SOLAR_FLARE,        # 12 — radiation surge
	GRAVITATIONAL_WAVE, # 13 — spacetime ripple
}
var _current_env_event: int = EnvironmentEvent.NONE
var _env_event_intensity: float = 0.0  # 0.0 = none, 1.0 = full
var _env_event_target_intensity: float = 0.0
var _nebula_filter_state: float = 0.0   # nebula lowpass state
var _nebula_lfo: float = 0.0
var _asteroid_ping_timer: float = 0.0
var _asteroid_ping_phase: float = 0.0
var _supernova_crackle_state: float = 0.0

# --- 16c. ENVIRONMENT EVENT DSP STATE (AAA+ multi-layered synthesis) ---
# Event change detection for state reset
var _prev_env_event: int = EnvironmentEvent.NONE

# ANOMALY — 7-oscillator detuned cluster, morphing bandpass, ring mod, microtonal drift
var _anom_phases: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _anom_bp_lo: float = 0.0        # bandpass lowpass state
var _anom_bp_hi: float = 0.0        # bandpass highpass state
var _anom_lfo_phase: float = 0.0    # slow detuning morph LFO
var _anom_ring_phase: float = 0.0   # ring mod carrier phase
var _anom_pitch_drift: float = 0.0  # microtonal pitch drift amount
var _anom_detune_factors: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])  # cached per-oscillator detune ratios (updated every 100 samples)
var _anom_detune_counter: int = 0   # sample counter for detune factor recompute

# DISCOVERY — FM bell arpeggio with reverb-like decay + pad layer
var _disc_timer: float = 0.0        # arpeggio note trigger timer
var _disc_step: int = 0             # arpeggio step counter
var _disc_note_env: float = 0.0     # per-note decay envelope
var _disc_carrier_phase: float = 0.0  # FM carrier phase
var _disc_mod_phase: float = 0.0    # FM modulator phase
var _disc_carrier_freq: float = 0.0  # current carrier frequency
var _disc_mod_freq: float = 0.0     # current modulator frequency
var _disc_pad_phase: float = 0.0    # pad layer phase

# DOCKING — mechanical clunks + proximity hum + metallic resonance
var _dock_clunk_timer: float = 0.0  # clunk trigger timer
var _dock_clunk_env: float = 0.0    # clunk fast decay envelope
var _dock_clunk_filter: float = 0.0 # clunk noise filter state
var _dock_metal_state: float = 0.0  # metallic resonance filter state
var _dock_hum_phase: float = 0.0    # proximity hum phase

# DERELICT — cold drone + metallic creaks + air leak hiss
var _derelict_drone_phase: float = 0.0   # cold drone phase
var _derelict_creak_timer: float = 0.0   # creak random trigger timer
var _derelict_creak_active: bool = false  # creak currently playing
var _derelict_creak_age: float = 0.0     # creak age for attack/decay envelope
var _derelict_creak_filter: float = 0.0  # creak noise filter state
var _derelict_hiss_state: float = 0.0    # air leak hiss filter state

# DISTRESS_SIGNAL — Morse SOS beacon + background static
var _distress_morse_timer: float = 0.0   # Morse element timer
var _distress_morse_idx: int = 0         # current Morse element index
var _distress_beacon_phase: float = 0.0  # beacon carrier phase
var _distress_beacon_env: float = 0.0    # beacon envelope (on/off with edges)
var _distress_static_state: float = 0.0  # static noise filter state
var _morse_unit: float = 0.09            # seconds per Morse time unit
var _morse_sos: Array[float] = [1.0, -1.0, 1.0, -1.0, 1.0, -3.0, 3.0, -1.0, 3.0, -1.0, 3.0, -3.0, 1.0, -1.0, 1.0, -1.0, 1.0, -7.0]

# COMBAT_AMBUSH — one-shot tension spike (noise burst + impact boom)
var _ambush_triggered: bool = false   # one-shot trigger flag
var _ambush_env: float = 0.0         # one-shot decay envelope
var _ambush_impact_phase: float = 0.0  # impact boom phase
var _ambush_noise_filter: float = 0.0  # noise burst filter state

# SOLAR_FLARE — multi-band noise + shimmer + sub-bass pressure
var _flare_env_phase: float = 0.0    # flare build/decay LFO phase
var _flare_crackle: float = 0.0      # high crackle state
var _flare_hiss_state: float = 0.0   # mid hiss filter state
var _flare_rumble_state: float = 0.0 # sub rumble filter state
var _flare_shimmer_phase: float = 0.0  # high-freq shimmer phase
var _flare_sub_phase: float = 0.0    # sub-bass pressure wave phase

# GRAVITATIONAL_WAVE — doppler AM + deep sub-bass + stereo phase offset
var _grav_lfo_phase: float = 0.0     # ripple LFO phase (slow AM)
var _grav_doppler_phase: float = 0.0  # doppler-shifted carrier phase
var _grav_doppler_rate: float = 0.0   # current doppler carrier frequency
var _grav_sub_phase: float = 0.0     # deep sub-bass phase
var _grav_stereo_phase: float = 0.0  # stereo spatial offset phase


# ==============================================================================
# Lifecycle Methods
# ==============================================================================
func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if DisplayServer.get_name() == "headless":
		return
	_sample_step = 1.0 / maxf(1.0, sample_rate)
	_init_wavetables()
	_init_grain_pool()
	_init_prime_loops()
	_setup_audio_stream()

func _exit_tree() -> void:
	playback = null
	if audio_player:
		audio_player.stop()
		audio_player.stream = null

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_sync_organ_telemetry()
	_update_biometric_engine(delta)
	_update_dynamic_music_timers(delta)
	_update_prime_loops(delta)
	_update_heartbeat_rhythm(delta)
	_update_tinnitus(delta)
	_update_sidechain(delta)
	_update_stem_transitions(delta)
	_update_grains(delta)
	_update_pad_envelopes(delta)

	if playback == null and audio_player != null and audio_player.playing:
		playback = audio_player.get_stream_playback() as AudioStreamGeneratorPlayback

	# Auto-restart: if the player stopped (buffer underrun), restart it
	if audio_player != null and not audio_player.playing:
		_diag_restart_count += 1
		audio_player.play()
		playback = audio_player.get_stream_playback() as AudioStreamGeneratorPlayback

	if playback != null:
		_fill_audio_buffer()


## Updates pad envelope amplitudes and filter cutoff targets based on tension
func _update_pad_envelopes(delta: float) -> void:
	# Pad 1 (main drone pad): fades in with exploration, out with stethoscope
	# Boosted from 0.35 to 0.60 to compensate for 5-voice averaging attenuation
	var pad1_target: float = 0.0
	if not stethoscope_mode:
		pad1_target = 0.60 + tension_index * 0.30
	_pad_amp = lerpf(_pad_amp, pad1_target, delta * 2.0)

	# Pad 2 (higher octave): more present in tension/combat
	var pad2_target: float = 0.0
	if not stethoscope_mode:
		pad2_target = 0.15 + tension_index * 0.25
	_pad2_amp = lerpf(_pad2_amp, pad2_target, delta * 2.0)

	# Sub-bass: always present for weight, louder with tension
	var sub_target: float = 0.0
	if not stethoscope_mode:
		sub_target = 0.35 + tension_index * 0.20
	_sub_bass_amp = lerpf(_sub_bass_amp, sub_target, delta * 2.0)

	# Noise texture bed: atmospheric depth
	_noise_sub_amp = lerpf(_noise_sub_amp, 0.06 if not stethoscope_mode else 0.0, delta * 1.5)
	_noise_mid_amp = lerpf(_noise_mid_amp, 0.05 + tension_index * 0.05 if not stethoscope_mode else 0.0, delta * 1.5)
	_noise_high_amp = lerpf(_noise_high_amp, 0.02 + tension_index * 0.03 if not stethoscope_mode else 0.0, delta * 1.5)

	# Pad filter cutoff sweep: opens with tension
	_pad_cutoff_target = lerpf(400.0, 3500.0, tension_index)
	_pad_cutoff = lerpf(_pad_cutoff, _pad_cutoff_target, delta * 1.5)
	# Precompute filter coefficients (avoids tan() per sample)
	var mod_cutoff: float = _pad_cutoff * (1.0 + 0.15 * sin(_pad_sweep_lfo))
	_pad_lpf_coef = _compute_lpf_coef(clampf(mod_cutoff, 100.0, 8000.0))
	_pad2_lpf_coef = _compute_lpf_coef(clampf(_pad_cutoff * 2.5, 200.0, 12000.0))

	# Pad sweep LFO for evolving timbre
	_pad_sweep_lfo += TWO_PI * 0.08 * delta
	if _pad_sweep_lfo > TWO_PI: _pad_sweep_lfo -= TWO_PI

	# Noise LFO for wind modulation
	_noise_lfo += TWO_PI * 0.12 * delta
	if _noise_lfo > TWO_PI: _noise_lfo -= TWO_PI

	# Update system soundscape layers
	_update_system_soundscape(delta)

func _update_system_soundscape(delta: float) -> void:
	# --- Star-type ambient layers ---
	# Radiation hum phase advance
	if _star_radiation_amp > 0.001:
		_star_radiation_phase += TWO_PI * _apply_drift(_star_radiation_freq) * _sample_step * delta * 60.0
		if _star_radiation_phase > TWO_PI: _star_radiation_phase -= TWO_PI

	# Gravity drone phase advance
	if _star_gravity_drone_amp > 0.001:
		_star_gravity_phase += TWO_PI * _apply_drift(_star_gravity_drone_freq) * _sample_step * delta * 60.0
		if _star_gravity_phase > TWO_PI: _star_gravity_phase -= TWO_PI

	# Shimmer phase advance (high-frequency modulation)
	if _star_shimmer_amp > 0.001:
		_star_shimmer_phase += TWO_PI * 8.0 * delta
		if _star_shimmer_phase > TWO_PI: _star_shimmer_phase -= TWO_PI

	# Pulsar pulse timer
	if _pulsar_pulse_active:
		_pulsar_pulse_timer += delta
		if _pulsar_pulse_timer >= _pulsar_pulse_period:
			_pulsar_pulse_timer -= _pulsar_pulse_period
			_pulsar_pulse_phase = 0.0
		_pulsar_pulse_phase += delta

	# Black hole time-dilation drone
	if _black_hole_time_dilation > 0.001:
		_black_hole_drone_phase += TWO_PI * 7.0 * delta  # very slow modulation
		if _black_hole_drone_phase > TWO_PI: _black_hole_drone_phase -= TWO_PI

	# --- Planet proximity ambient ---
	if _current_planet_type >= 0 and _planet_proximity > 0.01:
		_planet_ambient_amp = lerpf(_planet_ambient_amp, _planet_proximity * 0.15, delta * 2.0)
		_planet_wind_amp = lerpf(_planet_wind_amp, _planet_proximity * 0.10, delta * 2.0)
		_planet_ambient_phase += TWO_PI * _planet_ambient_freq * _sample_step * delta * 60.0
		if _planet_ambient_phase > TWO_PI: _planet_ambient_phase -= TWO_PI
		# Wind noise filter
		var wind_noise: float = randf_range(-1.0, 1.0)
		_planet_wind_state += (wind_noise - _planet_wind_state) * (_planet_wind_freq * _sample_step * delta * 60.0)
	else:
		_planet_ambient_amp = lerpf(_planet_ambient_amp, 0.0, delta * 2.0)
		_planet_wind_amp = lerpf(_planet_wind_amp, 0.0, delta * 2.0)

	# --- Environment event intensity ramp ---
	_env_event_intensity = lerpf(_env_event_intensity, _env_event_target_intensity, delta * 1.5)

	# Nebula LFO
	if _current_env_event == EnvironmentEvent.NEBULA:
		_nebula_lfo += TWO_PI * 0.15 * delta
		if _nebula_lfo > TWO_PI: _nebula_lfo -= TWO_PI

	# Asteroid field ping timer
	if _current_env_event == EnvironmentEvent.ASTEROID_FIELD:
		_asteroid_ping_timer += delta
		if _asteroid_ping_timer >= 2.5:  # ping every ~2.5 seconds
			_asteroid_ping_timer = 0.0
			_asteroid_ping_phase = 0.0
		_asteroid_ping_phase += delta


# ==============================================================================
# Audio Initialization & Bus Assignment
# ==============================================================================
func _setup_audio_stream() -> void:
	if audio_player != null:
		return

	audio_player = AudioStreamPlayer.new()
	audio_player.name = "BioAudioSynthMaster"
	# Route to Music bus for proper sidechain compression and EQ
	audio_player.bus = "Music" if AudioServer.get_bus_index("Music") != -1 else "Master"

	generator = AudioStreamGenerator.new()
	generator.mix_rate = sample_rate
	generator.buffer_length = buffer_length

	audio_player.stream = generator
	audio_player.volume_db = master_volume_db
	add_child(audio_player)

	if autoplay:
		audio_player.play()
		playback = audio_player.get_stream_playback() as AudioStreamGeneratorPlayback


# ==============================================================================
# WAVETABLE OSCILLATOR INITIALIZATION
# ==============================================================================
func _init_wavetables() -> void:
	if _wt_initialized:
		return
	_wt_sine_tbl = PackedFloat32Array()
	_wt_saw_tbl = PackedFloat32Array()
	_wt_square_tbl = PackedFloat32Array()
	_wt_triangle_tbl = PackedFloat32Array()
	_wt_sine_tbl.resize(WAVETABLE_SIZE)
	_wt_saw_tbl.resize(WAVETABLE_SIZE)
	_wt_square_tbl.resize(WAVETABLE_SIZE)
	_wt_triangle_tbl.resize(WAVETABLE_SIZE)
	for i in range(WAVETABLE_SIZE):
		var phase: float = float(i) / float(WAVETABLE_SIZE)
		_wt_sine_tbl[i] = sin(phase * TWO_PI)
		_wt_saw_tbl[i] = 2.0 * phase - 1.0
		_wt_square_tbl[i] = 1.0 if phase < 0.5 else -1.0
		_wt_triangle_tbl[i] = 2.0 * absf(2.0 * phase - 1.0) - 1.0
	_wt_initialized = true

## Wavetable lookup with linear interpolation — much faster than sin() for complex waveforms
func _wt_read(table: PackedFloat32Array, phase: float) -> float:
	var pos: float = phase * float(WAVETABLE_SIZE)
	var idx: int = int(pos) % WAVETABLE_SIZE
	var frac: float = pos - floorf(pos)
	var next_idx: int = (idx + 1) % WAVETABLE_SIZE
	return lerpf(table[idx], table[next_idx], frac)

## Sawtooth wave via wavetable
func _wt_saw(phase: float) -> float:
	return _wt_read(_wt_saw_tbl, phase)

## Square wave via wavetable
func _wt_square(phase: float) -> float:
	return _wt_read(_wt_square_tbl, phase)

## Triangle wave via wavetable
func _wt_triangle(phase: float) -> float:
	return _wt_read(_wt_triangle_tbl, phase)

## Sine wave via wavetable (faster than sin() for batch operations)
func _wt_sine(phase: float) -> float:
	return _wt_read(_wt_sine_tbl, phase)


# ==============================================================================
# ONE-POLE LOWPASS FILTER (precomputed coefficient — no tan() per sample)
# ==============================================================================
## Computes the filter coefficient for a one-pole lowpass. Call once per frame, not per sample.
func _compute_lpf_coef(cutoff_hz: float) -> float:
	# alpha = dt / (RC + dt) where RC = 1/(2*pi*cutoff)
	var rc: float = 1.0 / (TWO_PI * maxf(1.0, cutoff_hz))
	return _sample_step / (rc + _sample_step)

## Applies one-pole lowpass using precomputed coefficient and persistent state
func _onepole_lpf(input: float, coef: float, state: float) -> float:
	return state + coef * (input - state)


# ==============================================================================
# GRANULAR CLOUD TEXTURE
# ==============================================================================
func _init_grain_pool() -> void:
	_grain_pool.clear()
	for i in range(GRAIN_POOL_SIZE):
		_grain_pool.append({
			"active": false,
			"phase": 0.0,
			"freq": 0.0,
			"pos": 0.0,
			"dur": 0.0,
			"amp": 0.0,
			"pan": 0.0,
			"age": 0.0,
		})

func _spawn_grain() -> void:
	# Find inactive grain slot
	for g in _grain_pool:
		if not g["active"]:
			g["active"] = true
			g["phase"] = randf()
			# Random pitch in D Dorian across 2 octaves
			var dorian_pcs: Array[int] = [0, 2, 3, 5, 7, 9, 10]
			var pc: int = dorian_pcs[randi() % dorian_pcs.size()]
			var octave: int = randi_range(3, 5)
			var midi: int = 50 + pc + (octave - 3) * 12
			g["freq"] = 440.0 * pow(2.0, (float(midi) - 69.0) / 12.0)
			g["dur"] = randf_range(0.3, 1.5)
			g["amp"] = randf_range(0.02, 0.08)
			g["pan"] = randf_range(-0.5, 0.5)
			g["age"] = 0.0
			return

func _update_grains(delta: float) -> void:
	_grain_spawn_timer += delta
	# Spawn grains at a rate influenced by tension (more grains in combat)
	var spawn_rate: float = lerpf(0.8, 2.5, tension_index)
	if _grain_spawn_timer >= 1.0 / spawn_rate:
		_grain_spawn_timer = 0.0
		_spawn_grain()
	# Age active grains
	for g in _grain_pool:
		if g["active"]:
			g["age"] = g["age"] + delta
			if g["age"] >= g["dur"]:
				g["active"] = false

func _render_grains(dt: float) -> Vector2:
	var left: float = 0.0
	var right: float = 0.0
	for g in _grain_pool:
		if g["active"]:
			var age: float = g["age"]
			var dur: float = g["dur"]
			var t: float = age / dur
			# Granular envelope: Gaussian-like window
			var env: float = sin(t * PI) * exp(-t * 2.0)
			var freq: float = _apply_drift(float(g["freq"]))
			g["phase"] = fmod(float(g["phase"]) + freq * dt, 1.0)
			# Use wavetable sine for warmth
			var grain_val: float = _wt_sine(float(g["phase"])) * env * float(g["amp"])
			var pan: float = float(g["pan"])
			left += grain_val * (1.0 - pan)
			right += grain_val * (1.0 + pan)
	return Vector2(left, right)


# ==============================================================================
# 1/f PINK NOISE JITTER ENGINE (Voss-McCartney)
# ==============================================================================
func _pink_noise_sample() -> float:
	# Voss-McCartney algorithm: update one octave per step based on stride
	_pink_counter += 1
	if _pink_counter >= 64:
		_pink_counter = 0
		_pink_stride = 0
	var bit: int = _pink_counter
	while bit > 0:
		if (bit & 1) == 1:
			break
		_pink_stride += 1
		bit >>= 1
	if _pink_stride < _pink_octaves.size():
		_pink_octaves[_pink_stride] = randf_range(-1.0, 1.0)
	var sum: float = 0.0
	for o in _pink_octaves:
		sum += o
	return sum / float(_pink_octaves.size())

func _timing_jitter_ms(sigma_ms: float = 4.0) -> float:
	# Returns a Gaussian-ish timing offset in seconds using pink noise
	if not enable_timing_jitter:
		return 0.0
	var pink: float = _pink_noise_sample()
	# Approximate Gaussian via central limit (sum of 3 pink samples)
	pink = (pink + _pink_noise_sample() + _pink_noise_sample()) / 3.0
	return pink * sigma_ms * 0.001


# ==============================================================================
# THERMAL VCO DRIFT
# ==============================================================================
func _update_thermal_drift(delta: float) -> void:
	if not enable_thermal_drift:
		_thermal_cents = 0.0
		_wow_cents = 0.0
		return
	# Thermal: ±3 cents at 0.02 Hz
	_thermal_phase += TWO_PI * 0.02 * delta
	if _thermal_phase > TWO_PI: _thermal_phase -= TWO_PI
	_thermal_cents = sin(_thermal_phase) * 3.0
	# Wow: ±1.5 cents at 0.4 Hz
	_wow_phase += TWO_PI * 0.4 * delta
	if _wow_phase > TWO_PI: _wow_phase -= TWO_PI
	_wow_cents = sin(_wow_phase) * 1.5

func _apply_drift(freq: float) -> float:
	# Apply thermal + wow cents offset to a frequency
	if not enable_thermal_drift:
		return freq
	var total_cents: float = _thermal_cents + _wow_cents
	return freq * pow(2.0, total_cents / 1200.0)


# ==============================================================================
# ANTI-MACHINE-GUN PERTURBATION
# ==============================================================================
func _anti_machine_gun_perturb(base_gain: float, base_cutoff: float, base_attack: float) -> Dictionary:
	if not enable_anti_machine_gun:
		return {"gain": base_gain, "cutoff": base_cutoff, "attack": base_attack}
	_trigger_count += 1
	# Micro-spectral shifts: gain ±0.35 dB, cutoff ±22 Hz, attack ×[0.94, 1.06]
	var gain_trim: float = randf_range(-0.35, 0.35) * 0.01  # in linear gain
	var cutoff_jitter: float = randf_range(-22.0, 22.0)
	var attack_warp: float = randf_range(0.94, 1.06)
	# Ensure consecutive triggers differ
	if absf(gain_trim - _last_trigger_gain) < 0.001:
		gain_trim = -gain_trim
	if absf(cutoff_jitter - _last_trigger_cutoff) < 1.0:
		cutoff_jitter = -cutoff_jitter
	_last_trigger_gain = gain_trim
	_last_trigger_cutoff = cutoff_jitter
	_last_trigger_attack = attack_warp
	return {
		"gain": clampf(base_gain * (1.0 + gain_trim), 0.0, 2.0),
		"cutoff": maxf(20.0, base_cutoff + cutoff_jitter),
		"attack": base_attack * attack_warp
	}


# ==============================================================================
# TRIODE WARMTH SATURATION
# ==============================================================================
func _triode_warmth(x: float) -> float:
	if not enable_triode_warmth:
		return x
	# Asymmetric soft-clipper: y = (x + 0.25x²) / (1 + 0.4|x|)
	# Adds rich 2nd/3rd harmonics like a tube triode stage
	_triode_dc = _triode_dc * 0.9999 + x * 0.0001  # DC blocker
	var x_ac: float = x - _triode_dc
	return (x_ac + 0.25 * x_ac * x_ac) / (1.0 + 0.4 * absf(x_ac))


# ==============================================================================
# INCOMMENSURATE PRIME LOOP CLOCKS
# ==============================================================================
func _init_prime_loops() -> void:
	_prime_loops.clear()
	for i in range(PRIME_LENGTHS.size()):
		_prime_loops.append({
			"length": PRIME_LENGTHS[i],
			"step": 0,
			"timer": 0.0,
			"freq": 0.0,
			"env": 0.0,
			"phase": 0.0,
		})

func _update_prime_loops(delta: float) -> void:
	var sec_per_beat: float = 60.0 / maxf(30.0, music_bpm)
	var scale_pcs: Array[int] = _get_active_scale()
	# Base MIDI note varies by theme for correct octave placement
	var base_midi: int = 50  # D3 for exploration
	if music_theme == MusicTheme.MENU:
		base_midi = 57  # A3 for menu
	elif music_theme == MusicTheme.CINEMATIC:
		base_midi = 50  # D3 for cinematic
	for i in range(_prime_loops.size()):
		var loop: Dictionary = _prime_loops[i]
		var step_dur: float = sec_per_beat * 4.0  # Each prime step = 1 whole note
		# Menu theme: slower prime loops for more spacious feel
		if music_theme == MusicTheme.MENU:
			step_dur *= 1.5
		loop["timer"] = loop["timer"] + delta
		if loop["timer"] >= step_dur:
			loop["timer"] -= step_dur
			loop["step"] = (int(loop["step"]) + 1) % int(loop["length"])
			# Trigger a note from the active theme's scale
			var pc: int = scale_pcs[int(loop["step"]) % scale_pcs.size()]
			var octave: int = (i % 2) + 2  # Octave 2 or 3
			var midi: int = base_midi + pc + octave * 12
			loop["freq"] = 440.0 * pow(2.0, (float(midi) - 69.0) / 12.0)
			loop["env"] = 1.0
		# Decay envelope — menu theme has longer decays for ambient sustain
		var decay_rate: float = 0.8
		if music_theme == MusicTheme.MENU:
			decay_rate = 0.4  # Slower decay = longer notes
		loop["env"] = maxf(0.0, float(loop["env"]) - delta * decay_rate)
		_prime_loops[i] = loop


# ==============================================================================
# 2ND-ORDER MARKOV HARMONIC TRANSITIONS
# ==============================================================================
func _advance_markov_chord() -> void:
	var matrix: Array[Array] = _get_active_markov()
	var chord_roots: Array[int] = _get_active_chord_roots()
	if _current_harmonic_state >= matrix.size():
		_current_harmonic_state = 0
	var row: Array = matrix[_current_harmonic_state]
	var r: float = randf()
	var cumulative: float = 0.0
	for i in range(row.size()):
		cumulative += row[i]
		if r <= cumulative:
			_prev_harmonic_state = _current_harmonic_state
			_current_harmonic_state = i
			# Update drone anchor to new chord root
			_drone_anchor_freq = 440.0 * pow(2.0, (float(chord_roots[i]) - 69.0) / 12.0) * 0.5
			return


# ==============================================================================
# THEME MANAGEMENT — per-scene musical identity
# ==============================================================================

## Sets the active music theme. Resets harmonic state to the new theme's root.
func set_music_theme(theme: MusicTheme) -> void:
	if music_theme == theme:
		return
	music_theme = theme
	# Reset harmonic state for the new theme
	_current_harmonic_state = 0
	_prev_harmonic_state = 0
	# Update drone anchor to the new theme's root
	var chord_roots: Array[int] = _get_active_chord_roots()
	_drone_anchor_freq = 440.0 * pow(2.0, (float(chord_roots[0]) - 69.0) / 12.0) * 0.5
	# Reset arpeggio step
	_music_arp_step = 0
	_music_arp_timer = 0.0
	# Trigger a stem crossfade for smooth transition
	_stem_crossfade = 0.0

func _get_active_markov() -> Array[Array]:
	match music_theme:
		MusicTheme.MENU:
			return MENU_MARKOV
		MusicTheme.CINEMATIC:
			return CINEMATIC_MARKOV
		_:
			return EXPLORATION_MARKOV

func _get_active_chord_roots() -> Array[int]:
	match music_theme:
		MusicTheme.MENU:
			return MENU_CHORD_ROOTS
		MusicTheme.CINEMATIC:
			return CINEMATIC_CHORD_ROOTS
		_:
			return EXPLORATION_CHORD_ROOTS

func _get_active_arp_freqs() -> Array[float]:
	match music_theme:
		MusicTheme.MENU:
			return MENU_ARP_FREQS
		MusicTheme.CINEMATIC:
			return CINEMATIC_ARP_FREQS
		_:
			return EXPLORATION_ARP_FREQS

func _get_active_scale() -> Array[int]:
	match music_theme:
		MusicTheme.MENU:
			return MENU_SCALE
		MusicTheme.CINEMATIC:
			return CINEMATIC_SCALE
		_:
			return EXPLORATION_SCALE

func _get_active_lead_freq() -> float:
	match music_theme:
		MusicTheme.MENU:
			return MENU_LEAD_FREQ
		MusicTheme.CINEMATIC:
			return CINEMATIC_LEAD_FREQ
		_:
			return EXPLORATION_LEAD_FREQ

func _theme_allows_perc() -> bool:
	match music_theme:
		MusicTheme.MENU:
			return MENU_ALLOWS_PERC
		MusicTheme.CINEMATIC:
			return CINEMATIC_ALLOWS_PERC
		_:
			return EXPLORATION_ALLOWS_PERC

func _theme_allows_lead() -> bool:
	match music_theme:
		MusicTheme.MENU:
			return MENU_ALLOWS_LEAD
		MusicTheme.CINEMATIC:
			return CINEMATIC_ALLOWS_LEAD
		_:
			return EXPLORATION_ALLOWS_LEAD


# ==============================================================================
# SYSTEM SOUNDSCAPE — star-type-driven ambient layers
# ==============================================================================

## Sets the current star type and configures ambient layers accordingly.
## Star type values mirror ProceduralGalaxy.SpectralClass.
func set_star_type(star_type: int) -> void:
	if _current_star_type == star_type:
		return
	_current_star_type = star_type
	# Configure star-type-specific parameters
	match star_type:
		StarType.CLASS_O:
			# Blue Hypergiant: intense UV radiation, high-energy shimmer
			_star_radiation_freq = 2400.0
			_star_radiation_amp = 0.08
			_star_gravity_drone_freq = 28.0
			_star_gravity_drone_amp = 0.06
			_star_shimmer_amp = 0.05
			_pulsar_pulse_active = false
			_black_hole_time_dilation = 0.0
		StarType.CLASS_B:
			# Blue-White Giant: bright, energetic
			_star_radiation_freq = 1800.0
			_star_radiation_amp = 0.06
			_star_gravity_drone_freq = 32.0
			_star_gravity_drone_amp = 0.05
			_star_shimmer_amp = 0.04
			_pulsar_pulse_active = false
			_black_hole_time_dilation = 0.0
		StarType.CLASS_A:
			# White Main Sequence: clean, neutral, bright
			_star_radiation_freq = 1200.0
			_star_radiation_amp = 0.04
			_star_gravity_drone_freq = 36.0
			_star_gravity_drone_amp = 0.04
			_star_shimmer_amp = 0.02
			_pulsar_pulse_active = false
			_black_hole_time_dilation = 0.0
		StarType.CLASS_F:
			# Yellow-White: warm, golden
			_star_radiation_freq = 800.0
			_star_radiation_amp = 0.03
			_star_gravity_drone_freq = 40.0
			_star_gravity_drone_amp = 0.04
			_star_shimmer_amp = 0.01
			_pulsar_pulse_active = false
			_black_hole_time_dilation = 0.0
		StarType.CLASS_G:
			# Sol-Type: familiar, balanced — "home" system
			_star_radiation_freq = 600.0
			_star_radiation_amp = 0.02
			_star_gravity_drone_freq = 44.0
			_star_gravity_drone_amp = 0.03
			_star_shimmer_amp = 0.005
			_pulsar_pulse_active = false
			_black_hole_time_dilation = 0.0
		StarType.CLASS_K:
			# Orange Dwarf: warm, amber, slightly melancholic
			_star_radiation_freq = 400.0
			_star_radiation_amp = 0.02
			_star_gravity_drone_freq = 48.0
			_star_gravity_drone_amp = 0.04
			_star_shimmer_amp = 0.0
			_pulsar_pulse_active = false
			_black_hole_time_dilation = 0.0
		StarType.CLASS_M:
			# Red Dwarf: deep, dark, ominous
			_star_radiation_freq = 200.0
			_star_radiation_amp = 0.03
			_star_gravity_drone_freq = 24.0
			_star_gravity_drone_amp = 0.07
			_star_shimmer_amp = 0.0
			_pulsar_pulse_active = false
			_black_hole_time_dilation = 0.0
		StarType.NEUTRON_STAR:
			# Pulsar: rhythmic pulsing beep + extreme magnetic field hum
			_star_radiation_freq = 3000.0
			_star_radiation_amp = 0.05
			_star_gravity_drone_freq = 20.0
			_star_gravity_drone_amp = 0.08
			_star_shimmer_amp = 0.03
			_pulsar_pulse_active = true
			_pulsar_pulse_period = 0.714  # ~1.4 Hz (Crab Pulsar-like)
			_black_hole_time_dilation = 0.0
		StarType.BLACK_HOLE:
			# Singularity: gravitational drone, time-dilation pitch bend
			_star_radiation_freq = 100.0
			_star_radiation_amp = 0.02
			_star_gravity_drone_freq = 14.0  # Extremely deep
			_star_gravity_drone_amp = 0.12
			_star_shimmer_amp = 0.0
			_pulsar_pulse_active = false
			_black_hole_time_dilation = 0.3  # pitch bend depth
		StarType.WOLF_RAYET:
			# Mass-losing variable: chaotic, turbulent wind
			_star_radiation_freq = 1500.0
			_star_radiation_amp = 0.07
			_star_gravity_drone_freq = 30.0
			_star_gravity_drone_amp = 0.06
			_star_shimmer_amp = 0.06
			_pulsar_pulse_active = false
			_black_hole_time_dilation = 0.0

## Sets the current planet proximity type and closeness.
## planet_type values mirror ProceduralGalaxy.PlanetArchetype. Use -1 for "no planet nearby".
func set_planet_proximity(planet_type: int, proximity: float) -> void:
	_current_planet_type = planet_type
	_planet_proximity = clampf(proximity, 0.0, 1.0)
	# Configure planet-type-specific ambient parameters
	match planet_type:
		PlanetType.MOLTEN:
			_planet_ambient_freq = 80.0   # deep volcanic rumble
			_planet_wind_freq = 0.0
		PlanetType.METALLIC_BARREN:
			_planet_ambient_freq = 440.0  # metallic resonance
			_planet_wind_freq = 0.0
		PlanetType.DESERT_ARID:
			_planet_ambient_freq = 0.0
			_planet_wind_freq = 600.0    # sand wind
		PlanetType.TERRAN_OCEANIC:
			_planet_ambient_freq = 200.0  # ocean wave rumble
			_planet_wind_freq = 400.0    # gentle breeze
		PlanetType.ICE_WORLD:
			_planet_ambient_freq = 880.0  # crystal chimes
			_planet_wind_freq = 300.0    # cold wind
		PlanetType.GAS_GIANT_JOVIAN:
			_planet_ambient_freq = 50.0   # massive storm turbulence
			_planet_wind_freq = 200.0    # storm wind
		PlanetType.GAS_GIANT_ICE:
			_planet_ambient_freq = 70.0
			_planet_wind_freq = 500.0    # methane wind (higher)
		PlanetType.RADIOTROPHIC_BIO:
			_planet_ambient_freq = 330.0  # bioluminescent organic pulse
			_planet_wind_freq = 250.0
		_:
			_planet_ambient_freq = 0.0
			_planet_wind_freq = 0.0

## Sets the current environment event (nebula, asteroid field, etc.)
## EnvironmentEvent enum values. Use NONE (0) to clear.
func set_environment_event(event: int, intensity: float = 1.0) -> void:
	_current_env_event = event
	_env_event_target_intensity = clampf(intensity, 0.0, 1.0)
	# Reset event-specific state
	_nebula_lfo = 0.0
	_asteroid_ping_timer = 0.0

## Clears the current environment event
func clear_environment_event() -> void:
	_env_event_target_intensity = 0.0


# ==============================================================================
# STEM TRANSITION QUEUE (Bar/Beat Quantum)
# ==============================================================================
func _queue_stem_transition(new_stem_set: int) -> void:
	if new_stem_set == _current_stem_set:
		return
	# Queue the transition for the next bar boundary
	_stem_transition_queue.append({
		"target": new_stem_set,
		"queued_at_beat": _music_beat_count,
	})
	_pending_stem_set = new_stem_set

func _update_stem_transitions(delta: float) -> void:
	# Process queued transitions at bar boundaries (every 4 beats in 4/4)
	if _stem_transition_queue.size() > 0 and _music_beat_count % 4 == 0:
		var transition: Dictionary = _stem_transition_queue.pop_front()
		var target: int = int(transition["target"])
		if target != _current_stem_set:
			_current_stem_set = target
			_stem_crossfade = 0.0
			_reverb_tail_active = true
			_reverb_tail_time = 0.0
			# Advance Markov chord on stem change
			_advance_markov_chord()

	# Crossfade progression
	if _stem_crossfade < 1.0:
		_stem_crossfade = minf(1.0, _stem_crossfade + delta * 2.0)  # 0.5s crossfade

	# Reverb tail preservation
	if _reverb_tail_active:
		_reverb_tail_time += delta
		if _reverb_tail_time > 1.5:  # 1.5s tail
			_reverb_tail_active = false


# ==============================================================================
# 3-BAND CROSSOVER SIDESHAIN MATRIX
# ==============================================================================
func _trigger_sidechain(intensity: float = 1.0) -> void:
	_sidechain_trigger = maxf(_sidechain_trigger, intensity)

func _update_sidechain(delta: float) -> void:
	# Sidechain decays exponentially
	_sidechain_trigger = maxf(0.0, _sidechain_trigger - delta * 3.5)
	# Sub band ( < 120 Hz): preserved, only 10% ducking
	_sidechain_band_sub = 1.0 - _sidechain_trigger * 0.10
	# Mid band (250 Hz - 4.5 kHz): heavy ducking for combat clarity
	_sidechain_band_mid = 1.0 - _sidechain_trigger * 0.65
	# High band ( > 4.5 kHz): moderate ducking, Shepard risers breathe through
	_sidechain_band_high = 1.0 - _sidechain_trigger * 0.35

func _apply_sidechain(sample: float) -> float:
	# Simple broadband application — full 3-band split would need crossover filters
	# For now, apply mid-band ducking to the main mix
	return sample * _sidechain_band_mid


# ==============================================================================
# BIOMETRIC EXERTION & TRAUMA ENGINE
# ==============================================================================
func _update_biometric_engine(delta: float) -> void:
	# Derive exertion from throttle + bio-boost + G-force
	var total_throttle: float = clampf(_throttle_forward + _throttle_strafe * 0.7 + _throttle_retro * 0.8, 0.0, 1.0)
	if _bio_boost:
		total_throttle = 1.30
	var target_exertion: float = clampf(total_throttle * 0.6 + _g_force_stress * 0.4, 0.0, 1.0)
	# Low stamina increases exertion impact
	target_exertion *= (1.5 - pilot_stamina * 0.5)
	_exertion_level = lerpf(_exertion_level, clampf(target_exertion, 0.0, 1.0), delta * 3.0)

	# Heart rate increases with exertion (68 resting → 160 max)
	var target_hr: float = 68.0 + _exertion_level * 92.0
	# Damage increases HR further
	target_hr += damage_flash * 40.0
	# Arrhythmia increases with damage and low stamina
	_cardiac_arrhythmia = clampf(damage_flash * 0.7 + (1.0 - pilot_stamina) * 0.3, 0.0, 1.0)
	_heart_rate_bpm = lerpf(_heart_rate_bpm, clampf(target_hr, 50.0, 200.0), delta * 2.0)

	# Respiration rate (12 resting → 30 max)
	var target_rr: float = 12.0 + _exertion_level * 18.0
	_respiration_rate = lerpf(_respiration_rate, target_rr, delta * 2.0)
	_respiration_phase += TWO_PI * (_respiration_rate / 60.0) * delta
	if _respiration_phase > TWO_PI: _respiration_phase -= TWO_PI

	# Formant shifts with exertion (wider mouth, higher F1)
	var exertion_formant_shift: float = _exertion_level * 0.15
	_creature_formant_f1 *= (1.0 - delta * 2.0)
	_creature_formant_f1 += _creature_formant_f1_base * (1.0 + exertion_formant_shift) * delta * 2.0

	# Damage flash decay
	damage_flash = maxf(0.0, damage_flash - delta * 1.5)

	# Tinnitus from damage
	tinnitus_intensity = clampf(damage_flash * 0.8, 0.0, 1.0)

	# Thermal drift update
	_update_thermal_drift(delta)

# Store base formant for exertion modulation
var _creature_formant_f1_base: float = 380.0


# ==============================================================================
# TINNITUS / TRAUMA FILTER
# ==============================================================================
func _update_tinnitus(delta: float) -> void:
	if tinnitus_intensity > 0.01:
		_tinnitus_envelope = lerpf(_tinnitus_envelope, tinnitus_intensity, delta * 4.0)
		# Tinnitus pitch drifts slightly
		_tinnitus_freq = 7200.0 + sin(_tinnitus_phase * 0.1) * 200.0
		_tinnitus_phase += TWO_PI * _tinnitus_freq * delta
		if _tinnitus_phase > TWO_PI: _tinnitus_phase -= TWO_PI
	else:
		_tinnitus_envelope = maxf(0.0, _tinnitus_envelope - delta * 2.0)

func _render_tinnitus() -> float:
	if _tinnitus_envelope < 0.001:
		return 0.0
	return sin(_tinnitus_phase) * _tinnitus_envelope * 0.08


# ==============================================================================
# Telemetry Synchronization & Archetype Mappings
# ==============================================================================
func _sync_organ_telemetry() -> void:
	if has_node("/root/OrganTelemetry"):
		var ot = get_node("/root/OrganTelemetry")
		if "heart_rate_bpm" in ot:
			_heart_rate_bpm = ot.heart_rate_bpm
		if "damage_stress" in ot:
			ship_health_pct = clampf((1.0 - float(ot.damage_stress)) * 100.0, 0.0, 100.0)
			damage_flash = maxf(damage_flash, float(ot.damage_stress) * 0.5)

	if has_node("/root/BioManager"):
		var bm = get_node("/root/BioManager")
		if "current_archetype" in bm:
			_apply_archetype_leitmotif(bm.current_archetype)

## Manually sets ship hull health percentage [0.0 - 100.0]
func set_ship_health(pct: float) -> void:
	ship_health_pct = clampf(pct, 0.0, 100.0)
	if pct < 50.0:
		damage_flash = maxf(damage_flash, (50.0 - pct) / 50.0)

## Triggers a damage event (call from FlightController on hit)
func trigger_damage(severity: float) -> void:
	damage_flash = maxf(damage_flash, clampf(severity, 0.0, 1.0))
	play_chitin_creak()
	_trigger_sidechain(0.8)

## Sets pilot stamina [0.0 - 1.0]
func set_pilot_stamina(stamina: float) -> void:
	pilot_stamina = clampf(stamina, 0.0, 1.0)


func _apply_archetype_leitmotif(archetype_idx: int) -> void:
	# Clean, majestic, oceanic formant frequencies across the 5 archetypes
	match archetype_idx:
		0: # Apex Hive Leviathan (Colossal Oceanic Carrier) -> Deep, resonant whale-song tones
			_creature_formant_f1 = 260.0
			_creature_formant_f2 = 780.0
			_creature_formant_f3 = 1750.0
			_creature_vocal_pitch = 55.0
		1: # Neuro-Spore Interceptor (Agile Strike Symbiont) -> Crystalline, airy dolphin-like pulses
			_creature_formant_f1 = 620.0
			_creature_formant_f2 = 1850.0
			_creature_formant_f3 = 3100.0
			_creature_vocal_pitch = 125.0
		2: # Chitinous Void Harvester (Mining Dreadnought) -> Warm, deep oceanic bellows
			_creature_formant_f1 = 310.0
			_creature_formant_f2 = 940.0
			_creature_formant_f3 = 2050.0
			_creature_vocal_pitch = 65.0
		3: # Abyssal Symbiont Frigate (Stealth Recon) -> Ethereal, glass-like bioluminescent hum
			_creature_formant_f1 = 480.0
			_creature_formant_f2 = 1520.0
			_creature_formant_f3 = 2750.0
			_creature_vocal_pitch = 95.0
		4: # Viral Colony Carrier (Brood-Mother) -> Gentle harmonic chordal singing
			_creature_formant_f1 = 420.0
			_creature_formant_f2 = 1300.0
			_creature_formant_f3 = 2500.0
			_creature_vocal_pitch = 80.0
	_creature_formant_f1_base = _creature_formant_f1


# ==============================================================================
# Public API Methods
# ==============================================================================

## Modulates 6-DOF siphon thruster forces (forward, lateral strafe, retro reverse)
func set_6dof_thrust(forward: float, strafe: float, retro: float, g_force: float = 1.0) -> void:
	_throttle_forward = clampf(forward, 0.0, 1.0)
	_throttle_strafe = clampf(strafe, 0.0, 1.0)
	_throttle_retro = clampf(retro, 0.0, 1.0)
	_g_force_stress = clampf(g_force / 8.0, 0.0, 1.0)

## Triggers Bio-Boost plasma overdrive
func set_bio_boost(active: bool) -> void:
	if active and not _bio_boost:
		play_bio_boost_burst()
		_trigger_sidechain(0.5)
	_bio_boost = active

## Alcubierre Wave Engine state transition
func set_wave_engine_state(state: int) -> void:
	_wave_state = state
	_wave_time = 0.0
	if state == 2: # ENGAGED punch-in
		_wave_sub_boom_active = true
		_wave_sub_boom_time = 0.0
		_trigger_sidechain(1.0)

## Triggers the 3.0s Alcubierre HyperWave / Interstellar jump spool-up sequence
func play_hyperwave_charge() -> void:
	_wave_state = 1
	_wave_time = 0.0

## Triggers the superluminal warp punch-in/out boom and spacetime tear
func play_hyperwave_boom() -> void:
	_wave_sub_boom_active = true
	_wave_sub_boom_time = 0.0
	_trigger_sidechain(1.0)

## Toggles the sustained hyperspace transit tunnel soundscape (15-second superluminal cruise)
func set_hyperwave_tunnel(active: bool) -> void:
	_hyper_tunnel_active = active
	if active:
		_wave_state = 2
		_hyper_tunnel_time = 0.0
	else:
		_wave_state = 0

## Triggers an immediate interstellar hyperjump sound sequence
func play_interstellar_jump() -> void:
	play_hyperwave_charge()
	play_hyperwave_boom()

## Triggers Bio-Boost ignition transient
func play_bio_boost_burst() -> void:
	_wave_sub_boom_active = true
	_wave_sub_boom_time = 0.0

## Triggers dual bio-plasma disruptor discharge with stereo panning
func play_laser_fire(pan: float = 0.0) -> void:
	_laser_active = true
	_laser_time = 0.0
	_laser_pan = clampf(pan, -1.0, 1.0)
	_laser_carrier_phase = 0.0
	_laser_mod_phase = 0.0
	_trigger_sidechain(0.7)

## Updates conical lock-on tracking state (0=None, 1=In Cone, 2=Ramping, 3=Locked)
func set_lock_on_stage(stage: int) -> void:
	_lock_on_stage = stage
	if stage == 1:
		_lock_on_timer = 0.0

## Triggers defensive spore mist release
func play_spore_cloud_release() -> void:
	_spore_active = true
	_spore_time = 0.0

## Triggers bio-shield membrane impact
func play_shield_impact() -> void:
	_shield_impact_active = true
	_shield_impact_time = 0.0
	_trigger_sidechain(0.4)

## Triggers hull stress chitin acoustic tension
func play_chitin_creak() -> void:
	_chitin_active = true
	_chitin_time = 0.0
	# Anti-machine-gun: vary the frequency seed each trigger
	var perturbed: Dictionary = _anti_machine_gun_perturb(1.0, 4200.0, 1.0)
	_chitin_freq_seed = perturbed["cutoff"] + randf_range(-200.0, 200.0)

## Triggers majestic oceanic creature call
func play_creature_vocalization(pitch_scale: float = 1.0) -> void:
	_creature_vocal_active = true
	_creature_vocal_time = 0.0
	_creature_vocal_pitch = 85.0 * pitch_scale

## Plays a crisp Frutiger Aero tactile UI micro-chirp (glassy water-drop click)
func play_ui_click(is_confirm: bool = true) -> void:
	_ui_chirp_active = true
	_ui_chirp_time = 0.0
	_ui_chirp_phase = 0.0
	if is_confirm:
		_ui_chirp_freq_start = 3200.0
		_ui_chirp_freq_end = 6400.0
		_ui_chirp_duration = 0.032
	else:
		_ui_chirp_freq_start = 2400.0
		_ui_chirp_freq_end = 1200.0
		_ui_chirp_duration = 0.045

## Triggers immediate healthy heartbeat pulse
func play_heartbeat_pulse() -> void:
	_heart_timer = 0.0
	_trigger_lub()

## Sets the Dynamic Tension Index and queues stem transitions
func set_tension_index(dti: float) -> void:
	var new_dti: float = clampf(dti, 0.0, 1.0)
	tension_index = new_dti
	# Map DTI to stem sets and queue bar-quantized transitions
	var target_stem: int = 0
	if new_dti > 0.75:
		target_stem = 4  # Climax
	elif new_dti > 0.45:
		target_stem = 3  # Combat
	elif new_dti > 0.20:
		target_stem = 2  # Tension
	elif new_dti > 0.05:
		target_stem = 1  # Exploration
	else:
		target_stem = 0  # Calm
	_queue_stem_transition(target_stem)


# ==============================================================================
# Internal Synthesis & DSP Buffer Render Loop
# ==============================================================================

## Advances the arpeggio step with algorithmic variation (ported from Godot Synth
## MusicTheme variation techniques: octave displacement, neighbor tone ornamentation,
## rhythmic displacement). Variation probability scales with tension_index so
## calm exploration stays stable while combat/climax introduces dramatic leaps.
func _advance_arp_step() -> void:
	_music_arp_step = (_music_arp_step + 1) % 8
	# Reset variation for the new step
	_arp_octave_shift = 0
	_arp_neighbor_shift = 0
	_arp_rest_active = false
	# Variation probability scales with tension (5% at calm → 25% at climax)
	var variation_chance: float = lerpf(0.05, 0.25, tension_index)
	# Octave displacement (±12 semitones) — dramatic melodic leaps
	if randf() < variation_chance * 0.4:
		_arp_octave_shift = 12 if randf() > 0.5 else -12
	# Neighbor tone ornamentation (±1 semitone) — chromatic passing tones
	if randf() < variation_chance * 0.3:
		_arp_neighbor_shift = 1 if randf() > 0.5 else -1
	# Rhythmic rest — skip this step for syncopated spacing
	if randf() < variation_chance * 0.2:
		_arp_rest_active = true

func _update_dynamic_music_timers(delta: float) -> void:
	var sec_per_beat: float = 60.0 / maxf(30.0, music_bpm)
	_music_beat_timer += delta
	if _music_beat_timer >= sec_per_beat:
		_music_beat_timer -= sec_per_beat
		_music_beat_count = (_music_beat_count + 1) % 16
		# Euclidean 16-step rhythm trigger for clean biopunk percussion (E(5, 16) Bell pattern)
		# Only triggers if the current theme allows percussion
		var bell_mask: Array[int] = [1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 0]
		if _theme_allows_perc() and tension_index > 0.45 and bell_mask[_music_beat_count] == 1:
			_music_perc_active = true
			_music_perc_time = 0.0
		# Advance Markov chord every 4 bars
		if _music_beat_count == 0 and _music_beat_count % 16 == 0:
			_advance_markov_chord()

	var sec_per_16th: float = sec_per_beat * 0.25
	# Apply timing jitter to the 16th note clock
	var jittered_step: float = sec_per_16th
	if enable_timing_jitter:
		jittered_step += _timing_jitter_ms(2.5)
	_music_arp_timer += delta
	if _music_arp_timer >= jittered_step:
		_music_arp_timer -= sec_per_16th
		_advance_arp_step()

func _update_heartbeat_rhythm(delta: float) -> void:
	# Arrhythmia adds jitter to the cardiac cycle
	var cardiac_cycle: float = 60.0 / maxf(30.0, _heart_rate_bpm)
	if _cardiac_arrhythmia > 0.01:
		# Irregular rhythm: add pink noise jitter to the cycle
		var arrhythmia_jitter: float = _timing_jitter_ms(50.0 * _cardiac_arrhythmia)
		cardiac_cycle += arrhythmia_jitter
	_heart_timer += delta
	if _heart_timer >= cardiac_cycle:
		_heart_timer = 0.0
		_trigger_lub()

func _trigger_lub() -> void:
	_lub_active = true
	_lub_time = 0.0
	_dub_active = false

func _trigger_dub() -> void:
	_dub_active = true
	_dub_time = 0.0


func _fill_audio_buffer() -> void:
	var frames_available: int = playback.get_frames_available()
	if frames_available <= 0:
		return

	var buffer: PackedVector2Array = PackedVector2Array()
	buffer.resize(frames_available)

	var dt: float = _sample_step
	var dti: float = tension_index
	var steth: bool = stethoscope_mode

	# Theme-aware arpeggio frequencies
	var arp_freqs: Array[float] = _get_active_arp_freqs()
	var lead_freq: float = _get_active_lead_freq()

	# Stem crossfade gains
	var stem_old: float = 1.0 - _stem_crossfade
	var stem_new: float = _stem_crossfade

	# Current chord root frequency from Markov state (theme-aware)
	var active_chord_roots: Array[int] = _get_active_chord_roots()
	var chord_root_freq: float = 440.0 * pow(2.0, (float(active_chord_roots[_current_harmonic_state % active_chord_roots.size()]) - 69.0) / 12.0)

	# Precompute pad detune ratios (avoid pow() per sample)
	var pad_detune_ratios: Array[float] = []
	for v in range(PAD_VOICE_COUNT):
		pad_detune_ratios.append(pow(2.0, _pad_detune_cents[v] / 1200.0))
	var pad_freq_base: float = _apply_drift(chord_root_freq * 0.5)
	var pad2_freq_base: float = _apply_drift(chord_root_freq)
	var pad_amp_eff: float = _pad_amp * (stem_new + stem_old * 0.5)
	var pad_coef: float = _pad_lpf_coef
	var pad2_coef: float = _pad2_lpf_coef

	for i in range(frames_available):
		var left: float = 0.0
		var right: float = 0.0

		# ----------------------------------------------------------------------
		# LAYER A: 3-BAND NOISE TEXTURE BED (atmospheric depth — always present)
		# ----------------------------------------------------------------------
		if not steth:
			var white: float = randf_range(-1.0, 1.0)
			_noise_sub_state += (white - _noise_sub_state) * (80.0 * dt * 2.0)
			_noise_mid_state += (white - _noise_mid_state) * (1200.0 * dt * 2.0)
			var mid_filtered: float = _noise_mid_state - _noise_sub_state
			_noise_high_state += (white - _noise_high_state) * (6000.0 * dt * 2.0)
			var high_filtered: float = white - _noise_high_state

			var wind_mod: float = 0.7 + 0.3 * sin(_noise_lfo)

			left += _noise_sub_state * _noise_sub_amp
			right += _noise_sub_state * _noise_sub_amp
			left += mid_filtered * _noise_mid_amp * wind_mod
			right += mid_filtered * _noise_mid_amp * (2.0 - wind_mod)
			left += high_filtered * _noise_high_amp * 0.5
			right += high_filtered * _noise_high_amp * 0.5

		# ----------------------------------------------------------------------
		# LAYER B: SUB-BASS OCTAVE (cinematic weight below drone)
		# ----------------------------------------------------------------------
		if not steth and _sub_bass_amp > 0.001:
			var sub_freq: float = _apply_drift(_drone_anchor_freq * 0.5)  # D1 = 36.71 Hz
			_sub_bass_phase += TWO_PI * sub_freq * dt
			if _sub_bass_phase > TWO_PI: _sub_bass_phase -= TWO_PI
			var sub_val: float = _wt_triangle(_sub_bass_phase / TWO_PI) * _sub_bass_amp
			left += sub_val
			right += sub_val

		# ----------------------------------------------------------------------
		# LAYER C: DETUNED SUPERSAW PAD (main harmonic bed — 5 detuned saws)
		# Uses precomputed one-pole lowpass (no tan() per sample)
		# ----------------------------------------------------------------------
		if not steth and pad_amp_eff > 0.001:
			var pad_sum: float = 0.0
			for v in range(PAD_VOICE_COUNT):
				var voice_freq: float = pad_freq_base * pad_detune_ratios[v]
				_pad_phases[v] = fmod(_pad_phases[v] + voice_freq * dt, 1.0)
				pad_sum += _wt_saw(_pad_phases[v])
			pad_sum /= float(PAD_VOICE_COUNT)
			# One-pole lowpass with precomputed coefficient
			_pad_lpf_state = _onepole_lpf(pad_sum, pad_coef, _pad_lpf_state)
			var pad_out: float = _pad_lpf_state * pad_amp_eff
			left += pad_out
			right += pad_out

		# ----------------------------------------------------------------------
		# LAYER D: SECOND PAD (higher octave, softer — adds air and shimmer)
		# ----------------------------------------------------------------------
		if not steth and _pad2_amp > 0.001:
			var pad2_sum: float = 0.0
			for v in range(PAD_VOICE_COUNT):
				var voice_freq: float = pad2_freq_base * pad_detune_ratios[v]
				_pad2_phases[v] = fmod(_pad2_phases[v] + voice_freq * dt, 1.0)
				pad2_sum += _wt_triangle(_pad2_phases[v])
			pad2_sum /= float(PAD_VOICE_COUNT)
			_pad2_lpf_state = _onepole_lpf(pad2_sum, pad2_coef, _pad2_lpf_state)
			var pad2_out: float = _pad2_lpf_state * _pad2_amp
			left += pad2_out * 0.7
			right += pad2_out * 1.3

		# ----------------------------------------------------------------------
		# LAYER E: HARMONIC DRONE ANCHOR (key-stable sine for tonal center)
		# ----------------------------------------------------------------------
		if not steth:
			_drone_anchor_phase += TWO_PI * _apply_drift(_drone_anchor_freq) * dt
			if _drone_anchor_phase > TWO_PI: _drone_anchor_phase -= TWO_PI
			var anchor_val: float = _wt_sine(_drone_anchor_phase / TWO_PI) * 0.06
			left += anchor_val
			right += anchor_val

		# ----------------------------------------------------------------------
		# LAYER F: CRYSTALLINE BIOLUMINESCENT HARP ARPEGGIOS (additive harmonics)
		# Now uses 5-harmonic additive synthesis instead of single sine
		# Menu theme: wider arpeggio envelope (slower attack, longer decay)
		# Includes arpeggio variation engine (octave displacement + neighbor tones)
		# ----------------------------------------------------------------------
		if not steth and dti > 0.20 and not _arp_rest_active:
			var arp_freq: float = _apply_drift(arp_freqs[_music_arp_step])
			# Apply arpeggio variation: octave displacement + neighbor tone ornamentation
			var arp_semitone_shift: int = _arp_octave_shift + _arp_neighbor_shift
			if arp_semitone_shift != 0:
				arp_freq *= pow(2.0, float(arp_semitone_shift) / 12.0)
			_music_phase_arp += TWO_PI * arp_freq * dt
			if _music_phase_arp > TWO_PI: _music_phase_arp -= TWO_PI
			var arp_env: float = exp(-_music_arp_timer * 16.0)
			var arp_phase_norm: float = _music_phase_arp / TWO_PI
			# Additive synthesis: fundamental + 4 harmonics with 1/n decay
			var arp_val: float = (
				_wt_sine(arp_phase_norm) * 1.0 +
				_wt_sine(fmod(arp_phase_norm * 2.0, 1.0)) * 0.5 +
				_wt_sine(fmod(arp_phase_norm * 3.0, 1.0)) * 0.33 +
				_wt_sine(fmod(arp_phase_norm * 4.0, 1.0)) * 0.25 +
				_wt_sine(fmod(arp_phase_norm * 5.0, 1.0)) * 0.20
			) * arp_env * 0.06 * (dti - 0.20) * 1.25
			# Stereo spread
			left += arp_val * 0.85
			right += arp_val * 1.15

		# ----------------------------------------------------------------------
		# LAYER G: CLEAN EUCLIDEAN MICRO-PERCUSSION (Tension > 0.45)
		# Only plays if the current theme allows percussion (menu has none)
		# ----------------------------------------------------------------------
		if not steth and _music_perc_active and _theme_allows_perc():
			_music_perc_time += dt
			var perc_env: float = exp(-_music_perc_time * 28.0)
			var perc_freq: float = 160.0 * exp(-_music_perc_time * 30.0) + 52.0
			var perc_phase: float = fmod(perc_freq * _music_perc_time, 1.0)
			# Triangle body + noise transient for impact
			var perc_val: float = (_wt_triangle(perc_phase) * 0.7 + randf_range(-0.5, 0.5) * exp(-_music_perc_time * 80.0) * 0.3) * perc_env * 0.22 * (dti - 0.45) * 1.8
			left += perc_val
			right += perc_val
			if _music_perc_time > 0.14:
				_music_perc_active = false

		# ----------------------------------------------------------------------
		# LAYER H: RADIANT LYDIAN LEAD CLIMAX (Tension > 0.75)
		# Only plays if the current theme allows lead (menu theme has no lead)
		# ----------------------------------------------------------------------
		if not steth and dti > 0.75 and _theme_allows_lead():
			_music_lead_phase += TWO_PI * _apply_drift(lead_freq) * dt
			if _music_lead_phase > TWO_PI: _music_lead_phase -= TWO_PI
			var lead_vib: float = sin(_music_phase_drone * 4.0) * 8.0
			var lead_phase_norm: float = fmod((_music_lead_phase + lead_vib * dt) / TWO_PI, 1.0)
			# Sawtooth lead through gentle lowpass for warmth
			var lead_raw: float = _wt_saw(lead_phase_norm)
			var lead_val: float = lead_raw * 0.15 * (dti - 0.75) * 4.0
			left += lead_val
			right += lead_val

		# ----------------------------------------------------------------------
		# LAYER I: INCOMMENSURATE PRIME LOOP VOICES (Brian Eno Ambient Automata)
		# Now uses wavetable sine + triangle for richer character
		# ----------------------------------------------------------------------
		if not steth:
			for pl in _prime_loops:
				if float(pl["env"]) > 0.001:
					var pl_freq: float = _apply_drift(float(pl["freq"]))
					pl["phase"] = fmod(float(pl["phase"]) + pl_freq * dt, 1.0)
					# Mix sine and triangle for warmth
					var pl_val: float = (_wt_sine(float(pl["phase"])) * 0.7 + _wt_triangle(float(pl["phase"])) * 0.3) * float(pl["env"]) * 0.04
					var pan: float = sin(float(pl["phase"]) * 0.13) * 0.3
					left += pl_val * (1.0 - pan)
					right += pl_val * (1.0 + pan)

		# ----------------------------------------------------------------------
		# LAYER J: GRANULAR CLOUD TEXTURE (cosmic ambience — NMS Pulse-style)
		# Scattered short grains creating evolving textural atmosphere
		# ----------------------------------------------------------------------
		if not steth:
			var grain_stereo: Vector2 = _render_grains(dt)
			left += grain_stereo.x
			right += grain_stereo.y

		# ----------------------------------------------------------------------
		# LAYER K: REVERB TAIL PRESERVATION (fading old stem)
		# ----------------------------------------------------------------------
		if not steth and _reverb_tail_active:
			var tail_val: float = _wt_sine(fmod(_music_phase_drone * 3.0 / TWO_PI, 1.0)) * exp(-_reverb_tail_time * 2.0) * 0.03
			left += tail_val * stem_old
			right += tail_val * stem_old

		# ----------------------------------------------------------------------
		# LAYER 2: CLEAN CARDIOVASCULAR & CALM BIOLOGICAL ENGINE
		# ----------------------------------------------------------------------
		var heart_audible_gain: float = 0.0
		if stethoscope_mode:
			heart_audible_gain = 1.0
		elif ship_health_pct < 40.0:
			heart_audible_gain = clampf((40.0 - ship_health_pct) / 40.0, 0.0, 1.0)

		if heart_audible_gain > 0.001:
			if _lub_active:
				_lub_time += dt
				var lub_env: float = exp(-_lub_time * 24.0)
				var lub_freq: float = 52.0 * exp(-_lub_time * 12.0) + 26.0
				if _cardiac_arrhythmia > 0.01:
					lub_freq *= 1.0 + sin(_lub_time * 80.0) * _cardiac_arrhythmia * 0.1
				# Use triangle for richer heartbeat (less pure-sine)
				var lub_phase: float = fmod(lub_freq * _lub_time, 1.0)
				var lub_val: float = _wt_triangle(lub_phase) * lub_env * 0.38 * heart_audible_gain
				left += lub_val
				right += lub_val
				if _lub_time > 0.09 and not _dub_active and _lub_time < 0.11:
					_trigger_dub()
				if _lub_time > 0.22:
					_lub_active = false

			if _dub_active:
				_dub_time += dt
				var dub_env: float = exp(-_dub_time * 30.0)
				var dub_freq: float = 65.0 * exp(-_dub_time * 15.0) + 32.0
				if _cardiac_arrhythmia > 0.01:
					dub_freq *= 1.0 + sin(_dub_time * 90.0) * _cardiac_arrhythmia * 0.08
				var dub_phase: float = fmod(dub_freq * _dub_time, 1.0)
				var dub_val: float = _wt_triangle(dub_phase) * dub_env * 0.26 * heart_audible_gain
				left += dub_val
				right += dub_val
				if _dub_time > 0.18:
					_dub_active = false
		else:
			if _lub_active:
				_lub_time += dt
				if _lub_time > 0.09 and not _dub_active and _lub_time < 0.11:
					_trigger_dub()
				if _lub_time > 0.22:
					_lub_active = false
			if _dub_active:
				_dub_time += dt
				if _dub_time > 0.18:
					_dub_active = false

		# ----------------------------------------------------------------------
		# LAYER 3: LAMINAR HYDRODYNAMIC PULSE THRUSTER & ION FLOW
		# Now uses sawtooth rumble + filtered noise for richer engine sound
		# ----------------------------------------------------------------------
		var total_throttle: float = clampf(_throttle_forward + _throttle_strafe * 0.7 + _throttle_retro * 0.8, 0.0, 1.0)
		if _bio_boost: total_throttle = 1.30

		if total_throttle > 0.01:
			var white_noise: float = randf_range(-1.0, 1.0)
			_engine_brown_noise = (_engine_brown_noise + (0.04 * white_noise)) / 1.04
			var cutoff: float = lerpf(160.0, 920.0, minf(1.0, total_throttle))
			var rc: float = 1.0 / (TWO_PI * cutoff)
			var alpha: float = dt / (rc + dt)
			_engine_lpf_state += alpha * (_engine_brown_noise - _engine_lpf_state)

			_engine_rumble_phase += TWO_PI * _apply_drift(42.0 + total_throttle * 55.0) * dt
			_engine_lfo_phase += TWO_PI * 4.2 * dt
			if _engine_rumble_phase > TWO_PI: _engine_rumble_phase -= TWO_PI
			if _engine_lfo_phase > TWO_PI: _engine_lfo_phase -= TWO_PI

			var pulse_mod: float = 1.0 + 0.25 * sin(_engine_lfo_phase)
			# Sawtooth rumble for richer engine tone (instead of pure sine)
			var siphon_val: float = (_engine_lpf_state * 1.4 + _wt_saw(_engine_rumble_phase / TWO_PI) * 0.18) * pulse_mod * total_throttle * 0.30
			left += siphon_val
			right += siphon_val

		# ----------------------------------------------------------------------
		# LAYER 4: ALCUBIERRE WAVE ENGINE (WARP FIELD RESONANCE)
		# Now uses sawtooth + noise for richer warp sound
		# ----------------------------------------------------------------------
		if _wave_state == 1: # CHARGING
			_wave_time += dt
			var t_norm: float = clampf(_wave_time / 2.0, 0.0, 1.0)
			var f_whine: float = 220.0 * exp(t_norm * 2.5)
			_wave_shepard_phase1 += TWO_PI * _apply_drift(f_whine) * dt
			_wave_shepard_phase2 += TWO_PI * _apply_drift(f_whine * 1.5) * dt
			if _wave_shepard_phase1 > TWO_PI: _wave_shepard_phase1 -= TWO_PI
			if _wave_shepard_phase2 > TWO_PI: _wave_shepard_phase2 -= TWO_PI
			# Sawtooth for Shepard tone richness
			var whine_val: float = (_wt_saw(_wave_shepard_phase1 / TWO_PI) * 0.14 + _wt_sine(_wave_shepard_phase2 / TWO_PI) * 0.07) * t_norm
			left += whine_val
			right += whine_val

		elif _wave_state == 2: # ENGAGED
			_wave_cruise_phase += TWO_PI * _apply_drift(58.0) * dt
			if _wave_cruise_phase > TWO_PI: _wave_cruise_phase -= TWO_PI
			# Triangle for smooth cruise resonance
			var warp_val: float = _wt_triangle(_wave_cruise_phase / TWO_PI) * 0.20
			left += warp_val
			right += warp_val

		# Hyperspace Transit Tunnel
		if _hyper_tunnel_active:
			_hyper_tunnel_time += dt
			_hyper_tunnel_phase += TWO_PI * _apply_drift(56.0) * dt
			_hyper_tunnel_lfo_phase += TWO_PI * 0.45 * dt
			if _hyper_tunnel_phase > TWO_PI: _hyper_tunnel_phase -= TWO_PI
			if _hyper_tunnel_lfo_phase > TWO_PI: _hyper_tunnel_lfo_phase -= TWO_PI

			var particle_noise: float = randf_range(-1.0, 1.0)
			_hyper_tunnel_noise_state += 0.08 * (particle_noise - _hyper_tunnel_noise_state)

			var tunnel_mod: float = 1.0 + 0.35 * sin(_hyper_tunnel_lfo_phase)
			# Sawtooth tunnel tone + filtered noise wind
			var tunnel_val: float = (_wt_saw(_hyper_tunnel_phase / TWO_PI) * 0.22 + _hyper_tunnel_noise_state * 0.16) * tunnel_mod
			left += tunnel_val
			right += tunnel_val

		if _wave_sub_boom_active:
			_wave_sub_boom_time += dt
			var boom_env: float = exp(-_wave_sub_boom_time * 5.0)
			var boom_freq: float = 62.0 * exp(-_wave_sub_boom_time * 5.5) + 20.0
			var boom_phase: float = fmod(boom_freq * _wave_sub_boom_time, 1.0)
			# Triangle for smoother boom
			var boom_val: float = _wt_triangle(boom_phase) * boom_env * 0.48
			left += boom_val
			right += boom_val
			if _wave_sub_boom_time > 0.7:
				_wave_sub_boom_active = false

		# ----------------------------------------------------------------------
		# LAYER 5: TACTICAL WEAPONS & COMBAT SFX
		# Now uses sawtooth carrier for grittier weapon sound
		# ----------------------------------------------------------------------
		if _laser_active:
			_laser_time += dt
			var t_laser: float = _laser_time
			var mod_freq: float = 140.0 * exp(-t_laser * 20.0) + 30.0
			_laser_mod_phase += TWO_PI * mod_freq * dt
			if _laser_mod_phase > TWO_PI: _laser_mod_phase -= TWO_PI

			var car_freq: float = 1600.0 * exp(-t_laser * 24.0) + 120.0
			var mod_idx: float = 3.5 * exp(-t_laser * 16.0)
			_laser_carrier_phase += TWO_PI * car_freq * dt + mod_idx * sin(_laser_mod_phase)
			if _laser_carrier_phase > TWO_PI: _laser_carrier_phase -= TWO_PI

			var laser_env: float = exp(-t_laser * 14.0)
			# Sawtooth carrier for aggressive plasma discharge
			var laser_val: float = _wt_saw(_laser_carrier_phase / TWO_PI) * laser_env * 0.36

			left += laser_val * (1.0 - maxf(0.0, _laser_pan))
			right += laser_val * (1.0 + minf(0.0, _laser_pan))

			if _laser_time > 0.30:
				_laser_active = false

		# Conical Lock-On Telemetry Beeps
		if _lock_on_stage > 0:
			_lock_on_timer += dt
			var lock_pitch: float = 920.0
			var is_sounding: bool = false

			if _lock_on_stage == 1:
				lock_pitch = 800.0
				is_sounding = fmod(_lock_on_timer, 0.38) < 0.07
			elif _lock_on_stage == 2:
				lock_pitch = 1200.0
				is_sounding = fmod(_lock_on_timer, 0.15) < 0.05
			elif _lock_on_stage == 3:
				lock_pitch = 1600.0
				is_sounding = true

			if is_sounding:
				_lock_on_phase += TWO_PI * _apply_drift(lock_pitch) * dt
				if _lock_on_phase > TWO_PI: _lock_on_phase -= TWO_PI
				var lock_val: float = _wt_sine(_lock_on_phase / TWO_PI) * 0.10
				left += lock_val
				right += lock_val

		# Crystalline Bio-Shield Membrane Impact
		if _shield_impact_active:
			_shield_impact_time += dt
			var shield_env: float = exp(-_shield_impact_time * 18.0)
			var shield_freq: float = 180.0 * exp(-_shield_impact_time * 26.0) + 50.0
			var shield_phase: float = fmod(shield_freq * _shield_impact_time, 1.0)
			var shield_phase2: float = fmod(shield_freq * 2.5 * _shield_impact_time, 1.0)
			# Triangle + sine harmonics for crystalline membrane
			var shield_val: float = (_wt_triangle(shield_phase) + 0.3 * _wt_sine(shield_phase2)) * shield_env * 0.40
			left += shield_val
			right += shield_val
			if _shield_impact_time > 0.32:
				_shield_impact_active = false

		# ----------------------------------------------------------------------
		# LAYER 6: MAJESTIC OCEANIC VOCALIEN FORMANT ENGINE
		# Now uses wavetable for glottal source (richer than raw sine)
		# ----------------------------------------------------------------------
		if _creature_vocal_active:
			_creature_vocal_time += dt
			var voc_t: float = _creature_vocal_time
			var exertion_mod: float = 1.0 + _exertion_level * 0.12 * sin(TWO_PI * 5.5 * voc_t)
			var glottal_freq: float = _creature_vocal_pitch * (1.0 + 0.08 * sin(TWO_PI * 4.5 * voc_t)) * exertion_mod
			_creature_glottal_phase += TWO_PI * _apply_drift(glottal_freq) * dt
			if _creature_glottal_phase > TWO_PI: _creature_glottal_phase -= TWO_PI

			# Sawtooth glottal source (richer harmonics for formant filtering)
			var glottal: float = _wt_saw(_creature_glottal_phase / TWO_PI)
			var f1_val: float = _wt_sine(fmod(_creature_formant_f1 * voc_t, 1.0)) * 0.55
			var f2_val: float = _wt_sine(fmod(_creature_formant_f2 * voc_t, 1.0)) * 0.30
			var f3_val: float = _wt_sine(fmod(_creature_formant_f3 * voc_t, 1.0)) * 0.15
			var voc_env: float = sin(clampf(voc_t / 0.70, 0.0, 1.0) * PI) * exp(-voc_t * 1.5)
			var creature_val: float = glottal * (f1_val + f2_val + f3_val) * voc_env * 0.32
			left += creature_val
			right += creature_val
			if _creature_vocal_time > 0.90:
				_creature_vocal_active = false

		# ----------------------------------------------------------------------
		# LAYER 7: FRUTIGER AERO GLASS UI MICRO-TRANSIENTS
		# Now uses wavetable sine for consistency
		# ----------------------------------------------------------------------
		if _ui_chirp_active:
			_ui_chirp_time += dt
			var ui_t: float = clampf(_ui_chirp_time / _ui_chirp_duration, 0.0, 1.0)
			var ui_freq: float = lerpf(_ui_chirp_freq_start, _ui_chirp_freq_end, ui_t)
			_ui_chirp_phase += TWO_PI * _apply_drift(ui_freq) * dt
			if _ui_chirp_phase > TWO_PI: _ui_chirp_phase -= TWO_PI
			var ui_env: float = sin(ui_t * PI)
			# Add a second harmonic for glassy richness
			var ui_val: float = (_wt_sine(_ui_chirp_phase / TWO_PI) + 0.3 * _wt_sine(fmod(_ui_chirp_phase * 2.0 / TWO_PI, 1.0))) * ui_env * 0.18
			left += ui_val
			right += ui_val
			if _ui_chirp_time >= _ui_chirp_duration:
				_ui_chirp_active = false

		# ----------------------------------------------------------------------
		# LAYER 8: TINNITUS / TRAUMA RINGING
		# ----------------------------------------------------------------------
		var tinnitus_val: float = _render_tinnitus()
		if tinnitus_val != 0.0:
			left += tinnitus_val
			right += tinnitus_val

		# ----------------------------------------------------------------------
		# LAYER 9: SYSTEM SOUNDSCAPE (star-type ambient + environment events)
		# ----------------------------------------------------------------------
		# Star radiation hum (sawtooth for harmonic richness)
		if _star_radiation_amp > 0.001:
			var rad_val: float = _wt_saw(_star_radiation_phase / TWO_PI) * _star_radiation_amp
			# Shimmer modulation for hot stars
			if _star_shimmer_amp > 0.001:
				rad_val *= 1.0 + sin(_star_shimmer_phase) * _star_shimmer_amp
			left += rad_val * 0.7
			right += rad_val * 1.3  # stereo spread

		# Star gravity drone (triangle for smooth deep tone)
		if _star_gravity_drone_amp > 0.001:
			var grav_val: float = _wt_triangle(_star_gravity_phase / TWO_PI) * _star_gravity_drone_amp
			# Black hole time-dilation: pitch bends downward periodically
			if _black_hole_time_dilation > 0.001:
				var bend: float = sin(_black_hole_drone_phase) * _black_hole_time_dilation
				grav_val *= 1.0 - bend * 0.5  # amplitude modulates with dilation
			left += grav_val
			right += grav_val

		# Pulsar pulse (neutron star — rhythmic beep)
		if _pulsar_pulse_active:
			var pulse_env: float = exp(-_pulsar_pulse_phase * 30.0)
			var pulse_val: float = _wt_sine(fmod(_pulsar_pulse_phase * 1200.0, 1.0)) * pulse_env * 0.06
			left += pulse_val * 0.8
			right += pulse_val * 1.2

		# Planet proximity ambience
		if _planet_ambient_amp > 0.001:
			var planet_val: float = 0.0
			match _current_planet_type:
				PlanetType.MOLTEN:
					# Volcanic rumble — low freq triangle + crackle
					planet_val = _wt_triangle(_planet_ambient_phase / TWO_PI) * 0.7
					planet_val += randf_range(-0.3, 0.3) * exp(-randf() * 10.0) * 0.3
				PlanetType.METALLIC_BARREN:
					# Metallic resonance — sine at resonant freq with slow decay
					planet_val = _wt_sine(_planet_ambient_phase / TWO_PI) * 0.6
				PlanetType.DESERT_ARID:
					# Sand wind — filtered noise
					planet_val = _planet_wind_state * 0.8
				PlanetType.TERRAN_OCEANIC:
					# Ocean waves — low rumble + gentle wind
					planet_val = _wt_triangle(_planet_ambient_phase / TWO_PI) * 0.5
					planet_val += _planet_wind_state * 0.3
				PlanetType.ICE_WORLD:
					# Crystal chimes — high freq sine with slow envelope
					planet_val = _wt_sine(_planet_ambient_phase / TWO_PI) * 0.4
					planet_val += _wt_sine(fmod(_planet_ambient_phase * 2.0 / TWO_PI, 1.0)) * 0.2
				PlanetType.GAS_GIANT_JOVIAN:
					# Massive storm — deep turbulence
					planet_val = _wt_triangle(_planet_ambient_phase / TWO_PI) * 0.8
					planet_val += _planet_wind_state * 0.5
				PlanetType.GAS_GIANT_ICE:
					# Methane wind — higher pitched
					planet_val = _planet_wind_state * 0.7
					planet_val += _wt_sine(_planet_ambient_phase / TWO_PI) * 0.3
				PlanetType.RADIOTROPHIC_BIO:
					# Bioluminescent organic pulse — pulsing sine
					var bio_pulse: float = 0.5 + 0.5 * sin(_planet_ambient_phase * 0.3)
					planet_val = _wt_sine(_planet_ambient_phase / TWO_PI) * bio_pulse * 0.6
				_:
					planet_val = 0.0
			planet_val *= _planet_ambient_amp
			left += planet_val * 0.85
			right += planet_val * 1.15

		# Environment event layers
		if _env_event_intensity > 0.001:
			var env_val: float = 0.0
			# Detect event change — reset all DSP state for the new event
			if _prev_env_event != _current_env_event:
				_prev_env_event = _current_env_event
				# ANOMALY reset
				for ai in range(_anom_phases.size()):
					_anom_phases[ai] = 0.0
				_anom_bp_lo = 0.0
				_anom_bp_hi = 0.0
				_anom_lfo_phase = 0.0
				_anom_ring_phase = 0.0
				_anom_pitch_drift = 0.0
				# DISCOVERY reset
				_disc_timer = 0.0
				_disc_step = 0
				_disc_note_env = 0.0
				_disc_carrier_phase = 0.0
				_disc_mod_phase = 0.0
				_disc_carrier_freq = 0.0
				_disc_mod_freq = 0.0
				_disc_pad_phase = 0.0
				# DOCKING reset
				_dock_clunk_timer = 0.0
				_dock_clunk_env = 0.0
				_dock_clunk_filter = 0.0
				_dock_metal_state = 0.0
				_dock_hum_phase = 0.0
				# DERELICT reset
				_derelict_drone_phase = 0.0
				_derelict_creak_timer = 0.0
				_derelict_creak_active = false
				_derelict_creak_age = 0.0
				_derelict_creak_filter = 0.0
				_derelict_hiss_state = 0.0
				# DISTRESS_SIGNAL reset
				_distress_morse_timer = 0.0
				_distress_morse_idx = 0
				_distress_beacon_phase = 0.0
				_distress_beacon_env = 0.0
				_distress_static_state = 0.0
				# COMBAT_AMBUSH reset
				_ambush_triggered = false
				_ambush_env = 0.0
				_ambush_impact_phase = 0.0
				_ambush_noise_filter = 0.0
				# SOLAR_FLARE reset
				_flare_env_phase = 0.0
				_flare_crackle = 0.0
				_flare_hiss_state = 0.0
				_flare_rumble_state = 0.0
				_flare_shimmer_phase = 0.0
				_flare_sub_phase = 0.0
				# GRAVITATIONAL_WAVE reset
				_grav_lfo_phase = 0.0
				_grav_doppler_phase = 0.0
				_grav_doppler_rate = 0.0
				_grav_sub_phase = 0.0
				_grav_stereo_phase = 0.0
				# Legacy event state reset (NEBULA / ASTEROID_FIELD / SUPERNOVA_REMNANT / MOLECULAR_CLOUD)
				_nebula_filter_state = 0.0
				_nebula_lfo = 0.0
				_asteroid_ping_phase = 0.0
				_asteroid_ping_timer = 0.0
				_supernova_crackle_state = 0.0
				# ANOMALY detune cache reset — force recompute on first sample
				_anom_detune_counter = 99
				# One-shot triggers and immediate note starts
				if _current_env_event == EnvironmentEvent.COMBAT_AMBUSH:
					_ambush_triggered = true
					_ambush_env = 1.0
				if _current_env_event == EnvironmentEvent.DISCOVERY:
					_disc_timer = 0.18  # trigger first arpeggio note immediately
				if _current_env_event == EnvironmentEvent.DOCKING:
					_dock_clunk_timer = 0.45  # trigger first clunk immediately
			match _current_env_event:
				EnvironmentEvent.NEBULA:
					# Diffuse, filtered, swirling — lowpass the noise bed
					var neb_noise: float = randf_range(-1.0, 1.0)
					_nebula_filter_state += (neb_noise - _nebula_filter_state) * (300.0 * _sample_step * 2.0)
					env_val = _nebula_filter_state * sin(_nebula_lfo) * 0.08
				EnvironmentEvent.ASTEROID_FIELD:
					# Proximity pings — sonar-like beeps
					var ping_env: float = exp(-_asteroid_ping_phase * 8.0)
					env_val = _wt_sine(fmod(_asteroid_ping_phase * 800.0, 1.0)) * ping_env * 0.05
				EnvironmentEvent.BLACK_HOLE_PROX:
					# Extreme gravitational drone — very deep, modulating
					env_val = _wt_triangle(fmod(_black_hole_drone_phase * 0.5, 1.0)) * 0.10
				EnvironmentEvent.SUPERNOVA_REMNANT:
					# Radioactive crackle — random spikes
					_supernova_crackle_state = lerpf(_supernova_crackle_state, randf_range(-1.0, 1.0), 0.3)
					env_val = _supernova_crackle_state * 0.04
				EnvironmentEvent.MOLECULAR_CLOUD:
					# Dense, muffled, deep — very low filtered noise
					var cloud_noise: float = randf_range(-1.0, 1.0)
					_nebula_filter_state += (cloud_noise - _nebula_filter_state) * (80.0 * _sample_step * 2.0)
					env_val = _nebula_filter_state * 0.06
				# --- Fully implemented AAA+ environment events ---
				EnvironmentEvent.ANOMALY:
					# 7-oscillator detuned cluster with morphing bandpass, ring mod, microtonal drift
					_anom_lfo_phase += TWO_PI * 0.07 * dt
					if _anom_lfo_phase > TWO_PI: _anom_lfo_phase -= TWO_PI
					_anom_pitch_drift = sin(_anom_lfo_phase) * 0.015
					var anom_sum: float = 0.0
					var anom_base_freq: float = 220.0
					# Recompute detune factors every 100 samples (LFO is 0.07 Hz — changes negligibly per sample)
					_anom_detune_counter += 1
					if _anom_detune_counter >= 100:
						_anom_detune_counter = 0
						var anom_detune_mod: float = 1.0 + sin(_anom_lfo_phase * 0.7) * 0.2
						for ai in range(7):
							_anom_detune_factors[ai] = pow(2.0, (float(ai) - 3.0) * 0.06 * anom_detune_mod / 1200.0)
					for ai in range(7):
						var anom_freq: float = anom_base_freq * _anom_detune_factors[ai] * (1.0 + _anom_pitch_drift)
						_anom_phases[ai] = fmod(_anom_phases[ai] + anom_freq * dt, 1.0)
						anom_sum += _wt_sine(_anom_phases[ai])
					anom_sum /= 7.0
					# Morphing bandpass (difference of two lowpasses with shifting cutoffs)
					var anom_bp_lo_coef: float = (400.0 + 300.0 * sin(_anom_lfo_phase * 0.5)) * dt * 2.0
					var anom_bp_hi_coef: float = (1600.0 + 800.0 * sin(_anom_lfo_phase * 0.3)) * dt * 2.0
					_anom_bp_lo += (anom_sum - _anom_bp_lo) * anom_bp_lo_coef
					_anom_bp_hi += (anom_sum - _anom_bp_hi) * anom_bp_hi_coef
					var anom_bp: float = _anom_bp_hi - _anom_bp_lo
					# Ring modulation with low-frequency carrier
					_anom_ring_phase += TWO_PI * 80.0 * dt
					if _anom_ring_phase > TWO_PI: _anom_ring_phase -= TWO_PI
					var anom_ring: float = _wt_sine(_anom_ring_phase / TWO_PI) * anom_bp * 0.3
					env_val = anom_bp * 0.05 + anom_ring * 0.03
				EnvironmentEvent.DISCOVERY:
					# Rising FM bell arpeggio with reverb-like decay + gentle pad layer
					_disc_timer += dt
					var disc_note_dur: float = 0.18
					if _disc_timer >= disc_note_dur:
						_disc_timer -= disc_note_dur
						_disc_step += 1
						_disc_note_env = 1.0
						var disc_scale: Array[int] = _get_active_scale()
						var disc_pc: int = disc_scale[_disc_step % disc_scale.size()]
						var disc_octave: int = 4 + int(_disc_step / float(disc_scale.size())) % 3
						var disc_midi: int = 50 + disc_pc + disc_octave * 12
						_disc_carrier_freq = 440.0 * pow(2.0, (float(disc_midi) - 69.0) / 12.0)
						_disc_mod_freq = _disc_carrier_freq * 3.0
					# Reverb-like per-note exponential decay envelope
					_disc_note_env *= exp(-dt * 4.0)
					if _disc_note_env < 0.001:
						_disc_note_env = 0.0
					# FM bell synthesis: sine carrier + triangle modulator
					_disc_carrier_phase += TWO_PI * _disc_carrier_freq * dt
					if _disc_carrier_phase > TWO_PI: _disc_carrier_phase -= TWO_PI
					_disc_mod_phase += TWO_PI * _disc_mod_freq * dt
					if _disc_mod_phase > TWO_PI: _disc_mod_phase -= TWO_PI
					var disc_mod_sig: float = _wt_triangle(_disc_mod_phase / TWO_PI) * 2.5
					var disc_fm_phase: float = fmod(_disc_carrier_phase / TWO_PI + disc_mod_sig, 1.0)
					if disc_fm_phase < 0.0: disc_fm_phase += 1.0
					var disc_bell: float = _wt_sine(disc_fm_phase) * _disc_note_env * 0.06
					# Gentle pad layer underneath
					_disc_pad_phase += TWO_PI * 110.0 * dt
					if _disc_pad_phase > TWO_PI: _disc_pad_phase -= TWO_PI
					var disc_pad: float = _wt_triangle(_disc_pad_phase / TWO_PI) * 0.02
					env_val = disc_bell + disc_pad
				EnvironmentEvent.DOCKING:
					# Rhythmic mechanical clunks + proximity hum + metallic resonance
					_dock_clunk_timer += dt
					var dock_clunk_period: float = 0.45
					if _dock_clunk_timer >= dock_clunk_period:
						_dock_clunk_timer -= dock_clunk_period
						_dock_clunk_env = 1.0
					# Fast exponential decay envelope for clunk impact
					_dock_clunk_env *= exp(-dt * 15.0)
					if _dock_clunk_env < 0.001:
						_dock_clunk_env = 0.0
					# Filtered noise burst (mechanical clunk body)
					var dock_noise: float = randf_range(-1.0, 1.0)
					_dock_clunk_filter += (dock_noise - _dock_clunk_filter) * (300.0 * dt * 2.0)
					var dock_clunk: float = _dock_clunk_filter * _dock_clunk_env * 0.06
					# Metallic resonance (high-passed ringing at metallic frequency)
					_dock_metal_state += (dock_clunk - _dock_metal_state) * (1800.0 * dt * 2.0)
					var dock_metal: float = (_dock_clunk_filter - _dock_metal_state) * _dock_clunk_env * 0.03
					# Proximity-based low-frequency hum (intensifies with event intensity)
					_dock_hum_phase += TWO_PI * 55.0 * dt
					if _dock_hum_phase > TWO_PI: _dock_hum_phase -= TWO_PI
					var dock_hum: float = _wt_sine(_dock_hum_phase / TWO_PI) * 0.03 * _env_event_intensity
					env_val = dock_clunk + dock_metal + dock_hum
				EnvironmentEvent.DERELICT:
					# Cold drone (sine + triangle) + random metallic creaks + air leak hiss
					_derelict_drone_phase += TWO_PI * 42.0 * dt
					if _derelict_drone_phase > TWO_PI: _derelict_drone_phase -= TWO_PI
					var derel_drone: float = (_wt_sine(_derelict_drone_phase / TWO_PI) * 0.5 +
							_wt_triangle(fmod(_derelict_drone_phase * 1.5 / TWO_PI, 1.0)) * 0.3) * 0.04
					# Random metallic creaks with slow attack/decay envelope
					var derel_creak: float = 0.0
					_derelict_creak_timer += dt
					if not _derelict_creak_active and _derelict_creak_timer > 2.0:
						if randf() < 0.02:
							_derelict_creak_active = true
							_derelict_creak_age = 0.0
							_derelict_creak_timer = 0.0
					if _derelict_creak_active:
						_derelict_creak_age += dt
						var creak_progress: float = clampf(_derelict_creak_age / 2.5, 0.0, 1.0)
						var creak_env: float = sin(creak_progress * PI) * exp(-_derelict_creak_age * 0.3)
						if creak_env < 0.001:
							_derelict_creak_active = false
						var creak_noise: float = randf_range(-1.0, 1.0)
						_derelict_creak_filter += (creak_noise - _derelict_creak_filter) * (1200.0 * dt * 2.0)
						derel_creak = _derelict_creak_filter * creak_env * 0.04
					# Air leak hiss (high-frequency filtered noise)
					var hiss_noise: float = randf_range(-1.0, 1.0)
					_derelict_hiss_state += (hiss_noise - _derelict_hiss_state) * (5000.0 * dt * 2.0)
					var derel_hiss: float = (hiss_noise - _derelict_hiss_state) * 0.02
					env_val = derel_drone + derel_creak + derel_hiss
				EnvironmentEvent.DISTRESS_SIGNAL:
					# Morse SOS beacon (...---...) with pulsing sine + background static
					_distress_morse_timer += dt
					var morse_cur_dur: float = absf(_morse_sos[_distress_morse_idx] * _morse_unit)
					if _distress_morse_timer >= morse_cur_dur:
						_distress_morse_timer = 0.0
						_distress_morse_idx = (_distress_morse_idx + 1) % _morse_sos.size()
						morse_cur_dur = absf(_morse_sos[_distress_morse_idx] * _morse_unit)
					# Beacon envelope: ON for dit/dah (positive), OFF for gaps (negative)
					var morse_on: float = 0.0
					if _morse_sos[_distress_morse_idx] > 0.0:
						var morse_edge: float = minf(_distress_morse_timer * 40.0, (morse_cur_dur - _distress_morse_timer) * 40.0)
						morse_on = clampf(morse_edge, 0.0, 1.0)
					_distress_beacon_env = morse_on
					# Pulsing sine beacon at mid-range frequency (121.5 MHz analogue)
					_distress_beacon_phase += TWO_PI * 880.0 * dt
					if _distress_beacon_phase > TWO_PI: _distress_beacon_phase -= TWO_PI
					var beacon: float = _wt_sine(_distress_beacon_phase / TWO_PI) * _distress_beacon_env * 0.06
					# Background static noise
					var static_noise: float = randf_range(-1.0, 1.0)
					_distress_static_state += (static_noise - _distress_static_state) * (3000.0 * dt * 2.0)
					var beacon_static: float = (static_noise - _distress_static_state) * 0.02
					env_val = beacon + beacon_static
				EnvironmentEvent.COMBAT_AMBUSH:
					# One-shot tension spike: filtered noise burst + low-freq impact boom
					if _ambush_triggered:
						_ambush_env *= exp(-dt * 5.0)
						if _ambush_env < 0.001:
							_ambush_env = 0.0
							_ambush_triggered = false
					# Filtered noise burst with fast attack and exponential decay
					var ambush_noise: float = randf_range(-1.0, 1.0)
					_ambush_noise_filter += (ambush_noise - _ambush_noise_filter) * (800.0 * dt * 2.0)
					var ambush_burst: float = _ambush_noise_filter * _ambush_env * 0.07
					# Subtle sustained tension layer after initial spike
					var ambush_sustain: float = _ambush_noise_filter * 0.015
					# Low-frequency impact boom (sine sweep 200Hz -> 50Hz)
					if _ambush_env > 0.001:
						var ambush_sweep_freq: float = lerpf(200.0, 50.0, 1.0 - _ambush_env)
						_ambush_impact_phase += TWO_PI * ambush_sweep_freq * dt
						if _ambush_impact_phase > TWO_PI: _ambush_impact_phase -= TWO_PI
					var ambush_boom: float = _wt_sine(_ambush_impact_phase / TWO_PI) * _ambush_env * 0.08
					env_val = ambush_burst + ambush_sustain + ambush_boom
				EnvironmentEvent.SOLAR_FLARE:
					# Multi-band noise (crackle + hiss + rumble) + shimmer + sub-bass pressure
					# Flare envelope with build/decay (half-wave rectified slow LFO)
					_flare_env_phase += TWO_PI * 0.08 * dt
					if _flare_env_phase > TWO_PI: _flare_env_phase -= TWO_PI
					var flare_amp: float = maxf(0.0, sin(_flare_env_phase))
					# High crackle (random spikes with fast interpolation)
					var flare_crackle_noise: float = randf_range(-1.0, 1.0)
					_flare_crackle = lerpf(_flare_crackle, flare_crackle_noise, 0.5)
					var flare_crackle_val: float = _flare_crackle * flare_amp * 0.04
					# Mid hiss (bandpass-filtered noise)
					var flare_hiss_noise: float = randf_range(-1.0, 1.0)
					_flare_hiss_state += (flare_hiss_noise - _flare_hiss_state) * (4000.0 * dt * 2.0)
					var flare_hiss_val: float = (flare_hiss_noise - _flare_hiss_state) * flare_amp * 0.03
					# Sub rumble (lowpass-filtered noise)
					var flare_rumble_noise: float = randf_range(-1.0, 1.0)
					_flare_rumble_state += (flare_rumble_noise - _flare_rumble_state) * (60.0 * dt * 2.0)
					var flare_rumble_val: float = _flare_rumble_state * flare_amp * 0.05
					# Sub-bass pressure wave
					_flare_sub_phase += TWO_PI * 35.0 * dt
					if _flare_sub_phase > TWO_PI: _flare_sub_phase -= TWO_PI
					var flare_sub_val: float = _wt_sine(_flare_sub_phase / TWO_PI) * flare_amp * 0.04
					# High-frequency shimmer (builds and decays with flare)
					_flare_shimmer_phase += TWO_PI * 5500.0 * dt
					if _flare_shimmer_phase > TWO_PI: _flare_shimmer_phase -= TWO_PI
					var flare_shimmer_val: float = _wt_sine(_flare_shimmer_phase / TWO_PI) * flare_amp * 0.02
					env_val = flare_crackle_val + flare_hiss_val + flare_rumble_val + flare_sub_val + flare_shimmer_val
				EnvironmentEvent.GRAVITATIONAL_WAVE:
					# Slow AM with doppler pitch shift + deep sub-bass + stereo phase offset
					# Ripple LFO (slow amplitude modulation ~20s cycle)
					_grav_lfo_phase += TWO_PI * 0.05 * dt
					if _grav_lfo_phase > TWO_PI: _grav_lfo_phase -= TWO_PI
					var grav_am: float = 0.5 + 0.5 * sin(_grav_lfo_phase)
					# Doppler-like pitch shifting (phase accumulator speeds up/slows down)
					_grav_doppler_rate = 220.0 * (1.0 + 0.3 * sin(_grav_lfo_phase * 0.7))
					_grav_doppler_phase += TWO_PI * _grav_doppler_rate * dt
					if _grav_doppler_phase > TWO_PI: _grav_doppler_phase -= TWO_PI
					var grav_doppler_val: float = _wt_sine(_grav_doppler_phase / TWO_PI) * grav_am * 0.04
					# Deep sub-bass wave
					_grav_sub_phase += TWO_PI * 28.0 * dt
					if _grav_sub_phase > TWO_PI: _grav_sub_phase -= TWO_PI
					var grav_sub_val: float = _wt_triangle(_grav_sub_phase / TWO_PI) * 0.04
					# Stereo phase offset — applied directly to L/R channels after env_val split (true stereo)
					_grav_stereo_phase += TWO_PI * 110.0 * dt
					if _grav_stereo_phase > TWO_PI: _grav_stereo_phase -= TWO_PI
					env_val = grav_doppler_val + grav_sub_val
				_:
					env_val = 0.0
			env_val *= _env_event_intensity
			left += env_val * 0.9
			right += env_val * 1.1
			# True stereo phase offset for GRAVITATIONAL_WAVE spatial effect
			if _current_env_event == EnvironmentEvent.GRAVITATIONAL_WAVE:
				var stereo_intensity: float = _env_event_intensity * 0.04
				left += _wt_sine(fmod(_grav_stereo_phase / TWO_PI, 1.0)) * stereo_intensity * 0.9
				right += _wt_sine(fmod((_grav_stereo_phase + PI * 0.5) / TWO_PI, 1.0)) * stereo_intensity * 1.1

		# ----------------------------------------------------------------------
		# OUTPUT PROCESSING: SIDESHAIN → TRIODE → LIMITER
		# ----------------------------------------------------------------------
		left = _apply_sidechain(left)
		right = _apply_sidechain(right)

		if enable_triode_warmth:
			left = _triode_warmth(left)
			right = _triode_warmth(right)
		# Transparent soft-limiter
		left = tanh(left * 0.92)
		right = tanh(right * 0.92)

		buffer[i] = Vector2(left, right)

	playback.push_buffer(buffer)

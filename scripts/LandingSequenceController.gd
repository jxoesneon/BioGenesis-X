# ==============================================================================
# LandingSequenceController.gd
# BioGenesis-X: Planet Landing / Takeoff Animation & Ship-Foot Transition
# ==============================================================================
# Orchestrates the cinematic and gameplay transitions between ship flight and
# on-foot planet surface exploration. Driven by PlanetDescentController state
# changes (LANDED / ON_FOOT) and player input (F to exit/enter ship, thrust to
# take off).
#
# This controller is self-contained: it degrades gracefully if the ship,
# character, or camera nodes are missing, and it never calls BioAudioDirector
# directly (it emits `audio_event` signals that the audio director may listen
# to, keeping the systems decoupled).
#
# Landing sequence (triggered on LANDED):
#   ALIGN -> DESCEND -> TOUCHDOWN -> SETTLE -> READY -> (EXITING on F press)
# Takeoff sequence (triggered on thrust-up from LANDED):
#   IGNITE -> LIFT -> ASCEND -> CLEAR
# ==============================================================================
extends Node

# ------------------------------------------------------------------------------
# State Machines
# ------------------------------------------------------------------------------
enum LandingPhase {
	IDLE,      ## No landing sequence active
	ALIGN,     ## Ship rotates to align with surface normal
	DESCEND,   ## Ship lowers to the surface, gear/anchor extends
	TOUCHDOWN, ## Impact effect, dust, screen shake, audio thud
	SETTLE,    ## Ship powers down, engine glow fades, ambient shift
	READY,     ## "Press F to exit ship" prompt shown
	EXITING,   ## Player exiting ship to on-foot
}

enum TakeoffPhase {
	IDLE,    ## No takeoff sequence active
	IGNITE,  ## Engines spool up, glow intensifies, dust blows outward
	LIFT,    ## Ship rises vertically, landing gear retracts
	ASCEND,  ## Ship pitches up and begins forward thrust
	CLEAR,   ## Transition to atmospheric flight, audio shifts
}

# ------------------------------------------------------------------------------
# Signals
# ------------------------------------------------------------------------------
signal landing_phase_changed(phase: int, phase_name: String)
signal landing_complete()
signal exit_complete()
signal entry_complete()
signal takeoff_phase_changed(phase: int, phase_name: String)
signal takeoff_complete()
signal prompt_show(text: String)
signal prompt_hide()
signal audio_event(event_name: String)

# Staged-cinematics ready signals: emitted when a subsystem confirms the
# corresponding landing phase can advance. The controller holds at each phase
# until the matching signal fires (or the timeout fallback triggers).
signal align_phase_ready()
signal descend_phase_ready()
signal touchdown_phase_ready()
signal settle_phase_ready()

# ------------------------------------------------------------------------------
# Exported Tunables
# ------------------------------------------------------------------------------
@export_group("Landing Durations")
@export var landing_align_duration: float = 2.0
@export var landing_descend_duration: float = 3.0
@export var landing_touchdown_duration: float = 1.0
@export var landing_settle_duration: float = 1.0

@export_group("Takeoff Durations")
@export var takeoff_ignite_duration: float = 2.0
@export var takeoff_lift_duration: float = 3.0
@export var takeoff_ascend_duration: float = 2.0

@export_group("Input")
@export var exit_key: int = KEY_F

@export_group("Effects")
@export var screen_shake_intensity: float = 0.3
@export var dust_particle_count: int = 50

@export_group("Camera Transition")
@export var camera_transition_duration: float = 1.2
@export var cockpit_camera_offset: Vector3 = Vector3(0.0, 0.65, 4.8)

@export_group("Staged Cinematics")
## Force-advance a held phase after this many seconds (last-resort fallback so
## the landing sequence never gets stuck if a subsystem fails to signal).
@export var phase_timeout_sec: float = 8.0

# ------------------------------------------------------------------------------
# Internal State - Landing
# ------------------------------------------------------------------------------
var _landing_phase: LandingPhase = LandingPhase.IDLE
var _landing_phase_timer: float = 0.0
var _landing_phase_progress: float = 0.0

# ------------------------------------------------------------------------------
# Staged Cinematics - Phase Hold State
# ------------------------------------------------------------------------------
# When _phase_hold_enabled is true, each cinematic phase holds after its
# animation completes until the corresponding subsystem signals readiness via
# notify_*_ready(). The phase_timeout_sec export is the last-resort fallback.
var _phase_ready: Dictionary = {
	LandingPhase.ALIGN: false,
	LandingPhase.DESCEND: false,
	LandingPhase.TOUCHDOWN: false,
	LandingPhase.SETTLE: false,
}
var _phase_hold_enabled: bool = true  ## Hold at each phase until ready signal
var _phase_timer: float = 0.0  ## Time accumulated in the current phase (for timeout)

var _ship: Node3D = null
var _ship_start_basis: Basis = Basis.IDENTITY
var _ship_start_position: Vector3 = Vector3.ZERO
var _ship_target_basis: Basis = Basis.IDENTITY
var _ship_target_position: Vector3 = Vector3.ZERO
var _surface_normal: Vector3 = Vector3.UP
var _surface_position: Vector3 = Vector3.ZERO

# ------------------------------------------------------------------------------
# Internal State - Takeoff
# ------------------------------------------------------------------------------
var _takeoff_phase: TakeoffPhase = TakeoffPhase.IDLE
var _takeoff_phase_timer: float = 0.0
var _takeoff_phase_progress: float = 0.0
var _takeoff_start_basis: Basis = Basis.IDENTITY
var _takeoff_pitch_target_basis: Basis = Basis.IDENTITY

# ------------------------------------------------------------------------------
# Internal State - Exit / Entry
# ------------------------------------------------------------------------------
var _is_exiting: bool = false
var _is_entering: bool = false
var _exit_entry_timer: float = 0.0
const _EXIT_ENTRY_DURATION: float = 1.2

# ------------------------------------------------------------------------------
# Cached References (resolved lazily, never crash if missing)
# ------------------------------------------------------------------------------
var _character: PlanetCharacterController = null
var _planet_camera: PlanetCamera = null
var _flight_controller: FlightController = null
var _active_camera: Camera3D = null

# ------------------------------------------------------------------------------
# Effect State
# ------------------------------------------------------------------------------
var _screen_shake_time: float = 0.0
var _screen_shake_amp: float = 0.0
var _camera_transition_time: float = 0.0
var _camera_transitioning: bool = false
var _camera_from_position: Vector3 = Vector3.ZERO
var _camera_from_basis: Basis = Basis.IDENTITY
var _camera_to_position: Vector3 = Vector3.ZERO
var _camera_to_basis: Basis = Basis.IDENTITY
var _target_camera_current: bool = true ## whether third-person or cockpit is the target

var _anchor_node: Node3D = null
var _anchor_start_scale: Vector3 = Vector3.ONE
var _anchor_extended_scale: Vector3 = Vector3.ONE
var _anchor_target_scale: Vector3 = Vector3.ONE

var _engine_glow_intensity: float = 1.0
var _engine_glow_target: float = 1.0
var _engine_materials: Array[ShaderMaterial] = []

# ------------------------------------------------------------------------------
# Phase Name Tables (for signals)
# ------------------------------------------------------------------------------
var _LANDING_PHASE_NAMES: PackedStringArray = PackedStringArray([
	"Idle", "Align", "Descend", "Touchdown", "Settle", "Ready", "Exiting",
])
var _TAKEOFF_PHASE_NAMES: PackedStringArray = PackedStringArray([
	"Idle", "Ignite", "Lift", "Ascend", "Clear",
])

# ==============================================================================
# Lifecycle
# ==============================================================================
func _ready() -> void:
	set_process(true)
	set_process_unhandled_input(true)
	# Auto-connect to the PlanetDescentController autoload so landing/takeoff
	# animations are triggered automatically. The controller is registered
	# before this autoload, so it is already in the scene tree here.
	call_deferred("_connect_descent_controller_signals")

func _process(delta: float) -> void:
	_update_landing_sequence(delta)
	_update_takeoff_sequence(delta)
	_update_exit_entry(delta)
	_update_screen_shake(delta)
	_update_camera_transition(delta)
	_update_engine_glow(delta)
	_update_anchor(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key_event: InputEventKey = event as InputEventKey
		if key_event.keycode == exit_key:
			_handle_exit_enter_input()
			get_viewport().set_input_as_handled()

# ==============================================================================
# PlanetDescentController Signal Bridge
# ==============================================================================

## Resolves the PlanetDescentController autoload and connects its
## landing_complete / takeoff_complete signals so this controller drives the
# cinematic landing and takeoff animations automatically.
func _connect_descent_controller_signals() -> void:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return
	var dc: Node = tree.root.get_node_or_null("/root/PlanetDescentController")
	if dc == null:
		return
	if not dc.is_connected("landing_complete", _on_dc_landing_complete):
		dc.landing_complete.connect(_on_dc_landing_complete)
	if not dc.is_connected("takeoff_complete", _on_dc_takeoff_complete):
		dc.takeoff_complete.connect(_on_dc_takeoff_complete)

## Handler for PlanetDescentController.landing_complete(archetype, position).
## Begins the cinematic landing animation sequence using the ship and the
## surface normal reported by the descent controller.
func _on_dc_landing_complete(_planet_archetype: int, position: Vector3) -> void:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return
	var dc: Node = tree.root.get_node_or_null("/root/PlanetDescentController")
	var normal: Vector3 = Vector3.UP
	if dc != null and dc.has_method("get_surface_normal"):
		normal = dc.get_surface_normal()
	_resolve_gameplay_references()
	var ship: Node3D = _flight_controller
	if ship != null and is_instance_valid(ship):
		start_landing_sequence(ship, position, normal)

## Handler for PlanetDescentController.takeoff_complete(). Resets the landing
## phase to IDLE and begins the cinematic takeoff animation sequence so the ship
## lifts off the surface and transitions back to atmospheric flight.
func _on_dc_takeoff_complete() -> void:
	if _landing_phase != LandingPhase.IDLE:
		_set_landing_phase(LandingPhase.IDLE)
		landing_phase_changed.emit(int(_landing_phase), _phase_name(_landing_phase))
	# Begin the cinematic takeoff animation. The ship reference is retained from
	# the landing sequence; fall back to the resolved FlightController if the
	# cached ship was cleared or became invalid.
	_resolve_gameplay_references()
	var ship: Node3D = _ship
	if (ship == null or not is_instance_valid(ship)) and _flight_controller != null and is_instance_valid(_flight_controller):
		ship = _flight_controller
	if ship != null and is_instance_valid(ship):
		start_takeoff_sequence(ship)

# ==============================================================================
# Public API - Landing Sequence
# ==============================================================================
## Begins the landing animation sequence. Called when PlanetDescentController
## enters the LANDED state. The ship is rotated to align with the surface
## normal, lowered to the surface, and powered down.
func start_landing_sequence(ship: Node3D, surface_position: Vector3, surface_normal: Vector3) -> void:
	if not is_instance_valid(ship):
		push_warning("LandingSequenceController: start_landing_sequence called with invalid ship.")
		return
	_ship = ship
	_surface_position = surface_position
	_surface_normal = surface_normal.normalized()
	_ship_start_basis = ship.global_transform.basis.orthonormalized()
	_ship_start_position = ship.global_position
	# Target orientation: ship up = surface normal, keep forward projected onto tangent.
	var current_forward: Vector3 = -_ship_start_basis.z
	var tangent_forward: Vector3 = _project_to_tangent(current_forward, _surface_normal)
	if tangent_forward.length_squared() < 1e-4:
		tangent_forward = _surface_normal.cross(Vector3.RIGHT).normalized()
		if tangent_forward.length_squared() < 1e-4:
			tangent_forward = _surface_normal.cross(Vector3.FORWARD).normalized()
	tangent_forward = tangent_forward.normalized()
	_ship_target_basis = Basis.looking_at(tangent_forward, _surface_normal)
	# Target position: resting on the surface (ship origin at surface point).
	_ship_target_position = surface_position
	# Cache effect references.
	_resolve_effect_references(ship)
	_engine_glow_target = 1.0
	_engine_glow_intensity = 1.0
	# Reset staged-cinematics ready flags so each phase holds until the
	# corresponding subsystem re-signals readiness for this new landing.
	_phase_ready[LandingPhase.ALIGN] = false
	_phase_ready[LandingPhase.DESCEND] = false
	_phase_ready[LandingPhase.TOUCHDOWN] = false
	_phase_ready[LandingPhase.SETTLE] = false
	_phase_timer = 0.0
	_set_landing_phase(LandingPhase.ALIGN)
	landing_phase_changed.emit(int(_landing_phase), _phase_name(_landing_phase))

## Begins the ship-exit sequence (player presses F after landing). Spawns the
## character at the ship exit point and transitions the camera to third-person.
func start_exit_sequence() -> void:
	if _landing_phase != LandingPhase.READY:
		return
	if not is_instance_valid(_ship):
		push_warning("LandingSequenceController: start_exit_sequence called but ship is invalid.")
		return
	_resolve_gameplay_references()
	_set_landing_phase(LandingPhase.EXITING)
	_is_exiting = true
	_exit_entry_timer = 0.0
	audio_event.emit("ship_door")
	prompt_hide.emit()
	# Begin camera transition to third-person.
	_begin_camera_transition_to_third_person()

## Begins the ship-entry sequence (player presses F near ship while on foot).
## The character returns to the ship and the camera transitions back to cockpit.
func start_entry_sequence() -> void:
	if not is_instance_valid(_ship):
		push_warning("LandingSequenceController: start_entry_sequence called but ship is invalid.")
		return
	_resolve_gameplay_references()
	_is_entering = true
	_exit_entry_timer = 0.0
	audio_event.emit("ship_door")
	# Begin camera transition to cockpit.
	_begin_camera_transition_to_cockpit()

## Begins the takeoff animation sequence. Called when the player thrusts upward
## from the LANDED state. Engines spool up, the ship lifts, gear retracts, and
## it pitches into atmospheric flight.
func start_takeoff_sequence(ship: Node3D) -> void:
	if not is_instance_valid(ship):
		push_warning("LandingSequenceController: start_takeoff_sequence called with invalid ship.")
		return
	_ship = ship
	_resolve_effect_references(ship)
	_takeoff_start_basis = ship.global_transform.basis.orthonormalized()
	# Pitch target: tilt forward (-Z down) by ~20 degrees for ascent.
	var up: Vector3 = _takeoff_start_basis.y
	var forward: Vector3 = -_takeoff_start_basis.z
	var pitch_axis: Vector3 = up.cross(forward).normalized()
	if pitch_axis.length_squared() < 1e-6:
		pitch_axis = _takeoff_start_basis.x
	var pitch_angle: float = deg_to_rad(20.0)
	_takeoff_pitch_target_basis = _takeoff_start_basis.rotated(pitch_axis.normalized(), pitch_angle).orthonormalized()
	_engine_glow_target = 2.0
	_set_takeoff_phase(TakeoffPhase.IGNITE)
	takeoff_phase_changed.emit(int(_takeoff_phase), _takeoff_phase_name(_takeoff_phase))
	# Dust burst on ignite.
	_spawn_dust_burst(ship.global_position, _takeoff_start_basis.y)
	audio_event.emit("takeoff_ignite")

# ==============================================================================
# Public API - Queries
# ==============================================================================
func get_current_landing_phase() -> LandingPhase:
	return _landing_phase

func get_current_takeoff_phase() -> TakeoffPhase:
	return _takeoff_phase

func get_landing_phase_progress() -> float:
	return _landing_phase_progress

func get_takeoff_phase_progress() -> float:
	return _takeoff_phase_progress

func is_landing_sequence_active() -> bool:
	return _landing_phase != LandingPhase.IDLE

func is_takeoff_sequence_active() -> bool:
	return _takeoff_phase != TakeoffPhase.IDLE

func is_on_foot() -> bool:
	return _is_exiting and _exit_entry_timer >= _EXIT_ENTRY_DURATION

## Resets all landing/takeoff/exit/entry state to IDLE and clears the cached
## ship reference. Safe to call at any time (idempotent). Used by
## PlanetEntryManager during surface-system cleanup so a stale animation
## phase never persists into the next descent.
func reset() -> void:
	_set_landing_phase(LandingPhase.IDLE)
	_set_takeoff_phase(TakeoffPhase.IDLE)
	_is_exiting = false
	_is_entering = false
	_exit_entry_timer = 0.0
	_landing_phase_progress = 0.0
	_takeoff_phase_progress = 0.0
	_screen_shake_time = 0.0
	_screen_shake_amp = 0.0
	_camera_transitioning = false
	_camera_transition_time = 0.0
	_engine_glow_target = 1.0
	_engine_glow_intensity = 1.0
	_anchor_target_scale = _anchor_start_scale
	_ship = null
	_character = null
	_planet_camera = null
	_flight_controller = null
	_active_camera = null
	_engine_materials.clear()
	landing_phase_changed.emit(int(_landing_phase), _phase_name(_landing_phase))
	takeoff_phase_changed.emit(int(_takeoff_phase), _takeoff_phase_name(_takeoff_phase))

# ==============================================================================
# Public API - Staged Cinematics Ready Signals
# ==============================================================================
## Called by PlanetEntryManager when the terrain generator loads its first
## chunk. Releases the ALIGN hold so the ship begins descending.
func notify_align_ready() -> void:
	_phase_ready[LandingPhase.ALIGN] = true
	align_phase_ready.emit()

## Called by PlanetEntryManager when the surface environment is built.
## Releases the DESCEND hold so the ship touches down.
func notify_descend_ready() -> void:
	_phase_ready[LandingPhase.DESCEND] = true
	descend_phase_ready.emit()

## Called by PlanetEntryManager when the atmosphere visual system is built.
## Releases the TOUCHDOWN hold so the ship settles.
func notify_touchdown_ready() -> void:
	_phase_ready[LandingPhase.TOUCHDOWN] = true
	touchdown_phase_ready.emit()

## Called by PlanetEntryManager when the character controller and camera are
## spawned. Releases the SETTLE hold so the landing sequence reaches READY.
func notify_settle_ready() -> void:
	_phase_ready[LandingPhase.SETTLE] = true
	settle_phase_ready.emit()

# ==============================================================================
# Landing Sequence Update
# ==============================================================================
func _update_landing_sequence(delta: float) -> void:
	if _landing_phase == LandingPhase.IDLE:
		return
	if not is_instance_valid(_ship):
		_abort_landing_sequence()
		return
	_landing_phase_timer += delta
	_phase_timer += delta
	var duration: float = _current_landing_phase_duration()
	if duration <= 0.0:
		_landing_phase_progress = 1.0
	else:
		_landing_phase_progress = clampf(_landing_phase_timer / duration, 0.0, 1.0)

	match _landing_phase:
		LandingPhase.ALIGN:
			_process_align(_landing_phase_progress)
		LandingPhase.DESCEND:
			_process_descend(_landing_phase_progress)
		LandingPhase.TOUCHDOWN:
			_process_touchdown(_landing_phase_progress)
		LandingPhase.SETTLE:
			_process_settle(_landing_phase_progress)
		LandingPhase.READY:
			pass # Wait for player input.
		LandingPhase.EXITING:
			pass # Handled by exit/entry update.
		_:
			push_warning("[LandingSequenceController] Unknown landing phase in _process_landing: %d" % _landing_phase)

	if _landing_phase_progress >= 1.0 and _landing_phase != LandingPhase.READY and _landing_phase != LandingPhase.EXITING:
		_advance_landing_phase()

func _process_align(progress: float) -> void:
	if not is_instance_valid(_ship):
		return
	var eased: float = _ease_in_out(progress)
	var new_basis: Basis = _slerp_basis(_ship_start_basis, _ship_target_basis, eased)
	_ship.global_transform.basis = new_basis.orthonormalized()

func _process_descend(progress: float) -> void:
	if not is_instance_valid(_ship):
		return
	var eased: float = _ease_in_out(progress)
	_ship.global_position = _ship_start_position.lerp(_ship_target_position, eased)
	_ship.global_transform.basis = _ship_target_basis.orthonormalized()
	# Extend landing gear / organic anchor.
	_anchor_target_scale = _anchor_extended_scale

func _process_touchdown(progress: float) -> void:
	if not is_instance_valid(_ship):
		return
	# Snap to final resting transform.
	_ship.global_position = _ship_target_position
	_ship.global_transform.basis = _ship_target_basis.orthonormalized()
	# One-shot effects at the start of touchdown.
	if progress <= 0.01:
		_trigger_screen_shake(screen_shake_intensity)
		_spawn_dust_burst(_ship_target_position, _surface_normal)
		audio_event.emit("landing_touchdown")

func _process_settle(progress: float) -> void:
	if not is_instance_valid(_ship):
		return
	# Fade engine glow to zero.
	_engine_glow_target = lerpf(1.0, 0.0, _ease_in_out(progress))
	if progress > 0.5:
		audio_event.emit("ship_powerdown")

func _advance_landing_phase() -> void:
	# Staged cinematics: hold at each phase until the corresponding subsystem
	# signals readiness (notify_*_ready). The timeout (phase_timeout_sec) is a
	# last-resort fallback so the sequence never gets stuck if a subsystem
	# fails to signal. If _phase_hold_enabled is false, behavior is unchanged
	# and phases advance immediately on animation completion.
	if _phase_hold_enabled:
		var current_ready: bool = _phase_ready.get(_landing_phase, true)
		if not current_ready:
			# Still holding — check timeout
			if _phase_timer > phase_timeout_sec:
				_advance_to_next_landing_phase()
			return
	_advance_to_next_landing_phase()

## Performs the actual phase transition + signal emission. Called either
## immediately (hold disabled / ready signaled) or after the timeout fallback.
func _advance_to_next_landing_phase() -> void:
	var next_phase: LandingPhase = _next_phase(_landing_phase)
	_set_landing_phase(next_phase)
	# SETTLE -> READY completes the landing sequence and shows the exit prompt.
	if next_phase == LandingPhase.READY:
		landing_complete.emit()
		prompt_show.emit("Press F to exit ship")
	if _landing_phase != LandingPhase.IDLE:
		landing_phase_changed.emit(int(_landing_phase), _phase_name(_landing_phase))

## Returns the next phase in the landing sequence for the given phase.
func _next_phase(phase: LandingPhase) -> LandingPhase:
	match phase:
		LandingPhase.ALIGN:
			return LandingPhase.DESCEND
		LandingPhase.DESCEND:
			return LandingPhase.TOUCHDOWN
		LandingPhase.TOUCHDOWN:
			return LandingPhase.SETTLE
		LandingPhase.SETTLE:
			return LandingPhase.READY
		LandingPhase.READY:
			return LandingPhase.EXITING
		LandingPhase.EXITING:
			return LandingPhase.IDLE
		_:
			return LandingPhase.IDLE

func _set_landing_phase(phase: LandingPhase) -> void:
	_landing_phase = phase
	_landing_phase_timer = 0.0
	_landing_phase_progress = 0.0
	_phase_timer = 0.0

func _current_landing_phase_duration() -> float:
	match _landing_phase:
		LandingPhase.ALIGN:
			return landing_align_duration
		LandingPhase.DESCEND:
			return landing_descend_duration
		LandingPhase.TOUCHDOWN:
			return landing_touchdown_duration
		LandingPhase.SETTLE:
			return landing_settle_duration
		LandingPhase.READY:
			return 0.5
		_:
			return 0.0

func _abort_landing_sequence() -> void:
	_set_landing_phase(LandingPhase.IDLE)
	landing_phase_changed.emit(int(_landing_phase), _phase_name(_landing_phase))

# ==============================================================================
# Takeoff Sequence Update
# ==============================================================================
func _update_takeoff_sequence(delta: float) -> void:
	if _takeoff_phase == TakeoffPhase.IDLE:
		return
	if not is_instance_valid(_ship):
		_abort_takeoff_sequence()
		return
	_takeoff_phase_timer += delta
	var duration: float = _current_takeoff_phase_duration()
	if duration <= 0.0:
		_takeoff_phase_progress = 1.0
	else:
		_takeoff_phase_progress = clampf(_takeoff_phase_timer / duration, 0.0, 1.0)

	match _takeoff_phase:
		TakeoffPhase.IGNITE:
			_process_ignite(_takeoff_phase_progress)
		TakeoffPhase.LIFT:
			_process_lift(_takeoff_phase_progress)
		TakeoffPhase.ASCEND:
			_process_ascend(_takeoff_phase_progress)
		TakeoffPhase.CLEAR:
			_process_clear(_takeoff_phase_progress)
		_:
			push_warning("[LandingSequenceController] Unknown takeoff phase in _process_takeoff: %d" % _takeoff_phase)

	if _takeoff_phase_progress >= 1.0:
		_advance_takeoff_phase()

func _process_ignite(progress: float) -> void:
	if not is_instance_valid(_ship):
		return
	# Engines spool up: glow intensifies.
	_engine_glow_target = lerpf(0.0, 2.5, _ease_in_out(progress))
	# Retract anchor begins near end of ignite.
	if progress > 0.7:
		_anchor_target_scale = _anchor_start_scale

func _process_lift(progress: float) -> void:
	if not is_instance_valid(_ship):
		return
	var eased: float = _ease_in_out(progress)
	# Rise vertically along the ship's current up.
	var up: Vector3 = _ship.global_transform.basis.y.normalized()
	var lift_height: float = 25.0
	_ship.global_position = _ship_target_position + up * (lift_height * eased)
	# Fully retract gear.
	_anchor_target_scale = _anchor_start_scale
	_engine_glow_target = 2.5

func _process_ascend(progress: float) -> void:
	if not is_instance_valid(_ship):
		return
	var eased: float = _ease_in_out(progress)
	# Pitch up toward the target basis and begin forward motion.
	var new_basis: Basis = _slerp_basis(_takeoff_start_basis, _takeoff_pitch_target_basis, eased)
	_ship.global_transform.basis = new_basis.orthonormalized()
	var up: Vector3 = _ship.global_transform.basis.y.normalized()
	var fwd: Vector3 = -_ship.global_transform.basis.z.normalized()
	var lift_height: float = 25.0
	var forward_dist: float = 60.0
	_ship.global_position = _ship_target_position + up * (lift_height + 40.0 * eased) + fwd * (forward_dist * eased)

func _process_clear(progress: float) -> void:
	if not is_instance_valid(_ship):
		return
	# Hand control back to FlightController at the end.
	if progress > 0.5 and _flight_controller != null and is_instance_valid(_flight_controller):
		_enable_flight_controller()
	# Continue forward acceleration.
	var fwd: Vector3 = -_ship.global_transform.basis.z.normalized()
	_ship.global_position = _ship.global_position + fwd * (80.0 * _takeoff_phase_progress * 0.016)
	_engine_glow_target = lerpf(2.5, 1.0, _ease_in_out(progress))

func _advance_takeoff_phase() -> void:
	match _takeoff_phase:
		TakeoffPhase.IGNITE:
			_set_takeoff_phase(TakeoffPhase.LIFT)
		TakeoffPhase.LIFT:
			_set_takeoff_phase(TakeoffPhase.ASCEND)
		TakeoffPhase.ASCEND:
			_set_takeoff_phase(TakeoffPhase.CLEAR)
		TakeoffPhase.CLEAR:
			_complete_takeoff()
		_:
			push_warning("[LandingSequenceController] Unknown takeoff phase in _advance_takeoff: %d" % _takeoff_phase)
	if _takeoff_phase != TakeoffPhase.IDLE:
		takeoff_phase_changed.emit(int(_takeoff_phase), _takeoff_phase_name(_takeoff_phase))

func _complete_takeoff() -> void:
	_set_takeoff_phase(TakeoffPhase.IDLE)
	takeoff_complete.emit()
	takeoff_phase_changed.emit(int(_takeoff_phase), _takeoff_phase_name(_takeoff_phase))
	# Reset landing phase too.
	if _landing_phase != LandingPhase.IDLE:
		_set_landing_phase(LandingPhase.IDLE)
		landing_phase_changed.emit(int(_landing_phase), _phase_name(_landing_phase))

func _set_takeoff_phase(phase: TakeoffPhase) -> void:
	_takeoff_phase = phase
	_takeoff_phase_timer = 0.0
	_takeoff_phase_progress = 0.0

func _current_takeoff_phase_duration() -> float:
	match _takeoff_phase:
		TakeoffPhase.IGNITE:
			return takeoff_ignite_duration
		TakeoffPhase.LIFT:
			return takeoff_lift_duration
		TakeoffPhase.ASCEND:
			return takeoff_ascend_duration
		TakeoffPhase.CLEAR:
			return 1.0
		_:
			return 0.0

func _abort_takeoff_sequence() -> void:
	_set_takeoff_phase(TakeoffPhase.IDLE)
	takeoff_phase_changed.emit(int(_takeoff_phase), _takeoff_phase_name(_takeoff_phase))

# ==============================================================================
# Exit / Entry Sequence
# ==============================================================================
func _update_exit_entry(delta: float) -> void:
	if not _is_exiting and not _is_entering:
		return
	_exit_entry_timer += delta
	if _is_exiting:
		_update_exit_progress(_exit_entry_timer / _EXIT_ENTRY_DURATION)
		if _exit_entry_timer >= _EXIT_ENTRY_DURATION:
			_finalize_exit()
	if _is_entering:
		_update_entry_progress(_exit_entry_timer / _EXIT_ENTRY_DURATION)
		if _exit_entry_timer >= _EXIT_ENTRY_DURATION:
			_finalize_entry()

func _update_exit_progress(progress: float) -> void:
	# Door opens at 30%, character spawns at 50%, controllers swap at 100%.
	if progress > 0.3 and progress < 0.35:
		audio_event.emit("ship_door_open")
	if progress > 0.5:
		_spawn_character_at_exit()
	if progress >= 1.0:
		_swap_to_on_foot()

func _update_entry_progress(progress: float) -> void:
	if progress > 0.3 and progress < 0.35:
		audio_event.emit("ship_door_open")
	if progress > 0.7:
		_retrieve_character_into_ship()
	if progress >= 1.0:
		_swap_to_ship()

func _finalize_exit() -> void:
	_is_exiting = false
	_exit_entry_timer = 0.0
	# Landing sequence fully complete; return to READY-idle so F can re-enter.
	_set_landing_phase(LandingPhase.IDLE)
	landing_phase_changed.emit(int(_landing_phase), _phase_name(_landing_phase))
	exit_complete.emit()
	prompt_show.emit("Press F to enter ship")

func _finalize_entry() -> void:
	_is_entering = false
	_exit_entry_timer = 0.0
	entry_complete.emit()
	# Return to READY so the player can exit again or take off.
	_set_landing_phase(LandingPhase.READY)
	landing_phase_changed.emit(int(_landing_phase), _phase_name(_landing_phase))
	prompt_show.emit("Press F to exit ship")

func _spawn_character_at_exit() -> void:
	if _character == null or not is_instance_valid(_character):
		return
	if not is_instance_valid(_ship):
		return
	_character.enter_from_ship(_ship.global_position, _ship.global_transform.basis.orthonormalized())
	_character.set_process(true)
	_character.set_physics_process(true)
	_character.visible = true
	audio_event.emit("footstep_surface")

func _retrieve_character_into_ship() -> void:
	if _character == null or not is_instance_valid(_character):
		return
	_character.return_to_ship()
	_character.visible = false
	_character.set_physics_process(false)

func _swap_to_on_foot() -> void:
	# Disable flight controller, enable character controller.
	_disable_flight_controller()
	if _character != null and is_instance_valid(_character):
		_character.set_physics_process(true)
	# Make planet camera current.
	if _planet_camera != null and is_instance_valid(_planet_camera):
		_planet_camera.set_target(_character)
		_planet_camera.set_planet_up(_surface_normal)
		_planet_camera.current = true

func _swap_to_ship() -> void:
	# Disable character controller, enable flight controller.
	if _character != null and is_instance_valid(_character):
		_character.set_physics_process(false)
	_enable_flight_controller()
	# Make flight camera current.
	if _flight_controller != null and is_instance_valid(_flight_controller):
		var cam: Camera3D = _flight_controller.fpv_camera
		if cam == null and _flight_controller.camera_node != null:
			cam = _flight_controller.camera_node
		if cam != null:
			cam.current = true

func _disable_flight_controller() -> void:
	if _flight_controller == null or not is_instance_valid(_flight_controller):
		return
	_flight_controller.set_physics_process(false)
	_flight_controller.set_process_input(false)
	_flight_controller.set_process_unhandled_input(false)

func _enable_flight_controller() -> void:
	if _flight_controller == null or not is_instance_valid(_flight_controller):
		return
	_flight_controller.set_physics_process(true)
	_flight_controller.set_process_input(true)
	_flight_controller.set_process_unhandled_input(true)

# ==============================================================================
# Input Handling
# ==============================================================================
func _handle_exit_enter_input() -> void:
	if _landing_phase == LandingPhase.READY and not _is_exiting and not _is_entering:
		start_exit_sequence()
	elif _is_exiting == false and _is_entering == false and _character != null and is_instance_valid(_character) and _character.visible:
		# On foot near ship - enter.
		start_entry_sequence()

# ==============================================================================
# Screen Shake
# ==============================================================================
func _trigger_screen_shake(amplitude: float) -> void:
	_screen_shake_time = 0.6
	_screen_shake_amp = amplitude

func _update_screen_shake(delta: float) -> void:
	if _screen_shake_time <= 0.0:
		return
	_screen_shake_time -= delta
	var cam: Camera3D = _get_active_camera()
	if cam == null:
		return
	var decay: float = maxf(0.0, _screen_shake_time / 0.6)
	var amp: float = _screen_shake_amp * decay
	cam.h_offset = randf_range(-amp, amp)
	cam.v_offset = randf_range(-amp, amp)
	if _screen_shake_time <= 0.0:
		cam.h_offset = 0.0
		cam.v_offset = 0.0

# ==============================================================================
# Camera Transition
# ==============================================================================
func _begin_camera_transition_to_third_person() -> void:
	var cam: Camera3D = _get_active_camera()
	if cam == null:
		return
	_camera_from_position = cam.global_position
	_camera_from_basis = cam.global_transform.basis.orthonormalized()
	if _planet_camera != null and is_instance_valid(_planet_camera):
		# Compute a desired third-person position behind/above the ship.
		var target_pos: Vector3 = _ship.global_position + _surface_normal * 3.0
		_camera_to_position = target_pos + (-_ship.global_transform.basis.z.normalized() * 7.0)
		_camera_to_basis = Basis.looking_at((_ship.global_position - _camera_to_position).normalized(), _surface_normal)
	else:
		_camera_to_position = _camera_from_position
		_camera_to_basis = _camera_from_basis
	_camera_transition_time = 0.0
	_camera_transitioning = true
	_target_camera_current = true

func _begin_camera_transition_to_cockpit() -> void:
	var cam: Camera3D = _get_active_camera()
	if cam == null:
		return
	_camera_from_position = cam.global_position
	_camera_from_basis = cam.global_transform.basis.orthonormalized()
	if _flight_controller != null and is_instance_valid(_flight_controller):
		var fpv: Camera3D = _flight_controller.fpv_camera
		if fpv != null and is_instance_valid(fpv):
			_camera_to_position = fpv.global_position
			_camera_to_basis = fpv.global_transform.basis.orthonormalized()
		else:
			_camera_to_position = _ship.global_position + _ship.global_transform.basis * cockpit_camera_offset
			_camera_to_basis = _ship.global_transform.basis.orthonormalized()
	else:
		_camera_to_position = _ship.global_position + _ship.global_transform.basis * cockpit_camera_offset
		_camera_to_basis = _ship.global_transform.basis.orthonormalized()
	_camera_transition_time = 0.0
	_camera_transitioning = true
	_target_camera_current = false

func _update_camera_transition(delta: float) -> void:
	if not _camera_transitioning:
		return
	_camera_transition_time += delta
	var progress: float = clampf(_camera_transition_time / camera_transition_duration, 0.0, 1.0)
	var eased: float = _ease_in_out(progress)
	var cam: Camera3D = _get_active_camera()
	if cam == null:
		_camera_transitioning = false
		return
	cam.global_position = _camera_from_position.lerp(_camera_to_position, eased)
	cam.global_transform.basis = _slerp_basis(_camera_from_basis, _camera_to_basis, eased).orthonormalized()
	if progress >= 1.0:
		_camera_transitioning = false
		# Hand off to the target camera.
		if _target_camera_current and _planet_camera != null and is_instance_valid(_planet_camera):
			_planet_camera.current = true
		elif not _target_camera_current and _flight_controller != null and is_instance_valid(_flight_controller):
			var fpv: Camera3D = _flight_controller.fpv_camera
			if fpv != null and is_instance_valid(fpv):
				fpv.current = true
			elif _flight_controller.camera_node != null:
				_flight_controller.camera_node.current = true

# ==============================================================================
# Engine Glow
# ==============================================================================
func _update_engine_glow(delta: float) -> void:
	if _engine_materials.is_empty():
		return
	_engine_glow_intensity = lerpf(_engine_glow_intensity, _engine_glow_target, clampf(delta * 4.0, 0.0, 1.0))
	for mat: ShaderMaterial in _engine_materials:
		if mat == null or not is_instance_valid(mat):
			continue
		# Try common shader parameter names; set_shader_parameter silently
		# ignores missing uniforms in Godot 4.7, so no has_shader_param needed.
		for param: StringName in [_S_GLOW, _S_EMISSION, _S_INTENSITY]:
			mat.set_shader_parameter(param, _engine_glow_intensity)

const _S_GLOW: StringName = &"glow_intensity"
const _S_EMISSION: StringName = &"emission_energy"
const _S_INTENSITY: StringName = &"engine_intensity"

# ==============================================================================
# Landing Gear / Organic Anchor
# ==============================================================================
func _update_anchor(delta: float) -> void:
	if _anchor_node == null or not is_instance_valid(_anchor_node):
		return
	var current: Vector3 = _anchor_node.scale
	var target: Vector3 = _anchor_target_scale
	_anchor_node.scale = current.lerp(target, clampf(delta * 6.0, 0.0, 1.0))

# ==============================================================================
# Dust Particles
# ==============================================================================
func _spawn_dust_burst(position: Vector3, up: Vector3) -> void:
	if dust_particle_count <= 0:
		return
	var dust: GPUParticles3D = _create_dust_system(position, up)
	if dust == null:
		return
	add_child(dust)
	dust.emitting = true
	# Auto-free after the lifetime.
	var lifetime: float = 2.0
	get_tree().create_timer(lifetime).timeout.connect(dust.queue_free)

func _create_dust_system(pos: Vector3, up: Vector3) -> GPUParticles3D:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.global_position = pos
	particles.amount = dust_particle_count
	particles.lifetime = 1.5
	particles.one_shot = true
	particles.emitting = false
	# Build a simple process material that bursts outward along the tangent plane.
	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 35.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 8.0
	mat.gravity = up * -2.0
	mat.scale_min = 0.2
	mat.scale_max = 0.6
	particles.process_material = mat
	# Simple sphere mesh for particles.
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.3
	mesh.height = 0.6
	var mat_override: StandardMaterial3D = StandardMaterial3D.new()
	mat_override.albedo_color = Color(0.7, 0.6, 0.45, 0.6)
	mat_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat_override
	particles.draw_pass_1 = mesh
	return particles

# ==============================================================================
# Reference Resolution (lazy, defensive)
# ==============================================================================
func _resolve_gameplay_references() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	# Character controller.
	if _character == null or not is_instance_valid(_character):
		var chars: Array[Node] = tree.get_nodes_in_group("planet_character")
		for c: Node in chars:
			if c is PlanetCharacterController:
				_character = c as PlanetCharacterController
				break
	# Planet camera.
	if _planet_camera == null or not is_instance_valid(_planet_camera):
		var cams: Array[Node] = tree.get_nodes_in_group("planet_camera")
		for c: Node in cams:
			if c is PlanetCamera:
				_planet_camera = c as PlanetCamera
				break
	# Flight controller.
	if _flight_controller == null or not is_instance_valid(_flight_controller):
		var ships: Array[Node] = tree.get_nodes_in_group("flight_controller")
		for s: Node in ships:
			if s is FlightController:
				_flight_controller = s as FlightController
				break

func _resolve_effect_references(ship: Node3D) -> void:
	# Find anchor / landing gear node.
	_anchor_node = _find_anchor_node(ship)
	if _anchor_node != null:
		_anchor_start_scale = _anchor_node.scale
		# Extended scale: stretch along the ship's local Y (downward).
		_anchor_extended_scale = Vector3(_anchor_start_scale.x, _anchor_start_scale.y * 2.5, _anchor_start_scale.z)
		_anchor_target_scale = _anchor_start_scale
	# Collect shader materials for engine glow control.
	_engine_materials.clear()
	_collect_engine_materials(ship)

func _find_anchor_node(root: Node) -> Node3D:
	# Look for a child named "anchor" (case-insensitive) or in group "landing_gear".
	for child: Node in root.get_children():
		if child is Node3D:
			var n3d: Node3D = child as Node3D
			var nm: String = n3d.name.to_lower()
			if nm.find("anchor") >= 0 or n3d.is_in_group("landing_gear"):
				return n3d
		var deeper: Node3D = _find_anchor_node(child)
		if deeper != null:
			return deeper
	return null

func _collect_engine_materials(root: Node) -> void:
	if root is MeshInstance3D:
		var mi: MeshInstance3D = root as MeshInstance3D
		for surf_idx: int in range(mi.get_surface_override_material_count()):
			var mat: Material = mi.get_surface_override_material(surf_idx)
			if mat is ShaderMaterial:
				_engine_materials.append(mat as ShaderMaterial)
		var mesh: Mesh = mi.mesh
		if mesh != null:
			for surf_idx: int in range(mesh.get_surface_count()):
				var mat: Material = mesh.surface_get_material(surf_idx)
				if mat is ShaderMaterial:
					_engine_materials.append(mat as ShaderMaterial)
	for child: Node in root.get_children():
		_collect_engine_materials(child)

func _get_active_camera() -> Camera3D:
	var vp: Viewport = get_viewport()
	if vp != null:
		return vp.get_camera_3d()
	return null

# ==============================================================================
# Math Utilities
# ==============================================================================
func _ease_in_out(t: float) -> float:
	# Smoothstep-style ease in/out.
	var x: float = clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

func _project_to_tangent(vec: Vector3, normal: Vector3) -> Vector3:
	return vec - normal * vec.dot(normal)

func _slerp_basis(from: Basis, to: Basis, t: float) -> Basis:
	var q_from: Quaternion = Quaternion(from.orthonormalized())
	var q_to: Quaternion = Quaternion(to.orthonormalized())
	var q_result: Quaternion = q_from.slerp(q_to, t)
	return Basis(q_result)

func _phase_name(phase: LandingPhase) -> String:
	var idx: int = int(phase)
	if idx >= 0 and idx < _LANDING_PHASE_NAMES.size():
		return _LANDING_PHASE_NAMES[idx]
	return "Unknown"

func _takeoff_phase_name(phase: TakeoffPhase) -> String:
	var idx: int = int(phase)
	if idx >= 0 and idx < _TAKEOFF_PHASE_NAMES.size():
		return _TAKEOFF_PHASE_NAMES[idx]
	return "Unknown"

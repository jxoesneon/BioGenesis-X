@tool
extends Node3D

const UniverseManagerClass = preload("res://scripts/UniverseManager.gd")
const FlightControllerClass = preload("res://scripts/FlightController.gd")
const GalaxyMapManagerClass = preload("res://scripts/GalaxyMapManager.gd")
const HyperWaveAutopilotClass = preload("res://scripts/HyperWaveAutopilot.gd")

var universe: Node
var ship: Node3D
var galaxy_map_scene: Node
var map_manager: Node

var flight_camera: Camera3D
var ui_layer: CanvasLayer

func _ready():
    # Setup test environment
    universe = UniverseManagerClass.new()
    add_child(universe)
    
    ship = FlightControllerClass.new()
    ship.position = Vector3(0, 5000, 20000)
    add_child(ship)
    
    flight_camera = Camera3D.new()
    flight_camera.position = Vector3(0, 2, 5)
    ship.add_child(flight_camera)
    ship.fpv_camera = flight_camera
    ship.camera_mode = ship.CameraMode.FPV
    
    ui_layer = CanvasLayer.new()
    add_child(ui_layer)
    
    # Instance Galaxy Map
    var map_packed := load("res://scenes/galaxy_map.tscn")
    if map_packed:
        galaxy_map_scene = map_packed.instantiate()
        ui_layer.add_child(galaxy_map_scene)
        
        map_manager = galaxy_map_scene.get_node("GalaxyMapManager")
        var map_ui := galaxy_map_scene.get_node("UI/GalaxyMapUI")
        if map_ui:
            map_ui.connect("wave_ride_engaged", Callable(self, "_on_wave_ride_engaged"))
            print("Successfully hooked up Galaxy Map UI to HyperWave Autopilot test.")

func _on_wave_ride_engaged(system_data: Dictionary):
    print("User clicked OVERCHARGE WAVE DRIVE. Hiding map, starting Autopilot...")
    
    # Hide map
    if galaxy_map_scene:
        galaxy_map_scene.hide()
        
    if not map_manager or not map_manager.current_route_path or map_manager.current_route_path.size() < 2:
        print("ERROR: No valid route found in GalaxyMapManager.")
        return
        
    var autopilot := HyperWaveAutopilotClass.new()
    add_child(autopilot)
    
    # Connect signals for debug output
    autopilot.connect("jump_sequence_started", Callable(self, "_on_jump_sequence_started"))
    autopilot.connect("jump_segment_started", Callable(self, "_on_jump_segment_started"))
    autopilot.connect("jump_segment_finished", Callable(self, "_on_jump_segment_finished"))
    autopilot.connect("jump_sequence_finished", Callable(self, "_on_jump_sequence_finished"))
    
    autopilot.start_jump_sequence(ship, universe, map_manager.current_route_path, map_manager.current_route_names)

func _on_jump_sequence_started():
    print("--- HYPERWAVE MULTI-JUMP SEQUENCE STARTED ---")

func _on_jump_segment_started(target: String):
    print(">>> PUNCHING HOLE TO: ", target)

func _on_jump_segment_finished(target: String):
    print("<<< DROPPED OUT AT: ", target)

func _on_jump_sequence_finished(aborted: bool):
    print("--- HYPERWAVE SEQUENCE FINISHED (Aborted: ", aborted, ") ---")
    if galaxy_map_scene:
        galaxy_map_scene.show() # Re-show map for further testing

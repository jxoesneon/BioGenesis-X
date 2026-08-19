# res://scripts/ScaledSpaceManager.gd
# ==============================================================================
# BioGenesis-X: Scaled Space Manager (Elite Dangerous-style POI indicators)
# ==============================================================================
# Instead of rendering miniaturized planet replicas (which look like they move
# with the ship), this system uses Elite Dangerous-style HUD markers that
# indicate the direction, distance, and name of celestial bodies (points of
# interest). The actual planet meshes only render when you're close enough
# to see them at real scale.
#
# This approach matches Elite Dangerous: you don't see planet meshes from
# across the system — you see navigation markers and target indicators.
# ==============================================================================

extends Node

const POIIndicatorClass: GDScript = preload("res://scripts/POIIndicatorManager.gd")

var _poi_manager: Node = null

func _ready() -> void:
	# Create the POI indicator manager as a child
	_poi_manager = POIIndicatorClass.new()
	_poi_manager.name = "POIIndicatorManager"
	add_child(_poi_manager)
	print("[ScaledSpace] Initialized: Elite Dangerous-style POI indicators (no visual replicas)")

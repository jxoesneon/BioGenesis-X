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
# WHY NOT MINIATURIZED REPLICAS:
#   Miniaturized replicas (e.g. a 1m sphere representing a 6,371km planet)
#   break down because they must be positioned relative to the ship. As the
#   ship moves, the replica moves with it, creating the illusion that the
#   planet is following the ship. This destroys the sense of astronomical
#   scale — the core fantasy of BioGenesis-X.
#
#   The Elite Dangerous approach preserves scale: you see navigation markers
#   (direction + distance + name) until you're close enough for the real
#   planet mesh to render at actual size. This is why the Void-Fauna's
#   Multispectral Eye Pods (LORE.md) detect stellar EM fluctuations — the
#   ship senses distant bodies through instruments, not through a window.
#   The HUD markers ARE the ship's sensor display.
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

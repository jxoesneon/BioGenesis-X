@tool
extends EditorPlugin

# BioGenesis-X integration: stripped to the core ocean features only.
# Per the Council verdict, only the Ocean type (core water.gdshader + Gerstner
# wave system) is registered. The CameraFollower3D and WaterMaterialDesigner
# features are disabled — they are not used for planet ocean rendering.
# OceanSurfaceManager.gd drives the shader uniforms directly at runtime.


func _enter_tree():
	add_custom_type(
		"Ocean",
		"Node3D",
		preload("res://addons/boujie_water_shader/types/ocean.gd"),
		preload("res://addons/boujie_water_shader/icons/Ocean.svg")
	)


func _exit_tree():
	remove_custom_type("Ocean")

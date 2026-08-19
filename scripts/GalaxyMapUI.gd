extends Control
class_name GalaxyMapUI

var info_panel: MarginContainer
var system_name_label: Label
var spectral_class_label: Label
var planets_label: Label
var distance_label: Label
var threat_label: Label
var engage_button: Button

signal wave_ride_engaged(system_data)
signal refocus_current_system()

var current_system_data = null

func _ready():
    self.set_anchors_preset(Control.PRESET_FULL_RECT)
    self.mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    _build_ui()
    info_panel.hide()

func _build_ui():
    # ---------------------------------------------------------
    # Info Panel (NMS Style: Minimal, Thin Lines, Clean typography)
    # ---------------------------------------------------------
    info_panel = MarginContainer.new()
    add_child(info_panel)
    
    # Position: Bottom Left (NMS often anchors info panels nicely to the sides)
    info_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 20)
    info_panel.offset_left = 60
    info_panel.offset_right = 450
    info_panel.offset_top = -350
    info_panel.offset_bottom = -80
    
    var hbox := HBoxContainer.new()
    hbox.add_theme_constant_override("separation", 24)
    info_panel.add_child(hbox)
    
    # Left accent line
    var left_line := Panel.new()
    left_line.custom_minimum_size = Vector2(2, 0)
    var line_style := StyleBoxFlat.new()
    line_style.bg_color = Color(1.0, 1.0, 1.0, 0.7)
    left_line.add_theme_stylebox_override("panel", line_style)
    hbox.add_child(left_line)
    
    # Content Box
    var content_vbox := VBoxContainer.new()
    content_vbox.add_theme_constant_override("separation", 10)
    content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    hbox.add_child(content_vbox)
    
    # System Name
    system_name_label = Label.new()
    system_name_label.text = "SYSTEM: UNKNOWN"
    system_name_label.add_theme_font_size_override("font_size", 30)
    system_name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
    content_vbox.add_child(system_name_label)
    
    var sep1 := HSeparator.new()
    var sep_style := StyleBoxLine.new()
    sep_style.color = Color(1.0, 1.0, 1.0, 0.2)
    sep_style.thickness = 1
    sep1.add_theme_stylebox_override("separator", sep_style)
    content_vbox.add_child(sep1)
    
    # Details
    spectral_class_label = _create_detail_label()
    content_vbox.add_child(spectral_class_label)
    
    planets_label = _create_detail_label()
    content_vbox.add_child(planets_label)
    
    threat_label = _create_detail_label()
    content_vbox.add_child(threat_label)
    
    distance_label = _create_detail_label()
    distance_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.2)) # Pale gold
    content_vbox.add_child(distance_label)
    
    var spacer := Control.new()
    spacer.custom_minimum_size = Vector2(0, 15)
    content_vbox.add_child(spacer)
    
    # Engage Button - NMS Style Outline Button
    engage_button = Button.new()
    engage_button.text = "WARP TO SYSTEM"
    engage_button.add_theme_font_size_override("font_size", 16)
    
    var btn_style_normal := StyleBoxFlat.new()
    btn_style_normal.bg_color = Color(0, 0, 0, 0.3)
    btn_style_normal.border_width_left = 1
    btn_style_normal.border_width_top = 1
    btn_style_normal.border_width_right = 1
    btn_style_normal.border_width_bottom = 1
    btn_style_normal.border_color = Color(1.0, 1.0, 1.0, 0.6)
    engage_button.add_theme_stylebox_override("normal", btn_style_normal)
    
    var btn_style_hover := btn_style_normal.duplicate()
    btn_style_hover.bg_color = Color(1.0, 1.0, 1.0, 0.9)
    engage_button.add_theme_stylebox_override("hover", btn_style_hover)
    
    var btn_style_pressed := btn_style_normal.duplicate()
    btn_style_pressed.bg_color = Color(0.8, 0.8, 0.8, 1.0)
    engage_button.add_theme_stylebox_override("pressed", btn_style_pressed)
    
    engage_button.add_theme_color_override("font_color", Color(1, 1, 1))
    engage_button.add_theme_color_override("font_hover_color", Color(0, 0, 0))
    engage_button.add_theme_color_override("font_pressed_color", Color(0, 0, 0))
    
    engage_button.custom_minimum_size = Vector2(200, 45)
    engage_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    engage_button.pressed.connect(_on_engage_pressed)
    
    content_vbox.add_child(engage_button)
    
    var refocus_button := Button.new()
    refocus_button.text = "REFOCUS CURRENT SYSTEM"
    refocus_button.add_theme_font_size_override("font_size", 12)
    refocus_button.add_theme_stylebox_override("normal", btn_style_normal)
    refocus_button.add_theme_stylebox_override("hover", btn_style_hover)
    refocus_button.add_theme_stylebox_override("pressed", btn_style_pressed)
    refocus_button.add_theme_color_override("font_color", Color(1, 1, 1))
    refocus_button.add_theme_color_override("font_hover_color", Color(0, 0, 0))
    refocus_button.add_theme_color_override("font_pressed_color", Color(0, 0, 0))
    refocus_button.custom_minimum_size = Vector2(200, 30)
    refocus_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    
    # We will emit a custom signal that the Manager can listen to
    refocus_button.pressed.connect(func(): emit_signal("refocus_current_system"))
    content_vbox.add_child(refocus_button)

    # ---------------------------------------------------------
    # Persistent Minimal Header
    # ---------------------------------------------------------
    var header_margin := MarginContainer.new()
    add_child(header_margin)
    header_margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
    header_margin.add_theme_constant_override("margin_top", 30)
    header_margin.add_theme_constant_override("margin_left", 40)
    header_margin.add_theme_constant_override("margin_right", 40)
    
    var h_hbox := HBoxContainer.new()
    header_margin.add_child(h_hbox)
    
    var lbl_title := Label.new()
    lbl_title.text = "GALAXY MAP"
    lbl_title.add_theme_font_size_override("font_size", 18)
    lbl_title.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.8))
    lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    h_hbox.add_child(lbl_title)
    
    var lbl_map_controls := Label.new()
    lbl_map_controls.text = "LMB: SELECT  //  WASD: PAN  //  SCROLL: ZOOM  //  M: CLOSE"
    lbl_map_controls.add_theme_font_size_override("font_size", 12)
    lbl_map_controls.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.4))
    h_hbox.add_child(lbl_map_controls)

func _create_detail_label() -> Label:
    var lbl := Label.new()
    lbl.add_theme_font_size_override("font_size", 15)
    lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
    return lbl

func _on_system_selected(system_data: Dictionary):
    display_system_info(system_data)

func display_system_info(system_data: Dictionary):
    current_system_data = system_data
    
    if not system_data.is_empty():
        system_name_label.text = system_data.get("name", "UNKNOWN").to_upper()
        spectral_class_label.text = "CLASS: " + system_data.get("spectral_class", "N/A") + "  //  LUM: " + str(system_data.get("luminosity", "N/A"))
        planets_label.text = "PLANETS: " + str(system_data.get("planets", 0)) + "  //  RES: " + system_data.get("resources", "Unknown")
        
        var threat = system_data.get("threat_level", "UNKNOWN")
        threat_label.text = "THREAT: " + threat + "  //  FACTION: " + system_data.get("faction", "None")
        
        if system_data.has("distance_from_current"):
            var dist_text := "DIST: %.1f LY" % system_data["distance_from_current"]
            if system_data.has("jumps"):
                if system_data["jumps"] == -1:
                    dist_text += "  //  OUT OF RANGE"
                    distance_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
                else:
                    dist_text += "  //  JUMPS: %d" % system_data["jumps"]
                    distance_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
            distance_label.text = dist_text
            distance_label.show()
        else:
            distance_label.hide()
        
        # Threat Color Coding
        if threat in ["HIGH", "CRITICAL"]:
            threat_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
        elif threat == "MODERATE":
            threat_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
        else:
            threat_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.8))
            
        info_panel.show()
    else:
        info_panel.hide()

func hide_ui():
    info_panel.hide()
    current_system_data = null

func _on_engage_pressed():
    if current_system_data != null:
        wave_ride_engaged.emit(current_system_data)
        print("Engaging WARP to: ", current_system_data.get("name", "Unknown"))

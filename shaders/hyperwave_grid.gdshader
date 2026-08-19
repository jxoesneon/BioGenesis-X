shader_type spatial;
render_mode blend_add, unshaded, cull_disabled;

uniform float charge_ratio : hint_range(0.0, 1.0) = 0.0;
uniform vec3 grid_color : source_color = vec3(0.8, 0.95, 1.0);
uniform float grid_thickness : hint_range(0.0, 1.0) = 0.02;
uniform float grid_scale = 30.0;

void vertex() {
    // Distance from center in local space (XZ plane)
    float dist = length(VERTEX.xz);
    
    // Deform the center forward (away from ship) as charge_ratio increases
    // smoothstep creates a bell-like funnel curve
    float deform = smoothstep(80.0, 0.0, dist) * charge_ratio * 200.0;
    VERTEX.y -= deform; 
}

void fragment() {
    // Use UV mapped to the grid scale
    vec2 grid_uv = UV * grid_scale;
    
    // Procedural grid lines
    vec2 grid = fract(grid_uv);
    float line_x = smoothstep(grid_thickness, 0.0, grid.x) + smoothstep(1.0 - grid_thickness, 1.0, grid.x);
    float line_y = smoothstep(grid_thickness, 0.0, grid.y) + smoothstep(1.0 - grid_thickness, 1.0, grid.y);
    float grid_alpha = clamp(line_x + line_y, 0.0, 1.0);
    
    // Distance from center of the plane (0.0 to 0.5)
    float dist = length(UV - 0.5);
    
    // Hole in the center that expands rapidly at the end of the charge
    float hole_radius = pow(charge_ratio, 5.0) * 0.15; 
    float hole_mask = smoothstep(hole_radius, hole_radius + 0.02, dist);
    
    // Soft fade at the outer edges
    float outer_fade = smoothstep(0.5, 0.1, dist);
    
    // Fade in when charging starts
    float appear = smoothstep(0.0, 0.1, charge_ratio);
    
    ALBEDO = grid_color * 6.0; // High intensity for bloom
    ALPHA = grid_alpha * hole_mask * outer_fade * appear * 0.15;
}

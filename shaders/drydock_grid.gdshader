shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 berth_base_color : source_color = vec3(0.04, 0.05, 0.07);
uniform vec3 berth_metal_color : source_color = vec3(0.12, 0.15, 0.19);
uniform vec3 trench_color : source_color = vec3(0.015, 0.02, 0.025);
uniform vec3 grid_laser_color : source_color = vec3(0.0, 0.75, 0.95);

uniform float displacement_strength = 0.045; // Subtle, refined physical depth
uniform float grid_spacing = 3.0; // Unified 3.0m modular panel and laser spacing
uniform float ring_spacing = 6.0; // Unified 6.0m concentric conduit ring spacing
uniform float seam_width = 0.06;
uniform float metallic_val = 0.92;
uniform float roughness_val = 0.35;

// Micro-surface noise
float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Unified procedural height function that exactly aligns with the laser grid
float get_platform_height(vec2 pos) {
    float dist = length(pos);
    
    // 1. Grid Seam Recesses (Exactly aligned with 3.0m grid)
    vec2 grid_frac = abs(fract(pos / grid_spacing - 0.5) - 0.5) * grid_spacing;
    float dist_to_grid_seam = min(grid_frac.x, grid_frac.y);
    float grid_groove = smoothstep(0.0, seam_width * 2.0, dist_to_grid_seam);
    
    // 2. Concentric Annular Trench Recesses (Exactly aligned with 6.0m rings)
    float ring_frac = abs(fract(dist / ring_spacing - 0.5) - 0.5) * ring_spacing;
    float ring_groove = smoothstep(0.0, seam_width * 2.5, ring_frac);
    
    // 3. Subtle Chamfer Plate Top
    float plate_relief = grid_groove * ring_groove;
    
    // 4. Subtle Micro-grain Texture
    float micro_grain = (noise(pos * 6.0) - 0.5) * 0.08;
    
    // Combine height features
    float total_h = (plate_relief * 0.8 + micro_grain * 0.2);
    
    // Rim falloff near platform edge
    float rim_taper = smoothstep(28.0, 24.0, dist);
    return total_h * rim_taper;
}

void vertex() {
    if (VERTEX.y > -0.1) {
        float h = get_platform_height(VERTEX.xz);
        VERTEX.y += h * displacement_strength;
    }
}

void fragment() {
    vec2 pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
    float dist = length(pos);
    
    // Calculate normal using finite differences of the unified height function
    float eps = 0.03;
    float h_center = get_platform_height(pos);
    float h_x = get_platform_height(pos + vec2(eps, 0.0));
    float h_z = get_platform_height(pos + vec2(0.0, eps));
    
    vec3 local_n = normalize(vec3(
        (h_center - h_x) * displacement_strength / eps,
        1.0,
        (h_center - h_z) * displacement_strength / eps
    ));
    
    NORMAL = normalize(VIEW_MATRIX * vec4(local_n, 0.0)).xyz;
    
    // Aligned Laser Grid (Runs precisely inside the recessed grooves)
    vec2 grid_frac = abs(fract(pos / grid_spacing - 0.5) - 0.5) * grid_spacing;
    float dist_to_grid_seam = min(grid_frac.x, grid_frac.y);
    float grid_laser = 1.0 - smoothstep(0.0, seam_width * 0.8, dist_to_grid_seam);
    
    // Aligned Concentric Laser Calibration Rings
    float ring_frac = abs(fract(dist / ring_spacing - 0.5) - 0.5) * ring_spacing;
    float ring_laser = 1.0 - smoothstep(0.0, seam_width * 1.0, ring_frac);
    
    float boundary_fade = smoothstep(27.0, 14.0, dist);
    float total_laser = max(grid_laser * 0.7, ring_laser * 0.9) * boundary_fade;
    
    // PBR Albedo blending
    float cavity = clamp(h_center, 0.0, 1.0);
    vec3 surface_color = mix(trench_color, mix(berth_base_color, berth_metal_color, clamp(h_center * 1.5, 0.0, 1.0)), cavity);
    
    ALBEDO = surface_color;
    METALLIC = metallic_val;
    ROUGHNESS = mix(roughness_val + 0.15, roughness_val - 0.05, cavity);
    AO = mix(0.5, 1.0, cavity);
    
    // Glowing laser grid perfectly registered inside the grooves
    EMISSION = grid_laser_color * total_laser * 1.2;
}

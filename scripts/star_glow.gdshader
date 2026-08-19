shader_type spatial;
render_mode blend_add, depth_draw_never, unshaded;

// Instance custom data: 
// r: Spectral Class (0.0 to 1.0 mapped to O-M)
// g: Luminosity/Size scale

uniform sampler2D noise_texture;
uniform vec3 color_O = vec3(0.2, 0.6, 2.0); // Vibrant deep blue
uniform vec3 color_B = vec3(0.3, 0.9, 1.8); // Bright glowing cyan
uniform vec3 color_A = vec3(1.5, 1.5, 1.5); // Intense white
uniform vec3 color_F = vec3(1.8, 1.6, 0.7); // Bright yellow-white
uniform vec3 color_G = vec3(1.8, 1.2, 0.2); // Vibrant sun yellow
uniform vec3 color_K = vec3(2.0, 0.6, 0.1); // Fiery orange
uniform vec3 color_M = vec3(2.0, 0.1, 0.3); // Deep vibrant pink/red

varying vec3 star_color;
varying float star_intensity;

void vertex() {
    float spectral_idx = INSTANCE_CUSTOM.x;
    float luminosity = INSTANCE_CUSTOM.y;
    
    // Map spectral index to Harvard Spectral Class colors
    if (spectral_idx < 0.16) {
        star_color = mix(color_O, color_B, spectral_idx / 0.16);
    } else if (spectral_idx < 0.33) {
        star_color = mix(color_B, color_A, (spectral_idx - 0.16) / 0.17);
    } else if (spectral_idx < 0.5) {
        star_color = mix(color_A, color_F, (spectral_idx - 0.33) / 0.17);
    } else if (spectral_idx < 0.66) {
        star_color = mix(color_F, color_G, (spectral_idx - 0.5) / 0.16);
    } else if (spectral_idx < 0.83) {
        star_color = mix(color_G, color_K, (spectral_idx - 0.66) / 0.17);
    } else {
        star_color = mix(color_K, color_M, (spectral_idx - 0.83) / 0.17);
    }
    
    star_intensity = max(luminosity, 0.1);
    
    // Spherical billboarding
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
    MODELVIEW_MATRIX[0][0] = length(MODEL_MATRIX[0]);
    MODELVIEW_MATRIX[1][1] = length(MODEL_MATRIX[1]);
    MODELVIEW_MATRIX[2][2] = length(MODEL_MATRIX[2]);
    
    // Scale quad by luminosity and global multiplier so it's visible from 1000 units away
    VERTEX *= star_intensity * 20.0;
}

void fragment() {
    vec2 center_uv = UV * 2.0 - 1.0;
    float dist = length(center_uv);
    
    // Smooth envelope to ensure it hits exactly 0 before the quad boundary
    float edge_fade = smoothstep(1.0, 0.7, dist);
    
    // Angle for radial rays
    float angle = atan(center_uv.y, center_uv.x);
    float ray1 = sin(angle * 8.0 + TIME * 0.5) * 0.5 + 0.5;
    float ray2 = sin(angle * 13.0 - TIME * 0.8) * 0.5 + 0.5;
    float rays = mix(1.0, (ray1 * ray2), 0.3); // Subtle radial rays
    
    // Smooth falloff and core intensity
    float glow = exp(-dist * 5.0) * rays;
    float core = smoothstep(0.3, 0.0, dist) * 3.0;
    
    // Add procedural noise to the star surface for flicker/texture
    vec2 noise_uv = UV + vec2(TIME * 0.05);
    float noise = texture(noise_texture, noise_uv).r;
    
    // Final alpha must be clamped by edge_fade to remove hard edges
    float final_alpha = clamp((glow + core) * (0.8 + 0.4 * noise), 0.0, 1.0) * edge_fade;
    
    // NMS style: Crank up the brightness multiplier to ensure heavy bloom from WorldEnvironment
    ALBEDO = star_color * star_intensity * 3.5;
    ALPHA = final_alpha;
}

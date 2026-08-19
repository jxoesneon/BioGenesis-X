shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// ============================================================================
// BIO-GENESIS-X: PROCEDURAL SPACE PLASMA NEBULA & ION CLOUD SHADER
// Multi-Frequency 3D Simplex & Curl Noise Textures for System-Wide Space Clouds
// ============================================================================

uniform vec4 plasma_color_core : source_color = vec4(0.0, 0.95, 0.75, 1.0);     // Bioluminescent Cyan-Emerald
uniform vec4 plasma_color_fringe : source_color = vec4(0.55, 0.08, 0.85, 1.0);   // Ionized Deep Violet
uniform vec4 solar_flare_color : source_color = vec4(1.0, 0.45, 0.1, 1.0);       // Exothermal Plasma

uniform float plasma_density : hint_range(0.0, 5.0, 0.1) = 1.6;
uniform float plasma_scale : hint_range(0.01, 2.0, 0.01) = 0.15;
uniform float plasma_flow_speed : hint_range(0.0, 2.0, 0.05) = 0.08;
uniform float turbulence_strength : hint_range(0.0, 3.0, 0.1) = 1.2;

varying vec3 v_world_pos;
varying vec3 v_normal;

// ----------------------------------------------------------------------------
// 3D Noise Texture Mathematical Algorithms
// ----------------------------------------------------------------------------

float hash31(vec3 p) {
    p = fract(p * vec3(443.897, 441.423, 437.195));
    p += dot(p, p.yzx + 19.19);
    return fract((p.x + p.y) * p.z);
}

float noise3D(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float n000 = hash31(i);
    float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash31(i + vec3(1.0, 1.0, 1.0));

    return mix(
        mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
        mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
        f.z
    );
}

float fbm_plasma(vec3 p, int octaves) {
    float v = 0.0;
    float a = 0.5;
    mat3 rot = mat3(
        vec3(0.00,  0.80,  0.60),
        vec3(-0.80,  0.36, -0.48),
        vec3(-0.60, -0.48,  0.64)
    );
    for (int i = 0; i < octaves; i++) {
        v += a * noise3D(p);
        p = rot * p * 2.04;
        a *= 0.48;
    }
    return v;
}

// 3D Curl Noise Field for plasma fluid swirling
vec3 curl_noise(vec3 p) {
    float eps = 0.1;
    float n1 = noise3D(p + vec3(0.0, eps, 0.0)) - noise3D(p - vec3(0.0, eps, 0.0));
    float n2 = noise3D(p + vec3(0.0, 0.0, eps)) - noise3D(p - vec3(0.0, 0.0, eps));
    float n3 = noise3D(p + vec3(eps, 0.0, 0.0)) - noise3D(p - vec3(eps, 0.0, 0.0));
    return normalize(vec3(n1, n2, n3));
}

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    vec3 local_pos = VERTEX;
    float time = TIME * plasma_flow_speed;

    // 1. Dynamic 3D Coordinates with Curl Fluid Turbulence
    vec3 sample_pos = (v_world_pos * plasma_scale) + vec3(0.0, time * 0.4, 0.0);
    vec3 curl = curl_noise(sample_pos * 1.5) * turbulence_strength;
    vec3 turb_pos = sample_pos + curl;

    // 2. Multi-Octave Noise Textures for Filamentous Plasma Density
    float primary_noise = fbm_plasma(turb_pos, 5);
    float secondary_noise = fbm_plasma(turb_pos * 2.2 + vec3(time * 0.6, -time * 0.3, time * 0.2), 4);
    float fine_filaments = noise3D(turb_pos * 8.0 + vec3(time));

    // 3. Density Thresholding & Smooth Dissolution Falloff
    float density = smoothstep(0.42, 0.78, primary_noise + secondary_noise * 0.35);
    float filament_mask = smoothstep(0.55, 0.85, fine_filaments);
    
    // Sphere Boundary Soft Falloff (fades out at geometry edges)
    float dist_from_center = length(local_pos);
    float edge_fade = smoothstep(1.0, 0.2, dist_from_center / max(1.0, length(local_pos)));

    // 4. Color Grading across Plasma Thermal Layers
    vec3 plasma_mix = mix(plasma_color_fringe.rgb, plasma_color_core.rgb, smoothstep(0.45, 0.75, primary_noise));
    plasma_mix = mix(plasma_mix, solar_flare_color.rgb, filament_mask * 0.6);

    // 5. Fresnel Atmospheric Glow
    float NdotV = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
    float fresnel = pow(1.0 - NdotV, 2.5);

    // Composite Final Radiance Output
    float final_alpha = density * plasma_density * (0.4 + fresnel * 0.6);
    ALBEDO = plasma_mix * (1.2 + filament_mask * 1.8);
    ALPHA = clamp(final_alpha * 0.45, 0.0, 0.85);
}

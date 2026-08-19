shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// ============================================================================
// BIO-GENESIS-X: PHOTOSPHERIC SOLAR CORONA & PROMINENCE NOISE SHADER
// Dynamic Multi-Octave Noise Textures for Solar Granulation & Magnetic Flares
// ============================================================================

uniform vec4 star_core_color : source_color = vec4(1.0, 0.92, 0.65, 1.0);
uniform vec4 star_corona_color : source_color = vec4(1.0, 0.45, 0.12, 1.0);
uniform vec4 prominence_color : source_color = vec4(0.95, 0.15, 0.05, 1.0);

uniform float corona_speed : hint_range(0.0, 2.0, 0.05) = 0.25;
uniform float turbulence_scale : hint_range(0.5, 10.0, 0.5) = 3.5;
uniform float prominence_intensity : hint_range(0.0, 5.0, 0.1) = 2.4;

varying vec3 v_world_pos;

float star_hash(vec3 p) {
    p = fract(p * vec3(443.897, 441.423, 437.195));
    p += dot(p, p.yzx + 19.19);
    return fract((p.x + p.y) * p.z);
}

float star_noise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float n000 = star_hash(i);
    float n100 = star_hash(i + vec3(1.0, 0.0, 0.0));
    float n010 = star_hash(i + vec3(0.0, 1.0, 0.0));
    float n110 = star_hash(i + vec3(1.0, 1.0, 0.0));
    float n001 = star_hash(i + vec3(0.0, 0.0, 1.0));
    float n101 = star_hash(i + vec3(1.0, 0.0, 1.0));
    float n011 = star_hash(i + vec3(0.0, 1.0, 1.0));
    float n111 = star_hash(i + vec3(1.0, 1.0, 1.0));

    return mix(
        mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
        mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
        f.z
    );
}

float fbm_star(vec3 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * star_noise(p);
        p *= 2.08;
        a *= 0.48;
    }
    return v;
}

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec3 local_pos = normalize(VERTEX);
    float time = TIME * corona_speed;

    // 1. Multi-Octave Granulation & Convective Cell Noise Textures
    vec3 gran_coord = local_pos * turbulence_scale + vec3(time * 0.4, -time * 0.2, time * 0.3);
    float gran_1 = fbm_star(gran_coord);
    float gran_2 = fbm_star(gran_coord * 2.5 - vec3(time * 0.5));
    float flare_noise = star_noise(local_pos * 8.0 + vec3(time * 0.8));

    // 2. Chromospheric Limb & Radiance
    float NdotV = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
    float limb_glow = pow(1.0 - NdotV, 2.8) * prominence_intensity;

    // 3. Composite Solar Radiance
    vec3 color_mix = mix(star_corona_color.rgb, star_core_color.rgb, gran_1 * 1.2);
    color_mix = mix(color_mix, prominence_color.rgb, smoothstep(0.65, 0.90, flare_noise));

    float final_glow = (gran_1 + gran_2 * 0.5 + limb_glow) * 2.0;
    ALBEDO = color_mix * final_glow;
    ALPHA = clamp(pow(1.0 - NdotV, 1.5) * 1.2, 0.0, 1.0);
}

shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// ============================================================================
// INTERIOR LIVING MEMBRANE & COCKPIT PBR SHADER - BioGenesis-X
// Pumilio Studios - AAA+ Next-Gen Biological PBR System
// ============================================================================
// Features:
// 1. Vascular muscle tissue fibers & pulsating capillaries
// 2. High-gloss biological slime/mucus layer (Clearcoat & Roughness)
// 3. Subsurface scattering (SSS) for fleshy, living organ walls
// 4. Ambient cavity occlusion in cellular crevices
// ============================================================================

group_uniforms Base_Tissue_Colors;
uniform vec4 tissue_base_color : source_color = vec4(0.18, 0.06, 0.08, 1.0);     // Deep crimson muscle
uniform vec4 tissue_fiber_color : source_color = vec4(0.32, 0.10, 0.14, 1.0);    // Striated muscle fiber
uniform vec4 capillary_color : source_color = vec4(0.0, 0.95, 0.85, 1.0);        // Bioluminescent capillaries
uniform vec4 sss_color : source_color = vec4(0.95, 0.25, 0.15, 1.0);

group_uniforms PBR_Parameters;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.22;
uniform float metallic : hint_range(0.0, 1.0, 0.01) = 0.08;
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.75;
uniform float sss_strength : hint_range(0.0, 1.0, 0.05) = 0.65;
uniform float capillary_glow : hint_range(0.0, 5.0, 0.1) = 1.6;

varying vec3 v_model_pos;

float hash31(vec3 p) {
    p = fract(p * vec3(443.897, 441.423, 437.195));
    p += dot(p, p.yzx + 19.19);
    return fract((p.x + p.y) * p.z);
}

float noise3d(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash31(i);
    float b = hash31(i + vec3(1.0, 0.0, 0.0));
    float c = hash31(i + vec3(0.0, 1.0, 0.0));
    float d = hash31(i + vec3(1.0, 1.0, 0.0));
    float e = hash31(i + vec3(0.0, 0.0, 1.0));
    float f1 = hash31(i + vec3(1.0, 0.0, 1.0));
    float g = hash31(i + vec3(0.0, 1.0, 1.0));
    float h = hash31(i + vec3(1.0, 1.0, 1.0));
    float nx0 = mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    float nx1 = mix(mix(e, f1, f.x), mix(g, h, f.x), f.y);
    return mix(nx0, nx1, f.z);
}

float fbm3d(vec3 p) {
    float val = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; i++) {
        val += amp * noise3d(p);
        p *= 2.1;
        amp *= 0.47;
    }
    return val;
}

void vertex() {
    v_model_pos = VERTEX;
}

void fragment() {
    vec3 pos = v_model_pos;

    // 1. Muscle tissue striations along body
    float muscle_fibers = sin(pos.x * 25.0 + sin(pos.z * 15.0) * 0.8) * 0.5 + 0.5;
    float tissue_noise = fbm3d(pos * 6.0);
    
    // 2. Capillary web
    float cap_fbm = fbm3d(pos * 18.0 + vec3(0.0, 0.0, TIME * 0.05));
    float capillary = clamp(pow(1.0 - abs(cap_fbm - 0.5) * 2.0, 4.0), 0.0, 1.0);
    float capillary_pulse = capillary * (0.6 + 0.4 * sin(TIME * 2.5 + pos.z * 3.0));

    // 3. Normal mapping for wet flesh
    float delta = 0.02;
    float h0 = muscle_fibers * 0.2 + tissue_noise * 0.3;
    float hx = sin((pos.x + delta) * 25.0) * 0.2 + fbm3d((pos + vec3(delta, 0.0, 0.0)) * 6.0) * 0.3;
    float hy = muscle_fibers * 0.2 + fbm3d((pos + vec3(0.0, delta, 0.0)) * 6.0) * 0.3;
    vec3 bump = normalize(vec3((h0 - hx) * 0.8, (h0 - hy) * 0.8, 1.0));
    NORMAL = normalize(TANGENT * bump.x + BINORMAL * bump.y + NORMAL * bump.z);

    // 4. Color blending
    vec3 albedo_col = mix(tissue_base_color.rgb, tissue_fiber_color.rgb, muscle_fibers);
    albedo_col = mix(albedo_col, capillary_color.rgb * 0.3, capillary);

    ALBEDO = albedo_col;
    ROUGHNESS = clamp(roughness + (1.0 - muscle_fibers) * 0.15, 0.08, 0.85);
    METALLIC = metallic;
    SPECULAR = specular;

    // Emissive capillaries
    EMISSION = capillary_color.rgb * capillary_pulse * capillary_glow;

    // SSS for living tissue
    SSS_STRENGTH = sss_strength;
    SSS_TRANSMITTANCE_COLOR = vec4(sss_color.rgb, 1.0);
    float NdotV = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
    BACKLIGHT = sss_color.rgb * sss_strength * (1.0 - NdotV);
}

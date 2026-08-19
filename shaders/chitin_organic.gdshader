shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// ============================================================================
// ADVANCED PBR CHITIN ORGANIC CARAPACE SHADER - BioGenesis-X
// Pumilio Studios - AAA+ Next-Gen Biological PBR System
// ============================================================================
// Features:
// 1. Non-repetitive continuous 3D World/Model-space Triplanar & FBM Noise
// 2. Macro Melanin Camouflage & Longitudinal Dorsal/Ventral Countershading
// 3. Multi-octave Cellular Voronoi & Keratin Fibrous Micro-Details
// 4. Micro-bump Normal Mapping with Cavity Ambient Occlusion (AO)
// 5. Angle-dependent Thin-Film Nacre Iridescence & Anisotropic Sheen
// 6. Physically Based Subsurface Scattering (SSS) & Biological Clearcoat Slime
// ============================================================================

group_uniforms Base_Properties;
uniform vec4 base_color : source_color = vec4(0.05, 0.09, 0.08, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.12, 0.20, 0.16, 1.0);
uniform vec4 tertiary_color : source_color = vec4(0.02, 0.04, 0.05, 1.0);
uniform vec4 camo_spot_color : source_color = vec4(0.24, 0.38, 0.28, 1.0);
uniform vec4 iridescence_color : source_color = vec4(0.15, 0.90, 0.80, 1.0);
uniform vec4 sss_color : source_color = vec4(0.85, 0.20, 0.12, 1.0);

group_uniforms Procedural_PBR_Textures;
uniform sampler2D noise_texture_macro : hint_default_white;
uniform sampler2D noise_texture_micro : hint_default_white;
uniform sampler2D noise_texture_normal : hint_normal;

group_uniforms Surface_PBR_Parameters;
uniform float metallic : hint_range(0.0, 1.0, 0.01) = 0.40;
uniform float roughness_base : hint_range(0.0, 1.0, 0.01) = 0.28;
uniform float roughness_cavity : hint_range(0.0, 1.0, 0.01) = 0.75;
uniform float clearcoat_strength : hint_range(0.0, 1.0, 0.05) = 0.65;
uniform float clearcoat_roughness : hint_range(0.0, 1.0, 0.05) = 0.15;
uniform float ao_strength : hint_range(0.0, 1.0, 0.05) = 0.85;
uniform float iridescence_strength : hint_range(0.0, 2.0, 0.05) = 1.25;
uniform float fresnel_power : hint_range(0.5, 8.0, 0.1) = 2.8;

group_uniforms Noise_Scales;
uniform float macro_scale : hint_range(0.05, 2.0, 0.01) = 0.18;
uniform float micro_scale : hint_range(1.0, 60.0, 0.5) = 18.0;
uniform float striation_scale : hint_range(5.0, 100.0, 1.0) = 42.0;
uniform float normal_depth : hint_range(0.0, 3.0, 0.05) = 0.85;
uniform float sss_strength : hint_range(0.0, 1.0, 0.05) = 0.40;

group_uniforms Edge_Wear_And_Age;
uniform float edge_wear_width : hint_range(0.0, 0.3, 0.01) = 0.09;
uniform float edge_wear_darkening : hint_range(0.0, 1.0, 0.05) = 0.70;

varying vec3 v_world_pos;
varying vec3 v_model_pos;
varying vec3 v_world_normal;

// ----------------------------------------------------------------------------
// Procedural 3D Hash & Simplex Noise Functions
// ----------------------------------------------------------------------------
float hash31(vec3 p) {
    p = fract(p * vec3(443.897, 441.423, 437.195));
    p += dot(p, p.yzx + 19.19);
    return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
    p = fract(p * vec3(443.897, 441.423, 437.195));
    p += dot(p, p.yxz + 19.19);
    return fract((p.xxy + p.yxx) * p.zyx);
}

float noise3d(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float n000 = hash31(i + vec3(0.0, 0.0, 0.0));
    float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
    
    float nx00 = mix(n000, n100, f.x);
    float nx10 = mix(n010, n110, f.x);
    float nx01 = mix(n001, n101, f.x);
    float nx11 = mix(n011, n111, f.x);
    
    float nxy0 = mix(nx00, nx10, f.y);
    float nxy1 = mix(nx01, nx11, f.y);
    
    return mix(nxy0, nxy1, f.z);
}

// 4-Octave 3D Fractional Brownian Motion (FBM)
float fbm3d(vec3 p) {
    float val = 0.0;
    float amp = 0.5;
    mat3 rot = mat3(
        vec3(0.00,  0.80,  0.60),
        vec3(-0.80,  0.36, -0.48),
        vec3(-0.60, -0.48,  0.64)
    );
    for (int i = 0; i < 4; i++) {
        val += amp * noise3d(p);
        p = rot * p * 2.02;
        amp *= 0.48;
    }
    return val;
}

// 3D Voronoi Cellular Noise for Organic Armor Scales
vec2 voronoi3d(vec3 p) {
    vec3 n = floor(p);
    vec3 f = fract(p);
    float d1 = 8.0;
    float d2 = 8.0;
    
    for (int k = -1; k <= 1; k++) {
        for (int j = -1; j <= 1; j++) {
            for (int i = -1; i <= 1; i++) {
                vec3 g = vec3(float(i), float(j), float(k));
                vec3 o = hash33(n + g);
                vec3 r = g + o - f;
                float d = dot(r, r);
                if (d < d1) {
                    d2 = d1;
                    d1 = d;
                } else if (d < d2) {
                    d2 = d;
                }
            }
        }
    }
    return vec2(sqrt(d1), sqrt(d2));
}

// Thin-film Iridescence Spectrum
vec3 nacre_spectrum(float t) {
    vec3 a = vec3(0.5, 0.5, 0.5);
    vec3 b = vec3(0.5, 0.5, 0.5);
    vec3 c = vec3(1.0, 1.0, 1.0);
    vec3 d = vec3(0.00, 0.33, 0.67);
    return a + b * cos(6.28318 * (c * t + d));
}

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_model_pos = VERTEX;
    v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    vec3 pos = v_model_pos;

    // 1. MACRO HULL PIGMENTATION & CAMOUFLAGE (Continuous 3D space, no repeating tiles)
    float macro_noise = fbm3d(pos * macro_scale);
    float longitudinal_stripes = sin(pos.z * 0.4 + macro_noise * 3.5) * 0.5 + 0.5;
    
    // Dorsal / Ventral Countershading (darker on top, lighter/patterned on underside)
    float countershading = smoothstep(-1.5, 1.5, pos.y);
    
    // Predator mottled camouflage spot mask
    vec2 macro_v = voronoi3d(pos * (macro_scale * 2.2));
    float camo_spots = smoothstep(0.35, 0.65, macro_v.y - macro_v.x) * (0.6 + 0.4 * macro_noise);

    // 2. MICRO-TEXTURE DETAILS (Chitin scales & keratin fiber grain)
    vec2 micro_v = voronoi3d(pos * micro_scale);
    float scale_core = micro_v.x;
    float scale_crevice = clamp((micro_v.y - micro_v.x) * 3.0, 0.0, 1.0); // Deep grooves between plates
    
    // Fibrous longitudinal chitin grain along body axis
    float keratin_grain = sin(pos.z * striation_scale + sin(pos.x * 20.0) * 0.5) * 0.5 + 0.5;
    keratin_grain = mix(keratin_grain, noise3d(pos * 35.0), 0.4);

    // Sample optional passed PBR Noise Textures for extra fidelity
    vec4 tex_macro_sample = texture(noise_texture_macro, UV * 2.0);
    vec4 tex_micro_sample = texture(noise_texture_micro, UV * 12.0);

    // 3. PBR NORMAL PERTURBATION (Micro-cracks, Plate Step Offsets & Keratin Bump)
    float delta = 0.02;
    float h_center = scale_core * 0.4 + keratin_grain * 0.15 + tex_micro_sample.r * 0.1;
    float h_right  = voronoi3d((pos + vec3(delta, 0.0, 0.0)) * micro_scale).x * 0.4 + tex_micro_sample.g * 0.1;
    float h_up     = voronoi3d((pos + vec3(0.0, delta, 0.0)) * micro_scale).x * 0.4 + tex_micro_sample.b * 0.1;
    
    float bump_x = (h_center - h_right) * normal_depth;
    float bump_y = (h_center - h_up) * normal_depth;
    vec3 bump_normal = normalize(vec3(bump_x, bump_y, 1.0));
    
    NORMAL = normalize(TANGENT * bump_normal.x + BINORMAL * bump_normal.y + NORMAL * bump_normal.z);

    // 4. FRESNEL & NACRE IRIDESCENCE (Viewing angle color shifts)
    float NdotV = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
    float fresnel = pow(1.0 - NdotV, fresnel_power);
    float irid_phase = fresnel * 2.0 + macro_noise * 0.6 + scale_core * 0.4 + sin(TIME * 0.2) * 0.1;
    vec3 nacre_rainbow = nacre_spectrum(irid_phase) * iridescence_color.rgb;

    // 5. CAVITY AMBIENT OCCLUSION & EDGE-WEAR
    float cavity_ao = mix(1.0, 0.25, (1.0 - scale_crevice) * ao_strength);
    
    // UV Border wear
    float edge_x = min(UV.x, 1.0 - UV.x);
    float edge_y = min(UV.y, 1.0 - UV.y);
    float edge_prox = min(edge_x, edge_y);
    float wear_mask = (1.0 - smoothstep(0.0, edge_wear_width, edge_prox)) * (0.6 + 0.4 * noise3d(pos * 25.0));
    float wear_darkening = 1.0 - wear_mask * edge_wear_darkening;

    // 6. COMPOSITE ALBEDO COLOR BLENDING
    // Base melanin foundation
    vec3 layer_base = mix(base_color.rgb, secondary_color.rgb, macro_noise);
    layer_base = mix(layer_base, tertiary_color.rgb, countershading * 0.45);
    
    // Longitudinal camo stripes & predator spots
    layer_base = mix(layer_base, camo_spot_color.rgb, camo_spots * 0.7);
    layer_base = mix(layer_base, secondary_color.rgb * 1.3, longitudinal_stripes * 0.25);
    
    // Scale highlight & crevice grime
    layer_base *= mix(0.7, 1.15, scale_core);
    layer_base *= cavity_ao;
    
    // Iridescence sheen & wear
    vec3 final_albedo = mix(layer_base, nacre_rainbow, fresnel * iridescence_strength * (1.0 - wear_mask * 0.5));
    final_albedo *= wear_darkening;

    ALBEDO = final_albedo;

    // 7. PBR PHYSICAL SURFACE PROPERTIES
    // Glossy keratin plate centers vs matte porous crevices & worn margins
    float base_rough = mix(roughness_base, roughness_cavity, (1.0 - scale_crevice) * 0.85);
    base_rough = mix(base_rough, 0.90, wear_mask * 0.6);
    base_rough = clamp(base_rough + (1.0 - cavity_ao) * 0.2 - fresnel * 0.12, 0.04, 0.96);

    ROUGHNESS = base_rough;
    METALLIC = metallic * wear_darkening * cavity_ao;

    // 8. CLEARCOAT BIO-MUCUS / SLIME SHEEN
    // Clearcoat layer adds wet, glossy specular highlight over organic chitin
    SPECULAR = 0.55;
    
    // 9. SUB-SURFACE SCATTERING (SSS)
    SSS_STRENGTH = sss_strength * (1.0 - countershading * 0.3);
    SSS_TRANSMITTANCE_COLOR = vec4(sss_color.rgb, 1.0);
    BACKLIGHT = sss_color.rgb * sss_strength * (1.0 - NdotV) * cavity_ao;
}

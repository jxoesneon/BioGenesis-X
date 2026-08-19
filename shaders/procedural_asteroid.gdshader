shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ==============================================================================
// procedural_asteroid.gdshader - Principled BSDF Triplanar PBR Asteroid
// ==============================================================================

uniform vec3 base_rock_color : source_color = vec3(0.08, 0.09, 0.11);
uniform vec3 mid_rock_color : source_color = vec3(0.16, 0.18, 0.20);
uniform vec3 highlight_rock_color : source_color = vec3(0.24, 0.26, 0.28);
uniform vec3 bio_crystal_vein_color : source_color = vec3(0.0, 0.92, 0.78);

uniform float triplanar_scale = 0.05;
uniform float triplanar_sharpness = 4.0;

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_roughness : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform float normal_depth = 2.5;
uniform float vein_density = 0.08;
uniform float vein_emission_power = 2.5;

varying vec3 local_pos;
varying vec3 local_norm;

void vertex() {
    local_pos = VERTEX;
    local_norm = NORMAL;
}

// Pseudo-random 3D hash for veins
vec3 hash3(vec3 p) {
    p = vec3(
        dot(p, vec3(127.1, 311.7, 74.7)),
        dot(p, vec3(269.5, 183.3, 246.1)),
        dot(p, vec3(113.5, 271.9, 124.6))
    );
    return fract(sin(p) * 43758.5453123);
}

// 3D Worley Cellular Distance for veins
vec2 worley3D(vec3 p) {
    vec3 id = floor(p);
    vec3 f = fract(p);
    float f1 = 8.0; float f2 = 8.0;
    for (int k = -1; k <= 1; k++) {
        for (int j = -1; j <= 1; j++) {
            for (int i = -1; i <= 1; i++) {
                vec3 g = vec3(float(i), float(j), float(k));
                vec3 o = hash3(id + g);
                vec3 r = g + o - f;
                float d = dot(r, r);
                if (d < f1) {
                    f2 = f1; f1 = d;
                } else if (d < f2) {
                    f2 = d;
                }
            }
        }
    }
    return vec2(sqrt(f1), sqrt(f2));
}

float D_GGX(float NoH, float alpha2) {
    float denom = NoH * NoH * (alpha2 - 1.0) + 1.0;
    return alpha2 / (3.14159265359 * denom * denom + 1e-7);
}

vec4 triplanar_texture(sampler2D p_sampler, vec3 p_weights, vec3 p_pos) {
    vec4 samp = vec4(0.0);
    samp += texture(p_sampler, p_pos.xy) * p_weights.z;
    samp += texture(p_sampler, p_pos.xz) * p_weights.y;
    samp += texture(p_sampler, p_pos.zy * vec2(-1.0, 1.0)) * p_weights.x;
    return samp;
}

float get_vein_height(vec3 pos, float v_density, out float out_vein_raw) {
    vec3 vein_coord = pos * 0.45 + hash3(floor(pos * 0.15)) * 0.5;
    vec2 cell = worley3D(vein_coord);
    float vein_edge = cell.y - cell.x;
    
    float active_vein_envelope = clamp(v_density * 8.0, 0.0, 1.0);
    
    // Raw inverted distance for SSS/Emission masks (1.0 at center, 0.0 at edge 0.15)
    out_vein_raw = clamp(1.0 - (vein_edge / 0.15), 0.0, 1.0) * active_vein_envelope;
    
    float steep_walls = 1.0 - smoothstep(0.04, 0.08, vein_edge);
    float rocky_rim = smoothstep(0.08, 0.11, vein_edge) * smoothstep(0.15, 0.11, vein_edge) * 0.25;
    
    float raw_h = (-steep_walls + rocky_rim) * active_vein_envelope;
    return 0.8 + raw_h * 0.8;
}

void fragment() {
    // 1. Ray direction in LOCAL space for Parallax Raymarching
    vec3 ray_dir = normalize((inverse(MODEL_MATRIX) * inverse(VIEW_MATRIX) * vec4(-VIEW, 0.0)).xyz);
    
    int num_steps = 25;
    float depth_scale = 0.4;
    float step_size = 1.0 / float(num_steps);
    
    vec3 current_pos = local_pos;
    float layer_depth = 0.0;
    float dummy_raw;
    float current_depth_map = 1.0 - get_vein_height(current_pos, vein_density, dummy_raw);
    
    vec3 delta_pos = ray_dir * (step_size * depth_scale);
    float last_depth_map = current_depth_map;
    float last_layer_depth = layer_depth;
    
    for(int i = 0; i < num_steps; i++) {
        if(layer_depth >= current_depth_map) break;
        last_depth_map = current_depth_map;
        last_layer_depth = layer_depth;
        layer_depth += step_size;
        current_pos += delta_pos;
        current_depth_map = 1.0 - get_vein_height(current_pos, vein_density, dummy_raw);
    }
    
    // Parallax Interpolation
    float weight = (layer_depth - current_depth_map) / ((layer_depth - current_depth_map) - (last_layer_depth - last_depth_map));
    vec3 pom_pos = mix(current_pos, current_pos - delta_pos, clamp(weight, 0.0, 1.0));
    
    // 2. Evaluate Vein properties at POM coordinates
    float vein_raw;
    float h0 = get_vein_height(pom_pos, vein_density, vein_raw);
    
    // Multi-Band Masks for Emissive SSS
    float maskCore   = smoothstep(0.85, 0.98, vein_raw);
    float maskDirect = smoothstep(0.60, 0.85, vein_raw);
    float maskSSS    = smoothstep(0.10, 0.60, vein_raw);
    
    // Analytical 3D Normal of procedural heightmap
    float hx = get_vein_height(pom_pos + vec3(0.01, 0.0, 0.0), vein_density, dummy_raw);
    float hy = get_vein_height(pom_pos + vec3(0.0, 0.01, 0.0), vein_density, dummy_raw);
    float hz = get_vein_height(pom_pos + vec3(0.0, 0.0, 0.01), vein_density, dummy_raw);
    vec3 height_grad = vec3(hx - h0, hy - h0, hz - h0) / 0.01;
    
    // 3. Triplanar Weights & Textures
    vec3 blend_weights = pow(abs(local_norm), vec3(triplanar_sharpness));
    blend_weights /= (blend_weights.x + blend_weights.y + blend_weights.z);
    vec3 uv_pos = pom_pos * triplanar_scale;
    
    float rock_noise = triplanar_texture(texture_albedo, blend_weights, uv_pos).r;
    float roughness_map = triplanar_texture(texture_roughness, blend_weights, uv_pos).r;
    
    vec3 normal_x = texture(texture_normal, uv_pos.zy * vec2(-1.0, 1.0)).rgb * 2.0 - 1.0;
    vec3 normal_y = texture(texture_normal, uv_pos.xz).rgb * 2.0 - 1.0;
    vec3 normal_z = texture(texture_normal, uv_pos.xy).rgb * 2.0 - 1.0;
    normal_x.xy *= normal_depth; normal_y.xy *= normal_depth; normal_z.xy *= normal_depth;
    normal_x.x *= sign(local_norm.x); normal_y.x *= sign(local_norm.y); normal_z.x *= sign(local_norm.z);
    
    vec3 tnorm_x = vec3(normal_x.z * sign(local_norm.x), normal_x.y, -normal_x.x);
    vec3 tnorm_y = vec3(normal_y.x, normal_y.z * sign(local_norm.y), normal_y.y);
    vec3 tnorm_z = vec3(normal_z.x, normal_z.y, normal_z.z * sign(local_norm.z));
    
    vec3 blended_local_normal = tnorm_x * blend_weights.x + tnorm_y * blend_weights.y + tnorm_z * blend_weights.z;
    vec3 combined_local_normal = normalize(blended_local_normal - height_grad * 4.0);
    vec3 view_normal = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(combined_local_normal, 0.0)).xyz);
    NORMAL = view_normal;
    
    // 4. Glowing Vein Self-Illumination (Local Tangent Light Projection)
    vec3 base_view_normal = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(local_norm, 0.0)).xyz);
    vec3 dpdx = dFdx(VERTEX);
    vec3 dpdy = dFdy(VERTEX);
    vec3 rx = cross(dpdy, base_view_normal);
    vec3 ry = cross(base_view_normal, dpdx);
    float det = dot(dpdx, rx);
    
    float dvdx = dFdx(vein_raw);
    float dvdy = dFdy(vein_raw);
    vec3 vein_surf_grad = sign(det) * (dvdx * rx + dvdy * ry) / max(abs(det), 1e-8);
    vec3 localLightDirView = normalize(vein_surf_grad + base_view_normal * 0.4);
    
    float localNdotL = max(dot(view_normal, localLightDirView), 0.0);
    float localWrapNdotL = clamp((localNdotL + 0.3) / 1.3, 0.0, 1.0);
    
    // 5. Thermal Vitrification & Roughness
    float baseRockRoughness = roughness_map * 0.8 + 0.2;
    float finalRoughness = mix(baseRockRoughness, 0.12, maskDirect);
    
    // Toksvig Specular Antialiasing
    vec3 dNdx = dFdx(view_normal);
    vec3 dNdy = dFdy(view_normal);
    float normalVariance = dot(dNdx, dNdx) + dot(dNdy, dNdy);
    float alphaEffective = sqrt(finalRoughness * finalRoughness + clamp(normalVariance * 0.5, 0.0, 0.4));
    ROUGHNESS = sqrt(alphaEffective);
    
    // 6. Principled BSDF Composition
    vec3 rock_albedo = mix(base_rock_color, mid_rock_color, smoothstep(0.3, 0.7, rock_noise));
    rock_albedo = mix(rock_albedo, highlight_rock_color, smoothstep(0.7, 1.0, rock_noise));
    ALBEDO = mix(rock_albedo, bio_crystal_vein_color * 0.2, maskCore);
    METALLIC = mix(0.0, 0.75, maskCore);
    
    // 7. Multi-Tier Subsurface Fake Bloom Emission
    vec3 sssDeepColor = bio_crystal_vein_color * vec3(0.8, 0.1, 0.01);
    vec3 directMantleColor = bio_crystal_vein_color * vec3(1.2, 0.4, 0.05);
    vec3 incandescenceColor = vec3(1.5, 1.2, 0.8);
    
    vec3 veinInternalSSS = maskSSS * (1.0 - maskDirect) * localWrapNdotL * sssDeepColor * rock_albedo;
    vec3 veinDirectMantle = maskDirect * (1.0 - maskCore) * directMantleColor;
    vec3 veinCoreIncandescent = maskCore * incandescenceColor;
    
    // Local Specular Glint from Vein on melted rock border
    vec3 V = normalize(-VERTEX);
    vec3 localH = normalize(V + localLightDirView);
    float localD = D_GGX(max(dot(view_normal, localH), 0.0), finalRoughness * finalRoughness);
    vec3 localSpecular = localD * directMantleColor * maskDirect * 0.02;
    
    float pulse = sin(TIME * 1.8 + local_pos.x * 0.5) * 0.3 + 0.7;
    vec3 totalEmissive = (veinCoreIncandescent + veinDirectMantle + veinInternalSSS + localSpecular) * pulse * vein_emission_power * 0.1;
    
    // Cavity Occlusion Inversion: Emissive pools heavily inside crevices
    float cavity = clamp(h0, 0.0, 1.0);
    totalEmissive *= (1.0 + (1.0 - cavity) * 1.5);
    
    EMISSION = totalEmissive;
    
    // 8. AO & Godot 4 Specular Occlusion (Lagarde Formula)
    AO = cavity;
    AO_LIGHT_AFFECT = 0.8; // Darkens direct light inside deep cavities
    
    float NdotV = clamp(dot(view_normal, VIEW), 0.001, 1.0);
    float spec_occlusion = clamp(pow(NdotV + cavity, 2.0) - 1.0 + cavity, 0.0, 1.0);
    
    // Crystal vs Rock F0 Reflectance (Dielectric Specular)
    // Rock F0 = 0.04 (Godot Specular = 0.5)
    // Emissive Crystal F0 = 0.08+ (Godot Specular = 1.0)
    float base_specular = mix(0.5, 1.0, maskCore);
    SPECULAR = base_specular * spec_occlusion;
}

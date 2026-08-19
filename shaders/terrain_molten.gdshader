shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// ============================================================================
// BIOGENESIS-X — ARCHETYPE 0: MOLTEN / VOLCANIC TERRAIN SURFACE SHADER
// ----------------------------------------------------------------------------
// Glowing lava cracks (emissive orange/red in crevices), black basalt rock,
// heat distortion shimmer, and animated lava flow in low-elevation basins.
// Fully procedural — no external textures required.
// ============================================================================

group_uniforms Elevation;
uniform float elevation_min = -8000.0;       // World Y at sea-level reference
uniform float elevation_max = 8000.0;        // World Y at mountain peaks
uniform float displacement_strength : hint_range(0.0, 2.0, 0.01) = 0.15;
uniform sampler2D elevation_data : hint_default_white; // Optional vertex-color / mask

group_uniforms Lighting;
uniform vec3 sun_direction = vec3(0.35, 0.85, 0.4);
uniform vec4 sun_color : source_color = vec4(1.0, 0.78, 0.45, 1.0);
uniform float time = 0.0;

group_uniforms Lava;
uniform vec4 lava_color_hot : source_color = vec4(1.0, 0.45, 0.05, 1.0);
uniform vec4 lava_color_cool : source_color = vec4(0.85, 0.18, 0.02, 1.0);
uniform vec4 basalt_color : source_color = vec4(0.04, 0.03, 0.03, 1.0);
uniform float lava_flow_speed : hint_range(0.0, 1.0, 0.01) = 0.08;
uniform float lava_crack_scale : hint_range(1.0, 40.0, 0.5) = 8.0;
uniform float lava_crack_threshold : hint_range(0.0, 1.0, 0.01) = 0.46;
uniform float lava_emission_strength : hint_range(0.0, 12.0, 0.1) = 4.5;
uniform float heat_shimmer : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float low_elevation_lava : hint_range(0.0, 1.0, 0.01) = 0.55; // Lava fills basins

varying vec3 v_world_pos;
varying vec3 v_normal_w;
varying float v_elevation;
varying vec2 v_flow_uv;

// ----------------------------------------------------------------------------
// Procedural hash & 3D value noise
// ----------------------------------------------------------------------------
float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise3(vec3 x) {
	vec3 p = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(p + vec3(0, 0, 0)), hash3(p + vec3(1, 0, 0)), f.x),
			mix(hash3(p + vec3(0, 1, 0)), hash3(p + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(p + vec3(0, 0, 1)), hash3(p + vec3(1, 0, 1)), f.x),
			mix(hash3(p + vec3(0, 1, 1)), hash3(p + vec3(1, 1, 1)), f.x), f.y),
		f.z
	);
}

float fbm3(vec3 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	mat3 rot = mat3(
		vec3(0.00, 0.80, 0.60),
		vec3(-0.80, 0.36, -0.48),
		vec3(-0.60, -0.48, 0.64)
	);
	for (int i = 0; i < oct; i++) {
		v += a * vnoise3(p);
		p = rot * p * 2.02;
		a *= 0.5;
	}
	return v;
}

float ridge3(vec3 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < oct; i++) {
		float n = 1.0 - abs(vnoise3(p) * 2.0 - 1.0);
		v += a * n * n;
		p *= 2.08;
		a *= 0.48;
	}
	return v;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal_w = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// Elevation from optional elevation_data sampler (vertex color / mask), else
	// fall back to local Y normalized into [0,1].
	float elev_tex = texture(elevation_data, UV).r;
	bool has_tex = elev_tex > 0.001 && abs(elev_tex - 1.0) > 0.001;
	v_elevation = has_tex ? elev_tex : clamp((VERTEX.y - elevation_min) / max(elevation_max - elevation_min, 0.001), 0.0, 1.0);

	// Animated lava-flow UV: scrolls downhill along the tangent XZ gradient.
	v_flow_uv = UV + vec2(time * lava_flow_speed, 0.0);

	// Subtle heat-driven vertex ripple on low-elevation (lava) areas.
	float low_mask = smoothstep(low_elevation_lava, low_elevation_lava + 0.15, 1.0 - v_elevation);
	float shimmer = sin(time * 3.0 + v_world_pos.x * 0.5 + v_world_pos.z * 0.5) * 0.5 + 0.5;
	VERTEX.y += low_mask * shimmer * displacement_strength * heat_shimmer;
}

void fragment() {
	vec3 N = normalize(v_normal_w);
	vec3 V = normalize(VIEW);
	vec3 L = normalize(sun_direction);

	// --- Crevass / crack mask: ridge noise produces sharp fissure networks ---
	float crack = ridge3(vec3(UV * lava_crack_scale, time * lava_flow_speed * 0.25), 5);
	float crack_mask = smoothstep(lava_crack_threshold, lava_crack_threshold + 0.06, crack);

	// --- Low-elevation lava basins: animated flowing lava ---
	float basin = smoothstep(low_elevation_lava, low_elevation_lava + 0.20, 1.0 - v_elevation);
	float flow_n = fbm3(vec3(v_flow_uv * 6.0, 0.0), 4);
	float lava_flow = smoothstep(0.40, 0.62, flow_n);
	float lava_mask = clamp(basin * 0.7 + crack_mask * 0.85, 0.0, 1.0);

	// --- Basalt rock surface ---
	float rock_grain = vnoise3(vec3(UV * 28.0, 0.0)) * 0.08;
	vec3 basalt = basalt_color.rgb + rock_grain;
	float roughness_out = 0.82;

	// --- Lava color (hot -> cool gradient by flow noise) ---
	vec3 lava_rgb = mix(lava_color_cool.rgb, lava_color_hot.rgb, lava_flow);
	// Brighten where cracks are hottest (interior of fissures).
	float heat_pulse = 0.85 + 0.15 * sin(time * 2.0 + flow_n * 8.0);
	lava_rgb *= heat_pulse;

	// --- Composite albedo ---
	vec3 albedo_out = mix(basalt, lava_rgb, lava_mask);

	// --- Emission: glowing lava in cracks and basins ---
	float emit = lava_mask * lava_emission_strength;
	// Extra glow deep in crevices (low elevation + crack).
	float crevice_glow = crack_mask * (1.0 - v_elevation) * lava_emission_strength * 0.6;
	vec3 emission_out = lava_color_hot.rgb * (emit + crevice_glow);

	// --- Heat distortion shimmer: subtle view-dependent wobble of albedo ---
	float shimmer_amt = heat_shimmer * basin * (0.5 + 0.5 * sin(time * 4.0 + v_world_pos.x * 0.3));
	albedo_out += lava_color_hot.rgb * shimmer_amt * 0.08;

	// --- Sun lighting (Lambert + warm specular) ---
	float NdotL = clamp(dot(N, L), 0.0, 1.0);
	vec3 H = normalize(L + V);
	float NdotH = clamp(dot(N, H), 0.0, 1.0);
	float spec = pow(NdotH, 32.0) * 0.25 * NdotL;
	albedo_out *= (0.25 + 0.75 * NdotL);
	albedo_out += sun_color.rgb * spec;

	// Darken basalt where unlit (volcanic night side stays dark except lava).
	albedo_out = mix(albedo_out, basalt * 0.4, (1.0 - NdotL) * (1.0 - lava_mask) * 0.5);

	ALBEDO = albedo_out;
	ROUGHNESS = mix(roughness_out, 0.15, lava_mask);
	METALLIC = 0.0;
	EMISSION = emission_out;
	NORMAL_MAP = vec3(0.5, 0.5, 1.0);
}

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// ============================================================================
// BIOGENESIS-X — ARCHETYPE 5: GAS GIANT JOVIAN SURFACE SHADER (Jupiter-like)
// ----------------------------------------------------------------------------
// Horizontal turbulent banded stripes, Great Red Spot analog (procedural storm),
// swirling vortex patterns. Applied to a sphere shell (no solid surface).
// Orange/cream/brown palette. Fully procedural — no external textures required.
// ============================================================================

group_uniforms Lighting;
uniform vec3 sun_direction = vec3(0.35, 0.85, 0.4);
uniform vec4 sun_color : source_color = vec4(1.0, 0.92, 0.78, 1.0);
uniform vec3 camera_position = vec3(0.0, 0.0, 0.0);
uniform float time = 0.0;

group_uniforms Bands;
uniform vec4 band_color_amber : source_color = vec4(0.82, 0.52, 0.22, 1.0);
uniform vec4 band_color_ivory : source_color = vec4(0.92, 0.86, 0.70, 1.0);
uniform vec4 band_color_terracotta : source_color = vec4(0.68, 0.30, 0.15, 1.0);
uniform float band_frequency : hint_range(2.0, 80.0, 0.5) = 38.0;
uniform float band_turbulence : hint_range(0.0, 8.0, 0.1) = 5.0;
uniform float band_speed : hint_range(0.0, 0.2, 0.005) = 0.015;

group_uniforms Storm;
uniform vec3 storm_center = vec3(1.0, -0.35, 0.5);
uniform float storm_radius : hint_range(0.05, 0.6, 0.01) = 0.28;
uniform vec4 storm_color_core : source_color = vec4(0.98, 0.45, 0.25, 1.0);
uniform vec4 storm_color_ring : source_color = vec4(0.85, 0.22, 0.12, 1.0);
uniform float storm_swirl_speed : hint_range(0.0, 0.5, 0.005) = 0.08;
uniform float storm_intensity : hint_range(0.0, 2.0, 0.05) = 1.0;

group_uniforms Displacement;
uniform float displacement_strength : hint_range(0.0, 0.5, 0.005) = 0.02;

varying vec3 v_world_pos;
varying vec3 v_normal_w;
varying vec3 v_local_pos;

// ----------------------------------------------------------------------------
// Procedural hash & 3D noise
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

// Cyclonic swirl: rotate sample around storm center by angle proportional to radius.
vec2 cyclonic_uv(vec2 q, float radius_frac) {
	float angle = (1.0 - radius_frac) * 6.2831 * 1.5 + time * storm_swirl_speed;
	float s = sin(angle);
	float c = cos(angle);
	return vec2(q.x * c - q.y * s, q.x * s + q.y * c);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal_w = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_local_pos = normalize(VERTEX);

	// Subtle band-driven bulge: stripes undulate along latitude.
	float band_wave = sin(v_local_pos.y * band_frequency * 0.5 + time * band_speed * 10.0);
	VERTEX += NORMAL * band_wave * displacement_strength;
}

void fragment() {
	vec3 N = normalize(v_normal_w);
	vec3 V = normalize(camera_position - v_world_pos);
	vec3 L = normalize(sun_direction);
	vec3 p = normalize(v_local_pos);

	// --- Latitudinal jet-stream turbulence ---
	float jet = fbm3(vec3(p.x * 2.5, p.y * 18.0, p.z * 2.5) + vec3(time * band_speed, 0.0, 0.0), 5);
	float latitude_bands = sin(p.y * band_frequency + jet * band_turbulence);
	float band_fac = (latitude_bands + 1.0) * 0.5;

	// --- Base banded albedo ---
	vec3 albedo_out = mix(band_color_amber.rgb, band_color_ivory.rgb, band_fac);
	// Terracotta storm-vortex tint blended by turbulence
	float storm_vortices = fbm3(vec3(p.x * 8.0 + time * band_speed, p.y * 16.0, p.z * 8.0), 5);
	albedo_out = mix(albedo_out, band_color_terracotta.rgb, storm_vortices * 0.55);

	// --- Great Red Spot analog (procedural cyclonic storm) ---
	vec3 sc = normalize(storm_center);
	float dist_to_storm = length(p - sc);
	if (dist_to_storm < storm_radius) {
		float radius_frac = dist_to_storm / storm_radius;
		// Project into storm-local 2D plane (tangent basis around sc).
		vec3 tangent1 = normalize(cross(sc, vec3(0.0, 1.0, 0.0) + vec3(0.001)));
		vec3 tangent2 = cross(sc, tangent1);
		vec2 plane = vec2(dot(p - sc, tangent1), dot(p - sc, tangent2));
		vec2 swirl_uv = cyclonic_uv(plane, radius_frac);
		float swirl_n = vnoise3(vec3(swirl_uv * 24.0, time * storm_swirl_speed));
		float spot_intensity = smoothstep(storm_radius, 0.05, dist_to_storm) * storm_intensity;
		vec3 spot_color = mix(storm_color_ring.rgb, storm_color_core.rgb, swirl_n);
		// Spiral arm modulation
		float arms = sin(atan(swirl_uv.y, swirl_uv.x) * 3.0 + radius_frac * 8.0);
		spot_color *= (0.8 + 0.2 * arms);
		albedo_out = mix(albedo_out, spot_color, spot_intensity);
	}

	// --- Swirling vortex patterns (smaller eddies) ---
	float eddy = fbm3(vec3(p * 12.0 + vec3(time * band_speed * 2.0, 0.0, 0.0)), 4);
	albedo_out = mix(albedo_out, band_color_ivory.rgb * 0.9, smoothstep(0.6, 0.85, eddy) * 0.25);

	// --- Lighting ---
	float NdotL = clamp(dot(N, L), 0.0, 1.0);
	float NdotV = clamp(dot(N, V), 0.0, 1.0);
	vec3 H = normalize(L + V);
	float NdotH = clamp(dot(N, H), 0.0, 1.0);
	float spec = pow(NdotH, 48.0) * 0.25 * NdotL;

	// Limb darkening (gas giant atmosphere gets darker at edge)
	float limb = pow(NdotV, 0.6);
	albedo_out *= (0.25 + 0.75 * NdotL) * limb;
	albedo_out += sun_color.rgb * spec;

	// Warm fresnel limb glow
	float fres = pow(1.0 - NdotV, 4.0);
	albedo_out += band_color_terracotta.rgb * fres * 0.25 * NdotL;

	ALBEDO = albedo_out;
	ROUGHNESS = 0.55;
	METALLIC = 0.0;
	EMISSION = vec3(0.0);
	NORMAL_MAP = vec3(0.5, 0.5, 1.0);
}

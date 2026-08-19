shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// ============================================================================
// BIOGENESIS-X — ARCHETYPE 6: GAS GIANT ICE SURFACE SHADER (Neptune-like)
// ----------------------------------------------------------------------------
// Horizontal banded stripes (less turbulent than Jovian), methane blue /
// turquoise palette, white cloud streaks, dark spots. Applied to a sphere
// shell (no solid surface). Fully procedural — no external textures required.
// ============================================================================

group_uniforms Lighting;
uniform vec3 sun_direction = vec3(0.35, 0.85, 0.4);
uniform vec4 sun_color : source_color = vec4(0.95, 1.0, 0.98, 1.0);
uniform vec3 camera_position = vec3(0.0, 0.0, 0.0);
uniform float time = 0.0;

group_uniforms Bands;
uniform vec4 band_color_azure : source_color = vec4(0.12, 0.42, 0.88, 1.0);
uniform vec4 band_color_cyan : source_color = vec4(0.32, 0.78, 0.98, 1.0);
uniform vec4 cloud_streak_color : source_color = vec4(0.94, 0.98, 1.0, 1.0);
uniform float band_frequency : hint_range(2.0, 80.0, 0.5) = 30.0;
uniform float band_turbulence : hint_range(0.0, 8.0, 0.1) = 3.0; // less turbulent
uniform float band_speed : hint_range(0.0, 0.2, 0.005) = 0.012;
uniform float cloud_streak_density : hint_range(0.0, 1.0, 0.01) = 0.55;

group_uniforms Dark_Spot;
uniform vec3 dark_spot_center = vec3(-0.8, 0.25, 0.45);
uniform float dark_spot_radius : hint_range(0.05, 0.6, 0.01) = 0.22;
uniform vec4 dark_spot_color : source_color = vec4(0.02, 0.08, 0.28, 1.0);
uniform float dark_spot_intensity : hint_range(0.0, 1.0, 0.01) = 0.85;

group_uniforms Displacement;
uniform float displacement_strength : hint_range(0.0, 0.5, 0.005) = 0.015;

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

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal_w = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_local_pos = normalize(VERTEX);

	// Gentle latitude-driven bulge.
	float band_wave = sin(v_local_pos.y * band_frequency * 0.5 + time * band_speed * 10.0);
	VERTEX += NORMAL * band_wave * displacement_strength;
}

void fragment() {
	vec3 N = normalize(v_normal_w);
	vec3 V = normalize(camera_position - v_world_pos);
	vec3 L = normalize(sun_direction);
	vec3 p = normalize(v_local_pos);

	// --- Latitudinal bands (less turbulent than Jovian) ---
	float jet = fbm3(vec3(p.x * 2.5, p.y * 14.0, p.z * 2.5) + vec3(time * band_speed, 0.0, 0.0), 4);
	float latitude_bands = sin(p.y * band_frequency + jet * band_turbulence);
	float band_fac = (latitude_bands + 1.0) * 0.5;

	vec3 albedo_out = mix(band_color_azure.rgb, band_color_cyan.rgb, band_fac);

	// --- White cloud streaks (methane cirrus) ---
	vec3 streak_pos = vec3(p.x * 6.0 + time * band_speed * 1.5, p.y * 10.0, p.z * 6.0);
	float streak_n = fbm3(streak_pos, 5);
	float streaks = smoothstep(1.0 - cloud_streak_density, 1.0, streak_n);
	// Streaks elongated along latitude (horizontal)
	float streak_elong = fbm3(vec3(p.x * 20.0, p.y * 4.0, p.z * 20.0), 3);
	streaks *= smoothstep(0.4, 0.7, streak_elong);
	albedo_out = mix(albedo_out, cloud_streak_color.rgb, streaks * 0.75);

	// --- Dark spot (Great Dark Spot analog) ---
	vec3 dc = normalize(dark_spot_center);
	float dist_to_spot = length(p - dc);
	if (dist_to_spot < dark_spot_radius) {
		float spot_intensity = smoothstep(dark_spot_radius, 0.05, dist_to_spot) * dark_spot_intensity;
		// Subtle swirl inside the dark spot
		vec3 tangent1 = normalize(cross(dc, vec3(0.0, 1.0, 0.0) + vec3(0.001)));
		vec3 tangent2 = cross(dc, tangent1);
		vec2 plane = vec2(dot(p - dc, tangent1), dot(p - dc, tangent2));
		float angle = time * 0.04;
		float s = sin(angle); float c = cos(angle);
		plane = vec2(plane.x * c - plane.y * s, plane.x * s + plane.y * c);
		float swirl = vnoise3(vec3(plane * 18.0, 0.0));
		vec3 spot_col = mix(dark_spot_color.rgb, dark_spot_color.rgb * 1.4, swirl);
		albedo_out = mix(albedo_out, spot_col, spot_intensity);
	}

	// --- Smaller dark vortices ---
	float vortex = fbm3(vec3(p * 9.0 + vec3(time * band_speed * 1.2, 0.0, 0.0)), 4);
	albedo_out = mix(albedo_out, band_color_azure.rgb * 0.5, smoothstep(0.7, 0.9, vortex) * 0.20);

	// --- Lighting ---
	float NdotL = clamp(dot(N, L), 0.0, 1.0);
	float NdotV = clamp(dot(N, V), 0.0, 1.0);
	vec3 H = normalize(L + V);
	float NdotH = clamp(dot(N, H), 0.0, 1.0);
	float spec = pow(NdotH, 56.0) * 0.22 * NdotL;

	// Limb darkening
	float limb = pow(NdotV, 0.6);
	albedo_out *= (0.28 + 0.72 * NdotL) * limb;
	albedo_out += sun_color.rgb * spec;

	// Cool fresnel limb glow
	float fres = pow(1.0 - NdotV, 4.0);
	albedo_out += band_color_cyan.rgb * fres * 0.30 * NdotL;

	ALBEDO = albedo_out;
	ROUGHNESS = 0.50;
	METALLIC = 0.0;
	EMISSION = vec3(0.0);
	NORMAL_MAP = vec3(0.5, 0.5, 1.0);
}

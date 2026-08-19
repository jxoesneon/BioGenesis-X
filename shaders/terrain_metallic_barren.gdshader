shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// ============================================================================
// BIOGENESIS-X — ARCHETYPE 1: METALLIC BARREN TERRAIN SURFACE SHADER
// ----------------------------------------------------------------------------
// Cratered metallic world: high-specular metallic sheen, impact crater patterns
// (dark centers, bright rims), gray/silver palette. No vegetation, no water.
// Fully procedural — no external textures required.
// ============================================================================

group_uniforms Elevation;
uniform float elevation_min = -8000.0;
uniform float elevation_max = 8000.0;
uniform float displacement_strength : hint_range(0.0, 2.0, 0.01) = 0.05;

group_uniforms Lighting;
uniform vec3 sun_direction = vec3(0.35, 0.85, 0.4);
uniform vec4 sun_color : source_color = vec4(1.0, 0.96, 0.92, 1.0);
uniform float time = 0.0;

group_uniforms Surface;
uniform vec4 metal_color_base : source_color = vec4(0.32, 0.30, 0.28, 1.0);
uniform vec4 metal_color_bright : source_color = vec4(0.62, 0.60, 0.56, 1.0);
uniform vec4 crater_rim_color : source_color = vec4(0.78, 0.76, 0.72, 1.0);
uniform float crater_scale_macro : hint_range(1.0, 40.0, 0.5) = 5.0;
uniform float crater_scale_micro : hint_range(5.0, 80.0, 0.5) = 24.0;
uniform float metallic_intensity : hint_range(0.0, 1.0, 0.01) = 0.55;
uniform float specular_sharpness : hint_range(1.0, 256.0, 1.0) = 64.0;
uniform float specular_intensity : hint_range(0.0, 4.0, 0.05) = 1.4;

varying vec3 v_world_pos;
varying vec3 v_normal_w;
varying float v_elevation;

// ----------------------------------------------------------------------------
// Procedural hash & 3D value noise + Worley (crater) noise
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

// Worley-style crater field: returns distance-to-nearest-cell feature.
// Produces ring patterns: dark center, bright raised rim.
float crater_field(vec2 uv, float scale) {
	vec2 g = uv * scale;
	vec2 i = floor(g);
	vec2 f = fract(g);
	float min_d = 8.0;
	float second_d = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 cell = vec2(float(x), float(y));
			vec2 h = vec2(hash3(vec3(i + cell, 0.0)), hash3(vec3(i + cell, 1.0)));
			h = 0.5 + 0.5 * sin(h * 6.2831);
			vec2 diff = cell + h - f;
			float d = dot(diff, diff);
			if (d < min_d) {
				second_d = min_d;
				min_d = d;
			} else if (d < second_d) {
				second_d = d;
			}
		}
	}
	return sqrt(min_d);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal_w = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_elevation = clamp((VERTEX.y - elevation_min) / max(elevation_max - elevation_min, 0.001), 0.0, 1.0);

	// Tiny micro-displacement for crater rims (parallax hint).
	float rim = crater_field(UV, crater_scale_macro);
	VERTEX.y += smoothstep(0.35, 0.5, rim) * displacement_strength;
}

void fragment() {
	vec3 N = normalize(v_normal_w);
	vec3 V = normalize(VIEW);
	vec3 L = normalize(sun_direction);

	// --- Macro & micro crater fields ---
	float d_macro = crater_field(UV, crater_scale_macro);
	float d_micro = crater_field(UV + 13.37, crater_scale_micro);

	// Crater profile: dark interior center, bright raised rim.
	// distance ~0 => center, ~0.5 => rim, >0.7 => ejecta/plain.
	float center = smoothstep(0.18, 0.0, d_macro);          // dark basin
	float rim = smoothstep(0.30, 0.45, d_macro) * (1.0 - smoothstep(0.45, 0.60, d_macro)); // bright rim
	float ejecta = smoothstep(0.60, 0.85, d_macro) * 0.15;

	// --- Base metallic albedo ---
	float grain = fbm3(vec3(UV * 18.0, 0.0), 4);
	vec3 base = mix(metal_color_base.rgb, metal_color_bright.rgb, grain);
	// Apply crater shading
	base = mix(base, metal_color_base.rgb * 0.35, center);          // dark crater floor
	base = mix(base, crater_rim_color.rgb, rim);                     // bright rim
	base += ejecta * metal_color_bright.rgb;

	// Micro craters add fine pitting
	float micro_pit = smoothstep(0.20, 0.0, d_micro) * 0.12;
	base *= (1.0 - micro_pit);

	// --- Metallic specular (high, sharp) ---
	vec3 H = normalize(L + V);
	float NdotH = clamp(dot(N, H), 0.0, 1.0);
	float NdotL = clamp(dot(N, L), 0.0, 1.0);
	float NdotV = clamp(dot(N, V), 0.0, 1.0);
	float spec = pow(NdotH, specular_sharpness) * specular_intensity * NdotL;

	// Fresnel metallic edge sheen
	float fres = pow(1.0 - NdotV, 4.0) * 0.4;
	vec3 albedo_out = base * (0.18 + 0.82 * NdotL);
	albedo_out += sun_color.rgb * spec;
	albedo_out += metal_color_bright.rgb * fres * NdotL;

	// Subtle anisotropic streak from micro-crater alignment
	float streak = sin(UV.x * 80.0 + grain * 6.0) * 0.5 + 0.5;
	albedo_out += sun_color.rgb * pow(streak, 12.0) * spec * 0.25;

	ALBEDO = albedo_out;
	ROUGHNESS = mix(0.55, 0.18, rim);   // rims are polished bright, floors rough
	METALLIC = metallic_intensity;
	EMISSION = vec3(0.0);
	NORMAL_MAP = vec3(0.5, 0.5, 1.0);
}

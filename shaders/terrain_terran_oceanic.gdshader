shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// ============================================================================
// BIOGENESIS-X — ARCHETYPE 3: TERRAN OCEANIC TERRAIN SURFACE SHADER
// ----------------------------------------------------------------------------
// Earth-like multi-biome terrain driven by altitude + moisture:
//   below sea level -> underwater blue, beach -> sand, lowland -> green grass,
//   highland -> darker green/brown, mountain -> gray rock, snow cap -> white.
// Vegetation color variation. Fully procedural — no external textures required.
// ============================================================================

group_uniforms Elevation;
uniform float elevation_min = -8000.0;
uniform float elevation_max = 8000.0;
uniform float displacement_strength : hint_range(0.0, 2.0, 0.01) = 0.10;
uniform sampler2D moisture_data : hint_default_white; // Optional moisture mask

group_uniforms Lighting;
uniform vec3 sun_direction = vec3(0.35, 0.85, 0.4);
uniform vec4 sun_color : source_color = vec4(1.0, 0.95, 0.82, 1.0);
uniform float time = 0.0;

group_uniforms Biome;
uniform float sea_level : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform vec4 water_color_shallow : source_color = vec4(0.10, 0.42, 0.62, 1.0);
uniform vec4 water_color_deep : source_color = vec4(0.01, 0.08, 0.22, 1.0);
uniform vec4 sand_color : source_color = vec4(0.85, 0.78, 0.55, 1.0);
uniform vec4 grass_color : source_color = vec4(0.18, 0.55, 0.20, 1.0);
uniform vec4 forest_color : source_color = vec4(0.08, 0.32, 0.12, 1.0);
uniform vec4 highland_color : source_color = vec4(0.30, 0.34, 0.18, 1.0);
uniform vec4 rock_color : source_color = vec4(0.42, 0.38, 0.35, 1.0);
uniform vec4 snow_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform float snow_line : hint_range(0.0, 1.0, 0.01) = 0.78;
uniform float vegetation_variation : hint_range(0.0, 1.0, 0.01) = 0.4;

varying vec3 v_world_pos;
varying vec3 v_normal_w;
varying float v_elevation;
varying float v_moisture;

// ----------------------------------------------------------------------------
// Procedural hash & noise
// ----------------------------------------------------------------------------
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm2(vec2 p, int oct) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < oct; i++) {
		v += a * vnoise2(p);
		p = (p + vec2(3.1, 7.7)) * 2.03;
		a *= 0.5;
	}
	return v;
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
	v_elevation = clamp((VERTEX.y - elevation_min) / max(elevation_max - elevation_min, 0.001), 0.0, 1.0);

	// Moisture from optional sampler, else procedural.
	float m_tex = texture(moisture_data, UV).r;
	bool has_m = m_tex > 0.001 && abs(m_tex - 1.0) > 0.001;
	v_moisture = has_m ? m_tex : fbm2(UV * 4.0 + vec2(1.5, 2.7), 4);

	// Gentle vegetation / dune micro-displacement on land.
	float land = smoothstep(sea_level, sea_level + 0.05, v_elevation);
	VERTEX.y += sin(dot(UV, vec2(80.0))) * displacement_strength * land * 0.25;
}

void fragment() {
	vec3 N = normalize(v_normal_w);
	vec3 V = normalize(VIEW);
	vec3 L = normalize(sun_direction);

	float elev = v_elevation;
	float moisture = v_moisture;

	vec3 albedo_out = vec3(0.0);
	float roughness_out = 0.85;
	float metallic_out = 0.0;

	if (elev < sea_level) {
		// --- Underwater: depth gradient shallow -> deep ---
		float depth = clamp(elev / max(sea_level, 0.001), 0.0, 1.0);
		vec3 water = mix(water_color_deep.rgb, water_color_shallow.rgb, depth);
		// Animated wave caustics
		float caustic = fbm2(UV * 12.0 + vec2(time * 0.05, time * 0.03), 4);
		water += (caustic - 0.5) * 0.08;
		// Coastal foam near shoreline
		float foam = smoothstep(sea_level - 0.03, sea_level, elev) * smoothstep(0.5, 0.7, fbm2(UV * 30.0, 3));
		water = mix(water, vec3(0.92, 0.96, 1.0), foam * 0.6);
		albedo_out = water;
		roughness_out = mix(0.08, 0.35, foam);
		metallic_out = 0.05;
	} else {
		float land_norm = (elev - sea_level) / max(1.0 - sea_level, 0.001);

		// Beach sand near shoreline
		if (land_norm < 0.06) {
			float sand_n = vnoise2(UV * 40.0);
			albedo_out = sand_color.rgb + (sand_n - 0.5) * 0.08;
			roughness_out = 0.78;
		}
		// Lowland: grass / forest by moisture
		else if (land_norm < 0.45) {
			float veg = fbm2(UV * 8.0, 4);
			vec3 grass = mix(grass_color.rgb, forest_color.rgb, moisture * vegetation_variation);
			// Vegetation color variation patches
			grass = mix(grass, grass * 1.15, smoothstep(0.5, 0.7, veg));
			grass = mix(grass, grass * 0.85, smoothstep(0.3, 0.5, veg));
			albedo_out = grass;
			roughness_out = 0.82;
		}
		// Highland: darker green/brown transition
		else if (land_norm < 0.70) {
			float rock_mix = smoothstep(0.45, 0.70, land_norm);
			vec3 highland = mix(highland_color.rgb, rock_color.rgb, rock_mix);
			highland *= (0.85 + 0.15 * fbm2(UV * 20.0, 3));
			albedo_out = highland;
			roughness_out = 0.70;
		}
		// Mountain: gray rock
		else {
			float rock_n = fbm2(UV * 24.0, 4);
			albedo_out = mix(rock_color.rgb, rock_color.rgb * 1.2, rock_n);
			roughness_out = 0.55;
		}

		// Snow caps above snow line (modulated by slope: snow sticks to flats)
		if (land_norm > snow_line - 0.1) {
			float slope = 1.0 - clamp(N.y, 0.0, 1.0); // steep => less snow
			float snow_amt = smoothstep(snow_line - 0.05, snow_line + 0.05, land_norm) * (1.0 - slope * 0.6);
			float snow_n = fbm2(UV * 18.0, 3);
			vec3 snow = snow_color.rgb * (0.92 + 0.08 * snow_n);
			albedo_out = mix(albedo_out, snow, snow_amt);
			roughness_out = mix(roughness_out, 0.30, snow_amt);
		}
	}

	// --- Sun lighting ---
	float NdotL = clamp(dot(N, L), 0.0, 1.0);
	vec3 H = normalize(L + V);
	float NdotH = clamp(dot(N, H), 0.0, 1.0);
	float spec = pow(NdotH, 48.0) * 0.20 * NdotL;
	albedo_out *= (0.30 + 0.70 * NdotL);
	albedo_out += sun_color.rgb * spec;

	// Polar ice caps by latitude (using world Y as pole proxy on a sphere shell)
	float latitude = abs(normalize(v_world_pos).y);
	float polar = smoothstep(0.80, 0.92, latitude);
	albedo_out = mix(albedo_out, snow_color.rgb * 0.95, polar * 0.8);
	roughness_out = mix(roughness_out, 0.25, polar);

	ALBEDO = albedo_out;
	ROUGHNESS = roughness_out;
	METALLIC = metallic_out;
	EMISSION = vec3(0.0);
	NORMAL_MAP = vec3(0.5, 0.5, 1.0);
}

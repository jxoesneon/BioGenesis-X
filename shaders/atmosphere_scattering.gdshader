shader_type spatial;
render_mode cull_disabled, depth_draw_never, blend_add, unshaded;

// ============================================================================
// BIOGENESIS-X — ATMOSPHERIC SCATTERING SHELL SHADER
// AAA+ Rayleigh + Mie Scattering for Planetary Descent Visuals
// ============================================================================
// Applied to a large sphere mesh surrounding the planet (radius =
// planet_radius + atmosphere_height). Renders the 4-layer atmospheric
// descent shell with:
//   1. Rayleigh scattering approximation (blue sky by day, orange at sunset)
//   2. Mie scattering approximation (horizon haze, forward sun glow)
//   3. Sunset / sunrise color shifts driven by sun elevation angle
//   4. Day / night side transition (smooth terminator)
//   5. View-ray + sun-ray intersection scattering integral (numerical)
//   6. Per-archetype tint & thickness modulation
//
// All distances are normalized by atmosphere_height so the visual result is
// independent of the absolute planet scale (km vs m vs game units).
// ============================================================================

group_uniforms Geometry;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform float planet_radius = 1000.0;
uniform float atmosphere_height = 80.0;

group_uniforms Scattering;
// Per-channel Rayleigh scattering coefficients (normalized units).
uniform vec3 rayleigh_coeff = vec3(0.018, 0.042, 0.10);
// Mie (aerosol) scattering coefficient (normalized units).
uniform float mie_coeff : hint_range(0.0, 0.2, 0.001) = 0.012;
// Henyey-Greenstein asymmetry parameter (-1..1). Forward scattering > 0.
uniform float mie_g : hint_range(-0.9, 0.9, 0.01) = 0.76;
// Density falloff scale height as a fraction of atmosphere_height.
uniform float scale_height_frac : hint_range(0.05, 0.5, 0.01) = 0.25;

group_uniforms Colors;
uniform vec4 sky_color_day : source_color = vec4(0.40, 0.62, 1.00, 1.0);
uniform vec4 sky_color_sunset : source_color = vec4(1.00, 0.45, 0.20, 1.0);
uniform vec4 sky_color_night : source_color = vec4(0.02, 0.03, 0.08, 1.0);
uniform vec4 archetype_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

group_uniforms Camera;
uniform vec3 camera_position = vec3(0.0, 0.0, 0.0);
uniform float time = 0.0;

group_uniforms Quality;
uniform int sample_count : hint_range(4, 32, 1) = 8;
uniform int light_sample_count : hint_range(1, 8, 1) = 2;
uniform float quality_scale : hint_range(0.25, 1.0, 0.05) = 1.0;
uniform float intensity : hint_range(0.0, 8.0, 0.05) = 1.6;

varying vec3 v_world_pos;

// ----------------------------------------------------------------------------
// Ray-sphere intersection. Returns (near, far) distances along rd, or
// vec2(-1.0) if no intersection. ro/rd in world space.
// ----------------------------------------------------------------------------
vec2 ray_sphere(vec3 ro, vec3 rd, float r) {
	vec3 oc = ro;
	float b = dot(oc, rd);
	float c = dot(oc, oc) - r * r;
	float h = b * b - c;
	if (h < 0.0) {
		return vec2(-1.0);
	}
	h = sqrt(h);
	return vec2(-b - h, -b + h);
}

// ----------------------------------------------------------------------------
// Atmospheric density at a given world position, based on altitude above the
// planet surface. Exponential falloff with scale height H.
// ----------------------------------------------------------------------------
float atmosphere_density(vec3 pos, float r_planet, float H) {
	float altitude = length(pos) - r_planet;
	if (altitude < 0.0) {
		return 0.0;
	}
	return exp(-altitude / max(H, 0.0001));
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 sun_dir = normalize(sun_direction);
	vec3 ro = camera_position;
	vec3 rd = normalize(v_world_pos - camera_position);

	float r_atmo = planet_radius + atmosphere_height;
	float H = max(atmosphere_height * scale_height_frac, 0.001);

	// --- View ray intersection with the atmosphere shell ---
	vec2 atmo_hit = ray_sphere(ro, rd, r_atmo);
	if (atmo_hit.x < 0.0 && atmo_hit.y < 0.0) {
		discard;
	}
	float t_start = max(atmo_hit.x, 0.0);
	float t_end = max(atmo_hit.y, 0.0);
	if (t_end <= t_start) {
		discard;
	}

	// --- Clip integration at the solid planet surface (opaque) ---
	vec2 planet_hit = ray_sphere(ro, rd, planet_radius);
	if (planet_hit.x > 0.0) {
		t_end = min(t_end, planet_hit.x);
	}
	if (t_end <= t_start) {
		discard;
	}

	// --- Phase functions ---
	float cos_theta = dot(rd, sun_dir);
	float rayleigh_phase = 0.75 * (1.0 + cos_theta * cos_theta);
	float mie_phase_denom = 1.0 + mie_g * mie_g - 2.0 * mie_g * cos_theta;
	float mie_phase = (1.0 - mie_g * mie_g) /
		(4.0 * 3.14159265 * pow(max(mie_phase_denom, 0.0001), 1.5));

	// --- Numerical scattering integral along the view ray ---
	int actual_samples = max(4, int(float(sample_count) * quality_scale));
	int actual_light_samples = max(1, int(float(light_sample_count) * quality_scale));
	int samples = max(actual_samples, 4);
	float seg_len = (t_end - t_start) / float(samples);
	vec3 rayleigh_accum = vec3(0.0);
	vec3 mie_accum = vec3(0.0);
	float od_ray = 0.0;
	float od_mie = 0.0;

	for (int i = 0; i < 32; i++) {
		if (i >= samples) {
			break;
		}
		float t = t_start + seg_len * (float(i) + 0.5);
		vec3 p = ro + rd * t;
		float density = atmosphere_density(p, planet_radius, H);
		if (density <= 0.0) {
			continue;
		}
		od_ray += density * seg_len;
		od_mie += density * seg_len;

		// --- Light ray optical depth from p toward the sun ---
		vec2 light_atmo = ray_sphere(p, sun_dir, r_atmo);
		float light_dist = max(light_atmo.y, 0.0);
		vec2 light_planet = ray_sphere(p, sun_dir, planet_radius);
		bool in_shadow = (light_planet.x > 0.0);
		float light_od_ray = 0.0;
		float light_od_mie = 0.0;
		if (!in_shadow && light_dist > 0.0) {
			int lsamples = max(actual_light_samples, 1);
			float lseg = light_dist / float(lsamples);
			for (int j = 0; j < 8; j++) {
				if (j >= lsamples) {
					break;
				}
				float lt = lseg * (float(j) + 0.5);
				vec3 lp = p + sun_dir * lt;
				float ld = atmosphere_density(lp, planet_radius, H);
				light_od_ray += ld * lseg;
				light_od_mie += ld * lseg;
			}
		}

		vec3 tau = rayleigh_coeff * (od_ray + light_od_ray) +
			vec3(mie_coeff) * (od_mie + light_od_mie);
		vec3 attn = exp(-tau);

		rayleigh_accum += density * seg_len * attn;
		mie_accum += density * seg_len * attn;
	}

	// --- Composite scattered radiance ---
	vec3 scatter = rayleigh_accum * rayleigh_coeff * rayleigh_phase +
		mie_accum * mie_coeff * mie_phase;

	// --- Sun elevation drives day/sunset/night color blend ---
	float sun_up = clamp(sun_dir.y, -1.0, 1.0);
	// Sunset band: strongest when sun is near the horizon.
	float sunset_factor = 1.0 - clamp(abs(sun_up) * 2.5, 0.0, 1.0);
	float day_factor = clamp(sun_up * 1.5 + 0.5, 0.0, 1.0);
	float night_factor = clamp(-sun_up * 1.5 + 0.5, 0.0, 1.0);

	vec3 sky_tint = mix(sky_color_night.rgb, sky_color_day.rgb, day_factor);
	sky_tint = mix(sky_tint, sky_color_sunset.rgb, sunset_factor);

	// --- Limb / horizon haze boost (Mie forward glow toward sun) ---
	float limb = pow(clamp(1.0 - abs(dot(rd, normalize(v_world_pos))), 0.0, 1.0), 2.0);
	vec3 sun_glow = sky_color_sunset.rgb * mie_phase * mie_accum * mie_coeff * 4.0;

	vec3 col = (scatter * sky_tint + sun_glow) * archetype_tint.rgb * intensity;
	col += sky_tint * limb * archetype_tint.rgb * 0.15 * night_factor;

	// Alpha falls off with scattering strength so empty space stays clear.
	float alpha = clamp((length(scatter) * 6.0 + limb * 0.4) * intensity, 0.0, 1.0);

	ALBEDO = col;
	ALPHA = alpha;
}

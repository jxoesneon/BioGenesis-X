// ============================================================================
// BIO-GENESIS-X: Physical Atmosphere Scattering Shader
// ============================================================================
// Sean O'Neil's Rayleigh + Mie single-scattering technique (GPU Gems 2, 2004).
// Adapted from the Procedural Planet Chunked LOD asset for Godot 4.7.1.
//
// Renders a transparent sphere around the planet with physically-based
// atmospheric scattering. Superior to the simple Fresnel limb glow in the
// procedural_planet.gdshader because it models:
//   - Rayleigh scattering (wavelength-dependent — blue sky, red sunset)
//   - Mie scattering (forward-peaked — haze, sun glow)
//   - Optical depth via Chapman function approximation
//   - Ray marching through the atmosphere volume
//
// Usage: Apply to a sphere mesh slightly larger than the planet.
//        Set inner_radius = planet radius, outer_radius = planet + atmosphere.
//        Update camera_pos, sun_direction, camera_height each frame.
// ============================================================================

shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_front;

// --- Scattering parameters (tune in inspector for visual quality) ---
group_uniforms scattering;
uniform float kr : hint_range(0.0, 0.01, 0.0001) = 0.0035;          // Rayleigh coefficient
uniform float km : hint_range(0.0, 0.01, 0.0001) = 0.001;           // Mie coefficient
uniform float sun_intensity : hint_range(0.0, 50.0, 0.5) = 20.0;    // Sun brightness
uniform float g : hint_range(-1.0, 0.0, 0.01) = -0.95;              // Mie phase asymmetry (negative = forward)
uniform float scale_depth : hint_range(0.0, 1.0, 0.01) = 0.25;      // Altitude fraction of average density
uniform int num_samples : hint_range(1, 8, 1) = 4;                  // Ray march steps (more = better but slower)
uniform float wavelength_r : hint_range(0.3, 1.0, 0.001) = 0.650;   // Red wavelength (micrometers)
uniform float wavelength_g : hint_range(0.3, 1.0, 0.001) = 0.570;   // Green wavelength (micrometers)
uniform float wavelength_b : hint_range(0.3, 1.0, 0.001) = 0.475;   // Blue wavelength (micrometers)

// --- Per-archetype atmosphere color tint (0: none, 1: molten, etc.) ---
uniform int atmosphere_archetype : hint_range(0, 7) = 3;
uniform vec3 atmosphere_tint : source_color = vec3(0.25, 0.65, 1.0); // Custom tint override
uniform float tint_strength : hint_range(0.0, 1.0, 0.05) = 0.3;     // How much archetype tint affects scattering

// --- Managed by ProceduralPlanet each frame ---
group_uniforms runtime;
uniform vec3 camera_pos;          // Camera position in planet-local space
uniform vec3 sun_direction;       // Normalized direction toward the sun
uniform float camera_height;      // Distance from camera to planet center
uniform float inner_radius;       // Planet surface radius (meters)
uniform float outer_radius;       // Atmosphere edge radius (meters)
uniform float atm_scale;          // 1.0 / (outer_radius - inner_radius)
// Overall scattering intensity multiplier (driven by PlanetDescentController
// during descent: low in orbit, full in atmosphere/surface). Scales both the
// scattered color and alpha so the near-field sphere fades in smoothly as the
// camera descends from space.
uniform float atmosphere_intensity : hint_range(0.0, 1.0, 0.01) = 1.0;

// Pass vertex position to fragment shader
varying vec3 vertex_pos;

// Polynomial approximation of the Chapman function for optical depth.
// From O'Neil's original implementation.
float scale_func(float cos_angle, float sd) {
	float x = 1.0 - cos_angle;
	return sd * exp(-0.00287 + x * (0.459 + x * (3.83 + x * (-6.80 + x * 5.25))));
}

// Per-archetype wavelength adjustment for exotic atmospheres.
vec3 archetype_wavelengths(int archetype) {
	if (archetype == 0) {
		// MOLTEN: thick sulfuric atmosphere — reddish-brown scattering
		return mix(vec3(wavelength_r, wavelength_g, wavelength_b), vec3(0.70, 0.45, 0.30), tint_strength);
	} else if (archetype == 4) {
		// ICE WORLD: thin cryogenic atmosphere — pale blue
		return mix(vec3(wavelength_r, wavelength_g, wavelength_b), vec3(0.50, 0.60, 0.75), tint_strength);
	} else if (archetype == 5) {
		// JOVIAN GAS GIANT: deep ammonia atmosphere — amber/gold
		return mix(vec3(wavelength_r, wavelength_g, wavelength_b), vec3(0.65, 0.55, 0.40), tint_strength);
	} else if (archetype == 6) {
		// ICE GIANT: methane atmosphere — deep blue/cyan
		return mix(vec3(wavelength_r, wavelength_g, wavelength_b), vec3(0.48, 0.55, 0.70), tint_strength);
	} else if (archetype == 7) {
		// RADIOTROPHIC BIO: dense organic atmosphere — greenish
		return mix(vec3(wavelength_r, wavelength_g, wavelength_b), vec3(0.52, 0.58, 0.50), tint_strength);
	}
	// Default: Terran-like or barren — use standard wavelengths with optional tint
	return mix(vec3(wavelength_r, wavelength_g, wavelength_b), atmosphere_tint, tint_strength);
}

void vertex() {
	vertex_pos = VERTEX;
}

void fragment() {
	// Ray from camera to this pixel's position on the atmosphere sphere
	vec3 pos = vertex_pos;
	vec3 ray = pos - camera_pos;
	float far_dist = length(ray);
	ray /= far_dist;

	// Precompute scattering constants with per-archetype wavelength adjustment
	vec3 wl = archetype_wavelengths(atmosphere_archetype);
	vec3 inv_wavelength4 = 1.0 / (wl * wl * wl * wl);
	float kr_sun = kr * sun_intensity;
	float km_sun = km * sun_intensity;
	float kr_4pi = kr * 4.0 * PI;
	float km_4pi = km * 4.0 * PI;
	float scale_over_depth = atm_scale / scale_depth;

	// Find ray-atmosphere intersection. When camera is outside, near_dist > 0
	// and the ray starts at the atmosphere boundary. When camera is inside,
	// near_dist <= 0 so we clamp to 0 and start at the camera position.
	float B = 2.0 * dot(camera_pos, ray);
	float C = camera_height * camera_height - outer_radius * outer_radius;
	float det = max(0.0, B * B - 4.0 * C);
	float near_dist = max(0.0, 0.5 * (-B - sqrt(det)));
	vec3 start_pos = camera_pos + ray * near_dist;
	far_dist -= near_dist;

	float start_height = length(start_pos);
	float start_angle = dot(ray, start_pos) / max(start_height, 0.001);
	float start_depth = exp(scale_over_depth * (inner_radius - start_height));
	float start_offset = start_depth * scale_func(start_angle, scale_depth);

	// Ray march through the atmosphere
	float sample_length = far_dist / float(num_samples);
	float scaled_length = sample_length * atm_scale;
	vec3 sample_ray = ray * sample_length;
	vec3 sample_point = start_pos + sample_ray * 0.5;

	vec3 front_color = vec3(0.0);
	for (int i = 0; i < num_samples; i++) {
		float h = length(sample_point);
		float d = exp(scale_over_depth * (inner_radius - h));
		float light_angle = dot(sun_direction, sample_point) / max(h, 0.001);
		float camera_angle = dot(ray, sample_point) / max(h, 0.001);
		float scatter = start_offset + d * (scale_func(light_angle, scale_depth) - scale_func(camera_angle, scale_depth));
		vec3 attenuate = exp(-scatter * (inv_wavelength4 * kr_4pi + km_4pi));
		front_color += attenuate * (d * scaled_length);
		sample_point += sample_ray;
	}

	// Rayleigh and Mie colors
	vec3 rayleigh_color = front_color * (inv_wavelength4 * kr_sun);
	vec3 mie_color = front_color * km_sun;

	// Phase functions
	float cos_angle = dot(sun_direction, normalize(camera_pos - pos));

	// Rayleigh phase function: 3/4 * (1 + cos²θ)
	float rayleigh_phase = 0.75 * (1.0 + cos_angle * cos_angle);

	// Henyey-Greenstein Mie phase function
	float g2 = g * g;
	float mie_phase = 1.5 * ((1.0 - g2) / (2.0 + g2))
		* (1.0 + cos_angle * cos_angle)
		/ pow(max(1.0 + g2 - 2.0 * g * cos_angle, 0.001), 1.5);

	ALBEDO = rayleigh_phase * rayleigh_color + mie_phase * mie_color;
	// Alpha from scattering intensity — strong scattering hides stars behind the sky
	ALPHA = clamp(max(ALBEDO.r, max(ALBEDO.g, ALBEDO.b)) * 5.0, 0.0, 1.0);
	// Apply the descent-driven intensity multiplier so the near-field sphere
	// fades in/out smoothly as the camera transitions between space and surface.
	ALBEDO *= atmosphere_intensity;
	ALPHA *= atmosphere_intensity;
}

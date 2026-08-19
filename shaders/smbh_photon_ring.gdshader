shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

// SMBH Photon Ring Shader
// The photon ring is a thin, bright ring at ~1.5x the Schwarzschild radius
// where photons orbit the black hole. It appears as a near-perfect circle
// of intense light, slightly brighter on the Doppler-approaching side.

uniform float ring_radius = 0.22;
uniform float ring_thickness : hint_range(0.001, 0.05) = 0.008;
uniform float brightness = 8.0;
uniform float doppler_boost = 1.8;
uniform float doppler_angle = 0.0;
uniform vec3 ring_color = vec3(1.0, 0.85, 0.6); // hot white-gold

void fragment() {
	float r = length(VERTEX.xz);
	float angle = atan(VERTEX.z, VERTEX.x);

	// Distance from ideal ring radius
	float dist_from_ring = abs(r - ring_radius);

	// Gaussian falloff for thin bright ring
	float ring_mask = exp(-dist_from_ring * dist_from_ring / (ring_thickness * ring_thickness));

	// Doppler beaming — slightly brighter on one side
	float doppler_angle_adj = angle - doppler_angle;
	float doppler_factor = 1.0 + doppler_boost * cos(doppler_angle_adj);
	doppler_factor = clamp(doppler_factor, 0.4, 3.0);

	// Subtle angular variation for realism (photon ring isn't perfectly uniform)
	float angular_variation = 0.9 + 0.1 * sin(angle * 7.0);

	float intensity = ring_mask * doppler_factor * angular_variation * brightness;

	ALBEDO = ring_color * intensity;
	ALPHA = clamp(ring_mask * 0.95, 0.0, 1.0);
	EMISSION = ring_color * intensity * 1.5;
}

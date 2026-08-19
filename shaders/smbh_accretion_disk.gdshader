shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

// SMBH Accretion Disk Shader
// Features: radial temperature gradient, turbulent swirl, Doppler beaming,
// relativistic brightness boost, time-animated rotation, edge falloff.
//
// UV mapping: disk geometry is a flat ring in the XZ plane.
// We compute radial position from vertex position in object space.

uniform float inner_radius : hint_range(0.0, 1.0) = 0.15;
uniform float outer_radius : hint_range(0.0, 2.0) = 1.0;
uniform float disk_thickness : hint_range(0.0, 0.5) = 0.02;
uniform float time_scale = 0.15;
uniform float swirl_strength = 8.0;
uniform float doppler_boost = 2.5;
uniform float doppler_angle = 0.0; // rotation of beaming axis
uniform float temperature_inner : hint_range(1000.0, 50000.0) = 15000.0;
uniform float temperature_outer : hint_range(100.0, 10000.0) = 3000.0;
uniform float noise_scale = 3.0;
uniform float noise_speed = 0.5;
uniform float brightness = 1.5;
uniform float edge_falloff = 3.0;

// Blackbody color approximation (Tanner Helland's algorithm, simplified)
vec3 blackbody(float temp_k) {
	float t = clamp(temp_k / 100.0, 0.0, 400.0);
	vec3 color;
	if (t <= 66.0) {
		color.r = 1.0;
		color.g = clamp(0.39008157876 * log(t) - 0.63184144378, 0.0, 1.0);
		if (t <= 19.0) {
			color.b = 0.0;
		} else {
			color.b = clamp(0.54320678911 * log(t - 10.0) - 1.19625408934, 0.0, 1.0);
		}
	} else {
		color.r = clamp(1.29293618606 * pow(t - 60.0, -0.1332047592), 0.0, 1.0);
		color.g = clamp(1.12989086089 * pow(t - 60.0, -0.0755148492), 0.0, 1.0);
		color.b = 1.0;
	}
	return color;
}

// Hash-based noise for turbulence
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise2d(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	// Pass object-space position to fragment for radial calculations
	// The disk mesh is a flat ring in XZ plane (y ≈ 0)
}

void fragment() {
	float r = length(VERTEX.xz);
	float angle = atan(VERTEX.z, VERTEX.x);

	// Normalize radius to [0, 1] across disk
	float r_norm = clamp((r - inner_radius) / (outer_radius - inner_radius), 0.0, 1.0);

	// Discard outside disk bounds
	if (r < inner_radius || r > outer_radius) {
		discard;
	}

	// Temperature gradient: hot inner → cool outer
	float temp = mix(temperature_inner, temperature_outer, pow(r_norm, 0.7));
	vec3 bb_color = blackbody(temp);

	// Swirling turbulence — angular noise that rotates with time
	float swirl_phase = angle + TIME * time_scale + r_norm * swirl_strength;
	float turb = fbm(vec2(swirl_phase * noise_scale, r_norm * noise_scale * 2.0 + TIME * noise_speed * 0.1));
	float turb2 = fbm(vec2(swirl_phase * noise_scale * 2.0 + turb * 3.0, r_norm * noise_scale * 4.0));

	// Spiral density bands — matter spiraling inward
	float spiral = sin(swirl_phase * 3.0 + r_norm * 12.0) * 0.5 + 0.5;
	spiral = mix(0.6, 1.0, spiral);

	// Combine turbulence
	float density = turb * 0.6 + turb2 * 0.4;
	density = clamp(density * spiral, 0.0, 1.5);

	// Doppler beaming — brighter on approaching side
	float doppler_angle_adj = angle - doppler_angle;
	float doppler_factor = 1.0 + doppler_boost * cos(doppler_angle_adj);
	doppler_factor = clamp(doppler_factor, 0.3, 4.0);

	// Relativistic beaming is stronger at higher orbital velocity (inner disk)
	float relativistic_boost = 1.0 + (1.0 - r_norm) * 1.5;

	// Edge falloff — disk fades at inner and outer edges
	float edge_mask = smoothstep(0.0, 0.08, r_norm) * smoothstep(1.0, 0.85, r_norm);
	edge_mask = pow(edge_mask, edge_falloff * 0.5);

	// Vertical falloff — disk is thinner at edges
	float vertical_falloff = 1.0 - abs(NORMAL.y) * 0.3;

	// Final color and alpha
	vec3 final_color = bb_color * density * doppler_factor * relativistic_boost * brightness;
	float alpha = density * edge_mask * vertical_falloff;

	ALBEDO = final_color;
	ALPHA = clamp(alpha, 0.0, 1.0);
	EMISSION = final_color * 2.0;
}

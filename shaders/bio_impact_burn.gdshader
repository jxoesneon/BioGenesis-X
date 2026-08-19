shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled;

// ============================================================================
// BIO-GENESIS-X: BIO-IMPACT BURN & ENERGY DISCHARGE SHADER
// ============================================================================
// Adapted from godotshaders.com impact/scorch patterns (MIT / CC0 sources).
// Renders a weapon-impact effect on a ship hull mesh:
//   - Radial energy discharge ripple emanating from an impact point
//   - Organic scorch / plasma burn pattern (procedural noise)
//   - Bioluminescent cyan-magenta discharge that fades over time
// Driven by per-instance uniforms: impact_point (object space), impact_age,
// impact_strength. Stack multiple impacts via a second pass or decal.
// Compatible with floating-origin: all math is in object/model space.
// ============================================================================

group_uniforms Impact_Geometry;
uniform vec3 impact_point : source_color; // Object-space hit location
uniform float impact_age : hint_range(0.0, 10.0, 0.01) = 0.0; // Seconds since hit
uniform float impact_strength : hint_range(0.0, 4.0, 0.05) = 1.0; // Damage magnitude
uniform float impact_radius : hint_range(0.05, 8.0, 0.05) = 1.2; // Effect falloff radius

group_uniforms Discharge_Dynamics;
uniform float ripple_speed : hint_range(0.5, 20.0, 0.1) = 6.0; // Wave expansion speed
uniform float ripple_sharpness : hint_range(1.0, 12.0, 0.5) = 5.0;
uniform float discharge_decay : hint_range(0.2, 4.0, 0.1) = 1.2; // Fade rate

group_uniforms Color_Palette;
uniform vec4 discharge_color : source_color = vec4(0.0, 0.95, 1.0, 1.0);   // Bio-cyan
uniform vec4 scorch_color : source_color = vec4(1.0, 0.05, 0.45, 1.0);     // Bio-magenta
uniform vec4 core_flash_color : source_color = vec4(1.0, 0.85, 0.2, 1.0);  // Amber flash

group_uniforms Organic_Scorch;
uniform float scorch_scale : hint_range(2.0, 40.0, 0.5) = 16.0;
uniform float scorch_intensity : hint_range(0.0, 3.0, 0.05) = 1.0;

varying vec3 v_model_pos;

// ----------------------------------------------------------------------------
// Procedural 3D noise (self-contained, no texture dependencies)
// ----------------------------------------------------------------------------
float hash31(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash31(i);
	float b = hash31(i + vec3(1.0, 0.0, 0.0));
	float c = hash31(i + vec3(0.0, 1.0, 0.0));
	float d = hash31(i + vec3(1.0, 1.0, 0.0));
	float e = hash31(i + vec3(0.0, 0.0, 1.0));
	float f1 = hash31(i + vec3(1.0, 0.0, 1.0));
	float g = hash31(i + vec3(0.0, 1.0, 1.0));
	float h = hash31(i + vec3(1.0, 1.0, 1.0));
	float nx0 = mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
	float nx1 = mix(mix(e, f1, f.x), mix(g, h, f.x), f.y);
	return mix(nx0, nx1, f.z);
}

float fbm3d(vec3 p) {
	float val = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		val += amp * noise3d(p);
		p *= 2.15;
		amp *= 0.46;
	}
	return val;
}

void vertex() {
	v_model_pos = VERTEX;
}

void fragment() {
	vec3 pos = v_model_pos;
	float dist = distance(pos, impact_point);

	// Normalized distance from impact, scaled by radius
	float d_norm = dist / max(impact_radius, 0.001);

	// --- Energy discharge ripple: expanding ring ---
	float wave_radius = impact_age * ripple_speed;
	float ring_dist = abs(d_norm * impact_radius - wave_radius);
	float ring = exp(-ring_dist * ripple_sharpness) * impact_strength;

	// --- Core flash at impact center (fades fast) ---
	float core_flash = exp(-impact_age * 6.0) * exp(-d_norm * 8.0) * impact_strength;

	// --- Organic scorch pattern (procedural, persistent) ---
	float scorch_noise = fbm3d(pos * scorch_scale + impact_point * 3.3);
	scorch_noise = pow(scorch_noise, 2.0);
	float scorch_falloff = exp(-d_norm * 3.0) * (1.0 - smoothstep(0.0, 1.0, impact_age * 0.15));
	float scorch = scorch_noise * scorch_falloff * scorch_intensity * impact_strength;

	// --- Overall decay over time ---
	float decay = exp(-impact_age * discharge_decay);

	// --- Color composite ---
	vec3 color = vec3(0.0);
	color += discharge_color.rgb * ring * decay * 2.5;
	color += core_flash_color.rgb * core_flash * 3.0;
	color += scorch_color.rgb * scorch * 1.5;

	float intensity = (ring * decay + core_flash + scorch) * impact_strength;
	float alpha = clamp(intensity, 0.0, 1.0);

	ALBEDO = color * 0.2;
	EMISSION = color * (1.5 + core_flash * 4.0);
	ALPHA = alpha * 0.9;
}

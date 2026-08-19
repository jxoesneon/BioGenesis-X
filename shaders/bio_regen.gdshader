shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, blend_mix;

// ============================================================================
// BIO-GENESIS-X: NeuralRegen Bioluminescent Regeneration Visual Shader
// ============================================================================
// Renders a pulsing bioluminescent regeneration pattern on the ship mesh.
//   - Cyan-green glow for healthy regen (healing in progress)
//   - Red-orange glow for damaged areas (wounds, recent hits)
//   - Noise-based organic cellular/vein patterns
//   - Intensity scales with NeuralRegen.regen_visual_intensity [0-1]
// ============================================================================

group_uniforms Regen_Dynamics;
uniform float regen_intensity : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float damage_flash : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float pulse_speed : hint_range(0.1, 10.0, 0.1) = 2.0;
uniform float pulse_amplitude : hint_range(0.0, 2.0, 0.05) = 0.8;

group_uniforms Color_Palette;
uniform vec4 healthy_color : source_color = vec4(0.0, 0.95, 0.55, 1.0);  // Cyan-green
uniform vec4 damaged_color : source_color = vec4(1.0, 0.35, 0.1, 1.0);   // Red-orange
uniform vec4 vein_color : source_color = vec4(0.1, 0.9, 0.7, 1.0);       // Bio-teal veins

group_uniforms Damage_Map;
// 2D damage map (R = damage intensity 0..1, G = heal chemical 0..1).
// Sampled with the mesh UVs. Defaults to white (no damage, full heal) so the
// overlay is invisible when no damage map is assigned.
uniform sampler2D damage_map : hint_default_white;
uniform float damage_map_influence : hint_range(0.0, 1.0, 0.01) = 0.7;

group_uniforms Organic_Pattern;
uniform float cell_scale : hint_range(1.0, 50.0, 0.5) = 12.0;
uniform float vein_scale : hint_range(1.0, 30.0, 0.5) = 8.0;
uniform float vein_sharpness : hint_range(1.0, 10.0, 0.5) = 4.0;
uniform float time_offset : hint_range(0.0, 100.0, 0.1) = 0.0;

// ---------------------------------------------------------------------------
// Simplex-like 3D noise (compact, self-contained — no texture dependencies)
// ---------------------------------------------------------------------------
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 permute(vec4 x) { return mod289(((x * 34.0) + 1.0) * x); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) {
	const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
	const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);
	vec3 i = floor(v + dot(v, C.yyy));
	vec3 x0 = v - i + dot(i, C.xxx);
	vec3 g = step(x0.yzx, x0.xyz);
	vec3 l = 1.0 - g;
	vec3 i1 = min(g.xyz, l.zxy);
	vec3 i2 = max(g.xyz, l.zxy);
	vec3 x1 = x0 - i1 + C.xxx;
	vec3 x2 = x0 - i2 + C.yyy;
	vec3 x3 = x0 - D.yyy;
	i = mod289(i);
	vec4 p = permute(permute(permute(
		i.z + vec4(0.0, i1.z, i2.z, 1.0))
		+ i.y + vec4(0.0, i1.y, i2.y, 1.0))
		+ i.x + vec4(0.0, i1.x, i2.x, 1.0));
	float n_ = 0.142857142857;
	vec3 ns = n_ * D.wyz - D.xzx;
	vec4 j = p - 49.0 * floor(p * ns.z * ns.z);
	vec4 x_ = floor(j * ns.z);
	vec4 y_ = floor(j - 7.0 * x_);
	vec4 x = x_ * ns.x + ns.yyyy;
	vec4 y = y_ * ns.x + ns.yyyy;
	vec4 h = 1.0 - abs(x) - abs(y);
	vec4 b0 = vec4(x.xy, y.xy);
	vec4 b1 = vec4(x.zw, y.zw);
	vec4 s0 = floor(b0) * 2.0 + 1.0;
	vec4 s1 = floor(b1) * 2.0 + 1.0;
	vec4 sh = -step(h, vec4(0.0));
	vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
	vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
	vec3 p0 = vec3(a0.xy, h.x);
	vec3 p1 = vec3(a0.zw, h.y);
	vec3 p2 = vec3(a1.xy, h.z);
	vec3 p3 = vec3(a1.zw, h.w);
	vec4 norm = taylorInvSqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
	p0 *= norm.x;
	p1 *= norm.y;
	p2 *= norm.z;
	p3 *= norm.w;
	vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
	m = m * m;
	return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

// ---------------------------------------------------------------------------
// Fractal Brownian Motion (multi-octave noise for organic patterns)
// ---------------------------------------------------------------------------
float fbm(vec3 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < octaves; i++) {
		value += amplitude * snoise(p * frequency);
		frequency *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

// ---------------------------------------------------------------------------
// Voronoi-like cellular pattern for organic cell structure
// ---------------------------------------------------------------------------
float cellular_pattern(vec3 p, float scale) {
	vec3 scaled = p * scale;
	vec3 cell = floor(scaled);
	vec3 local = fract(scaled);
	float min_dist = 1.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 neighbor = vec3(float(x), float(y), float(z));
				vec3 point = neighbor + 0.5 + 0.5 * sin(TIME * 0.5 + vec3(
					dot(cell + neighbor, vec3(12.9898, 78.233, 37.719)),
					dot(cell + neighbor, vec3(39.346, 11.135, 83.155)),
					dot(cell + neighbor, vec3(73.156, 52.288, 9.151))
				) * 4.37);
				vec3 diff = neighbor + point - local;
				min_dist = min(min_dist, length(diff));
			}
		}
	}
	return min_dist;
}

void fragment() {
	float t = TIME * pulse_speed + time_offset;

	// --- Organic vein pattern (FBM noise) ---
	float veins = fbm(VERTEX * vein_scale, 4);
	veins = pow(abs(veins), vein_sharpness);
	float vein_glow = smoothstep(0.3, 0.7, veins) * pulse_amplitude;

	// --- Cellular pattern (Voronoi-like) ---
	float cells = cellular_pattern(VERTEX, cell_scale);
	float cell_glow = smoothstep(0.0, 0.4, cells) * pulse_amplitude * 0.5;

	// --- Pulsing bioluminescent wave ---
	float pulse = 0.5 + 0.5 * sin(t);
	float wave = (vein_glow + cell_glow) * pulse;

	// --- Damage map: localized damage (R) and heal chemical (G) from UV ---
	vec4 dmg_sample = texture(damage_map, UV);
	float local_damage = dmg_sample.r * damage_map_influence;
	float local_heal = dmg_sample.g;

	// --- Color blend: healthy (cyan-green) vs damaged (red-orange) ---
	// Combine the global damage_flash (recent hit) with localized damage map.
	float damage_blend = clamp(damage_flash + local_damage, 0.0, 1.0);
	vec3 color = mix(healthy_color.rgb, damaged_color.rgb, damage_blend);
	color = mix(color, vein_color.rgb, vein_glow * 0.3);

	// --- Intensity scales with regen activity ---
	// Healing areas (high local_heal) glow brighter cyan-green; damaged areas
	// glow red-orange even at lower global regen intensity.
	float heal_boost = local_heal * 0.5;
	float intensity = regen_intensity * wave + local_damage * 0.4 + heal_boost * wave;
	intensity = clamp(intensity, 0.0, 2.0);
	float alpha = intensity * 0.7;

	// --- Emissive bioluminescent glow ---
	ALBEDO = color * intensity;
	EMISSION = color * intensity * 2.0;
	ROUGHNESS = 0.6;
	METALLIC = 0.0;
	ALPHA = alpha;
}

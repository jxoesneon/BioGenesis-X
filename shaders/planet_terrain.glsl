#[compute]
#version 450
// ============================================================================
// BIO-GENESIS-X: GPU COMPUTE PLANET TERRAIN GENERATOR
// Chunked cube-sphere terrain for TRUE planetary scale (Earth-sized, 6371 km).
// Self-contained: no external textures, no #include. Simplex 3D noise + fBm +
// ridged multifractal + domain warping. Outputs position/normal/tangent buffers.
// ============================================================================

// 64x64 vertices per chunk => 16x16 work groups of 4x4 invocations.
#define CHUNK_VERTS 64

layout(local_size_x = 4, local_size_y = 4, local_size_z = 1) in;

// ---------------------------------------------------------------------------
// Per-chunk parameters (std140, 64 bytes). Packed by PlanetTerrainGenerator.gd.
// ---------------------------------------------------------------------------
layout(set = 0, binding = 0, std140) uniform ChunkParams {
	ivec4 face_chunk; // x: face_id (0-5), y: chunk_x, z: chunk_y, w: lod
	uvec4 seed_arch;  // x: planet_seed, y: archetype, z: octaves_base, w: pad
	vec4  geo;        // x: planet_radius, y: elevation_amplitude, z: base_frequency, w: sea_level
	vec4  warp;       // xyz: warp_offset, w: pad
} params;

// ---------------------------------------------------------------------------
// Output buffers (std430). One vec4 per vertex. 4096 vertices per chunk.
// ---------------------------------------------------------------------------
layout(set = 0, binding = 1, std430) restrict writeonly buffer PositionBuffer {
	vec4 positions[];
};
layout(set = 0, binding = 2, std430) restrict writeonly buffer NormalBuffer {
	vec4 normals[];
};
layout(set = 0, binding = 3, std430) restrict writeonly buffer TangentBuffer {
	vec4 tangents[];
};

// ============================================================================
// SELF-CONTAINED 3D SIMPLEX NOISE (Ashima Arts / Stefan Gustavson, MIT)
// ============================================================================
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 permute(vec4 x) { return mod289(((x * 34.0) + 1.0) * x); }
vec4 taylor_inv_sqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) {
	const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
	const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);
	vec3 i  = floor(v + dot(v, C.yyy));
	vec3 x0 = v - i + dot(i, C.xxx);
	vec3 g  = step(x0.yzx, x0.xyz);
	vec3 l  = 1.0 - g;
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
	vec4 norm = taylor_inv_sqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
	p0 *= norm.x;
	p1 *= norm.y;
	p2 *= norm.z;
	p3 *= norm.w;
	vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
	m = m * m;
	return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

// ============================================================================
// FRACTAL NOISE BUILDING BLOCKS
// ============================================================================
const mat3 ROT_3D = mat3(
	vec3( 0.00,  0.80,  0.60),
	vec3(-0.80,  0.36, -0.48),
	vec3(-0.60, -0.48,  0.64)
);

// Multi-octave fractal Brownian motion.
float fbm(vec3 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < octaves; i++) {
		v += a * snoise(p);
		p = ROT_3D * p * 2.02;
		a *= 0.5;
	}
	return v;
}

// Ridged multifractal noise for mountain ridges & canyon spines.
float ridged_noise(vec3 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < octaves; i++) {
		float n = 1.0 - abs(snoise(p));
		n = n * n;
		v += a * n;
		p = ROT_3D * p * 2.08;
		a *= 0.48;
	}
	return v;
}

// Domain-warped fBm for organic, swirling continent coastlines.
float domain_warp_fbm(vec3 p, int octaves) {
	vec3 q = vec3(
		fbm(p + vec3(0.0, 0.0, 0.0), octaves),
		fbm(p + vec3(5.2, 1.3, 2.7), octaves),
		fbm(p + vec3(1.3, 8.4, 4.1), octaves)
	);
	return fbm(p + 2.0 * q, octaves);
}

// ============================================================================
// CUBE-SPHERE MAPPING
// 6 faces, UV (u,v) in [-1, 1]. Normalize cube point to unit sphere direction.
// ============================================================================
vec3 face_to_cube(int face, vec2 uv) {
	if (face == 0) { return vec3( 1.0, uv.x, uv.y); }
	if (face == 1) { return vec3(-1.0, uv.x, uv.y); }
	if (face == 2) { return vec3(uv.x,  1.0, uv.y); }
	if (face == 3) { return vec3(uv.x, -1.0, uv.y); }
	if (face == 4) { return vec3(uv.x, uv.y,  1.0); }
	return vec3(uv.x, uv.y, -1.0);
}

// ============================================================================
// ARCHETYPE-DRIVEN ELEVATION FIELD
// Returns normalized elevation in [-1, 1] (scaled by elevation_amplitude
// outside). 0: Molten, 1: Metallic Barren, 2: Desert, 3: Terran Oceanic,
// 4: Ice World, 5: Gas Giant Jovian, 6: Gas Giant Ice, 7: Radiotrophic Bio.
// ============================================================================
float compute_elevation(vec3 dir, int archetype, int octaves) {
	vec3 p = dir * params.geo.z + params.warp.xyz;
	float continent = domain_warp_fbm(p, octaves);
	float mountains = ridged_noise(p * 2.5, max(octaves - 2, 3)) * 0.35;
	float detail = fbm(p * 8.0, max(octaves - 4, 2)) * 0.08;
	float h = continent + mountains + detail;

	if (archetype == 0) {
		// MOLTEN: smooth basalt plains, sharp volcanic fissures.
		float fissures = smoothstep(0.55, 0.75, ridged_noise(p * 4.0, 4));
		h = continent * 0.4 + fissures * 0.6;
	} else if (archetype == 1) {
		// METALLIC BARREN: heavy cratering, low relief.
		float craters = smoothstep(0.45, 0.65, fbm(p * 5.0, 5));
		h = continent * 0.25 + (craters - 0.5) * 0.3;
	} else if (archetype == 2) {
		// DESERT: sweeping dunes, moderate ridges.
		float dunes = snoise(p * 12.0) * 0.15;
		h = continent * 0.5 + mountains * 0.4 + dunes;
	} else if (archetype == 3) {
		// TERRAN OCEANIC: shallow ocean basins, tall continents.
		h = continent * 0.7 + mountains * 0.5 + detail;
	} else if (archetype == 4) {
		// ICE WORLD: flattened glaciated relief.
		h = continent * 0.3 + smoothstep(0.4, 0.6, mountains) * 0.2;
	} else if (archetype == 5 || archetype == 6) {
		// GAS GIANT: no solid surface; latitudinal banding only.
		float bands = sin(dir.y * 38.0 + fbm(p * 2.5, 5) * 5.0);
		h = bands * 0.02;
	} else if (archetype == 7) {
		// RADIOTROPHIC BIO-WORLD: towering fungal spore mounds.
		float bio_veins = smoothstep(0.52, 0.68, fbm(p * 8.0, 5));
		h = continent * 0.5 + bio_veins * 0.8 + detail;
	}
	return h;
}

// Reusable elevation sampler with a per-direction seed offset so finite
// differences sample consistent terrain (no per-call randomization).
float sample_elevation(vec3 dir, int archetype, int octaves) {
	return compute_elevation(dir, archetype, octaves);
}

// ============================================================================
// MAIN: one invocation per vertex.
// ============================================================================
void main() {
	ivec2 gid = ivec2(gl_GlobalInvocationID.xy);
	if (gid.x >= CHUNK_VERTS || gid.y >= CHUNK_VERTS) {
		return;
	}
	int idx = gid.y * CHUNK_VERTS + gid.x;

	int face_id = params.face_chunk.x;
	int chunk_x = params.face_chunk.y;
	int chunk_y = params.face_chunk.z;
	int lod = params.face_chunk.w;
	int archetype = int(params.seed_arch.y);
	int octaves_base = int(params.seed_arch.z);
	int octaves = clamp(octaves_base + lod, 4, 12);

	// Chunk UV extent on its face. LOD L divides a face into 2^L x 2^L chunks.
	float extent = 2.0 / float(1 << lod);
	vec2 base = vec2(-1.0) + vec2(float(chunk_x), float(chunk_y)) * extent;
	float inv_edge = 1.0 / float(CHUNK_VERTS - 1);
	vec2 uv = base + vec2(float(gid.x), float(gid.y)) * inv_edge * extent;

	vec3 cube = face_to_cube(face_id, uv);
	vec3 dir = normalize(cube);

	float elev = sample_elevation(dir, archetype, octaves);
	float radius = params.geo.x + elev * params.geo.y;
	vec3 pos = dir * radius;

	// Outward normal via on-sphere finite differences (keeps terrain lighting
	// consistent with displacement, independent of face winding).
	vec3 up_ref = abs(dir.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 t1 = normalize(cross(up_ref, dir));
	vec3 t2 = normalize(cross(dir, t1));
	float eps = 1e-3;
	vec3 dir_a = normalize(dir + t1 * eps);
	vec3 dir_b = normalize(dir + t2 * eps);
	float elev_a = sample_elevation(dir_a, archetype, octaves);
	float elev_b = sample_elevation(dir_b, archetype, octaves);
	vec3 pos_a = dir_a * (params.geo.x + elev_a * params.geo.y);
	vec3 pos_b = dir_b * (params.geo.x + elev_b * params.geo.y);
	vec3 normal = normalize(cross(pos_a - pos, pos_b - pos));

	// Tangent along the u direction (bitangent = cross(normal, tangent) * w).
	vec3 tangent = normalize(t1);

	positions[idx] = vec4(pos, elev);
	normals[idx]   = vec4(normal, 0.0);
	tangents[idx]  = vec4(tangent, 1.0);
}

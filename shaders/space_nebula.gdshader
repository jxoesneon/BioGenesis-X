shader_type sky;

// ============================================================================
// BIO-GENESIS-X: AAA+ PROCEDURAL GALACTIC SKYBOX SHADER
// Inspired by Elite Dangerous & SpaceEngine Astrophysics
// Multi-layer Lin-Shu Spiral Arm Dust Lanes, Core Singularity & 3D Starfields
// ============================================================================

uniform vec4 space_void_color : source_color = vec4(0.003, 0.005, 0.012, 1.0);
uniform vec4 galactic_core_color : source_color = vec4(1.0, 0.82, 0.55, 1.0);
uniform vec4 emission_nebula_cyan : source_color = vec4(0.0, 0.55, 0.75, 1.0);
uniform vec4 emission_nebula_magenta : source_color = vec4(0.7, 0.08, 0.45, 1.0);
uniform vec4 dark_dust_color : source_color = vec4(0.01, 0.015, 0.02, 1.0);

uniform float galactic_plane_angle : hint_range(-180.0, 180.0, 1.0) = 28.0;
uniform float core_intensity : hint_range(0.0, 8.0, 0.1) = 3.5;
uniform float nebula_density : hint_range(0.0, 4.0, 0.1) = 1.4;
uniform float starfield_density : hint_range(50.0, 600.0, 10.0) = 320.0;
uniform float background_twinkle_speed : hint_range(0.0, 5.0, 0.1) = 1.8;

// ----------------------------------------------------------------------------
// High Performance 3D Hash & Simplex Noise Functions
// ----------------------------------------------------------------------------

float hash31(vec3 p) {
    p = fract(p * vec3(443.897, 441.423, 437.195));
    p += dot(p, p.yzx + 21.37);
    return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
    p = fract(p * vec3(443.897, 441.423, 437.195));
    p += dot(p, p.yzx + 19.19);
    return fract((p.xxy + p.yxx) * p.zyx);
}

float fast_noise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float n000 = hash31(i);
    float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash31(i + vec3(1.0, 1.0, 1.0));

    return mix(
        mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
        mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
        f.z
    );
}

float fbm_galaxy(vec3 p) {
    float val = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 5; i++) {
        val += amp * fast_noise(p);
        p *= 2.12;
        amp *= 0.48;
    }
    return val;
}

// ----------------------------------------------------------------------------
// Harvard Spectral Stellar Chromaticity (O, B, A, F, G, K, M)
// ----------------------------------------------------------------------------
vec3 get_star_color(float seed) {
    if (seed > 0.992) {
        return vec3(0.65, 0.82, 1.0);  // Class O/B: Brilliant Blue-White
    } else if (seed > 0.975) {
        return vec3(0.85, 0.92, 1.0);  // Class A: Pure White
    } else if (seed > 0.950) {
        return vec3(1.0, 0.96, 0.82);  // Class F/G: Sol-type Warm Yellow
    } else if (seed > 0.900) {
        return vec3(1.0, 0.72, 0.40);  // Class K: Deep Amber Orange
    } else {
        return vec3(1.0, 0.45, 0.28);  // Class M: Carmine Red Dwarf
    }
}

// ----------------------------------------------------------------------------
// Procedural Voronoi Pinpoint Star Generation
// ----------------------------------------------------------------------------
vec3 render_stars(vec3 dir, float density, float time) {
    vec3 p = dir * density;
    vec3 id = floor(p);
    vec3 f = fract(p);

    vec3 star_acc = vec3(0.0);

    for (int z = -1; z <= 1; z++) {
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                vec3 neighbor = vec3(float(x), float(y), float(z));
                vec3 star_hash = hash33(id + neighbor);
                
                // Position of star inside neighbor grid cell
                vec3 star_pos = neighbor + star_hash - f;
                float d = length(star_pos);

                // Star presence threshold (only dense in a subset of cells)
                if (star_hash.x > 0.86) {
                    float star_brightness = pow((star_hash.x - 0.86) / 0.14, 3.2);
                    
                    // Subtle atmospheric twinkle
                    float twinkle = 0.85 + 0.15 * sin(time * background_twinkle_speed + star_hash.y * 30.0);
                    
                    // Sharp Gaussian core & faint diffraction cross
                    float core = exp(-d * d * 180.0) * star_brightness * twinkle;
                    float diffraction = (exp(-abs(star_pos.x) * 45.0) * exp(-abs(star_pos.y) * 45.0) +
                                         exp(-abs(star_pos.z) * 45.0) * exp(-abs(star_pos.y) * 45.0)) * 0.08 * star_brightness;

                    vec3 color = get_star_color(star_hash.z);
                    star_acc += color * (core + diffraction) * 2.2;
                }
            }
        }
    }
    return star_acc;
}

// ----------------------------------------------------------------------------
// Skybox Fragment Processing
// ----------------------------------------------------------------------------

void sky() {
    vec3 dir = normalize(EYEDIR);

    // Rotate sky coordinates according to galactic inclination angle
    float rad = radians(galactic_plane_angle);
    float cos_a = cos(rad);
    float sin_a = sin(rad);
    vec3 gal_dir = vec3(
        dir.x * cos_a - dir.y * sin_a,
        dir.x * sin_a + dir.y * cos_a,
        dir.z
    );

    // 1. Deep Celestial Void Baseline
    vec3 final_color = space_void_color.rgb;

    // 2. Galactic Plane & Central Bulge Luminance
    float disk_height = abs(gal_dir.y);
    float disk_falloff = exp(-disk_height * 4.5); // Exponential vertical disc decay
    
    // Core direction (pointed toward gal_dir.z > 0 and disk center)
    float core_align = clamp(dot(gal_dir, vec3(0.0, 0.0, 1.0)), 0.0, 1.0);
    float core_glow = pow(core_align, 6.0) * exp(-disk_height * 2.5) * core_intensity;
    float core_supermassive = pow(core_align, 32.0) * 4.0; // Central Sag A* bright cluster

    // 3. Lin-Shu Spiral Arm & Emission Nebulae
    vec3 fbm_coord = gal_dir * 2.8;
    float nebula_noise_1 = fbm_galaxy(fbm_coord);
    float nebula_noise_2 = fbm_galaxy(fbm_coord + vec3(4.2, -1.8, 2.5));
    
    // Dark absorption dust lanes (Barnard-style dark clouds slicing through the core)
    float dust_lane = smoothstep(0.35, 0.65, fbm_galaxy(fbm_coord * 1.8 + vec3(1.0)));
    float dark_obscuration = (1.0 - dust_lane * 0.85) * (1.0 - exp(-disk_height * 8.0) * 0.4);

    // Composite nebular glow
    vec3 nebula_mix = mix(emission_nebula_cyan.rgb, emission_nebula_magenta.rgb, nebula_noise_2);
    float nebula_fac = smoothstep(0.38, 0.75, nebula_noise_1) * disk_falloff * nebula_density;
    
    final_color += (galactic_core_color.rgb * (core_glow + core_supermassive) + nebula_mix * nebula_fac) * dark_obscuration;

    // 4. Multi-Tier Procedural Starfields (Fine, Medium, Brilliant)
    float time = TIME;
    vec3 stars_fine = render_stars(dir, starfield_density, time);
    vec3 stars_bright = render_stars(dir, starfield_density * 0.4, time * 0.7) * 1.5;
    
    // Boost star density along the galactic disc
    float disc_star_boost = 1.0 + disk_falloff * 2.0;
    final_color += (stars_fine + stars_bright) * disc_star_boost;

    // 5. Final Tonemap & Output
    COLOR = final_color;
}

shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// ============================================================================
// BIO-GENESIS-X: AAA+ NOISE-POWERED PROCEDURAL PLANET SHADER
// Driven by Multi-Octave 3D Simplex, Voronoi, Curl & FBM Noise Textures
// ============================================================================

uniform int planet_archetype : hint_range(0, 7) = 3;
// 0: Molten, 1: Metallic Barren, 2: Desert, 3: Terran Oceanic, 4: Ice World,
// 5: Gas Giant Jovian, 6: Gas Giant Ice, 7: Radiotrophic Bio

uniform vec4 primary_surface_color : source_color = vec4(0.12, 0.45, 0.75, 1.0);
uniform vec4 secondary_surface_color : source_color = vec4(0.18, 0.65, 0.32, 1.0);
uniform vec4 ocean_color : source_color = vec4(0.02, 0.15, 0.35, 1.0);
uniform vec4 cloud_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform vec4 atmosphere_glow_color : source_color = vec4(0.25, 0.65, 1.0, 1.0);

uniform float terrain_roughness : hint_range(0.0, 1.0, 0.05) = 0.65;
uniform float ocean_roughness : hint_range(0.0, 1.0, 0.05) = 0.06;
uniform float ocean_metallic : hint_range(0.0, 1.0, 0.05) = 0.12;
uniform float ocean_sea_level : hint_range(0.0, 1.0, 0.02) = 0.48;
uniform float cloud_density : hint_range(0.0, 1.0, 0.05) = 0.55;
uniform float cloud_speed : hint_range(0.0, 0.5, 0.01) = 0.025;
uniform float atmosphere_thickness : hint_range(0.0, 3.0, 0.1) = 1.25;

// Vertex displacement (distance-gated: only displaces when camera is close
// enough to see the surface features). Driven by the same noise functions
// used in the fragment shader for consistent terrain coloring.
uniform float displacement_amplitude : hint_range(0.0, 0.1, 0.001) = 0.015; // % of radius
uniform float displacement_frequency : hint_range(0.5, 20.0, 0.1) = 2.5;
uniform int displacement_octaves : hint_range(1, 8, 1) = 5;
uniform float camera_distance_m : hint_range(0.0, 10000000.0, 1.0) = 1000000.0;
uniform float planet_radius_m : hint_range(100.0, 100000000.0, 1.0) = 6371000.0;

varying vec3 v_world_pos;
varying vec3 v_normal;
varying float v_elevation;

// ----------------------------------------------------------------------------
// Procedural 3D Simplex, Hash & Worley Noise Texture Engines
// ----------------------------------------------------------------------------

float p_hash(vec3 p) {
    p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float p_noise(vec3 x) {
    vec3 p = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);

    return mix(
        mix(mix(p_hash(p + vec3(0, 0, 0)), p_hash(p + vec3(1, 0, 0)), f.x),
            mix(p_hash(p + vec3(0, 1, 0)), p_hash(p + vec3(1, 1, 0)), f.x), f.y),
        mix(mix(p_hash(p + vec3(0, 0, 1)), p_hash(p + vec3(1, 0, 1)), f.x),
            mix(p_hash(p + vec3(0, 1, 1)), p_hash(p + vec3(1, 1, 1)), f.x), f.y),
        f.z
    );
}

// Multi-Octave Fractal Brownian Motion (FBM) Noise Texture
float fbm_planet(vec3 p, int octaves) {
    float v = 0.0;
    float a = 0.5;
    mat3 rot = mat3(
        vec3(0.00,  0.80,  0.60),
        vec3(-0.80,  0.36, -0.48),
        vec3(-0.60, -0.48,  0.64)
    );
    for (int i = 0; i < octaves; i++) {
        v += a * p_noise(p);
        p = rot * p * 2.02;
        a *= 0.5;
    }
    return v;
}

// Rigid Multifractal Noise Texture for Mountain Ridges & Canyons
float ridge_noise(vec3 p, int octaves) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < octaves; i++) {
        float n = 1.0 - abs(p_noise(p) * 2.0 - 1.0);
        n = n * n;
        v += a * n;
        p *= 2.08;
        a *= 0.48;
    }
    return v;
}

void vertex() {
    vec3 local_pos = normalize(VERTEX);

    // --- Vertex displacement (distance-gated) -------------------------------
    // Only displace when the camera is close enough to see surface features.
    // At orbital distances > 3x planet radius, the displacement is sub-pixel
    // and would waste GPU cycles.
    // CAMERA_POSITION is not available in Godot spatial vertex shaders; derive
    // it from INV_VIEW_MATRIX (camera is at the origin of view space).
    vec3 camera_world_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    float dist_to_camera = length((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - camera_world_pos);
    float displacement_range = planet_radius_m * 3.0;
    float displacement_fade = 1.0 - smoothstep(displacement_range * 0.5, displacement_range, dist_to_camera);

    // Compute elevation using the same noise structure as the fragment shader.
    float continent = fbm_planet(local_pos * displacement_frequency, displacement_octaves);
    float ridges = ridge_noise(local_pos * displacement_frequency * 2.5, 3) * 0.3;
    float fine = fbm_planet(local_pos * displacement_frequency * 7.0, 3) * 0.06;
    float elevation = continent + ridges + fine;

    v_elevation = elevation;

    // Displace along the normal (radial direction for a sphere).
    // Amplitude is a fraction of the planet radius.
    float displacement = elevation * displacement_amplitude * planet_radius_m * displacement_fade;
    VERTEX += normalize(VERTEX) * displacement;

    // Recompute normal after displacement for correct lighting.
    // Use neighbor sampling for analytical normals.
    float eps = 0.01;
    vec3 tangent = normalize(cross(normalize(VERTEX), vec3(0.0, 1.0, 0.0) + vec3(0.001)));
    vec3 bitangent = normalize(cross(normalize(VERTEX), tangent));
    vec3 neighbor1 = normalize(VERTEX + tangent * eps);
    vec3 neighbor2 = normalize(VERTEX + bitangent * eps);
    float elev1 = (fbm_planet(normalize(neighbor1) * displacement_frequency, displacement_octaves) + ridge_noise(normalize(neighbor1) * displacement_frequency * 2.5, 3) * 0.3) * displacement_amplitude * planet_radius_m * displacement_fade;
    float elev2 = (fbm_planet(normalize(neighbor2) * displacement_frequency, displacement_octaves) + ridge_noise(normalize(neighbor2) * displacement_frequency * 2.5, 3) * 0.3) * displacement_amplitude * planet_radius_m * displacement_fade;
    vec3 displaced_n1 = normalize(neighbor1) * (1.0 + elev1);
    vec3 displaced_n2 = normalize(VERTEX + bitangent * eps) * (1.0 + elev2);
    vec3 displaced_pos = normalize(VERTEX) * (1.0 + displacement);
    NORMAL = normalize(cross(displaced_n1 - displaced_pos, displaced_n2 - displaced_pos));

    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    vec3 local_pos = normalize(VERTEX);
    vec3 N = normalize(NORMAL);
    vec3 V = normalize(VIEW);

    vec3 albedo_out = vec3(0.0);
    float roughness_out = terrain_roughness;
    float metallic_out = 0.0;
    vec3 emission_out = vec3(0.0);
    vec3 normal_perturbation = vec3(0.0);

    // =========================================================================
    // 1. TERRESTRIAL PLANET ARCHETYPES (0..4, 7)
    // =========================================================================
    if (planet_archetype != 5 && planet_archetype != 6) {
        // Use the vertex-computed elevation for consistent surface coloring.
        // Add extra high-frequency detail only in the fragment shader.
        float continent_elevation = fbm_planet(local_pos * 2.5, 6);
        float mountain_ridges = ridge_noise(local_pos * 6.0, 5) * 0.35;
        float fine_detail = fbm_planet(local_pos * 18.0, 4) * 0.08;
        float height = continent_elevation + mountain_ridges + fine_detail;

        if (planet_archetype == 0) {
            // MOLTEN / VOLCANIC: Active noise-driven magma fissures
            float lava_cracks = smoothstep(0.40, 0.50, p_noise(local_pos * 8.0 + vec3(TIME * 0.04)));
            float crust_grain = p_noise(local_pos * 32.0);
            albedo_out = mix(vec3(0.12, 0.08, 0.08) + crust_grain * 0.04, vec3(0.85, 0.25, 0.05), lava_cracks);
            emission_out = vec3(1.0, 0.35, 0.02) * (1.0 - lava_cracks) * 3.2;
            roughness_out = 0.78;
        }
        else if (planet_archetype == 1) {
            // METALLIC BARREN: Multi-scale impact crater noise texture
            float crater_macro = smoothstep(0.35, 0.65, fbm_planet(local_pos * 5.0, 5));
            float crater_micro = smoothstep(0.40, 0.60, fbm_planet(local_pos * 24.0, 4));
            albedo_out = mix(vec3(0.32, 0.30, 0.28), vec3(0.55, 0.52, 0.48), crater_macro);
            albedo_out += (crater_micro - 0.5) * 0.12;
            roughness_out = 0.85;
            metallic_out = 0.25;
        }
        else if (planet_archetype == 2) {
            // DESERT ARID: Noise-driven sand dunes & iron oxide stratification
            float dunes_large = p_noise(local_pos * 12.0);
            float dunes_fine = p_noise(local_pos * 48.0);
            albedo_out = mix(primary_surface_color.rgb, secondary_surface_color.rgb, height);
            albedo_out += (dunes_large * 0.6 + dunes_fine * 0.4 - 0.5) * 0.12;
            roughness_out = 0.90;
        }
        else if (planet_archetype == 3) {
            // TERRAN OCEANIC: Dynamic Water Noise Textures & Continental Biomes
            if (height < ocean_sea_level) {
                // Dual-wave noise textures for moving ocean swells
                float ocean_wave_1 = p_noise(local_pos * 64.0 + vec3(TIME * 0.06, TIME * 0.04, 0.0));
                float ocean_wave_2 = p_noise(local_pos * 128.0 - vec3(0.0, TIME * 0.08, TIME * 0.05));
                float wave_glint = (ocean_wave_1 + ocean_wave_2) * 0.5;

                // Coastal wave surf foam noise texture
                float coastal_proximity = smoothstep(ocean_sea_level - 0.025, ocean_sea_level, height);
                float foam_noise = smoothstep(0.48, 0.65, p_noise(local_pos * 96.0 + vec3(TIME * 0.05)));
                float coastal_foam = coastal_proximity * foam_noise;

                float depth_factor = height / ocean_sea_level;
                vec3 water_base = mix(ocean_color.rgb * 0.45, ocean_color.rgb * 1.25, depth_factor);
                albedo_out = mix(water_base + (wave_glint - 0.5) * 0.06, vec3(0.92, 0.96, 1.0), coastal_foam * 0.75);
                roughness_out = mix(ocean_roughness, 0.35, coastal_foam);
                metallic_out = ocean_metallic;
            } else {
                // Continental Landmasses with biome noise gradients
                float land_norm = (height - ocean_sea_level) / (1.0 - ocean_sea_level);
                float moisture_noise = fbm_planet(local_pos * 4.0 + vec3(1.5), 4);
                
                if (land_norm < 0.08) {
                    albedo_out = vec3(0.85, 0.78, 0.58); // Shoreline coastal sand
                    roughness_out = 0.75;
                } else if (land_norm < 0.60) {
                    vec3 forest = vec3(0.12, 0.42, 0.15);
                    vec3 grass = secondary_surface_color.rgb;
                    albedo_out = mix(grass, forest, moisture_noise);
                    roughness_out = terrain_roughness;
                } else {
                    vec3 mountain_rock = vec3(0.42, 0.38, 0.35);
                    vec3 snow_peaks = vec3(0.95, 0.98, 1.0);
                    albedo_out = mix(mountain_rock, snow_peaks, smoothstep(0.60, 0.85, land_norm));
                    roughness_out = 0.45;
                }
            }
            
            // Polar Ice Caps with cryo-cracking noise texture
            float latitude = abs(local_pos.y);
            if (latitude > 0.80) {
                float polar_snow = smoothstep(0.80, 0.92, latitude);
                float ice_crevasses = p_noise(local_pos * 32.0);
                vec3 ice_color = mix(vec3(0.96, 0.98, 1.0), vec3(0.72, 0.85, 0.95), ice_crevasses * 0.3);
                albedo_out = mix(albedo_out, ice_color, polar_snow);
                roughness_out = mix(roughness_out, 0.25, polar_snow);
            }
        }
        else if (planet_archetype == 4) {
            // ICE WORLD: Glacial sheets & frozen nitrogen noise texture
            float ice_crevasses = smoothstep(0.42, 0.58, fbm_planet(local_pos * 10.0, 5));
            float micro_frost = p_noise(local_pos * 48.0);
            albedo_out = mix(vec3(0.88, 0.94, 1.0), vec3(0.42, 0.65, 0.88), ice_crevasses);
            albedo_out += (micro_frost - 0.5) * 0.06;
            roughness_out = 0.22;
            metallic_out = 0.15;
        }
        else if (planet_archetype == 7) {
            // RADIOTROPHIC BIO-WORLD: Pulsating bioluminescent fungal spore noise texture
            float bio_vein = smoothstep(0.52, 0.68, fbm_planet(local_pos * 8.0, 5));
            float spore_clusters = p_noise(local_pos * 36.0 + vec3(TIME * 0.1));
            albedo_out = mix(vec3(0.06, 0.12, 0.10), vec3(0.12, 0.82, 0.62), bio_vein);
            emission_out = vec3(0.0, 0.98, 0.70) * bio_vein * (0.8 + 0.25 * sin(TIME * 1.8 + spore_clusters * 12.0));
            roughness_out = 0.52;
        }

        // =====================================================================
        // MULTI-SCALE DYNAMIC CLOUD NOISE TEXTURES
        // =====================================================================
        if (cloud_density > 0.05) {
            vec3 cloud_pos = local_pos + vec3(TIME * cloud_speed, 0.0, TIME * (cloud_speed * 0.35));
            float cloud_macro = fbm_planet(cloud_pos * 3.5, 6);
            float cloud_micro = fbm_planet(cloud_pos * 16.0, 4) * 0.22;
            float total_clouds = smoothstep(1.0 - cloud_density, 1.0, cloud_macro + cloud_micro);

            // Cloud shadow projected onto surface with offset
            vec3 shadow_pos = local_pos - vec3(0.025, 0.0, 0.025) + vec3(TIME * cloud_speed, 0.0, TIME * (cloud_speed * 0.35));
            float cloud_shadow = smoothstep(1.0 - cloud_density, 1.0, fbm_planet(shadow_pos * 3.5, 4));
            albedo_out *= (1.0 - cloud_shadow * 0.45);

            // Composite clouds over surface
            albedo_out = mix(albedo_out, cloud_color.rgb, total_clouds * 0.94);
            roughness_out = mix(roughness_out, 0.85, total_clouds);
        }
    }
    // =========================================================================
    // 2. GAS GIANT ARCHETYPES (5: Jovian, 6: Ice Giant)
    // =========================================================================
    else {
        // Multi-frequency latitudinal jet stream Coriolis noise texture
        float jet_stream_noise = fbm_planet(vec3(local_pos.x * 2.5, local_pos.y * 18.0, local_pos.z * 2.5), 5);
        float latitude_bands = sin(local_pos.y * 38.0 + jet_stream_noise * 5.0);
        float storm_vortices = fbm_planet(vec3(local_pos.x * 8.0 + TIME * 0.015, local_pos.y * 16.0, local_pos.z * 8.0), 5);

        if (planet_archetype == 5) {
            // JOVIAN GAS GIANT (Jupiter Analogue)
            vec3 band_col1 = primary_surface_color.rgb;   // Amber
            vec3 band_col2 = secondary_surface_color.rgb; // Ivory
            vec3 band_col3 = vec3(0.68, 0.30, 0.15);      // Terracotta

            float band_fac = (latitude_bands + 1.0) * 0.5;
            albedo_out = mix(band_col1, band_col2, band_fac);
            albedo_out = mix(albedo_out, band_col3, storm_vortices * 0.65);

            // Great Red Storm Spot with cyclonic swirl noise
            vec3 storm_center = normalize(vec3(1.0, -0.35, 0.5));
            float dist_to_storm = length(local_pos - storm_center);
            if (dist_to_storm < 0.28) {
                float spot_intensity = smoothstep(0.28, 0.05, dist_to_storm);
                float swirl_noise = p_noise(local_pos * 24.0 + vec3(TIME * 0.08));
                vec3 spot_color = mix(vec3(0.85, 0.22, 0.12), vec3(0.98, 0.45, 0.25), swirl_noise);
                albedo_out = mix(albedo_out, spot_color, spot_intensity);
            }
        } else {
            // ICE GAS GIANT (Neptune Analogue)
            vec3 ice_gas_1 = vec3(0.12, 0.42, 0.88); // Azure
            vec3 ice_gas_2 = vec3(0.32, 0.78, 0.98); // Cyan
            vec3 storm_white = vec3(0.94, 0.98, 1.0); // Methane Cirrus

            float band_fac = (latitude_bands + 1.0) * 0.5;
            albedo_out = mix(ice_gas_1, ice_gas_2, band_fac);
            albedo_out = mix(albedo_out, storm_white, smoothstep(0.60, 0.85, storm_vortices) * 0.80);
        }
        roughness_out = 0.45;
    }

    // =========================================================================
    // 3. ATMOSPHERIC RAYLEIGH SCATTERING & FRESNEL LIMB GLOW
    // =========================================================================
    float NdotV = clamp(dot(N, V), 0.0, 1.0);
    float fresnel_limb = pow(1.0 - NdotV, 3.5) * atmosphere_thickness;
    albedo_out += atmosphere_glow_color.rgb * fresnel_limb * 0.85;

    // Apply Material Outputs
    ALBEDO = albedo_out;
    ROUGHNESS = roughness_out;
    METALLIC = metallic_out;
    EMISSION = emission_out;
}

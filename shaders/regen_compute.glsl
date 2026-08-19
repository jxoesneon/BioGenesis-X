#[compute]
#version 450
// ============================================================================
// BIO-GENESIS-X: NeuralRegen GPU Compute Self-Healing Shader
// ============================================================================
// Reaction-diffusion (simplified Gray-Scott) model for biological tissue
// healing. Simulates a damage map where:
//   - Channel R (u) = damage concentration (high = wounded)
//   - Channel G (v) = heal chemical concentration (high = healthy tissue)
//
// Healthy tissue (low damage, high heal) produces heal chemical that diffuses
// into wounded areas. Wounded cells near healthy tissue heal faster. This
// mimics biological wound healing: platelets clot, nanites migrate from
// healthy bio-nanite beds, and vascular conduits deliver hemolymph.
//
// Grid: 64x64 cells. Workgroup: 8x8. Dispatch: 8x8 groups.
// ============================================================================

#define GRID_SIZE 64
#define WORKGROUP_SIZE 8

layout(local_size_x = WORKGROUP_SIZE, local_size_y = WORKGROUP_SIZE, local_size_z = 1) in;

// ---------------------------------------------------------------------------
// Input/Output buffers (std430). Each cell is a vec2: (damage, heal_chemical).
// binding 0: current state (read)
// binding 1: next state (write)
// binding 2: simulation parameters (read)
// ---------------------------------------------------------------------------
layout(set = 0, binding = 0, std430) restrict readonly buffer DamageMapIn {
	vec2 cells[];
} stateIn;

layout(set = 0, binding = 1, std430) restrict writeonly buffer DamageMapOut {
	vec2 cells[];
} stateOut;

layout(set = 0, binding = 2, std140) uniform SimParams {
	vec4 params;  // x: feed_rate, y: kill_rate, z: diffusion_rate, w: delta_time
} simParams;

// ---------------------------------------------------------------------------
// Helper: wraparound grid index
// ---------------------------------------------------------------------------
int cellIndex(int x, int y) {
	x = (x + GRID_SIZE) % GRID_SIZE;
	y = (y + GRID_SIZE) % GRID_SIZE;
	return y * GRID_SIZE + x;
}

// ---------------------------------------------------------------------------
// Main: each invocation processes one cell using a 3x3 Laplacian stencil.
// ---------------------------------------------------------------------------
void main() {
	ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
	if (coord.x >= GRID_SIZE || coord.y >= GRID_SIZE) {
		return;
	}

	int idx = coord.y * GRID_SIZE + coord.x;
	vec2 current = stateIn.cells[idx];

	float damage = current.r;   // u: damage concentration
	float heal = current.g;     // v: heal chemical

	float feedRate = simParams.params.x;   // 0.055 — nutrient feed
	float killRate = simParams.params.y;   // 0.062 — damage decay
	float diffRate = simParams.params.z;   // 1.0   — diffusion rate
	float dt = simParams.params.w;         // 0.1   — timestep

	// --- 3x3 Laplacian stencil for diffusion ---
	// Weighted: center=0.5, edges=0.25, corners=0.125 (total = 1.0 + neighbors)
	float lapD = 0.0;
	float lapH = 0.0;

	// Orthogonal neighbors (weight 0.2)
	lapD += stateIn.cells[cellIndex(coord.x - 1, coord.y)].r * 0.2;
	lapD += stateIn.cells[cellIndex(coord.x + 1, coord.y)].r * 0.2;
	lapD += stateIn.cells[cellIndex(coord.x, coord.y - 1)].r * 0.2;
	lapD += stateIn.cells[cellIndex(coord.x, coord.y + 1)].r * 0.2;

	lapH += stateIn.cells[cellIndex(coord.x - 1, coord.y)].g * 0.2;
	lapH += stateIn.cells[cellIndex(coord.x + 1, coord.y)].g * 0.2;
	lapH += stateIn.cells[cellIndex(coord.x, coord.y - 1)].g * 0.2;
	lapH += stateIn.cells[cellIndex(coord.x, coord.y + 1)].g * 0.2;

	// Diagonal neighbors (weight 0.05)
	lapD += stateIn.cells[cellIndex(coord.x - 1, coord.y - 1)].r * 0.05;
	lapD += stateIn.cells[cellIndex(coord.x + 1, coord.y - 1)].r * 0.05;
	lapD += stateIn.cells[cellIndex(coord.x - 1, coord.y + 1)].r * 0.05;
	lapD += stateIn.cells[cellIndex(coord.x + 1, coord.y + 1)].r * 0.05;

	lapH += stateIn.cells[cellIndex(coord.x - 1, coord.y - 1)].g * 0.05;
	lapH += stateIn.cells[cellIndex(coord.x + 1, coord.y - 1)].g * 0.05;
	lapH += stateIn.cells[cellIndex(coord.x - 1, coord.y + 1)].g * 0.05;
	lapH += stateIn.cells[cellIndex(coord.x + 1, coord.y + 1)].g * 0.05;

	// Center weight (-1.0 for Laplacian operator)
	lapD += damage * -1.0;
	lapH += heal * -1.0;

	// --- Gray-Scott reaction-diffusion equations (adapted for healing) ---
	// Damage (u): diffuses, is consumed by heal chemical, decays via kill_rate.
	// Heal (v): diffuses, is produced by healthy tissue, consumed by healing damage.
	float dDamage = diffRate * lapD - damage * heal * heal + feedRate * (1.0 - damage);
	float dHeal = diffRate * 0.5 * lapH + damage * heal * heal - killRate * heal;

	// Heal chemical regenerates in healthy tissue (low damage)
	if (damage < 0.1) {
		dHeal += 0.02 * (1.0 - heal);
	}

	// Integrate
	float newDamage = clamp(damage + dDamage * dt, 0.0, 1.0);
	float newHeal = clamp(heal + dHeal * dt, 0.0, 1.0);

	// Cells near healthy tissue heal faster (proximity bonus)
	float neighborHealth = 0.0;
	neighborHealth += stateIn.cells[cellIndex(coord.x - 1, coord.y)].g;
	neighborHealth += stateIn.cells[cellIndex(coord.x + 1, coord.y)].g;
	neighborHealth += stateIn.cells[cellIndex(coord.x, coord.y - 1)].g;
	neighborHealth += stateIn.cells[cellIndex(coord.x, coord.y + 1)].g;
	neighborHealth *= 0.25;  // average neighbor health

	if (neighborHealth > 0.5 && newDamage > 0.0) {
		newDamage = max(0.0, newDamage - neighborHealth * 0.01 * dt);
	}

	stateOut.cells[idx] = vec2(newDamage, newHeal);
}

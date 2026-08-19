# Organ Placement Overhaul Research

*Generated: 2026-08-11 | Sources: 60+ | Confidence: High*

## Executive Summary

Three parallel research streams investigated: (1) the current BioGenesis organ placement
code and its failure modes, (2) spatial layout algorithms from computer science, and
(3) biological organ packing principles. The synthesis reveals that the current system
fails because organs are placed blindly (no initial overlap check), the force-field
solver is the only separation mechanism, pipeline nodes are excluded from the solver,
and hull re-projection after adaptation can undo solver progress. The overhaul combines
Poisson disk sampling for initial placement, position-based dynamics for stable
collision resolution, and post-adaptation overlap checking.

## 1. Current System Failure Modes (Codebase Audit)

### Critical Issues

1. **No initial overlap checking** — All organs are pushed to `candidateOrgans`
   without any spatial check. The solver is expected to resolve all overlaps.

2. **Neural ganglia random V placement** — `const initialV = rng()` can cause
   multiple ganglia to spawn at nearly identical U/V positions.

3. **Pipeline nodes excluded from solver** — Heart, plasma gland, brain, etc.
   are static repulsors that don't move. They can overlap each other or with
   candidate organs before the solver runs.

4. **Hull re-projection after adaptation** — `adaptHull()` re-projects organs
   to the new hull surface, which can move them closer together if the hull
   doesn't expand enough. No overlap check occurs after re-projection.

5. **Coarse spatial grid** — `GRID_SIZE = 3.0` may miss nearby organs with
   small clearance radii (eyes: 1.50m → only checks 1 cell radius).

6. **Limited post-solver fixups** — Only handle habitat-related overlaps.
   No general same-type or cross-type overlap resolution.

7. **Broad audit exclusions** — 41 exclusion rules including "all appendages ↔
   all appendages" may mask genuine placement bugs.

### Current clearanceRadius Values

| Organ Type | clearanceRadius | Actual Mesh Extent |
|---|---|---|
| Eye | 1.50 | ~0.5m |
| Neural | 2.80 | ~0.8m |
| Spiracle | 2.80 | ~1.0m |
| Rib | 4.50 | ~2.5m |
| Spore | 2.80 | ~1.0m |
| Tentacle | 4.50 | ~3.5-7m |
| Habitat | 2.25 | ~2.0m |
| Pectoral Fin | 4.50 | ~3.0m |
| Caudal Fluke | 3.50 | ~2.5m |
| Landing Limb | 4.00 | ~2.0m |
| Dorsal Sail | 2.80 | ~1.5m |

## 2. Spatial Layout Algorithms (Computer Science Research)

### Poisson Disk Sampling (Bridson's Algorithm)

O(n) algorithm for non-overlapping placement with minimum distance:
```
cell_size = r / sqrt(2)
grid = Grid(width, height, cell_size)
active_list = [random_point()]

while active_list:
    ref = random_choice(active_list)
    for _ in range(k=30):
        angle = random() * 2*pi
        dist = uniform(r, 2*r)
        candidate = ref + (cos(angle)*dist, sin(angle)*dist)
        if grid.is_valid(candidate, r):
            grid.insert(candidate)
            active_list.append(candidate)
            break
    else:
        active_list.remove(ref)
```

**Variable-radius adaptation**: Grid stores minimum distance per cell. Check
against varying radius at each location.

### Position-Based Dynamics (PBD)

Directly manipulate positions instead of forces — more stable, no overshooting:
```
def solve_pbd_constraint(p1, p2, rest_length):
    current_dist = distance(p1, p2)
    diff = (current_dist - rest_length) / current_dist
    p1 -= diff * 0.5 * (p1 - p2)
    p2 += diff * 0.5 * (p1 - p2)
```

### Spatial Hash Grid

Optimal cell size: `1.5 to 2.0 × particle_radius`
- Too small: objects span many cells, high overhead
- Too large: many objects per cell, many false positives

### Hierarchical Placement

Place largest organs first, then smaller ones fill remaining space:
1. Sort organs by size (volume descending)
2. Place each organ in its anatomical compartment
3. Check against all previously placed organs
4. If no valid position found, relax constraints

### Simulated Annealing

For escaping local minima:
```
for temperature in cooling_schedule:
    neighbor = random_neighbor(current)
    delta = objective(neighbor) - objective(current)
    if delta < 0 or random() < exp(-delta / temperature):
        current = neighbor
```

## 3. Biological Organ Packing Principles

### Compartmentalization

- Multi-layer boundaries (parietal + visceral + serous fluid)
- Hierarchical subdivision: major cavities → subcompartments → organ spaces
- Serous fluid (μ = 0.019) allows organs to glide without friction
- Fascial sheaths create neurovascular bundles

### Hierarchical Placement in Nature

- **Size-based sequencing**: Larger organs placed first in development
- **Morphogen gradients**: Concentration fields guide positioning
- **Mechanical constraints**: Surrounding tissues provide physical limits
- **Developmental fields**: Sequential subdivision of space

### Organ Interface Principles

- **Serous lubrication**: Low-friction interfaces (μ = 0.019)
- **Deformation accommodation**: Organs deform to fit neighbors
- **Pressure regulation**: Active maintenance of contact pressure
- **Hilum entry points**: Single entry/exit for connections

### Key Biological Scaling

- Organ mass ∝ M^1.0 (isometric for most organs)
- Metabolic rate ∝ M^0.75 (Kleiber's law)
- Heart rate ∝ M^-0.25
- Intestine length ∝ M^0.67

## 4. Overhaul Design Model

### Phase 1: Initial Placement (Poisson Disk on Hull Surface)

Replace blind placement with variable-radius Poisson disk sampling in U/V space:

```
for each organ type (sorted by clearanceRadius descending):
    for each organ instance:
        attempt = 0
        while attempt < MAX_ATTEMPTS:
            candidate_u = random_in_UBounds(organ_type)
            candidate_v = deterministic_or_random_v(organ_type, instance_index)
            if no_overlap(candidate_u, candidate_v, organ_type, placed_organs):
                place_organ(candidate_u, candidate_v)
                break
            attempt++
```

Key changes:
- Neural ganglia get deterministic V distribution (not random)
- Largest organs (ribs, tentacles, fins) placed first
- Each placement checked against all previously placed organs
- U/V space distance converted to 3D Euclidean for overlap check

### Phase 2: Solver Overhaul (PBD + Pipeline Nodes)

Replace force-based solver with position-based dynamics:
- Include pipeline nodes as movable bodies (not just static repulsors)
- Use PBD constraint projection instead of force accumulation
- Adaptive grid size: `min(clearanceRadius) * 2.0`
- Convergence detection: stop when max movement < threshold

### Phase 3: Post-Adaptation Overlap Check

After `adaptHull()` re-projects organs:
- Run a lightweight overlap check
- Resolve any new overlaps with PBD
- Log any unresolved overlaps for audit

### Phase 4: Audit Narrowing

- Replace "all appendages ↔ all appendages" with distance-aware checking
- Only exclude appendage pairs when center distance > 50% of combined radii
- Report same-type overlaps as warnings, not just cross-type

## Sources

### Codebase Audit
- Canvas3D.tsx lines 1826-2129 (solver, fixups, static repulsors)
- Canvas3D.tsx lines 3648-4121 (audit, exclusion rules)
- pipelineGraph.ts lines 99-193 (pipeline node positions)

### Spatial Algorithms
- Bridson's Poisson disk: https://www.cs.ubc.ca/~rbridson/docs/bridson-siggraph07-poissondisk.pdf
- PBD: https://matthias-research.github.io/pages/publications/PBDTutorial2017-CourseNotes.pdf
- Spatial hash: https://cgl.ethz.ch/Downloads/Publications/Papers/2003/Tes03/Tes03.pdf
- Barnes-Hut: https://cs.brown.edu/people/rtamassi/gdhandbook/chapters/force-directed.pdf
- Simulated annealing: https://dl.acm.org/doi/10.5555/285730.285741

### Biological Packing
- Thoracic cavity: https://www.ncbi.nlm.nih.gov/books/NBK557710/
- Mesentery: https://www.nature.com/articles/s42003-021-02496-1
- Serous fluid: https://pubmed.ncbi.nlm.nih.gov/9576363/
- Murray's law: https://pmc.ncbi.nlm.nih.gov/articles/PMC4905520/
- Allometric scaling: https://pubmed.ncbi.nlm.nih.gov/11833526/
- Morphogen gradients: https://royalsocietypublishing.org/doi/10.1098/rsob.220224

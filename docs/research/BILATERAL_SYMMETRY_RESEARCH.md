# Bilateral Symmetry Research

*Generated: 2026-08-11 | Sources: 50+ | Confidence: High*

## Executive Summary

Three parallel research streams investigated: (1) bilateral symmetry in nature,
(2) the current BioGenesis symmetry code, and (3) 3D reflection techniques.

The root cause of the missing bilateral mirror symmetry is a **V-coordinate bug**:
`getSymmetryVCoords('bilateral')` returns `[0.18, 0.68]`, which produces **diagonal
symmetry** (mirrored across the origin), not **bilateral mirror symmetry** across
the X=0 plane. The correct values are `[0.0, 0.5]` (starboard at X=+r, port at X=-r).

## 1. V-to-3D Position Mapping

The hull surface sampling uses:
```
angle = V × 2π
X = xArch + cos(angle) × r
Y = yArch + sin(angle) × r
Z = z
```

| V | Angle | cos | sin | Position |
|---|---|---|---|---|
| 0.0 | 0° | +1 | 0 | X=+r (starboard), Y=0 |
| 0.25 | 90° | 0 | +1 | X=0, Y=+r (dorsal) |
| 0.5 | 180° | -1 | 0 | X=-r (port), Y=0 |
| 0.75 | 270° | 0 | -1 | X=0, Y=-r (ventral) |

**Bilateral mirror across X=0 plane**: V and V+0.5 are mirror pairs.
- V=0.0 (starboard) ↔ V=0.5 (port) — both at Y=0 ✓
- V=0.1 (upper-starboard) ↔ V=0.6 (upper-port) — both at same Y ✓

## 2. The Bug

Current bilateral V coordinates: `[0.18, 0.68]`
- V=0.18 → angle=64.8° → X≈+0.31r, Y≈+0.95r (upper-right)
- V=0.68 → angle=244.8° → X≈-0.31r, Y≈-0.95r (lower-left)

These are **diagonal mirrors** (both X and Y opposite), not bilateral mirrors.

## 3. Biological Principles

### Bilateral Symmetry in Nature
- Body divided into two mirror halves along the **sagittal plane** (midline)
- Left-right axis is the **last** to be established in development
- Paired organs: eyes, ears, kidneys, lungs, limbs, fins, ribs, gills
- Midline organs: spine, brain, digestive tract
- Asymmetric organs: heart (left), liver (right), stomach (left)

### Symmetry Establishment
- Nodal cilia generate leftward flow at the "node" (LRO)
- Nodal gene expressed on left side only
- Lefty acts as midline barrier preventing bilateral expression
- Pitx2 drives asymmetric morphogenesis

### Paired Organ Development
- Same genetic program runs on both sides
- Midline signaling (Shh from notochord) patterns both sides equally
- Somites form synchronously on left and right
- ZPA + AER coordinate limb development bilaterally

## 4. Correct V Values for Bilateral Symmetry

### Paired Organs (Port ↔ Starboard)
| Organ | Starboard V | Port V | Y Position |
|---|---|---|---|
| Spiracle | 0.0 | 0.5 | Y=0 (equator) |
| Rib | 0.0 | 0.5 | Y=0 |
| Eye | 0.1 | 0.6 | Slightly dorsal |
| Pectoral Fin | 0.05 | 0.55 | Slightly ventral |
| Caudal Fluke | 0.1 | 0.6 | Slightly dorsal |
| Tentacle | 0.05 | 0.55 | Slightly ventral |
| Spore | 0.1 | 0.6 | Slightly dorsal |

### Midline Organs (Dorsal or Ventral)
| Organ | V | Position |
|---|---|---|
| Dorsal Sail | 0.25 | Dorsal ridge (Y=+r) |
| Neural (midline) | 0.25 | Dorsal ridge |

### Habitat Pairs (X-mirrored)
| Pair | Starboard V | Port V |
|---|---|---|
| 1 | 0.1 | 0.6 |
| 2 | 0.15 | 0.65 |
| 3 | 0.2 | 0.7 |
| 4 | 0.05 | 0.55 |

### Landing Limb Pairs (X-mirrored)
| Pair | Starboard V | Port V |
|---|---|---|
| 1 | 0.1 | 0.6 |
| 2 | 0.15 | 0.65 |
| 3 | 0.05 | 0.55 |

## 5. 3D Reflection Formula

For X=0 plane (Y-Z plane):
```
(x, y, z) → (-x, y, z)
```

In V-space: V and (V + 0.5) mod 1.0 are mirror pairs across X=0.

## Sources

### Bilateral Symmetry in Nature
- Britannica: https://www.britannica.com/science/symmetry-biology
- PMC (Urbilateria): https://pmc.ncbi.nlm.nih.gov/articles/PMC2614228/
- PMC (L-R patterning): https://pmc.ncbi.nlm.nih.gov/articles/PMC7443379/
- Palmer Primer (FA): https://grad.biology.ualberta.ca/palmer.hp/pubs/94Primer/Primer.pdf

### 3D Reflection
- Math StackExchange: https://math.stackexchange.com/questions/1974655
- Three.js mirroring: https://github.com/mrdoob/three.js/issues/4904
- Blender mirror modifier: https://docs.blender.org/manual/en/latest/modeling/modifiers/generate/mirror.html

### Procedural Symmetry
- Spore Creature Creator: https://interactioncultureclass.wordpress.com/2009/12/06/
- No Man's Sky: https://www.gamedeveloper.com/programming/what-the-code-of-i-no-man-s-sky-i-says
- Subnautica ECCLibrary: https://github.com/LeeTwentyThree/ECCLibrary

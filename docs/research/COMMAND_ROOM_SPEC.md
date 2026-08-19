# Command Room Specification — Geometry, Crew, and Window Cut

> **Status**: Approved design — ready for implementation
> **Date**: 2026-08-12
> **Author**: Ciel (Lord of Wisdom) + Master
> **Sources**: NASA JSC Design Standards, Apollo/LM/Shuttle window design,
>   Royal Navy submarine control room research, Star Trek bridge layout

---

## 1. Purpose

The command room is the human habitat interface layer at the head of the ship.
It is a square room extruded from the cranial hull section, with a window
cut at a defined angle plane. It houses 1-5 human crew in individual
workstations with negative-gravity grounding.

This is the "comfort bubble" — the Frutiger Aero / skeuomorphic futurism
layer from the BioGenesis aesthetic direction. Clean, bright, human-scale,
contrasting with the alien biology surrounding it.

---

## 2. Crew Roles (5 Stations)

Based on submarine command teams (Royal Navy Astute class research),
NASA mission control positions, and Star Trek bridge layout:

| # | Role | Station Name | Primary Systems | Neural-Link Channel |
|---|---|---|---|---|
| 1 | **Commander** | Command Station | Neural-link to brain, overall command, overclocking authority | Direct brain ↔ pilot |
| 2 | **Helm** | Helm Station | Propulsion, navigation, ship movement | Spinal cord motor |
| 3 | **Bio-Systems Officer** | Bio-Systems Station | Organ health, regeneration, metabolism monitoring | Autonomic ganglia |
| 4 | **Tactical** | Tactical Station | Spores, bio-plasma weapons, armor defense | Weapon ganglia |
| 5 | **Science/Sensors** | Science Station | Ocular pods, scanning, research | Sensory ganglia |

### 2.1 Crew Capacity Scaling

Room scales on integers (1-5) based on ship size:

| Ship length | Crew capacity | Room volume | Notes |
|---|---|---|---|
| 6m | 1 | ~19 m³ | Commander only — strained ship |
| 10m | 2 | ~27 m³ | Commander + Helm |
| 14m (default) | 3 | ~35 m³ | Commander + Helm + Bio-Systems |
| 20m | 4 | ~43 m³ | + Tactical |
| 30m+ | 5 | ~55 m³ | Full crew + Science |

```typescript
function crewCapacity(shipLength: number): number {
  if (shipLength <= 7) return 1;
  if (shipLength <= 12) return 2;
  if (shipLength <= 17) return 3;
  if (shipLength <= 25) return 4;
  return 5;
}
```

### 2.2 Workstation Sizing

Each workstation: ~2m × 2m × 2.5m (large cubicle equivalent)
Fixed overhead: ~15 m³ (walls, life support, shared central display)

```typescript
const STATION_FOOTPRINT = 2.0;  // meters, square
const STATION_HEIGHT = 2.5;     // meters
const STATION_VOLUME = STATION_FOOTPRINT * STATION_FOOTPRINT * STATION_HEIGHT; // 10 m³
const FIXED_OVERHEAD = 15.0;    // m³ (walls, life support, shared display)

function commandRoomVolume(crewCount: number): number {
  return crewCount * STATION_VOLUME + FIXED_OVERHEAD;
}
```

Room dimensions (square footprint):
```typescript
function commandRoomDimensions(crewCount: number) {
  const volume = commandRoomVolume(crewCount);
  const height = STATION_HEIGHT + 0.5; // ceiling clearance
  const footprint = volume / height;
  const side = Math.sqrt(footprint); // square room
  return { width: side, depth: side, height };
}
```

---

## 3. Geometry — Window Cut Specification

### 3.1 Coordinate System

The command room sits in the cranial section (u ≈ 0.05-0.12) of the hull.
The hull surface at this location defines the exterior boundary.

```
                    ┌─────────────────────────┐
                    │   COMMAND ROOM           │
                    │   (square section)       │
                    │                          │
   max window  ────┤═════════════════════════════════ ← top exterior edge
   angle plane ──→ │    window cut into        │
                   │    hull by extruding      │
                   │    the square outward     │
                   │                          │
   min window  ────┤                          │
   angle plane ──→ │                          │
                    │                          │
   hull skin  ────┤═════════════════════════════════ ← bottom exterior edge
   (few cm below)  │                          │
                    └─────────────────────────┘

   ← interior of ship          exterior of ship →
```

### 3.2 Three Critical Constraints

**Constraint 1 — Lower Exterior Edge (Skin Depth)**:
```
bottomExteriorY = hullSurfaceY(cranialU) - SKIN_DEPTH
  where SKIN_DEPTH = 0.05m (5 cm — accounts for hull skin thickness)
```
The room's floor sits just inside the hull, 5cm below the exterior surface.

**Constraint 2 — Top Exterior Edge (Maximum Window Angle)**:
```
topExteriorY = bottomExteriorY + roomHeight

maxWindowAngle = angle from horizontal at topExteriorY
  where a plane from this edge extends outward through the hull
  → this plane CUTS a window opening into the hull
  → the square room shape is extruded outward at this angle
```
The window is created by boolean subtraction: the square extrudes through
the hull at the maxWindowAngle, creating an opening.

**Constraint 3 — Minimum Window Angle**:
```
topInteriorY = topExteriorY - roomDepth (interior edge)

minWindowAngle = angle from topInteriorY to bottomExteriorY
  → defines the minimum viewing angle from the interior
```

### 3.3 Window Cut Implementation

The window is a planar cut through the hull:

```typescript
interface CommandRoomGeometry {
  // Position
  cranialU: number;           // u-coordinate on hull (0.05-0.12)
  centerPos: THREE.Vector3;   // world-space center of room

  // Dimensions
  width: number;              // square room width
  depth: number;              // square room depth (= width)
  height: number;             // room height

  // Edges (world-space Y coordinates)
  bottomExteriorY: number;    // hull surface - skinDepth
  topExteriorY: number;       // bottomExteriorY + height
  topInteriorY: number;       // topExteriorY - depth

  // Angles
  maxWindowAngle: number;     // radians from horizontal at topExteriorY
  minWindowAngle: number;     // radians from topInteriorY to bottomExteriorY

  // Window cut
  windowPlane: THREE.Plane;   // the cutting plane at maxWindowAngle
  windowMesh: THREE.Mesh;     // the glass/viewport mesh
}
```

### 3.4 Window Glass

The window is a flat pane of glass sitting in the cut plane:
- Material: transparent, slight cyan tint (Frutiger Aero aesthetic)
- Slight reflection (envMap from RoomEnvironment)
- Frame: thin metallic border (cassette futurism aesthetic)
- Shape: rectangular, matching the square room's extrusion through hull

### 3.5 Room Interior

The room interior uses the Interface Layer aesthetic:
- **Walls**: Glossy white panels with rounded organic curves
- **Floor**: Bright accent color (cyan #00CED1)
- **Ceiling**: Translucent panels revealing bioluminescent amber backlighting
  (#FFB347) — the ship is alive, you can see it through the clean surface
- **Central display**: Shared holographic situation display (hovering sphere)
- **Workstations**: 5 Skeuomorphic console chairs with holographic interfaces
- **Lighting**: Bright, even, human-comfortable (contrasts with dark biology)

### 3.6 Negative Gravity Grounding

The room has a negative-gravity field that keeps humans grounded:
- Not zero-G (floating) — negative-G (pressed to floor)
- Allows normal walking, sitting, operating
- Visual: subtle floor glow indicating the gravity field
- No floating objects, no restraints needed

---

## 4. Visibility Toggle

```typescript
// In AppState
showCommandRoom: boolean;  // toggle in GeneticsDrawer
```

The command room is part of the Life Support system group but has its own
toggle for independent visibility control. When hidden, the hull section
where the room would be remains solid (no window cut visible).

---

## 5. Implementation Notes

### 5.1 Hull Boolean Subtraction

The window cut requires modifying the hull mesh at the cranial section.
Three.js does not have built-in CSG, so we use one of:

1. **Manual vertex manipulation**: Remove/modify hull vertices in the
   window region and create new faces for the window opening.
2. **Three-CSG addon**: Use constructive solid geometry to subtract
   the room volume from the hull.
3. **Overlay approach**: Don't cut the hull — place the room and window
   as an overlay mesh that visually appears to cut through (simpler,
   less accurate but avoids CSG complexity).

**Recommended**: Start with approach 3 (overlay) for initial implementation.
The room sits on the hull surface with the window as a transparent plane
that visually reads as a cut. Upgrade to true CSG later if needed.

### 5.2 Crew Station Meshes

Each station is a simple mesh:
- Chair: rounded, ergonomic, glossy white
- Console: curved holographic display (translucent cyan plane)
- Footprint: 2m × 2m
- Arranged in a semicircle facing the window

```typescript
function createCrewStation(role: string, index: number, totalCrew: number): THREE.Group {
  // Semicircle arrangement facing forward (window)
  const angle = -Math.PI/3 + (index / Math.max(1, totalCrew - 1)) * (2 * Math.PI/3);
  const radius = 1.5; // distance from center
  // ... chair mesh, console mesh, holographic display
}
```

### 5.3 Integration with Existing Systems

- Command room is placed at cranial U position
- Commander station has a visible neural-link connection to the Brain Core
  (a glowing fiber from the chair to the brain mesh)
- Room visibility: `showCommandRoom && showSystemLifeSupport`
- Room is NOT a candidate organ — it's a fixed structural element
- Room size affects ship mass and energy consumption (life support load)

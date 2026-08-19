# Engineering Editor Limitations — Full Ship Wiring Audit

> **Date**: 2026-08-13
> **Author**: Devin (Ciel channel)
> **Method**: Systematic code trace of `EngineeringView.tsx` connect tool,
> `ORGAN_NODES` port model, `CONDUIT_PATHS`, `shipRequirements.ts` validator,
> and browser verification of organ placement.

---

## Summary

A fully featured ship requires 19 manually-placed organs across 5 pipelines,
connected by 17 connections (some auto-creating conduit organs). The current
engineering editor can place all 19 organs and create most connections, but
has **12 significant limitations** that prevent wiring a complete,
validator-clean ship.

---

## Limitation Catalog

### L1 — Port auto-match fails for conduit-mediated connections

**Severity**: High — affects 4 of 17 required connections

When connecting two organs that need a conduit between them (e.g.
`plasma_bladder → siphon_vent_nozzle`), the port auto-match fails because
the source organ's output port points to the **intermediate conduit nodeId**
(`plasma_trunk`), not the final target (`siphon_vent_nozzle`).

**Affected connections**:
- `plasma_bladder → siphon_vent_nozzle` (auto: plasma_trunk, caudal_manifold)
- `plasma_bladder → disruptor_gland` (auto: plasma_trunk)
- `hemolymph_atrium → spiracle_vent` (auto: aorta_highway, flank_artery)
- `neuro_link → muscle_tendon` (auto: axon_cord)

**Current behavior**: The connection IS created (with null port labels), and
conduits ARE auto-generated. But the connection line renders center-to-center
instead of port-to-port, and the port labels are missing.

**Fix**: When auto-match fails and a conduit path exists, use the first
conduit's input port as the source port's target, and the last conduit's
output port as the target port's source.

---

### L2 — No neural control ports on non-nervous organs

**Severity**: High — validator flags ALL non-nervous organs

The validator (`checkCompute`) requires ALL organs to have a connection path
to the Brain Core. But non-nervous organs (plasma, hemolymph, life support,
armor) don't have neural input/output ports in `ORGAN_NODES`.

**Current behavior**: You can still connect them at the organ-body level
(clicking the organ circle, not a specific port), which creates a connection
with null ports. The validator's `areConnected()` transitive check then
passes. But the connection has no port label and renders center-to-center.

**Fix**: Add a generic `neural` input port to every non-nervous organ:
```ts
plasma_gland: [...existing ports, { nodeId: 'brain_core', direction: 'in', label: 'Neural' }]
```
Or add a secondary connection type ("neural link") that doesn't require
port matching.

---

### L3 — No vascular supply ports on non-hemolymph organs

**Severity**: High — validator flags ALL non-hemolymph organs

Same as L2 but for hemolymph supply. The validator (`checkVascular`) requires
ALL organs to be connected to the Heart Core. But non-hemolymph organs don't
have vascular input ports.

**Fix**: Add a generic `hemolymph` input port to every non-hemolymph organ:
```ts
plasma_gland: [...existing ports, { nodeId: 'heart_core', direction: 'in', label: 'Blood' }]
```

---

### L4 — No visual feedback for rejected connections

**Severity**: Medium — UX confusion

When a port mismatch causes a connection to be rejected (lines 1970-1976),
the tool silently re-arms with the new organ as the source. There's no
tooltip, toast, or status message explaining why the connection was rejected.

**Fix**: Add a transient status message (e.g. "Port mismatch: Plasma output
doesn't match Brain input — re-armed") that appears for 2-3 seconds.

---

### L5 — No valid-target highlighting in connect mode

**Severity**: Medium — UX confusion

When in connect mode with a source organ selected, there's no highlighting
of which organs are valid connection targets. The user has to know from
memory which organs are compatible.

**Fix**: When `connectFromId` is set, highlight valid target organs with a
glowing outline. Valid targets = organs that have an input port matching
the source organ's nodeId, or organs that have a conduit path from the
source.

---

### L6 — No duplicate connection prevention

**Severity**: Low — data integrity

The code doesn't check if the same `fromId → toId` connection already
exists. You can create duplicate connections by clicking the same two
organs multiple times.

**Fix**: Before creating a connection, check:
```ts
const exists = connections.some(c =>
  (c.fromId === connectFromId && c.toId === hit.id) ||
  (c.fromId === hit.id && c.toId === connectFromId)
);
if (exists) { /* show message, cancel */ }
```

---

### L7 — No input port occupancy tracking

**Severity**: Low — visual clarity

Multiple connections can target the same input port. There's no visual
indication of which ports are already connected, and no limit on how many
connections a single input port can accept.

**Fix**: Render connected ports with a filled appearance vs. hollow for
unconnected. Optionally limit 1 connection per input port (biologically
realistic — one vein per organ interface).

---

### L8 — Command room is not connectable via the tool

**Severity**: Medium — missing feature

The `neuro_link` has an output port to `command_room`, but there's no
placeable organ with `nodeId: 'command_room'`. The command room is a fixed
structural element rendered directly on the canvas. Its crew station nodes
are visual only — they can't be connected to via the connect tool.

**Current behavior**: The `neuro_link → command_room` port exists in
`ORGAN_NODES` but can never be used because there's no organ to click.

**Fix**: Either (a) make the command room's pilot port a clickable hit
target in `hitTestPort`/`hitTestOrgan`, or (b) auto-create the
neuro_link → command_room connection when a neuro_link is placed
(since the command room always exists).

---

### L9 — No conduit paths for cross-pipeline supply connections

**Severity**: Medium — visual simplification

Cross-pipeline connections like `bio_moss → heart_core` (O₂ delivery) and
`bio_moss → brain_core` (O₂ delivery) are always direct connections. In
reality, oxygenated hemolymph would flow through arteries. The model treats
these as point-to-point links with no vascular conduit.

**Fix**: Add cross-pipeline conduit paths:
```ts
'bio_moss→heart_core': ['flank_artery'],
'bio_moss→brain_core': ['aorta_highway'],
```

---

### L10 — Port validation only when BOTH ports are specified

**Severity**: Medium — data integrity

The port compatibility check (lines 1966-1977) only runs when both
`fromPort` and `toPort` are non-null. If the user clicks a specific port on
one organ but clicks the body of the other, only one port is set, and the
validation is skipped. This can create connections with misleading port
labels (e.g. a 'Plasma' output port label on a connection to the brain).

**Fix**: Validate even when only one port is specified:
```ts
if (fromPort && fromPort.nodeId !== hit.nodeId) { /* reject */ }
if (toPort && toPort.nodeId !== fromOrgan.nodeId) { /* reject */ }
```

---

### L11 — Auto-conduit positioning is naive midpoint interpolation

**Severity**: Low — visual quality

Auto-conduits are placed at evenly-spaced midpoints along a straight line
between source and target. If organs are far apart, conduits can overlap
with other organs or sit in anatomically incorrect positions (e.g. a plasma
trunk crossing through the brain).

**Fix**: Route conduits along the spine axis (centerline) or use a
pathfinding algorithm that avoids other organs. At minimum, add a slight
curve to the conduit path.

---

### L12 — No connection between chitin_vertebra and axon_cord

**Severity**: Low — missing port

The vertebrae protect the axon cord anatomically (the spinal cord runs
through the vertebrae). The validator checks for this relationship
textually, but there's no port on either organ for this connection. You
can't connect `chitin_vertebra → axon_cord` using the connect tool because
neither organ has a port pointing to the other.

**Fix**: Add a port:
```ts
chitin_vertebra: [...existing, { nodeId: 'axon_cord', direction: 'out', label: 'Spine' }]
axon_cord: [...existing, { nodeId: 'chitin_vertebra', direction: 'in', label: 'Spine' }]
```

---

## Connection Matrix

Below is the full set of connections needed for a complete ship, with
status:

| # | From | To | Type | Conduit Auto-Created | Port Match | Status |
|---|------|----|------|---------------------|------------|--------|
| 1 | plasma_gland | plasma_bladder | intra | — | ✅ | ✅ Works |
| 2 | plasma_bladder | siphon_vent_nozzle | intra | plasma_trunk, caudal_manifold | ❌ null | ⚠️ L1 |
| 3 | plasma_bladder | disruptor_gland | intra | plasma_trunk | ❌ null | ⚠️ L1 |
| 4 | heart_core | hemolymph_atrium | intra | — | ✅ | ✅ Works |
| 5 | hemolymph_atrium | spiracle_vent | intra | aorta_highway, flank_artery | ❌ null | ⚠️ L1 |
| 6 | brain_core | neuro_link | intra | — | ✅ | ✅ Works |
| 7 | neuro_link | muscle_tendon | intra | axon_cord | ❌ null | ⚠️ L1 |
| 8 | ice_gizzard | bio_moss | intra | — | ✅ | ✅ Works |
| 9 | bio_moss | habitat_chamber | intra | — | ✅ | ✅ Works |
| 10 | habitat_chamber | cyber_airlock | intra | — | ✅ | ✅ Works |
| 11 | chitin_vertebra | carapace_plate | intra | — | ✅ | ✅ Works |
| 12 | carapace_plate | bio_nanite_bed | intra | — | ✅ | ✅ Works |
| 13 | bio_nanite_bed | shield_emitter | intra | — | ✅ | ✅ Works |
| 14 | ice_gizzard | plasma_gland | cross | — | ✅ | ✅ Works |
| 15 | bio_moss | heart_core | cross | — | ✅ | ✅ Works |
| 16 | bio_moss | brain_core | cross | — | ✅ | ✅ Works |
| 17 | ocular_pod | brain_core | cross | — | ✅ | ✅ Works |
| 18 | * → brain_core (neural control) | ALL non-nervous | cross | — | ❌ no port | ⚠️ L2 |
| 19 | heart_core → * (vascular supply) | ALL non-hemolymph | cross | — | ❌ no port | ⚠️ L3 |
| 20 | neuro_link | command_room | intra | — | ❌ no organ | ⚠️ L8 |
| 21 | chitin_vertebra | axon_cord | cross | — | ❌ no port | ⚠️ L12 |

**Summary**: 13 of 17 primary connections work correctly. 4 have null ports
due to conduit auto-match failure (L1). 3 additional connection types are
missing entirely (L2, L3, L8, L12).

---

## Browser Testing Limitations

During browser verification, the Playwright `browser_click` tool always
clicks at the center of the target element. Since the canvas fills the
viewport, all clicks land at (756, 367) — the same screen position. This
means:

- All organs stack at the same world position.
- You can't place organs at different locations.
- You can't test port-to-port connections (organs overlap).
- You can't test the connect tool with separated organs.

Synthetic `MouseEvent` dispatch via `evaluate()` doesn't trigger React's
event delegation properly. Only native Playwright clicks work, but they're
limited to center-of-element.

**Recommendation**: Add a dev-mode `placeOrganAt(nodeId, wx, wz)` function
exposed on `window` for automated testing, or add keyboard shortcuts to
place organs at the cursor position with offset.

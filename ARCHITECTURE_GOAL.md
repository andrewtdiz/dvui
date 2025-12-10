# High-Level Architecture: Bun/Solid → Zig Retained-Mode Renderer

## Overview
This architecture divides UI responsibilities between two coordinated layers:

- **Solid JS running inside Bun** determines *what the UI should be* through reactivity and diffing.
- **Zig** determines *how the UI is laid out, painted, and drawn* using a retained-mode scene graph and incremental rendering.

Communication across the FFI boundary consists of **small mutation operations**, not entire UI trees. Zig keeps all authoritative render state and only updates the parts of the scene that changed.

---

## JS Layer (Bun + Solid): UI Logic & Diff Production
Solid runs normally inside Bun, maintaining components, signals, and JSX output.  
When state changes:

- Solid updates the affected parts of the component tree.
- It diffs its virtual display list against the previous render.
- It emits **incremental operations** describing what changed.

Examples of FFI calls from JS to Zig:

- `createNode(id, type, props, parentId)`
- `updateNode(id, newProps)`
- `moveNode(id, newParent)`
- `removeNode(id)`

Solid does *not* send full frames—only the minimal deltas.  
It batches these ops and invokes something like `flushFrame()` only when needed.

---

## Zig Layer: Retained Scene Graph, Layout, Paint
Zig receives incremental updates and applies them to a **persistent scene graph**, where each node stores:

- structure (parent, children)
- props/style data
- cached layout results
- cached paint/geometry buffers
- dirty flags for layout and painting

Zig’s pipeline is incremental:

### Layout
Only nodes marked dirty (and their ancestors as needed) are recomputed.  
Unchanged subtrees reuse cached layout data.

### Paint
Nodes cache their geometry (triangles, glyph meshes, etc.).  
Painting happens only for nodes flagged `paintDirty`, with buffers updated in place from pooled resources.

### Dirty Region Tracking
Zig computes rectangular regions that changed based on old/new layout bounds.  
Only these regions are repainted, and only nodes intersecting them are processed.

This matches how browsers minimize work each frame.

---

## FFI Coordination: Mutations → Commit
The communication pattern is straightforward:

1. Solid emits mutation ops as the UI changes.
2. Solid calls `flushFrame()` to apply them.

In response, Zig:

- processes dirty nodes
- performs incremental layout
- performs incremental painting
- redraws only dirty regions via dvui
- clears dirty state

From Solid’s perspective, `flushFrame()` tells Zig to “take all the mutations I’ve sent and update the screen efficiently.”

---

## Event Flow and Scheduling
Zig operates the native event loop for input.  
When input is received:

- Zig dispatches events to JS through FFI callbacks.
- Solid reacts, updates state, and emits new diffs.
- Zig applies diffs and redraws only affected regions.

This makes the system **event-driven** and **idle-efficient**, with no continuous render loop on the JS side.

---

## Conceptual Model
You can think of the system like a small browser engine split across two layers:

- **Solid (in Bun)** acts like the DOM + reactivity layer, computing what the UI should look like.
- **Zig** acts like the layout + paint + compositor engine, maintaining the real scene and drawing only the minimal dirty set.

The FFI boundary is a simple mutation protocol that enables high performance with minimal overhead.

---

## Result
This design achieves:

- near-browser performance in a native renderer  
- redraw cost proportional to actual changes, not tree size  
- minimal cross-FFI communication  
- minimal allocations through native buffer reuse  
- a clean separation between declarative JS UI logic and optimized native rendering  

This makes the renderer both fast and predictable, while preserving Solid’s expressive development model.

------------
Create an informational cartoon diagram explaining the high-level concept described above
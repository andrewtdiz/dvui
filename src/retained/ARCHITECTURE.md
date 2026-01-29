# Retained Mode Architecture (`src/retained`)

This directory implements DVUI’s **retained-mode** UI: an external “driver” (often JS/Clay) sends a **node tree** (snapshot) or **incremental ops**, DVUI stores it in a `NodeStore`, computes layout, renders it via DVUI widgets/primitives, and pushes interaction events back to the driver through an `EventRing`.

The mental model is:

```
snapshot/ops (JSON) → NodeStore (u32 → SolidNode) → style (className) → layout → render → EventRing → driver polls events
```

## What lives where

```
src/retained/
  mod.zig                  Public entry points + JSON snapshot/op application + picking/rect queries + C ABI exports
  core/types.zig           SolidNode + NodeStore (tree, versions, caches, listeners, input/scroll runtime state)
  events/                  EventRing + focus + drag/drop helpers (feeds EventRing from DVUI input)
  style/                   Tailwind-like className parser + adapters into DVUI Options/visual props
  layout/                  Layout engine (absolute + flex + scroll), plus measurement and text wrapping
  render/                  Tag dispatch + rendering, paint caching, resource (image/icon) loading
```

## Core data model: `NodeStore` and `SolidNode`

**`core/types.zig`** is the center of retained mode.

- `NodeStore` owns all nodes in `nodes: AutoHashMap(u32, SolidNode)`.
- Node ids are `u32`. The **root** is always id `0`.
- Parent/children relationships are stored as:
  - `SolidNode.parent: ?u32`
  - `SolidNode.children: ArrayList(u32)`
- Mutations must call `NodeStore.markNodeChanged(id)` so the dirtiness/version system can:
  - bump `SolidNode.version` (self) and `SolidNode.subtree_version` (ancestors),
  - invalidate paint/layout caches that depend on the subtree.

`SolidNode` is “DOM-like” but data-oriented: it stores the raw properties (tag/text/className/etc), plus caches used by layout/render:

- `layout: LayoutCache` (computed `rect`, scaling, intrinsic size + text layout cache)
- `paint: PaintCache` (cached triangles for backgrounds/borders)
- `visual` / `visual_props` + `transform` (render-affecting fields)
- `scroll: ScrollState` and `input_state: ?InputState` (runtime state)
- `listeners: ListenerSet` (string event names registered by the driver)
- `access_*` fields (Accessibility props that map into AccessKit via DVUI)

## Public API surface: `src/retained/mod.zig`

`src/retained/mod.zig` is the integration hub:

- **Lifecycle**
  - `init()` / `deinit()` initialize and tear down retained subsystems (`layout`, `render`, and retained global state).
- **Rendering + layout**
  - `render(event_ring, store, input_enabled)` delegates to `render/mod.zig`.
  - `updateLayouts(store)` delegates to `layout/mod.zig`.
- **Tree updates**
  - `setSnapshot(store, event_ring, json_bytes)` replaces the entire tree from a JSON snapshot.
    - Important: it **captures and restores runtime state** (input text/focus, scroll offsets) across the rebuild.
  - `applyOps(store, seq_last, json_bytes)` applies a JSON batch of incremental ops (create/move/remove/set/listen, etc).
    - Uses `seq` to ignore out-of-order batches.
- **Inspection utilities**
  - `pickNodeAt(store, x, y)` returns the topmost node at a point (z-index + paint order + clipping).
  - `getNodeRect(store, node_id)` returns the final on-screen rect (layout + transform), or `null` if hidden.
- **C ABI bridge**
  - `dvui_retained_*` exports wrap a **shared global** `NodeStore` + `EventRing` stored in this module.
  - `sharedStore()` / `sharedEventRing()` give Zig callers access to that shared state when desired.

## Frame lifecycle (what happens each frame)

`render/mod.zig:render()` orchestrates the frame:

1. `focus.beginFrame(store)`
2. `layout.updateLayouts(store)` (also invalidates layout globally on window size/scale changes)
3. Visual sync pass when needed (tree dirty, layout changed, pointer moved, input toggled, overlay layer changed)
4. Paint caching update (`render/cache.zig:updatePaintCache`) for dirty nodes (background/border geometry, dirty regions)
5. Render traversal (base layer, plus optional overlay “portal” layer)
6. `focus.endFrame(event_ring, store, input_enabled)` (keyboard navigation + focus/blur events)
7. Emit interaction events to the `EventRing` (click/input/scroll/drag/focus/etc)

You generally don’t call layout separately—render does it—but `updateLayouts()` is used by picking/rect queries and by integrations that need layout results without drawing.

## Styling: `className` → `tailwind.Spec` → DVUI options

Retained nodes are styled via a Tailwind-like `className` string.

- Parsing: `style/tailwind.zig`
  - `SolidNode.prepareClassSpec()` lazily parses `className` and caches the resulting `tailwind.Spec` on the node.
- Application:
  - `style/apply.zig` adapts `tailwind.Spec` into:
    - `SolidNode.visual` (packed colors, opacity, corner radius, z-index, clip children, …)
    - `dvui.Options` for widget rendering (padding, border, fonts, etc)
  - Hover variants are applied in render via `tailwind.applyHover(&spec, node.hovered)`.

## Layout: absolute, flex, scroll

Layout is handled by `layout/mod.zig`:

- `computeNodeLayout(store, node, parent_rect)` computes:
  - absolute positioning (`position:absolute`, `top/left/right/bottom`)
  - margins/padding/borders, sizing tokens (`w-*`, `h-*`)
  - per-node layout scaling (`scale-*`), composed with DVUI’s `windowNaturalScale()`
- Flex layout:
  - `spec.is_flex` triggers flex layout of children.
  - The current default routes through `layout/yoga.zig` (with a fallback implementation in `layout/flex.zig`).
- Text/intrinsic sizing:
  - `layout/measure.zig` measures text and intrinsic sizes and caches results on the node.
  - `layout/text_wrap.zig` computes line breaks for wrapped paragraph-like tags.
- Scrolling:
  - Scroll state lives on the node (`ScrollState`), layout offsets the content rect, and render updates offsets from input.

## Rendering: tag dispatch + caching + resources

Rendering is centered in `render/mod.zig`:

- Tag dispatch happens in `renderElementBody()` (look here first when adding a new tag).
- **Interactive nodes** (listeners, `button/input/slider`, or nodes with accessibility props) render through DVUI widgets so DVUI can:
  - manage focus,
  - provide hit-testing,
  - deliver events.
- **Non-interactive nodes** often take the “direct draw” path:
  - `render/direct.zig` draws simple geometry/text directly (and applies transforms).
  - `render/cache.zig` caches background/border geometry per node (`PaintCache`) and tracks dirty screen regions.
- Images/icons:
  - `render/image_loader.zig` resolves and caches raster images (`ImageResource`).
  - `render/icon_registry.zig` resolves icons (vector/raster/glyph) into cached forms on the node.
- Portals/overlay:
  - `portal` elements are skipped in the base pass and rendered in an overlay subwindow.
  - Pointer input is gated by the current “hover layer” so only the active layer receives events.

## Events: listeners + `EventRing`

The retained driver registers interest via ops that call `NodeStore.addListener(id, "eventName")`.
At runtime:

- `events/mod.zig` defines:
  - `EventKind` (stable set of event types)
  - `EventRing` (packed ring buffer + a separate detail byte buffer)
- `events/focus.zig` bridges DVUI focus to retained nodes and emits `focus`/`blur` events.
- `events/drag_drop.zig` builds pointer/drag events from DVUI mouse events and emits `pointer*`, `drag*`, `drop`.
- Render emits `click`, `input`, `scroll`, `mouseenter/leave`, etc based on DVUI widget/event results.

On the FFI side, the driver typically polls:
- `dvui_retained_get_event_ring_header()`
- `dvui_retained_get_event_ring_buffer()` / `dvui_retained_get_event_ring_detail()`
- then acknowledges consumption via `dvui_retained_ack_events(new_read_head)`.

## Adding or changing behavior (practical workflow)

Common extension points:

1. **New node property**
   - Add storage to `core/types.zig` (`SolidNode` / `ScrollState` / etc).
   - Plumb it through `mod.zig` snapshot + ops:
     - `SolidSnapshotNode` / `SolidOp` fields
     - `setSnapshot()` assignment and/or `apply*Fields()` helpers
   - Ensure updates call `store.markNodeChanged(id)` (and `layout.invalidateLayoutSubtree()` if layout-affecting).
2. **New tag**
   - Add a case in `render/mod.zig:renderElementBody()` and implement a `renderX(...)`.
   - If the tag affects layout/measurement, add logic in `layout/mod.zig` and/or `layout/measure.zig`.
3. **New `className` token**
   - Extend parsing in `style/tailwind.zig` and apply it either:
     - directly in layout (`layout/mod.zig` reads from `tailwind.Spec`), or
     - in render via `style/apply.zig` → `node.visual` / `dvui.Options`.
4. **New event type**
   - Add the kind to `events/mod.zig` + `eventKindFromName()`.
   - Emit it from render or an events helper module when DVUI reports the interaction.

## Invariants and gotchas

- Root id is always `0`; most insertion ops treat missing `parent` as root.
- Hidden nodes (`className` includes `hidden`) are skipped in layout/render and treated as non-existent for picking/rect queries.
- If you mutate any field that affects layout, paint, hit-testing, or z-order, you must invalidate via `markNodeChanged()` (and sometimes `invalidateLayoutSubtree()`).
- Render uses a per-frame `ArenaAllocator` for scratch allocations; persistent data must live in the `NodeStore` allocator and be freed in `deinit()`.

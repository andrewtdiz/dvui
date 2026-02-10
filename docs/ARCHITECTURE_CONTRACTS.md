# Architecture Contracts

This document captures cross-cutting invariants that are relied on across `src/native_renderer/` and retained mode (`src/retained/`). It is intended to reduce “tribal knowledge” and prevent subtly inconsistent behavior across modules.

## Node Identity And Tree
- Node id `0` is the root and is expected to exist.
- Node id is the stable identity for stateful behavior (focus, input state, hover path, transition state); changing ids discards state.
- Children order is meaningful (used as a tie-breaker for paint and hit testing).
- `NodeStore.upsert*` operations remove any existing node with the same id (recursive delete), then insert the replacement node.
- `portal` is treated as a special tag for overlay behavior.

## Coordinate Spaces And Rect Contracts
- DVUI has “logical” units (`dvui.Rect`) and “physical pixel” units (`dvui.Rect.Physical`). The bridge between them is the per-window natural scale (`dvui.windowNaturalScale()`).
- Retained uses `types.Rect` in physical pixel space; convert to DVUI logical rects via `src/retained/render/internal/state.zig:physicalToDvuiRect(...)` (divide by natural scale).
- Retained layout stores rects in physical pixels:
  - `SolidNode.layout.rect` is the node’s physical rect.
  - `SolidNode.layout.child_rect` is the node’s content box (layout rect minus padding/border) and is used as the parent rect for laying out children.
- Rendering may apply additional transforms on top of layout:
  - Per-node transform (`SolidNode.transform`, plus transition-derived transforms) affects rendering and hit testing but does not reflow layout.
  - `RenderContext` (`src/retained/render/internal/state.zig`) applies a nested `scale`/`offset` and optional `clip` as the renderer traverses the tree (used for portals/overlays and clipping).
- Rect naming:
  - Layout rect: `SolidNode.layout.rect` (physical pixels, before `RenderContext`).
  - Context rect: `state.contextRect(ctx, layout_rect)` (physical pixels after applying `RenderContext`).
  - Bounds in context: `state.nodeBoundsInContext(ctx, node, layout_rect)` applies the node’s effective transform and then the `RenderContext`.
- Hit testing:
  - `hit_test.scan(...)` treats `ctx.clip` as a context-space clip rect and uses `state.nodeBoundsInContext(...)` for containment checks.
  - Children inherit a derived `RenderContext` with accumulated scale/offset from the node’s effective transform.
- Paint cache bounds:
  - `SolidNode.paint.painted_bounds_layout` is stored in layout space (physical pixels) and includes the node’s effective transform but not `RenderContext` scale/offset.
  - Treat it as a cache/dirtying artifact for dirty region tracking and triangle bounds; do not use it for placement decisions.

## Dirtying And Caches
- `NodeStore` maintains a monotonic version counter.
- `markNodeChanged(id)` means “layout-affecting change”:
  - bumps the global version
  - sets `node.version` and invalidates paint
  - updates ancestor `subtree_version` and `layout_subtree_version`
- `markNodePaintChanged(id)` means “paint-only change”:
  - bumps the global version
  - updates only `node.version` and invalidates paint
  - does not update `subtree_version` or `layout_subtree_version`
- Layout cache:
  - A node recomputes layout when `layout.rect` is missing or `layout.version < layout_subtree_version`.
  - Screen size or natural scale changes invalidate the full layout subtree.
  - Active spacing animations can force layout recompute even without tree changes.
- Paint cache:
  - A node needs paint recompute when `paint.paint_dirty` is set, when `paint.version < node.version`, or when `layout.version > paint.version`.
  - When paint is regenerated, `paint.version` is advanced and `paint.paint_dirty` is cleared so the dirty state stabilizes.
- Common pitfalls:
  - Using `markNodePaintChanged` for geometry/text changes can leave layout stale because it does not advance `layout_subtree_version`.

## Event Transport And Payload Contract
- Transport:
  - Retained code pushes events into an optional `EventRing` (`src/retained/events/mod.zig`).
  - `EventRing` is a fixed-capacity ring of `EventEntry` plus a byte buffer for variable-length detail payloads.
  - Consumers must advance consumption via `setReadHead(...)` (or `reset()`); when fully drained, the detail buffer is reclaimed by resetting the write cursor.
- Payload types (Luau boundary):
  - `input` / `enter` / `keydown` / `keyup`: UTF-8 string.
  - pointer/drag events: Lua table `{ x, y, button, modifiers = { shift, ctrl, alt, cmd } }`.
  - `click` / `focus` / `blur` / `mouseenter` / `mouseleave`: empty string (`""`).
  - Other `EventKind` values exist; if they are surfaced to Luau, their payload shape must be explicitly defined and decoded (otherwise Luau receives opaque bytes).
- Encoding detail:
  - Internally, pointer/drag details are stored as packed bytes (`events.PointerPayload`), then decoded to a Lua table in `src/native_renderer/window.zig` (`drainLuaEvents`) via `src/native_renderer/event_payload.zig`.
- Common pitfalls:
  - If a new event kind stores binary detail payloads, `src/native_renderer/window.zig` must decode them (otherwise Luau sees opaque bytes).

## Style Derivation Order
- `SolidNode.class_name` is parsed into a cached `tailwind.Spec` (invalidated when the class string changes).
- Effective visual derivation in render starts from explicit `visual_props`, then overlays Tailwind spec (and hover variants).
- Transition-enabled nodes may render with “effective” visual/transform values derived from `transition_state`.
- Layout scale (`Spec.scale`) and transform scale (`transform.scale`) are different:
  - layout scale participates in measurement and layout
  - transform scale participates in rendering/hit testing only

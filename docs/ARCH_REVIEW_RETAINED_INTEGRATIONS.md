# Retained + Integrations Architecture Risk Review (High/Critical)

Scope: `src/retained/**`, `src/integrations/**`

This review is biased toward upcoming work: UI_FEATURES.md hardening, robust layouting/cropping, and Figma-style editor controls (selection, transforms, hit-testing, overlays).

## Critical

### Logical errors
- **Transforms are not compositional (no parent→child transform propagation)**, but hit-testing/clipping/rendering are already relying on transforms.
  - Impact: group transforms, rotated frames, nested scaling, and editor selection handles will behave incorrectly unless transforms are moved to a composable “world transform” model.
  - Where: `src/retained/render/direct.zig:22` (`transformedRect` only uses the node’s transform), `src/retained/mod.zig:52` (`getNodeRect`), `src/retained/mod.zig:63` (`pickNodeAt`).

- **Hit-testing + clipping rules diverge across subsystems** (render hover, picking, drag/drop), guaranteeing “can click what you can’t see” edge cases.
  - Render hover uses a clip stack and transformed rect bounds; picking uses `Spec.clip_children`; drag/drop ignores clipping/transforms entirely.
  - Immediate impact: scrollframe clipping (forced via `node.scroll.enabled`) is enforced in render but can be ignored by `pickNodeAt`.
  - Where: `src/retained/render/mod.zig:702` (hover), `src/retained/render/mod.zig:776` (clip stack), `src/retained/mod.zig:121` (picking uses `spec.clip_children`), `src/retained/events/drag_drop.zig:264` (drop hit-test ignores clip/transforms).

- **“Visual props” layering is internally inconsistent (`visual` vs `visual_props`)**.
  - Render sync overwrites `node.visual` from `node.visual_props` each pass, but integrations mutate `node.visual` directly; overlay logic checks `visual_props.background`, not `visual.background`.
  - Impact: props-driven visuals (background/opacity/clipChildren) can be dropped on the next visual sync, and overlay hit rect inclusion can be wrong.
  - Where: `src/retained/core/types.zig:311` (both fields exist), `src/retained/render/mod.zig:748` (overwrite), `src/retained/render/mod.zig:356` (overlay hit rect inclusion checks `visual_props`).

### Memory management
- **Input buffer size limit is effectively not enforced**.
  - `InputState.limit` exists but `ensureCapacity` ignores it and can allocate arbitrarily large buffers; this is reachable via integrations and can OOM the host.
  - Where: `src/retained/core/types.zig:85`.

- **Unbounded global image/icon caches using `std.heap.c_allocator` (no eviction, not store-scoped)**.
  - Impact: long-running editor sessions with many assets will grow memory without bound (even if nodes are removed).
  - Where: `src/retained/render/image_loader.zig:4`, `src/retained/render/icon_registry.zig:6`.

### Runtime performance
- **Layout “early exit” still pre-walks the full tree every call**.
  - `hasMissingLayout` + `hasActiveLayoutAnimations` traverse the entire tree before deciding whether to return.
  - Impact: for large trees, layout becomes O(N) even when nothing changes.
  - Where: `src/retained/layout/mod.zig:43`.

- **Pointer move triggers whole-tree visual sync**.
  - Hover detection is computed by scanning every node each frame (when mouse moves), which will not scale to editor scenes.
  - Where: `src/retained/render/mod.zig:851`, `src/retained/render/mod.zig:862`.

### Code clarity / maintainability
- **Global mutable state across retained modules blocks multi-store/multi-viewport editor designs**.
  - Layout and render keep per-frame/per-window/per-store state in module globals (hover layer, portal caches, “last mouse”, screen size, etc.).
  - Impact: re-entrancy, multiple windows, multiple canvases, background layout/picking, and tests become fragile.
  - Where: `src/retained/layout/mod.zig:11`, `src/retained/render/mod.zig:34`, `src/retained/events/focus.zig:56`, `src/retained/events/drag_drop.zig:22`.

## High

### Logical errors
- **String property setters always allocate and invalidate even when values are unchanged**.
  - Re-sending the same `className`/text each frame causes needless heap churn and tailwind re-parse.
  - Where: `src/retained/core/types.zig:398` (`setText`), `src/retained/core/types.zig:419` (`setClassName`).

- **`upsertElement` destroys subtree state** and is exposed through the Luau surface.
  - If a driver uses “upsert” as a generic update, it will drop scroll offsets, input buffers, and caches (and can cause focus/hover churn).
  - Where: `src/retained/core/types.zig:657` (`upsertElement`), `src/integrations/luau_ui/mod.zig:173` (`createNode` uses upsert unconditionally).

- **Listener management is additive-only** (no removal), so interactivity and cacheability can drift.
  - Impact: a node can become permanently “interactive” (disabling paint cache) even if a driver would like to remove listeners later.
  - Where: `src/retained/core/types.zig:722` (`addListener`), `src/retained/core/types.zig:256` (`ListenerSet`).

### Runtime performance
- **Dirty propagation is too coarse: any change forces layout work**.
  - `needsLayoutUpdate` is keyed off `subtree_version`; `markNodeChanged` bumps `subtree_version` up the ancestor chain even for visual-only changes.
  - Impact: color/opacity changes can cascade into layout recomputation.
  - Where: `src/retained/core/types.zig:600` (`needsLayoutUpdate`), `src/retained/core/types.zig:808` (`markNodeChanged`).

- **Per-frame allocation hotspots in hot paths** (especially for editor-scale trees).
  - Child z-sorting allocates; various render paths build temporary text buffers; Yoga layout allocates nodes per flex container.
  - Where: `src/retained/render/mod.zig:2490` (z-sort), `src/retained/render/mod.zig:1513` (paragraph text buffer), `src/retained/layout/yoga.zig:16`.

### Memory management
- **`EventRing` uses monotonic `u32` heads** (risk of wrap/underflow logic errors in long sessions).
  - Where: `src/retained/events/mod.zig:47` (`read_head`/`write_head` are `u32` and `write_head += 1`).

- **Native renderer command buffer parsing is FFI-hostile without hard bounds/overflow checks**.
  - `expected_header_bytes = header_size * count` can overflow in release builds; `command_count` has no upper bound; allocations follow `count`.
  - Where: `src/integrations/native_renderer/commands.zig:28`.

### Code clarity / maintainability
- **Hit-testing logic is duplicated in multiple places** (pick, hover, overlay hit rect, drag/drop), with different rules.
  - Impact: every editor interaction feature will need to fix bugs N times unless this is unified.
  - Where: `src/retained/mod.zig:63`, `src/retained/render/mod.zig:420`, `src/retained/events/drag_drop.zig:231`.

- **Hardcoded asset search roots** complicate integrations and packaging.
  - Impact: editor/runtime will require a configuration surface to set image/icon roots and caching policy.
  - Where: `src/retained/render/image_loader.zig:39`, `src/retained/render/icon_registry.zig:37`.

## Guidance for upcoming editor + layout/cropping work

1. **Unify geometry + hit-testing**
   - Add a single “geometry pass” that computes per-node world transform + world bounds + effective clip (or clip stack) once, then reuse it for render, pick, hover, drag/drop, and overlay hit rect.
   - Make `pickNodeAt` and editor selection use the same z-order rules as rendering.

2. **Make retained state store-scoped**
   - Move per-frame/per-window caches and flags out of module globals and into a store-owned state struct (or a renderer context passed through render/layout).

3. **Put guardrails on untrusted inputs**
   - Enforce `InputState.limit` (hard error or hard clamp).
   - Add strict bounds/overflow validation at FFI boundaries before allocating.

4. **Separate “layout dirty” from “visual dirty”**
   - Keep a layout-specific dirty flag/version so color/opacity changes don’t trigger full layout recompute.

5. **Fix the “props vs class” layering contract**
   - Decide what `visual_props` is for (base props vs computed visual) and make integrations write to the correct layer; ensure render sync does not silently discard runtime props.

# Overflow-Hidden / clip_children Debug – Quick Context

## What Problem We’re Solving
- Tailwind `overflow-hidden` (mapped to `clip_children`) should clip all descendant rendering to a parent’s bounds.
- In the current Solid → Zig → DVUI pipeline, children still “bleed” outside the parent even when `overflow-hidden` is set.
- Repro is the yellow oversized absolute child in `frontend/solid/App.tsx`: it should be confined to its 32×32 dark parent, but yellow is visible outside the white border.

## High‑Level Data Path (JSX → Zig → DVUI)
1. **JSX / Solid**  
   - Demo in `frontend/solid/App.tsx` creates a parent `div` with `overflow-hidden` and a large absolute yellow child.
2. **Solid universal host → ops**  
   - Host nodes/ops are emitted via the Solid universal renderer and sent through FFI into Zig (see earlier docs).
3. **Zig NodeStore**  
   - Ops update `solid.NodeStore` (`src/integrations/solid/core/types.zig`) where each `SolidNode` holds:
     - `layout.rect` (physical px space)
     - `visual.clip_children` flag
4. **Layout** (`src/integrations/solid/layout/mod.zig`)  
   - Computes `node.layout.rect` in *physical pixels*, already scaled by `dvui.windowNaturalScale()`.
5. **Render** (`src/integrations/solid/render/mod.zig`)  
   - All child traversal funnels through `renderChildrenOrdered(...)`.
   - If `node.visual.clip_children` is true, it does:
     - `prev_clip = dvui.clip(parent_bounds_physical)`
     - renders children
     - restores `dvui.clipSet(prev_clip)`
6. **DVUI clipping**  
   - `dvui.clip(new)` intersects with current clip and stores it on the window (`src/dvui.zig`).
   - Each render command captures the current clip (`src/window/window.zig:addRenderCommand`).
   - When triangles are actually drawn, `dvui.renderTriangles` only enables backend scissor if  
     `triangles.bounds.clippedBy(current_clip)` is true (`src/render/render.zig`).

## Relevant Files / Symbols
- Tailwind parsing / spec:
  - `src/integrations/solid/style/tailwind.zig`
    - `Spec.clip_children: bool`
    - Literal rule `overflow-hidden` → `spec.clip_children = true`
- Visual sync:
  - `src/integrations/solid/style/apply.zig`
    - `applyClassSpecToVisual` copies `spec.clip_children` → `node.visual.clip_children`
- Child traversal + clipping:
  - `src/integrations/solid/render/mod.zig`
    - `renderChildrenOrdered` applies `dvui.clip(...)` when `clip_children`
    - Gated debug logs: `clip_children enter/applied …`
- Background/rect draw bounds:
  - `src/integrations/solid/render/cache.zig`
    - `renderCachedOrDirectBackground`
    - `buildRectGeometry` produces triangles + `bounds`
    - Gated debug logs: `paint under clip …` (added to inspect bounds under active clip)
- DVUI clip + scissor decision:
  - `src/dvui.zig` (`clipGet`, `clip`, `clipSet`)
  - `src/render/render.zig` (`renderTriangles` + `clippedBy` check)
  - `src/core/rect.zig` (`Rect.Physical.clippedBy`)
- Backend scissor:
  - Raylib backend `drawClippedTriangles` uses scissor only when `clipr != null`
    (`src/backends/raylib-zig.zig`).

## What We Know So Far
- `overflow-hidden` is correctly parsed and applied to nodes.
- `renderChildrenOrdered` is reached for the parent, and the clip is being set.
- Example log:
  - `clip_children enter id=12 … bounds=.{x=112.32,y=398.4,w=199.68,h=199.68}`
  - `clip_children applied … clip=.{x=112.32,y=398.4,w=199.68,h=163.6}`
- So the clip rect exists and is non‑fullscreen, yet the yellow child still appears outside.

## Current Hypothesis
DVUI only enables scissor if **the child’s triangle bounds are detected as overflowing the clip**.  
If the yellow child’s `Triangles.bounds` are wrong (too small, already clipped, or stale), then:
- `triangles.bounds.clippedBy(clip)` returns false
- `clipr` becomes `null`
- backend draws without scissor → visible bleed

This points to a bounds/space mismatch in one of:
- `direct.drawRectDirect` (triangle builder bounds from vertices)
- `buildRectGeometry` (returned `geom.bounds`)
- scaling/transform applied to vertices vs bounds

## How to Continue Debugging
1. **Collect “paint under clip” logs**  
   - Rebuild/run and capture the first few `paint under clip …` lines.
   - Identify the yellow child’s node id and its logged `layout`/`painted_rect` vs the active `clip`.
2. **Validate triangle bounds for the yellow node**  
   - If bounds look inside the clip even when visually outside, fix the bounds computation.
   - Check `buildRectGeometry` and `direct.drawRectDirect` for scale/transform inconsistencies.
3. **Sanity‑check coordinate spaces**
   - `layout.rect` is physical px.
   - `dvui.clip` expects physical px.
   - Triangles vertices/bounds must also be physical px for `clippedBy` to work.
4. **Temporary forcing test (optional)**
   - As a quick experiment, force scissor whenever current clip != full screen in `renderTriangles`.
   - If that “fixes” the bleed, it confirms the bounds/`clippedBy` gate is the issue.
   - **Status:** this forcing is now in place in `src/render/render.zig` to validate the hypothesis; if clipping works, we can later restore the gate once bounds are corrected.
5. **Remove debug**
   - After fixing, delete gated log counters/prints in:
     - `src/integrations/solid/render/mod.zig`
     - `src/integrations/solid/render/cache.zig`

## Repro Snippet (JS side)
- Parent: `div` with `overflow-hidden w-32 h-32 …`
- Child: `div` with `absolute top-0 left-0 w-48 h-48 bg-yellow-400`
- File: `frontend/solid/App.tsx`

Expected: yellow fully clipped to the parent’s square.  
Actual: yellow spills outside, meaning clip/scissor is not being applied to that draw call.

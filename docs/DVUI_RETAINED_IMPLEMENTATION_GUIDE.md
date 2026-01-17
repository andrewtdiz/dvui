# DVUI Retained Feature Implementation Guide

This guide maps the feature specification in `DVUI_RETAINED.md` to the current retained implementation and calls out the exact files/functions to extend. It is intentionally high level and data-oriented so you can start coding immediately without changing the public snapshot/ops/event-ring surface.

## Scope and invariants
- Keep the snapshot/ops JSON contract and exported C ABI stable in `src/retained/mod.zig` (`dvui_retained_set_snapshot`, `dvui_retained_apply_ops`, event ring and picking exports).
- Preserve runtime state on snapshot apply by extending `captureRuntimeState` and `restoreRuntimeState` in `src/retained/mod.zig` if new runtime fields are introduced.
- Follow explicit ownership: any new heap allocations added to nodes must be freed in `SolidNode.deinit` in `src/retained/core/types.zig`.

## Current retained pipeline (quick map)
- Snapshot/ops ingestion: `setSnapshot`, `applyOps`, and `applySolidOp` in `src/retained/mod.zig`.
- Node storage and ownership: `SolidNode`, `NodeStore` in `src/retained/core/types.zig`.
- Tailwind parsing and class spec: `parse` and `Spec` in `src/retained/style/tailwind.zig`; adapter in `src/retained/style/apply.zig`.
- Layout: `updateLayouts` and `computeNodeLayout` in `src/retained/layout/mod.zig`; flex in `src/retained/layout/flex.zig` and `src/retained/layout/yoga.zig`; text sizing in `src/retained/layout/measure.zig`; wrap in `src/retained/layout/text_wrap.zig`.
- Rendering: entry in `src/retained/render/mod.zig`; transforms in `src/retained/render/direct.zig`; background/paint cache in `src/retained/render/cache.zig`.
- Events: ring buffer in `src/retained/events/mod.zig`; pointer/drag in `src/retained/events/drag_drop.zig`.
- Image loading: `src/retained/render/image_loader.zig`.

## Feature-by-feature implementation map

### 1) div baseline (layout + transforms + visual props)
Data model and ops:
- Extend `SolidSnapshotNode` and `SolidOp` in `src/retained/mod.zig` only when new props are added.
- Store new per-node values in `SolidNode` in `src/retained/core/types.zig`; apply them via `setSnapshot` and `applySolidOp` in `src/retained/mod.zig`.

Layout:
- Absolute layout via `left/top/right/bottom` and `w/h` already lives in `computeNodeLayout` in `src/retained/layout/mod.zig`.
- Ensure any new sizing logic (aspect ratio) is applied before child layout runs.

Rendering:
- Transforms are applied through `applyTransformToOptions` in `src/retained/render/direct.zig` and `transformedRect`.
- Visual props are combined in `syncVisualsFromClasses` in `src/retained/render/mod.zig` and `applyClassSpecToVisual` in `src/retained/style/apply.zig`.

### 2) Tailwind className support
Parsing:
- Add new tokens and fields to `Spec` in `src/retained/style/tailwind.zig`.
- Use small, data-only fields (no side effects). Apply side effects in layout/render stages.

Where to apply:
- For layout-affecting tokens, consume the parsed spec in `src/retained/layout/mod.zig`, `src/retained/layout/flex.zig`, or `src/retained/layout/yoga.zig`.
- For render-only tokens, apply in `applyClassSpecToVisual` in `src/retained/style/apply.zig` or in `render/mod.zig` where needed.

Required additions:
- `order-*` / `order-[n]`: add `order` to `tailwind.Spec` and sort children in flex layout. For yoga, set `yoga.Node.setOrder` in `src/retained/layout/yoga.zig`. For the manual flex path, reorder in `src/retained/layout/flex.zig` before measuring and placing.
- `aspect-[ratio]` and `aspect-dominant-w/h`: add aspect fields to `tailwind.Spec`, then in `computeNodeLayout` adjust the missing axis based on the dominant axis.
- `overflow-scroll`, `overflow-x-scroll`, `overflow-y-scroll`: add scroll flags to `tailwind.Spec` and mirror them into `node.scroll` in `src/retained/render/mod.zig` or during class-spec application.
- `text-nowrap` already maps to `Spec.text_wrap`; keep using `text_wrap` in `src/retained/layout/text_wrap.zig`.

### 3) Text nodes (tag `text`)
Current behavior:
- `renderText` in `src/retained/render/mod.zig` uses parent class spec and does not apply text node class spec. This is insufficient for the new `text` tag requirements.

Required changes:
- Combine parent and node class specs in `renderText` in `src/retained/render/mod.zig`. Start with parent defaults, then override with node-specific spec (as in the immediate integration).
- Add explicit text alignment X/Y (either tokens or props) and pass align values into `LabelWidget.initNoFmt` in `src/widgets/LabelWidget.zig` via `InitOptions.align_x/align_y`.
- Implement auto-scale-to-fit: measure the text with `Font.textSize` or `text_wrap.computeLineBreaks` in `src/retained/layout/measure.zig`, compute a scale factor to fit inside `node.layout.rect`, then resize the font (see `dvui.Font.resize`) before rendering.
- Add stroke/outline: perform a multi-pass draw around the text (offset render) before the fill. A minimal pass can live in `src/retained/render/direct.zig` or directly in `renderText` using `dvui.renderText`.
- Preserve wrapping defaults via `class_spec.text_wrap` and `class_spec.break_words` in `src/retained/layout/text_wrap.zig`.

### 4) Image nodes (tag `image`)
Data and ops:
- Add image-specific props to `SolidSnapshotNode` and `SolidOp` in `src/retained/mod.zig` (fit mode, tint color, image opacity, per-image transform).
- Store them in `SolidNode` in `src/retained/core/types.zig` and apply in `renderImage` in `src/retained/render/mod.zig`.

Rendering path:
- Fit modes map to DVUI’s `Options.Expand` and image shrink behavior in `src/dvui.zig` (`ImageInitOptions.shrink`, `Options.expand`). If `cover` requires cropping, bypass `dvui.image` and call `render.renderImage` with custom `TextureOptions.uv` in `src/render/render.zig`.
- Tint and opacity should be applied via `TextureOptions.colormod` (see `src/render/render.zig`) rather than background color.
- Support per-image transform independently of node transform (apply rotation/scale to texture rendering only, not layout). `TextureOptions.rotation` already exists; scale can be handled by adjusting the destination rect before calling `render.renderImage`.

Placeholder behavior:
- Avoid repeated logging in `renderImage` in `src/retained/render/mod.zig`. Mark failures in `SolidNode.cached_image` and render a lightweight placeholder (e.g., a neutral rect with a cross) instead of error logs.

### 5) Scroll containers (overflow-scroll)
Data and ops:
- `ScrollState` lives in `src/retained/core/types.zig`. Extend it with axis flags if needed.

Layout:
- Scrolling already offsets children in `computeNodeLayout` and uses `updateScrollContentSize` in `src/retained/layout/mod.zig`. Ensure `autoCanvas` and `canvasWidth/Height` work for all scroll tokens.

Rendering and input:
- `renderScrollFrame` in `src/retained/render/mod.zig` drives wheel/touch and scrollbars. Update it to respect per-axis enablement (`overflow-x-scroll`, `overflow-y-scroll`) when constructing `dvui.ScrollInfo`.
- Ensure scrollbars are visible for enabled axes even when only one axis is scrollable.

### 6) Gradient backgrounds
Data and ops:
- `types.Gradient` already exists in `src/retained/core/types.zig` but is unused. Add props in `SolidSnapshotNode`/`SolidOp` in `src/retained/mod.zig` to carry gradient data (colors, stops, rotation).
- Store gradient data on `SolidNode.visual_props` and apply in render.

Rendering:
- Implement gradient rendering in `src/retained/render/cache.zig` or `src/retained/render/direct.zig`. Build a quad with per-vertex colors derived from the gradient angle and stops.
- Apply `node.visual.opacity` and `corner_radius` consistently so gradient respects opacity and rounding.

### 7) Picking and rect queries
Current behavior:
- `pickNodeAt` and `getNodeRect` in `src/retained/mod.zig` use layout and `transformedRect` but rely on `Spec.clip_children` and `node.visual.z_index`, which may be stale outside render.

Required changes:
- Use `node.visual.clip_children` for clipping (this includes props and scroll) and ensure it is computed without requiring a render pass.
- Apply z-index from `tailwind.Spec` directly in picking if `node.visual.z_index` is not guaranteed up to date.
- Make sure transforms and clipping match render logic; use `direct.transformedRect` consistently.

### 8) Config API for image roots and default fonts
Image roots:
- Replace the fixed `image_search_roots` list in `src/retained/render/image_loader.zig` with a mutable list owned by the retained module.
- Expose a small Zig API and a C ABI export in `src/retained/mod.zig` to set search roots (copy strings into a retained allocator; clear on `deinit`).

Default fonts:
- Provide configurable font IDs for `font-ui`, `font-mono`, `font-game`, `font-dyslexic` in `src/retained/style/tailwind.zig`.
- Expose setters (Zig and C ABI) in `src/retained/mod.zig` so the engine/editor can override defaults without changing builtins.

## Acceptance checklist (from spec)
- `div` position, transform, opacity, and clipping behave correctly.
- `text` wraps, aligns, and auto-scales; stroke renders; color comes from props or class.
- `image` supports fit, tint, placeholder, and independent transform.
- `flex` layout honors `order-*` and padding tokens.
- `overflow-scroll` scrolls with wheel/touch, and scrollbars appear for enabled axes.
- Hover/scroll events are pushed through the event ring (`src/retained/events/mod.zig`).
- `pick_node_at` and `get_node_rect` match visual output after transforms/clipping.

## Suggested validation path
- Use `src/retained-harness.zig` to load a snapshot/ops JSON and visually confirm rendering.
- Add a minimal retained snapshot covering the acceptance scene and verify `pick_node_at` and `get_node_rect`.
- Manually exercise scrolling and ensure `scroll` events are emitted by `renderScrollFrame` in `src/retained/render/mod.zig`.

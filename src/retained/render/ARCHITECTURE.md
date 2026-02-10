# Retained Render (`render/`)

## Responsibility
Implements the retained-mode per-frame renderer: runs layout, performs hit testing and hover synchronization, dispatches input events into an optional `EventRing`, and renders the retained node tree.

## Public Surface
- `render(event_ring, store, input_enabled, timings) bool` is the per-frame entrypoint for retained rendering.
- `FrameTimings` can be passed in to collect per-frame timing buckets.

## High-Level Architecture
- Entry: `render(event_ring, store, input_enabled, timings)` (`mod.zig`).
- Per-frame flow: `focus.beginFrame` -> `layout.updateLayouts` -> hit-test + hover sync (`internal/interaction.zig`, `internal/hover.zig`, with a single retry if hover affects layout) -> render traversal (`internal/renderers.zig`) -> `focus.endFrame`.
- Asset services: `image_loader.zig` and `icon_registry.zig` manage global caches for image/icon resolution.
- Rendering helpers: `direct.zig` (low-level drawing), `transitions.zig` (effective visual/transform with transitions), and `cache.zig` (optional per-node paint cache used by background rendering).

## Core Data Model
- `RenderRuntime` (`internal/runtime.zig`): module-global per-frame state (current render layer, pointer targets, cached portal ids, hovered path, overlay state, pressed node id, optional timing sink).
- `FrameTimings` (`internal/runtime.zig`): timing buckets for layout/hover/hit-test/render/focus and some draw sub-categories.
- Uses `NodeStore`/`SolidNode` as the source of truth; relies on each node’s `layout`, `visual`, `transform`, `transition_state`, and interaction flags.

## Critical Assumptions
- Root node id `0` exists. If the root has no children, the renderer returns `false` and does no work.
- Rendering assumes an active `dvui.Window` (layout and drawing depend on `dvui.currentWindow()` and `dvui.windowNaturalScale()`).
- `input_enabled` gates pointer/focus behavior; rendering still occurs with input disabled, but hover and event dispatch are suppressed.

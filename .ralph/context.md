# DVUI Retained Mode (for Ralph)

DVUI is an immediate-mode Zig GUI library that also includes a retained-mode subsystem in `src/retained/`. An external driver (now an embedded Luau runtime) sends a DOM-like node tree as a full snapshot or incremental ops; retained mode stores nodes in a `NodeStore`, computes layout, renders via DVUI primitives/widgets, and pushes interaction back through an `EventRing`.

Primary goal: reach feature parity with `UI_FEATURES.md` and the retained spec in `DVUI_RETAINED.md`, while keeping the snapshot/ops + event ring + picking/rect-query API stable.

## Key invariants
- Keep the snapshot/ops JSON contract stable (`setSnapshot`, `applyOps` in `src/retained/mod.zig`).
- Preserve runtime state on snapshot apply (scroll offsets, input buffer/focus) via `captureRuntimeState` / `restoreRuntimeState` in `src/retained/mod.zig`.
- Keep picking/inspection stable: `pickNodeAt` + `getNodeRect` in `src/retained/mod.zig` must match render transforms/clipping/z-index.
- No C ABI targets/exports (this repo has migrated to an embedded Luau runtime). Do not add/restore `dvui_retained_*` exports.

## Where things live
- `UI_FEATURES.md`: parity checklist (UIFrame/ImageFrame/TextFrame/etc).
- `DVUI_RETAINED.md`: retained-mode feature pass requirements + acceptance scene.
- `src/retained/ARCHITECTURE.md`: module map + frame pipeline overview.
- `docs/DVUI_RETAINED_IMPLEMENTATION_GUIDE.md`: per-feature file/function map and implementation notes.

### Public retained API
- `src/retained/mod.zig`: lifecycle (`init`/`deinit`), snapshot/ops application, `render`, `updateLayouts`, `pickNodeAt`, `getNodeRect`.

### Core state
- `src/retained/core/types.zig`: `NodeStore` + `SolidNode` (tree structure, versioning/dirtying, layout + paint caches, listeners, scroll/input runtime state).

### Styling
- `src/retained/style/tailwind.zig`: Tailwind-like `className` parser -> `tailwind.Spec` (add new tokens/fields here).
- `src/retained/style/apply.zig`: adapts `tailwind.Spec` -> `node.visual` / `node.visual_props` + `dvui.Options`.

### Layout
- `src/retained/layout/mod.zig`: layout engine (absolute + flex + scroll), intrinsic sizing hooks.
- `src/retained/layout/yoga.zig`: Yoga-backed flex implementation.
- `src/retained/layout/flex.zig`: fallback flex implementation.
- `src/retained/layout/measure.zig`: intrinsic sizing (text/image/etc).
- `src/retained/layout/text_wrap.zig`: wrapping + line break caching.

### Rendering
- `src/retained/render/mod.zig`: tag dispatch, hover detection, scroll input/scrollbars, portals/overlay, paint caching orchestration.
- `src/retained/render/direct.zig`: transforms + direct draw helpers.
- `src/retained/render/cache.zig`: cached background/border geometry + dirty region tracking.
- `src/retained/render/image_loader.zig`: image path resolution + caching (currently has hardcoded search roots).

### Events
- `src/retained/events/mod.zig`: `EventRing` and `EventKind`.
- `src/retained/events/focus.zig`: focus/blur integration.
- `src/retained/events/drag_drop.zig`: pointer + drag/drop event emission.

## Current validation workflow
- Visual/manual harness: `src/retained-harness.zig` loads a snapshot JSON, renders it, hot-reloads on file change, and prints drained `EventRing` entries.
- Build/run: `zig build run-retained -- path\\to\\snapshot.json`

## Embedded Luau driver
- `src/integrations/luau_ui/mod.zig`: registers a global `ui` table in Luau with ops-like functions (`ui.create`, `ui.set_class`, `ui.set_visual`, etc).
- `src/integrations/solid/`: a separate retained pipeline module used by the Luau bindings (core/style/layout/render/events). If your runtime uses this path, feature work in `src/retained/` may need to be mirrored.

## Known implementation gaps vs `UI_FEATURES.md` (quick map)
- `UIFrame` scale-based position/size (0..1 relative to parent) is not implemented; current positioning is via Tailwind tokens (`absolute left-* top-* w-* h-*`).
- `TextFrame` (`tag: "text"`): current `renderText` only inherits parent class spec; missing node-specific class spec, auto-scale-to-fit, outline/stroke, and full alignment control.
- `ImageFrame` (`tag: "image"`): current `renderImage` loads `src` but logs on failures and has no fit modes/tint/independent image transform/placeholder rendering.
- `UIListLayout` (`className: flex`): flex works, but `order-*` sorting is not implemented (Yoga path currently doesn't set order).
- `UIAspectRatioConstraint`: `aspect-*` tokens not implemented.
- `UIScrollingFrame`: scroll works via `node.scroll.enabled`, but per-axis enablement (`overflow-x-scroll` / `overflow-y-scroll`) is not implemented.
- `UIGradient`: `types.Gradient` exists in `src/retained/core/types.zig` but is currently unused.
- Tweening + heartbeat/render-stepped: not implemented in retained; expected to be driven from Luau with a per-frame dt hook/event.

## Coding constraints
- Follow explicit ownership (`init`/`deinit` on structs); anything allocated per node must be freed in `SolidNode.deinit` (`src/retained/core/types.zig`).
- `render/mod.zig` uses a per-frame arena allocator for scratch; don't store scratch memory into `NodeStore`.
- Zig constraints: use `const` for immutables, avoid variable shadowing, use `@min`/`@max`, and let `@intCast`/`@bitCast` infer types where possible.

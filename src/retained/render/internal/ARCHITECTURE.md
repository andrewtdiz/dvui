# Retained Render Internals (`render/internal/`)

## Responsibility
Provides the core rendering pipeline implementation: render context/state types, hit testing, hover tracking, overlay/portal behavior, and per-tag rendering of retained nodes.

## Public Surface
- Internal-only: these modules are called by `src/retained/render/mod.zig` and are not intended as a stable import surface.
- Shared internal types: `RenderContext`, `RenderRuntime`, pointer picks, and overlay state.

## High-Level Architecture
- `renderers.zig`: traverses the node tree, derives effective styling (Tailwind spec + `visual_props` + transitions), renders in z-order, uses DVUI widgets for interactive elements, and emits events into `EventRing`.
- `interaction.zig`: hit testing and pointer routing; computes “hover target” and “interactive target” picks.
- `hover.zig`: maintains the hovered path; emits enter/leave events and can invalidate layout if hover classes affect layout.
- `overlay.zig`: discovers portal/overlay nodes and manages overlay layering, modal behavior, and overlay hit rects.
- `derive.zig`: applies `tailwind.Spec` into `SolidNode.visual` (resolved colors, z-index, opacity, clip flags).
- `visual_sync.zig`: maps retained visuals/accessibility/layout-scale into `dvui.Options` and widget state.
- `state.zig`: shared geometry helpers and stable ids.
- `runtime.zig`: `RenderRuntime` and `FrameTimings`.

## Core Data Model
- `RenderContext` (`state.zig`): `{ origin, clip:?Rect, scale:[2]f32, offset:[2]f32 }` for nested transforms and clipping.
- `RenderLayer` (`state.zig`): `.base` or `.overlay` (used for portals/modals and input gating).
- `PointerPick` and `OrderedNode` (`state.zig`): z-index + order tuples used for selection and draw ordering.
- `RenderRuntime` (`runtime.zig`): cached portal ids, hover list, overlay state, pointer target ids, and pressed node id.
- `state.nodeIdExtra(u32) -> usize` hashes node ids into stable DVUI id extras for widget identity.

## Critical Assumptions
- Layout rects live in physical pixels; `RenderContext` applies additional scale/offset for overlays and per-node transforms.
- Clipping is opt-in: `clip_children` (from Tailwind spec or `visual_props`) determines whether clips are intersected in `RenderContext` and applied during render.
- Portal nodes are identified by tag `"portal"`.
- Interactive rendering goes through DVUI widgets to preserve focus/input behavior; non-interactive elements may be direct-rendered to avoid relying on widget layout.

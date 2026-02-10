# Retained Mode UI (`retained/`)

## Responsibility
Owns the retained-mode UI tree and renderer. The durable state lives in a `NodeStore` of `SolidNode`s, typically mutated by Luau (`src/native_renderer/luau_ui.zig`) or other host code, then rendered each frame via `retained.render(...)`.

## Public Surface
- `init()` / `deinit()` to initialize global retained subsystems (tailwind, layout, renderer).
- `render(event_ring, store, input_enabled, timings)` as the per-frame entrypoint.
- `updateLayouts(store)` for forcing layout.
- Picking helpers: `getNodeRect(...)`, `pickNodeAt*`, `pickNodeStackAtInto(...)`, `pickNodePathAtInto(...)`.
- Re-exports: `NodeStore`, `SolidNode`, rect/anchor types, and `events`/`EventRing`.

## High-Level Architecture
- `mod.zig` is the façade: re-exports the core types, wires up `init/deinit`, and exposes rendering, layout, and picking helpers.
- Frame entrypoint: `retained.render(event_ring, store, input_enabled, timings)` delegates to `src/retained/render/mod.zig`.
- Layout can be forced via `retained.updateLayouts(store)` (delegates to `src/retained/layout/mod.zig`).
- Picking APIs (`pickNodeAt*`, `pickNodeStackAtInto`, `pickNodePathAtInto`) use `src/retained/hit_test.zig` to scan the tree and select the topmost node (by `z_index`, then tree order).

## Core Data Model
- `NodeStore`: `u32 -> SolidNode` map with versioning for change propagation (`src/retained/core/node_store.zig`).
- `SolidNode`: one node in the retained tree (tag/text/class/style inputs, derived visual, layout+paint caches, interaction/accessibility flags).
- `tailwind.Spec`: parsed from `SolidNode.class_name` and treated as the layout + style contract (`src/retained/style/tailwind.zig`).
- `EventRing`: optional ring buffer that receives UI events during render for dispatch to the host/Lua (`src/retained/events/mod.zig`).

## Critical Assumptions
- Node id `0` is the root and must exist for rendering/picking to work.
- Layout rects are computed in physical pixels; transforms and overlays can apply additional scale/offset via a `RenderContext`.
- Nodes with `Spec.hidden` do not participate in layout or hit testing.
- Node ids are the stable identity for stateful behavior (focus, input, hover); changing ids discards per-node state.

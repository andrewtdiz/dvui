# Retained Core (`core/`)

## Responsibility
Defines the retained-mode scene graph data model and its change-tracking. This directory is where `NodeStore` and `SolidNode` live.

## Public Surface
- `NodeStore`: create/remove/reparent nodes, update properties, and mark nodes dirty.
- `SolidNode`: per-node durable state (tree links, style inputs, derived/cached layout + paint state, interaction/accessibility state).
- `types.zig`: re-export hub used by other retained modules.

## High-Level Architecture
- `node_store.zig` implements the node graph: creation/removal, reparenting, property updates, and dirty propagation through a version counter.
- `types.zig` is the public import surface that re-exports the core types.
- `geometry.zig`, `visual.zig`, `media.zig`, and `layout.zig` define the foundational value types used by all retained subsystems.

## Core Data Model
- `NodeStore`: `nodes: AutoHashMap(u32, SolidNode)` plus a monotonic `VersionTracker` for change propagation; `active_spacing_anim_ids` tracks nodes that may require layout recompute due to spacing transitions.
- `SolidNode`: identity (`id`, `kind`, `tag`, `text`), tree (`parent`, `children`), style inputs (`class_name`, `visual_props`, `transform`, `scroll`, accessibility), derived/cached (`class_spec`, `visual`, `layout`, `paint`), interaction (`listener_mask`, hover/focus flags, `total_interactive`), and state (`input_state`, `transition_state`).

## Critical Assumptions
- Root node id `0` exists (created by `NodeStore.init`).
- `upsertElement/upsertSlot/setTextNode` remove any existing node with the same id (recursive delete) before inserting the replacement node.
- `insert(parent, child, before)` detaches the child from any previous parent before reattaching and bubbles interactive-count deltas upward.
- `markNodeChanged(id)` increments the global version and updates `version`, `subtree_version`, and `layout_subtree_version` up the ancestor chain; `markNodePaintChanged(id)` is paint-only.
- `EventKind` must stay under 64 values to fit `SolidNode.listener_mask` (enforced by comptime check).

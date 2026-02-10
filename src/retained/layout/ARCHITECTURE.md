# Retained Layout (`layout/`)

## Responsibility
Computes `SolidNode.layout` for the retained tree: each node’s physical-pixel rectangle, its child/content rectangle, and scroll content bounds.

## Public Surface
- `updateLayouts(store)` to recompute layout when needed (typically called once per frame by the renderer).
- `invalidateLayoutSubtree(store, node)` to force a subtree to recompute layout.
- `didUpdateLayouts()` to query whether the most recent `updateLayouts` performed work.

## High-Level Architecture
- Entry: `updateLayouts(store)` (`mod.zig`) drives layout recomputation using DVUI window size and natural scale.
- Dirty detection is version-based: a node recomputes layout when its cached `layout.version` is behind `layout_subtree_version`, when rects are missing, or when active spacing animations are present.
- `computeNodeLayout(store, node, parent_rect)` applies the Tailwind-like spec (plus hover overrides) to compute absolute positioning, in-flow layout (margin/padding/border + intrinsic measurement), and scroll offsets/content sizing.
- Second pass: `applyAnchoredPlacement(...)` offsets nodes with `anchor_id` after the tree has a stable layout.

## Core Data Model
- `LayoutCache` (per-node, in `src/retained/core/layout.zig`): `rect`/`child_rect` in physical pixels, `layout_scale`, `version`, and intrinsic/text caches (`intrinsic_size`, `text_hash`, `text_layout`).
- `tailwind.Spec` fields that act as the layout contract: `position`, insets, `width/height`, `margin/padding/border`, `corner_radius`, flex config (`is_flex`, `direction`, `justify`, `align`, `gap`), `scale`, `hidden`, and scroll/clip flags.

## Critical Assumptions
- Layout depends on `dvui.currentWindow()`; layout units are physical pixels derived from window size and natural scale.
- Hidden nodes set a zero rect and are skipped for layout flow.
- `layout_scale` composes parent scale with local `spec.scale` and is used when interpreting spacing/sizing tokens.
- Anchoring is a post-pass that offsets the anchored node’s entire subtree to keep child layout consistent.

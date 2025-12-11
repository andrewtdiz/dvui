# Architecture Debugging - Black Screen with Text Only

## Observed Problem
Screen renders black with centered text visible, but element backgrounds (bg-gray-100, bg-amber-200, bg-blue-400) are not showing.

---

## Issues Identified

### CRITICAL: Layout Rect is Null for Root Children
**Severity: Critical**
**Location:** `src/solid/render/mod.zig:388-391`, `src/solid/layout/mod.zig:49-58`

The `renderNonInteractiveDirect` function bails out to `renderElementBody` when `node.layout.rect` is null:
```zig
const rect = node.layout.rect orelse {
    renderElementBody(runtime, store, node_id, node, allocator, class_spec, tracker);
    return;
};
```

**Root Cause:** The layout system at `layout/mod.zig:50` checks `needsLayoutUpdate()` which returns `false` if `layout.rect` is already set with a non-stale version. However, newly created nodes may have `layout.rect = null` but NOT be marked dirty because:
1. Nodes are created via mutation ops
2. `markNodeChanged()` updates versions but doesn't guarantee layout recomputation
3. `needsLayoutUpdate()` returns `true` only when `layout.rect == null OR layout.version < subtree_version`

The check at line 50-51 passes `parent_rect` to children but never actually computes rect for nodes that don't need updates. When screen size changes, root is invalidated but children may not be.

### HIGH: Class Spec Background Not Applied Before Render
**Severity: High**
**Location:** `src/solid/render/mod.zig:138-145`

The render path does:
```zig
const class_spec = node.prepareClassSpec();
applyClassSpecToVisual(node, &class_spec);
if (node.visual.background == null) {
    if (class_spec.background) |bg| {
        node.visual.background = dvuiColorToPacked(bg);
    }
}
```

This is correct, but `renderNonInteractiveDirect` can return early before ever calling `renderCachedOrDirectBackground` if rect is null.

### HIGH: Paint Cache May Return Empty Geometry
**Severity: High**
**Location:** `src/solid/render/cache.zig:55-57, 163-173`

`renderPaintCache` returns `false` if vertices/indices are empty:
```zig
if (node.paint.vertices.items.len == 0 or node.paint.indices.items.len == 0) return false;
```

And `buildRectGeometry` returns empty geometry if `visual.background` is null:
```zig
const bg = visual.background orelse return .{
    .vertices = &.{},
    .indices = &.{},
    .bounds = dvui.Rect.Physical{},
};
```

If the background wasn't set before cache regeneration, the cache stores empty geometry and never redraws.

### MEDIUM: w-full/h-full Don't Set Absolute Dimensions
**Severity: Medium**
**Location:** `src/solid/layout/mod.zig:82-93`, `src/solid/style/tailwind.zig:199-210`

`w-full` and `h-full` set spec.width/height to `.full` enum variant, but in `computeNodeLayout` this only affects the rect if parent dimensions are available:
```zig
if (spec.width) |w| {
    switch (w) {
        .full => rect.w = @max(0.0, parent_rect.w - (margin_left + margin_right)),
        ...
    }
}
```

But if parent_rect is 0x0 (because parent wasn't laid out), child gets 0x0.

### MEDIUM: dirty_tracker Adds Full Screen If No Regions
**Severity: Medium**
**Location:** `src/solid/render/mod.zig:87-96`

```zig
if (dirty_tracker.regions.items.len == 0) {
    const screen_rect = types.Rect{...};
    dirty_tracker.add(screen_rect);
}
```

This compensates for missing dirty regions but doesn't fix the underlying layout issue.

### LOW: Debug Logs Fire Only Once
**Severity: Low**
**Location:** `src/solid/render/mod.zig:57-81, 146-152`

`logged_tree_dump` and `logged_render_state` are static bools that prevent repeated logging. After first frame, no further debug info is available about node state changes.

---

## Likely Failure Sequence

1. JS creates nodes via mutation ops with className set
2. `rebuildSolidStoreFromJson` or `applySolidOps` creates nodes and marks them changed
3. Layout runs but `parent_rect` propagation may fail if first-frame timing is off
4. Nodes have `layout.rect = null` or `layout.rect = {0,0,0,0}`
5. `renderNonInteractiveDirect` bails early because rect is null
6. Even when rect exists, `visual.background` may be null at cache build time
7. Cache stores empty geometry, returns false
8. `drawRectDirect` is called but background is still null, returns early
9. Text renders because it uses DVUI widgets directly, not the cached path

---

## Verification Needed

1. Check debug log output: `background draw node X rect={...} visual_bg=... fallback_bg_present=...`
2. Confirm what `node.layout.rect` values are for the outer divs
3. Check if `class_spec.background` is being parsed correctly (colors exist in map)

---

## Recommended Fixes (Priority Order)

1. **Ensure layout always computes rects for all nodes** - even if not "dirty", newly inserted nodes need initial layout
2. **Apply class_spec to visual.background BEFORE cache regeneration** - move `applyClassSpecToVisual` call earlier in pipeline
3. **Add fallback in drawRectDirect when both visual.background and fallback_bg are null** - at minimum log a warning
4. **Consider forcing dirty state on insert** - when a node is inserted, its layout should be recomputed

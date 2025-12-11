# Yoga Layout Engine Migration Plan

This document provides a comprehensive guide for migrating from the custom flex layout implementation to Facebook's Yoga layout engine.

---

## Objective

Replace the custom flex layout code in `src/solid/layout/` with Yoga, enabling full CSS Flexbox support including:
- `flex-grow`, `flex-shrink`, `flex-basis`
- `flex-wrap`
- `items-stretch`, `self-*` alignment
- Percentage sizing (`w-1/2`, `w-2/3`)
- `min-*`, `max-*` constraints
- Absolute/relative positioning
- Auto margins

---

## Current Architecture

### Files to Modify

| File | Role | Migration Impact |
|------|------|------------------|
| `src/solid/core/types.zig` | `SolidNode` struct definition | Add `yoga_node: ?*yoga.Node` field |
| `src/solid/layout/mod.zig` | Layout entry point, `updateLayouts()`, `computeNodeLayout()` | Replace with Yoga tree sync and `calculateLayout()` |
| `src/solid/layout/flex.zig` | Custom flex layout algorithm | **DELETE** after migration |
| `src/solid/layout/measure.zig` | Text/node intrinsic measurement | Adapt as Yoga `measureFunc` callback |
| `src/solid/style/tailwind.zig` | Tailwind class parsing → `Spec` struct | Keep as-is, add mapping layer |
| `src/solid/render/mod.zig` | Uses `node.layout.rect` for rendering | No changes needed (reads same rect) |

### Current Data Flow

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Tailwind Spec  │───▶│  Custom Layout   │───▶│  node.layout    │
│  (parsed class) │    │  (flex.zig)      │    │  .rect          │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌──────────────────┐
                       │  Render Pass     │
                       │  (uses rect)     │
                       └──────────────────┘
```

### Target Data Flow

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Tailwind Spec  │───▶│  Yoga Adapter    │───▶│  Yoga Node      │
│  (parsed class) │    │  (new file)      │    │  (YGNodeRef)    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                      │
                              ┌────────────────────────
                              ▼
                       ┌──────────────────┐    ┌─────────────────┐
                       │ calculateLayout  │───▶│  node.layout    │
                       │ (viewport size)  │    │  .rect          │
                       └──────────────────┘    └─────────────────┘
                                                      │
                              ┌────────────────────────
                              ▼
                       ┌──────────────────┐
                       │  Render Pass     │
                       │  (uses rect)     │
                       └──────────────────┘
```

---

## Available Yoga Bindings

Located at: `deps/zig-yoga/src/root.zig`

### Key Types

```zig
const yoga = @import("yoga-zig");

// Create and manage nodes
yoga.Node.new()            // Create node
yoga.Node.free()           // Destroy node
yoga.Node.insertChild()    // Add child at index
yoga.Node.removeChild()    // Remove child
yoga.Node.getChildCount()  // Get child count

// Calculate layout
yoga.Node.calculateLayout(availableWidth, availableHeight, direction)

// Get computed layout
yoga.Node.getComputedLayout() -> Layout { left, top, width, height, ... }
yoga.Node.getComputedLeft()
yoga.Node.getComputedTop()
yoga.Node.getComputedWidth()
yoga.Node.getComputedHeight()
```

### Key Style Setters

```zig
// Flex container
setFlexDirection(FlexDirection.Row | .Column | .RowReverse | .ColumnReverse)
setJustifyContent(Justify.FlexStart | .Center | .FlexEnd | .SpaceBetween | .SpaceAround | .SpaceEvenly)
setAlignItems(Align.Auto | .FlexStart | .Center | .FlexEnd | .Stretch | .Baseline)
setAlignContent(Align.*)
setFlexWrap(Wrap.NoWrap | .Wrap | .WrapReverse)

// Flex item
setFlexGrow(f32)
setFlexShrink(f32)
setFlexBasis(Basis)
setAlignSelf(Align.*)

// Sizing
setWidth(f32)
setWidthPercent(f32)
setWidthAuto()
setHeight(f32)
setHeightPercent(f32)
setHeightAuto()
setMinWidth(f32)
setMaxWidth(f32)
setMinHeight(f32)
setMaxHeight(f32)

// Spacing
setMargin(Edge, f32)
setPadding(Edge, f32)
setGap(Gutter.Row | .Column | .All, f32)
setBorder(Edge, f32)

// Position
setPositionType(PositionType.Static | .Relative | .Absolute)
setPosition(Edge, f32)

// Display
setDisplay(Display.Flex | .None | .Contents)

// Measurement (for leaf nodes like text)
setMeasureFunc(fn(node, width, widthMode, height, heightMode) -> Size)
```

### Yoga Enums (from `deps/zig-yoga/src/enums.zig`)

```zig
Align = { Auto, FlexStart, Center, FlexEnd, Stretch, Baseline, SpaceBetween, SpaceAround, SpaceEvenly }
FlexDirection = { Column, ColumnReverse, Row, RowReverse }
Justify = { FlexStart, Center, FlexEnd, SpaceBetween, SpaceAround, SpaceEvenly }
Wrap = { NoWrap, Wrap, WrapReverse }
PositionType = { Static, Relative, Absolute }
Display = { Flex, None, Contents }
Edge = { Left, Top, Right, Bottom, Start, End, Horizontal, Vertical, All }
Gutter = { Column, Row, All }
Overflow = { Visible, Hidden, Scroll }
```

---

## Implementation Plan

### Phase 1: Add Yoga Node to SolidNode

**File: `src/solid/core/types.zig`**

```zig
const yoga = @import("yoga-zig");

pub const SolidNode = struct {
    // ... existing fields ...
    
    // Add Yoga node handle
    yoga_node: ?yoga.Node = null,
    
    // ... rest of struct ...
    
    pub fn initYogaNode(self: *SolidNode) void {
        if (self.yoga_node == null) {
            self.yoga_node = yoga.Node.new();
        }
    }
    
    pub fn deinitYogaNode(self: *SolidNode) void {
        if (self.yoga_node) |node| {
            node.free();
            self.yoga_node = null;
        }
    }
};
```

**File: `src/solid/core/types.zig` - NodeStore**

Update `createNode` and `removeNode` to manage Yoga nodes:

```zig
pub fn createNode(self: *NodeStore, kind: NodeKind) !u32 {
    // ... existing code ...
    node.initYogaNode();
    return id;
}

pub fn removeNode(self: *NodeStore, id: u32) void {
    if (self.nodes.getPtr(id)) |node| {
        node.deinitYogaNode();
        // ... existing cleanup ...
    }
}
```

---

### Phase 2: Create Yoga Adapter Module

**New File: `src/solid/layout/yoga_adapter.zig`**

```zig
const std = @import("std");
const yoga = @import("yoga-zig");
const tailwind = @import("../style/tailwind.zig");
const types = @import("../core/types.zig");

/// Apply Tailwind Spec to a Yoga Node
pub fn applySpec(yg: yoga.Node, spec: *const tailwind.Spec) void {
    // Flex container props
    if (spec.is_flex) {
        yg.setDisplay(.Flex);
    }
    
    if (spec.direction) |dir| {
        yg.setFlexDirection(switch (dir) {
            .horizontal => .Row,
            .vertical => .Column,
        });
    }
    
    if (spec.justify) |j| {
        yg.setJustifyContent(mapJustify(j));
    }
    
    if (spec.align_items) |a| {
        yg.setAlignItems(mapAlign(a));
    }
    
    // Sizing
    if (spec.width) |w| {
        switch (w) {
            .full => yg.setWidthPercent(100),
            .pixels => |px| yg.setWidth(px),
        }
    }
    
    if (spec.height) |h| {
        switch (h) {
            .full => yg.setHeightPercent(100),
            .pixels => |px| yg.setHeight(px),
        }
    }
    
    // Spacing
    if (spec.margin.left) |v| yg.setMargin(.Left, v);
    if (spec.margin.right) |v| yg.setMargin(.Right, v);
    if (spec.margin.top) |v| yg.setMargin(.Top, v);
    if (spec.margin.bottom) |v| yg.setMargin(.Bottom, v);
    
    if (spec.padding.left) |v| yg.setPadding(.Left, v);
    if (spec.padding.right) |v| yg.setPadding(.Right, v);
    if (spec.padding.top) |v| yg.setPadding(.Top, v);
    if (spec.padding.bottom) |v| yg.setPadding(.Bottom, v);
    
    // Gap
    if (spec.gap_row) |v| yg.setGap(.Row, v);
    if (spec.gap_col) |v| yg.setGap(.Column, v);
    
    // Hidden
    if (spec.hidden) {
        yg.setDisplay(.None);
    }
}

fn mapJustify(j: dvui.FlexBoxWidget.ContentPosition) yoga.enums.Justify {
    return switch (j) {
        .start => .FlexStart,
        .center => .Center,
        .end => .FlexEnd,
        .between => .SpaceBetween,
        .around => .SpaceAround,
    };
}

fn mapAlign(a: dvui.FlexBoxWidget.AlignItems) yoga.enums.Align {
    return switch (a) {
        .start => .FlexStart,
        .center => .Center,
        .end => .FlexEnd,
    };
}
```

---

### Phase 3: Update Tailwind Spec for New Features

**File: `src/solid/style/tailwind.zig`**

Add parsing for new features that Yoga supports:

```zig
pub const Spec = struct {
    // Existing...
    
    // New Yoga-supported features
    flex_grow: ?f32 = null,
    flex_shrink: ?f32 = null,
    flex_basis: ?FlexBasis = null,
    flex_wrap: ?FlexWrap = null,
    align_self: ?AlignSelf = null,
    position_type: ?PositionType = null,
    position_left: ?f32 = null,
    position_top: ?f32 = null,
    position_right: ?f32 = null,
    position_bottom: ?f32 = null,
    min_width: ?MinMax = null,
    max_width: ?MinMax = null,
    min_height: ?MinMax = null,
    max_height: ?MinMax = null,
};

pub const FlexBasis = union(enum) {
    auto,
    pixels: f32,
    percent: f32,
};

pub const FlexWrap = enum {
    nowrap,
    wrap,
    wrap_reverse,
};

pub const PositionType = enum {
    static,
    relative,
    absolute,
};

pub const MinMax = union(enum) {
    pixels: f32,
    percent: f32,
    full,
};
```

Add parsing rules:
- `flex-1` → `flex_grow: 1, flex_shrink: 1, flex_basis: .{ .percent = 0 }`
- `flex-grow` → `flex_grow: 1`
- `flex-shrink-0` → `flex_shrink: 0`
- `flex-wrap` → `flex_wrap: .wrap`
- `self-center` → `align_self: .center`
- `absolute` → `position_type: .absolute`
- `relative` → `position_type: .relative`
- `left-4` → `position_left: 16`
- `min-w-0` → `min_width: .{ .pixels = 0 }`
- `max-w-sm` → `max_width: .{ .pixels = 384 }`
- `w-1/2` → `width: .{ .percent = 50 }`

---

### Phase 4: Replace Layout Algorithm

**File: `src/solid/layout/mod.zig`**

```zig
const yoga = @import("yoga-zig");
const yoga_adapter = @import("yoga_adapter.zig");

pub fn updateLayouts(store: *types.NodeStore) void {
    const win = dvui.currentWindow();
    const viewport_w = win.rect_pixels.w;
    const viewport_h = win.rect_pixels.h;
    
    const root = store.node(0) orelse return;
    
    // Sync Yoga tree structure
    syncYogaTree(store, root);
    
    // Apply styles to Yoga nodes
    applyStylesToYogaTree(store, root);
    
    // Calculate layout from root
    if (root.yoga_node) |yg_root| {
        yg_root.calculateLayout(viewport_w, viewport_h, .LTR);
    }
    
    // Read computed layouts back into node.layout.rect
    readYogaLayouts(store, root, 0, 0);
}

fn syncYogaTree(store: *types.NodeStore, node: *types.SolidNode) void {
    node.initYogaNode();
    
    const yg = node.yoga_node.?;
    
    // Clear and rebuild children
    const child_count = yg.getChildCount();
    for (0..child_count) |_| {
        if (yg.getChild(0)) |child| {
            yg.removeChild(child);
        }
    }
    
    // Add children in order
    for (node.children.items, 0..) |child_id, idx| {
        if (store.node(child_id)) |child| {
            syncYogaTree(store, child);
            if (child.yoga_node) |child_yg| {
                yg.insertChild(child_yg, idx);
            }
        }
    }
}

fn applyStylesToYogaTree(store: *types.NodeStore, node: *types.SolidNode) void {
    if (node.yoga_node) |yg| {
        const spec = node.prepareClassSpec();
        yoga_adapter.applySpec(yg, &spec);
        
        // Set measure func for leaf nodes (text, etc.)
        if (node.kind == .text or isLeafElement(node)) {
            yg.setMeasureFunc(measureCallback);
        }
    }
    
    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            applyStylesToYogaTree(store, child);
        }
    }
}

fn readYogaLayouts(store: *types.NodeStore, node: *types.SolidNode, parent_x: f32, parent_y: f32) void {
    if (node.yoga_node) |yg| {
        const layout = yg.getComputedLayout();
        node.layout.rect = .{
            .x = parent_x + layout.left,
            .y = parent_y + layout.top,
            .w = layout.width,
            .h = layout.height,
        };
        
        const child_x = node.layout.rect.?.x;
        const child_y = node.layout.rect.?.y;
        
        for (node.children.items) |child_id| {
            if (store.node(child_id)) |child| {
                readYogaLayouts(store, child, child_x, child_y);
            }
        }
    }
}

// Yoga measurement callback for text nodes
fn measureCallback(
    yg_node: yoga.cdef.YGNodeRef,
    width: f32,
    width_mode: yoga.enums.MeasureMode,
    height: f32,
    height_mode: yoga.enums.MeasureMode,
) yoga.cdef.YGSize {
    // Retrieve SolidNode from Yoga node context (need to store pointer)
    // Use existing measure.zig logic
    _ = yg_node;
    _ = width;
    _ = width_mode;
    _ = height;
    _ = height_mode;
    
    return .{ .width = 100, .height = 20 }; // Placeholder
}
```

---

### Phase 5: Wire Yoga into Build System

**File: `build.zig`**

Add yoga-zig as a module dependency:

```zig
// In the solid module setup
solid_mod.addImport("yoga-zig", yoga_zig_mod);
```

Ensure `deps/zig-yoga` is built and linked.

---

### Phase 6: Testing Strategy

1. **Visual Comparison**: Create test layouts with the new system and compare visually
2. **Layout Logging**: Log computed rects before/after migration
3. **Feature Test Cases**:
   - Basic flex row/column
   - `justify-center`, `items-center`
   - `flex-1`, `flex-grow`
   - `w-1/2`, percentage widths
   - `items-stretch` (now works!)
   - `flex-wrap`
   - `absolute` positioning
   - Nested flex containers

---

### Phase 7: Cleanup

After validation:
1. Delete `src/solid/layout/flex.zig`
2. Remove custom flex code from `measure.zig` if fully replaced
3. Update `FEATURE_ROADMAP.md` to mark layout features as complete

---

## Migration Checklist

- [ ] Add yoga-zig import to solid module in build.zig
- [ ] Add `yoga_node` field to `SolidNode`
- [ ] Create `src/solid/layout/yoga_adapter.zig`
- [ ] Update `updateLayouts()` to use Yoga
- [ ] Implement measurement callback for text nodes
- [ ] Add new Tailwind parsing for Yoga features
- [ ] Test basic layouts
- [ ] Test advanced features (stretch, grow, wrap)
- [ ] Delete old flex.zig
- [ ] Update documentation

---

## Tailwind → Yoga Property Mapping Reference

| Tailwind | Yoga Method | Notes |
|----------|-------------|-------|
| `flex` | `setDisplay(.Flex)` | |
| `flex-row` | `setFlexDirection(.Row)` | |
| `flex-col` | `setFlexDirection(.Column)` | |
| `flex-wrap` | `setFlexWrap(.Wrap)` | |
| `flex-nowrap` | `setFlexWrap(.NoWrap)` | |
| `flex-1` | `setFlexGrow(1)`, `setFlexShrink(1)`, `setFlexBasis(0%)` | |
| `flex-grow` | `setFlexGrow(1)` | |
| `flex-grow-0` | `setFlexGrow(0)` | |
| `flex-shrink` | `setFlexShrink(1)` | |
| `flex-shrink-0` | `setFlexShrink(0)` | |
| `justify-start` | `setJustifyContent(.FlexStart)` | |
| `justify-center` | `setJustifyContent(.Center)` | |
| `justify-end` | `setJustifyContent(.FlexEnd)` | |
| `justify-between` | `setJustifyContent(.SpaceBetween)` | |
| `justify-around` | `setJustifyContent(.SpaceAround)` | |
| `justify-evenly` | `setJustifyContent(.SpaceEvenly)` | |
| `items-start` | `setAlignItems(.FlexStart)` | |
| `items-center` | `setAlignItems(.Center)` | |
| `items-end` | `setAlignItems(.FlexEnd)` | |
| `items-stretch` | `setAlignItems(.Stretch)` | **Now works!** |
| `items-baseline` | `setAlignItems(.Baseline)` | |
| `self-start` | `setAlignSelf(.FlexStart)` | |
| `self-center` | `setAlignSelf(.Center)` | |
| `self-end` | `setAlignSelf(.FlexEnd)` | |
| `self-stretch` | `setAlignSelf(.Stretch)` | |
| `w-full` | `setWidthPercent(100)` | |
| `w-1/2` | `setWidthPercent(50)` | |
| `w-{n}` | `setWidth(n * 4)` | |
| `h-full` | `setHeightPercent(100)` | |
| `h-screen` | `setHeightPercent(100)` | |
| `min-w-0` | `setMinWidth(0)` | |
| `max-w-sm` | `setMaxWidth(384)` | |
| `p-{n}` | `setPadding(.All, n * 4)` | |
| `m-{n}` | `setMargin(.All, n * 4)` | |
| `gap-{n}` | `setGap(.All, n * 4)` | |
| `absolute` | `setPositionType(.Absolute)` | |
| `relative` | `setPositionType(.Relative)` | |
| `left-{n}` | `setPosition(.Left, n * 4)` | |
| `top-{n}` | `setPosition(.Top, n * 4)` | |
| `hidden` | `setDisplay(.None)` | |
| `overflow-hidden` | `setOverflow(.Hidden)` | |

---

## Notes for Implementing LLM

1. **Start with Phase 1-2** before touching layout logic to ensure Yoga nodes work
2. **Test incrementally** - don't try to replace everything at once
3. **Keep existing rect reading** - render code doesn't need changes
4. **Measurement is critical** - text nodes need proper `measureFunc` or layout breaks
5. **Tree sync matters** - Yoga tree must match SolidNode tree exactly
6. **Dirty tracking** - Use `yoga.Node.markDirty()` when styles change

# Architecture Guidance: Solid → DVUI Retained-Mode Renderer

## Problem Statement

The current Solid → DVUI rendering pipeline uses **immediate-mode rendering**:
- Every frame, the entire `NodeStore` tree is traversed
- DVUI widgets (`dvui.box`, `dvui.button`, `dvui.label`) are created fresh each frame
- Widgets are destroyed at frame end via `defer widget.deinit()`
- No widget state or layout persists between frames

This is inefficient for UIs where most content is static or only a few nodes change per frame.

**Goal**: Transition to a **hybrid retained/immediate architecture** where:
- Layout is cached and only recomputed for dirty subtrees
- Transforms and visual properties update cheaply without layout recalc
- Animations run at full speed without triggering expensive operations
- DVUI immediate-mode rendering is preserved for interactive widgets (inputs, buttons)
- Non-interactive containers use direct drawing to bypass DVUI layout overhead

---

## Critical Constraint: DVUI Layout Behavior

**Key insight from review**: DVUI's `flexbox()` and `box()` widgets compute layout internally every frame. Simply caching a `rect` in `SolidNode` and passing it via `dvui.Options` does **not** skip DVUI's layout work.

```zig
// This still runs DVUI's internal layout algorithm:
var box = dvui.box(@src(), .{}, .{ .rect = cached_rect });
```

**Implication**: To realize layout caching benefits, we must either:
1. **Bypass DVUI layout entirely** for non-interactive elements (use `dvui.renderTriangles`/`renderText` directly)
2. **Keep DVUI widgets** only for interactive elements that need focus/input state

This guidance adopts approach #1 for containers, #2 for interactive widgets.

---

## Target Feature Set

The architecture must support (from `FRONTEND_FEATURES.md`):

| Category | Features |
|----------|----------|
| **Geometry** | Position, size, scale, anchor/pivot, rotation, z-order, clipping |
| **Layout** | Flexbox, padding, spacing, alignment |
| **Text** | Font selection, color, alignment, wrapping, auto-scaling |
| **Images** | Source, scaling, rotation, tint, alpha |
| **Visuals** | Background color, opacity, corner radius, gradients |
| **Animation** | Tweening position/size/rotation/color/opacity, easing functions |
| **Scrolling** | Scroll containers, scrollbars, scroll input handling |
| **Input** | Click, hover enter/exit events |

---

## Current Architecture

### Data Flow
```
SolidJS (reactive) → HostNode tree (JS) → FFI → NodeStore (Zig) → solid_renderer → DVUI widgets → GPU
```

### Key Components

| Layer | Component | Role |
|-------|-----------|------|
| JS | `HostNode` tree | Mirrors DOM; tracks props, children, listeners |
| JS | `solid-host.tsx` | Solid renderer; enqueues mutations; calls FFI |
| FFI | `native-renderer.ts` | Bun:ffi bindings; JSON payloads for tree sync |
| Zig | `NodeStore` | `HashMap<u32, SolidNode>`; retained tree structure |
| Zig | `SolidNode` | Node struct: id, tag, text, className, children, version fields |
| Zig | `solid_renderer.zig` | Walks tree each frame; maps tags to DVUI widgets |
| Zig | DVUI | Immediate-mode widget library |

### Current Render Loop
```zig
// solid_renderer.zig - called every frame
pub fn render(store: *NodeStore) bool {
    for (root.children.items) |child_id| {
        renderNode(store, child_id, allocator);  // Full traversal, full DVUI widget creation
    }
}
```

### Existing Infrastructure

**Dirty tracking** (currently disabled):
```zig
version: u64 = 0,           // Node's own version
subtree_version: u64 = 0,   // Max version in subtree
last_render_version: u64 = 0, // Version when last rendered
```

**Why disabled**: Using `hasDirtySubtree()` to skip rendering caused black screens because DVUI requires widget creation every frame to draw anything.

**Fallback paths** (must be preserved or consciously retired):
- Binary command path (`commitCommands` / `renderCommandsDvui`)
- Periodic resync every 300 frames
- Sequence number handling for mutation ordering

**State ownership** (critical for interactive widgets):
- `InputState` in `SolidNode` owns text buffer and value
- DVUI's `TextEntryWidget` owns cursor position, selection, IME state
- Focus management lives in `dvui.Window`

---

## Pre-Implementation: Profiling First

**Before any optimization, instrument the current implementation:**

```zig
// Add to renderFrame in native_renderer.zig
var timer = std.time.Timer{};
timer.reset();

// ... layout pass ...
const layout_ns = timer.lap();

// ... render pass ...
const render_ns = timer.lap();

logMessage(renderer, 1, "frame: layout={d}us render={d}us nodes={d}", .{
    layout_ns / 1000,
    render_ns / 1000,
    store.nodes.count(),
});
```

**Metrics to collect:**
- Time in DVUI widget creation vs drawing
- Number of nodes traversed per frame
- Text measurement calls per frame
- FFI call frequency and payload sizes

**Only proceed with optimization after confirming hot spots.**

---

## Proposed Architecture: Hybrid Rendering

### Core Strategy

Split rendering into two paths based on interactivity:

| Node Type | Rendering Path | Layout | State Management |
|-----------|---------------|--------|------------------|
| **Container** (`div`, `p`, `h1-h3`) | Direct draw | Cached in `SolidNode` | None needed |
| **Interactive** (`button`, `input`, scroll) | DVUI widgets | DVUI computes | DVUI owns |
| **Text** (non-interactive) | Direct `renderText` | Cached measurement | None needed |
| **Image** | Direct or DVUI image | Cached rect | None needed |

### Extended SolidNode

```zig
const SolidNode = struct {
    // === Existing ===
    id: u32,
    kind: NodeKind,
    tag: []u8,
    text: []u8,
    class_name: []u8,
    children: std.ArrayList(u32),
    parent: ?u32,
    listeners: ListenerSet,  // Determines interactivity

    // Dirty tracking (existing, will be re-enabled for layout)
    version: u64,
    subtree_version: u64,

    // === NEW: Cached Layout ===
    layout: LayoutCache,

    // === NEW: Transform (animated, no layout impact) ===
    transform: Transform,

    // === NEW: Visual Properties (animated, no layout impact) ===
    visual: VisualProps,

    // === Existing: Interactive widget state ===
    input_state: ?InputState,  // Already exists

    pub fn isInteractive(self: *const SolidNode) bool {
        // Has event listeners OR is inherently interactive tag
        return self.listeners.names.items.len > 0 or
               std.mem.eql(u8, self.tag, "button") or
               std.mem.eql(u8, self.tag, "input");
    }
};

const LayoutCache = struct {
    rect: ?Rect = null,           // Computed position/size
    version: u64 = 0,             // Version when computed
    intrinsic_size: ?Size = null, // For text: measured size
    text_hash: u64 = 0,           // Hash of text + font params
};

const Transform = struct {
    anchor: [2]f32 = .{ 0.5, 0.5 },  // Pivot point (0-1)
    scale: [2]f32 = .{ 1, 1 },
    rotation: f32 = 0,               // Radians
    translation: [2]f32 = .{ 0, 0 }, // Offset from layout position
};

const VisualProps = struct {
    background: ?Color = null,
    opacity: f32 = 1.0,
    corner_radius: f32 = 0,
    clip_children: bool = false,
    gradient: ?Gradient = null,
    z_index: i16 = 0,
};
```

### Two-Pass Rendering with Hybrid Paths

```zig
pub fn renderFrame(store: *NodeStore, screen_rect: Rect) void {
    // Pass 1: Update layout for dirty nodes (CACHED)
    // Only recomputes nodes where subtree_version > layout.version
    updateLayoutIfDirty(store, 0, screen_rect);

    // Pass 2: Render using appropriate path per node
    renderNode(store, 0);
}

fn renderNode(store: *NodeStore, node_id: u32) void {
    const node = store.node(node_id) orelse return;

    if (node.isInteractive()) {
        // DVUI widget path - preserves focus, input, IME state
        renderInteractiveWithDvui(store, node);
    } else {
        // Direct draw path - uses cached layout, bypasses DVUI layout
        renderNonInteractiveDirect(store, node);
    }
}

fn renderNonInteractiveDirect(store: *NodeStore, node: *SolidNode) void {
    const base_rect = node.layout.rect orelse return;
    const rect = applyTransform(base_rect, node.transform);

    // Clip if needed
    if (node.visual.clip_children) {
        dvui.pushClipRect(rect);
        defer dvui.popClipRect();
    }

    // Direct draw background (no DVUI widget overhead)
    if (node.visual.background) |bg| {
        drawRectDirect(rect, bg, node.visual.corner_radius, node.visual.opacity);
    }
    if (node.visual.gradient) |g| {
        drawGradientDirect(rect, g, node.visual.opacity);
    }

    // Render text directly if this is a text container
    if (node.kind == .text) {
        drawTextDirect(rect, node.text, node.visual);
    }

    // Recurse to children
    for (node.children.items) |child_id| {
        renderNode(store, child_id);
    }
}

fn renderInteractiveWithDvui(store: *NodeStore, node: *SolidNode) void {
    // Use existing DVUI widget path from solid_renderer.zig
    // This preserves: focus tracking, keyboard nav, IME, selection
    const class_spec = node.prepareClassSpec();

    if (std.mem.eql(u8, node.tag, "button")) {
        renderButton(store, node, class_spec);  // Existing implementation
    } else if (std.mem.eql(u8, node.tag, "input")) {
        renderInput(store, node, class_spec);   // Existing implementation
    }
    // ... other interactive widgets
}
```

### Direct Draw Functions

Bypass DVUI widget system, use low-level DVUI rendering:

```zig
fn drawRectDirect(rect: Rect, color: Color, corner_radius: f32, opacity: f32) void {
    const final_color = color.opacity(opacity);

    if (corner_radius > 0) {
        // Use DVUI's rounded rect rendering
        dvui.renderRoundedRect(rect, corner_radius, final_color);
    } else {
        // Direct triangle submission
        var builder = dvui.Triangles.Builder.init(allocator, 4, 6);
        defer builder.deinit();

        const pma = dvui.Color.PMA.fromColor(final_color);
        builder.appendVertex(.{ .pos = .{ .x = rect.x, .y = rect.y }, .col = pma });
        builder.appendVertex(.{ .pos = .{ .x = rect.x + rect.w, .y = rect.y }, .col = pma });
        builder.appendVertex(.{ .pos = .{ .x = rect.x + rect.w, .y = rect.y + rect.h }, .col = pma });
        builder.appendVertex(.{ .pos = .{ .x = rect.x, .y = rect.y + rect.h }, .col = pma });
        builder.appendTriangles(&.{ 0, 1, 2, 0, 2, 3 });

        dvui.renderTriangles(builder.build(), null);
    }
}

fn drawTextDirect(rect: Rect, text: []const u8, visual: VisualProps) void {
    const trimmed = std.mem.trim(u8, text, " \n\r\t");
    if (trimmed.len == 0) return;

    const color = visual.text_color orelse dvui.Color.white;
    const font = dvui.Options{}.fontGet();

    dvui.renderText(.{
        .font = font,
        .text = trimmed,
        .rs = .{ .r = rect, .s = 1.0 },
        .color = color.opacity(visual.opacity),
    });
}
```

---

## Layout Engine

### Layout Caching with Dirty Tracking

```zig
fn updateLayoutIfDirty(store: *NodeStore, node_id: u32, parent_rect: Rect) void {
    const node = store.node(node_id) orelse return;

    const needs_update = node.layout.version < node.subtree_version or
                         node.layout.rect == null;

    if (needs_update) {
        // Compute this node's layout
        node.layout.rect = computeLayout(node, parent_rect, store);
        node.layout.version = node.subtree_version;
    }

    // Always recurse - children might be dirty even if parent isn't
    const child_rect = node.layout.rect orelse parent_rect;
    for (node.children.items) |child_id| {
        updateLayoutIfDirty(store, child_id, child_rect);
    }
}

fn computeLayout(node: *SolidNode, parent_rect: Rect, store: *NodeStore) Rect {
    const spec = node.prepareClassSpec();

    // Determine size from Tailwind classes or intrinsic content
    var size = Size{
        .w = resolveSize(spec.width, parent_rect.w),
        .h = resolveSize(spec.height, parent_rect.h),
    };

    // Text nodes: use cached intrinsic size
    if (node.kind == .text) {
        const intrinsic = measureTextCached(node);
        if (size.w == 0) size.w = intrinsic.w;
        if (size.h == 0) size.h = intrinsic.h;
    }

    // Position based on layout mode
    const pos = computePosition(node, spec, parent_rect, size, store);

    return Rect{ .x = pos.x, .y = pos.y, .w = size.w, .h = size.h };
}

fn measureTextCached(node: *SolidNode) Size {
    const font = dvui.Options{}.fontGet();
    const hash = computeTextHash(node.text, font);

    if (node.layout.text_hash == hash and node.layout.intrinsic_size != null) {
        return node.layout.intrinsic_size.?;  // Cache hit
    }

    // Cache miss: measure text
    const size = font.textSize(node.text);
    node.layout.intrinsic_size = size;
    node.layout.text_hash = hash;
    return size;
}
```

### Dirty Propagation

```zig
// Called when structure or sizing changes
fn markLayoutDirty(store: *NodeStore, id: u32) void {
    var current: ?u32 = id;
    while (current) |node_id| {
        const node = store.nodes.getPtr(node_id) orelse break;
        node.layout.rect = null;  // Invalidate cache
        node.subtree_version = store.nextVersion();
        current = node.parent;
    }
}

// Called for transform/visual changes - NO propagation needed
fn setTransform(store: *NodeStore, id: u32, transform: Transform) void {
    const node = store.nodes.getPtr(id) orelse return;
    node.transform = transform;
    // No dirty propagation - transform doesn't affect layout
}

fn setVisual(store: *NodeStore, id: u32, visual: VisualProps) void {
    const node = store.nodes.getPtr(id) orelse return;
    node.visual = visual;
    // No dirty propagation - visuals don't affect layout
}
```

---

## FFI Operations

### Existing (Structure - triggers layout dirty)
```typescript
{ op: "create", id, parent, tag, className }
{ op: "remove", id }
{ op: "move", id, parent, before }
{ op: "set_class", id, className }  // May affect layout
{ op: "set_text", id, text }        // Affects intrinsic size
```

### New (Transform/Visual - no layout impact)
```typescript
// Transform: idempotent, last value wins, no sequencing needed
{ op: "set_transform", id, rotation?, scale?, anchor?, translation? }

// Visual: idempotent, last value wins
{ op: "set_visual", id, opacity?, cornerRadius?, background?, clipChildren? }

// Gradient
{ op: "set_gradient", id, colors: number[], stops: number[], angle: number }
```

### Integration with Existing Paths

**Periodic resync** (every 300 frames):
- Snapshots should include `transform` and `visual` state
- Ensures drift recovery covers all state

**Sequence numbers**:
- Structure ops: continue using `seq` for ordering
- Transform/visual ops: idempotent, no sequencing needed

**Binary command path** (`commitCommands`):
- Keep as fallback for debugging
- Consider deprecating once Solid path is proven stable
- Document: "Binary path does not support transforms/visuals"

---

## What Triggers Layout Recalc vs Not

| Change | Layout Dirty? | Why |
|--------|---------------|-----|
| Node added/removed | **Yes** | Tree structure changed |
| Node moved (reparent) | **Yes** | Parent changed |
| `set_class` with size change | **Yes** | Affects layout |
| `set_text` | **Yes** | Affects intrinsic size |
| `set_transform` | **No** | Only affects final position |
| `set_visual` | **No** | Visual only |
| Animation frame | **No** | Just transform/visual updates |

---

## Implementation Phases

### Phase 0: Instrumentation (Do First)
**Effort**: Low | **Impact**: Enables informed decisions

1. Add frame timing to `renderFrame()`
2. Count nodes traversed, text measurements, DVUI widget creations
3. Log metrics at debug level
4. Run with representative UI complexity
5. Identify actual hot spots

**Gate**: Only proceed to Phase 1 after confirming layout/widget creation is the bottleneck.

### Phase 1: Layout Caching + Direct Draw for Containers
**Effort**: Medium | **Impact**: High (if profiling confirms)

1. Add `LayoutCache` to `SolidNode`
2. Implement `updateLayoutIfDirty()`
3. Implement `renderNonInteractiveDirect()` with direct triangle/text rendering
4. Keep `renderInteractiveWithDvui()` for buttons, inputs
5. Re-enable dirty tracking for layout pass

**Validation**: Frame time should drop for static UIs.

### Phase 2: Transform/Visual Separation
**Effort**: Low | **Impact**: Medium

1. Add `Transform` and `VisualProps` to `SolidNode`
2. Add FFI ops (`set_transform`, `set_visual`)
3. Apply transform in render pass
4. Update `solid-host.tsx` to emit new ops

**Validation**: Animations should not trigger layout recalc.

### Phase 3: Text Measurement Caching
**Effort**: Low | **Impact**: Medium (for text-heavy UIs)

1. Implement `measureTextCached()` with hash-based invalidation
2. Store `intrinsic_size` and `text_hash` in `LayoutCache`

**Validation**: Text measurement calls should drop to near-zero for static text.

### Phase 4: Snapshot/Resync Updates
**Effort**: Low | **Impact**: Correctness

1. Include `transform` and `visual` in JSON snapshots
2. Update `rebuildSolidStoreFromJson()` to restore these fields
3. Document binary path limitations

---

## What We're NOT Doing (Defer These)

| Feature | Why Defer |
|---------|-----------|
| Display list | Only needed if render traversal itself is slow |
| Dirty region tracking | Only needed if GPU overdraw is measurable |
| Retained DVUI widgets | Would require forking DVUI; hybrid approach avoids this |
| Geometry caching | Only needed if gradient/rounded rect generation is slow |
| Event-driven frame loop | Current game loop is fine; optimize render cost first |

---

## State Ownership (Critical for Correctness)

### Interactive Widgets: DVUI Owns State

| State | Owner | Notes |
|-------|-------|-------|
| Focus | `dvui.Window` | Must use DVUI widgets to participate |
| Cursor position | `TextEntryWidget` | Internal to DVUI |
| Selection | `TextEntryWidget` | Internal to DVUI |
| IME composition | `TextEntryWidget` | Platform-specific |
| Hover state | DVUI hit testing | Requires DVUI widget bounds |

**Implication**: Interactive elements (`button`, `input`) MUST use DVUI widget path, not direct draw.

### Non-Interactive Elements: NodeStore Owns State

| State | Owner | Notes |
|-------|-------|-------|
| Layout rect | `SolidNode.layout` | Cached, dirty-tracked |
| Transform | `SolidNode.transform` | Updated via FFI |
| Visuals | `SolidNode.visual` | Updated via FFI |
| Text content | `SolidNode.text` | Synced from JS |

---

## Files to Modify

| File | Changes |
|------|---------|
| `src/jsruntime/solid/types.zig` | Add `LayoutCache`, `Transform`, `VisualProps` to `SolidNode`; add `isInteractive()` |
| `src/solid_renderer.zig` | Two-pass render; split `renderNode` into interactive/non-interactive paths |
| `src/native_renderer.zig` | Handle new ops; add frame timing instrumentation |
| `src/jsruntime/solid/dvui_tailwind.zig` | Layout computation from Tailwind classes |
| `frontend/solid/solid-host.tsx` | Emit `set_transform`, `set_visual` ops |

## New Files

| File | Purpose |
|------|---------|
| `src/jsruntime/solid/layout.zig` | Layout computation (flexbox subset) |
| `src/jsruntime/solid/direct_draw.zig` | Direct rendering utilities bypassing DVUI widgets |

---

## Performance Expectations

| Scenario | Current | After Phase 1 | After Phase 2 |
|----------|---------|---------------|---------------|
| Static UI (100 nodes) | O(n) widget creation | O(n) direct draw | O(n) direct draw |
| Static UI layout cost | O(n) DVUI layout | **O(1) cached** | O(1) cached |
| Text edit | O(n) / frame | O(dirty subtree) | O(dirty subtree) |
| Animation (transform) | O(n) / frame | O(n) / frame | **O(1) property update** |
| Interactive widget | O(1) DVUI widget | O(1) DVUI widget | O(1) DVUI widget |

**Key win**: Layout computation drops from O(n) to O(dirty). Direct draw is faster than DVUI widget creation but still O(n) traversal—this is acceptable for reasonable UI sizes.

---

## Summary

```
┌─────────────────────────────────────────────────────────────┐
│                      SOLID (JS/Bun)                         │
│   Reactivity │ Animation State │ Structure Mutations        │
└──────────────┬──────────────────────────────────────────────┘
               │
               │  FFI: Structure ops (layout) + Transform/Visual ops (no layout)
               │
┌──────────────▼──────────────────────────────────────────────┐
│                    ZIG NODE STORE                           │
│                                                             │
│  ┌────────────────┐  ┌────────────────┐  ┌───────────────┐ │
│  │  LayoutCache   │  │   Transform    │  │  VisualProps  │ │
│  │   (CACHED)     │  │  (per-frame)   │  │  (per-frame)  │ │
│  └───────┬────────┘  └───────┬────────┘  └───────┬───────┘ │
│          │                   │                   │         │
│          ▼                   ▼                   ▼         │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         Pass 1: updateLayoutIfDirty()               │   │
│  │         (skips clean subtrees)                      │   │
│  └─────────────────────────┬───────────────────────────┘   │
│                            ▼                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         Pass 2: renderNode()                        │   │
│  │  ┌─────────────────┐    ┌─────────────────────────┐ │   │
│  │  │ Non-Interactive │    │     Interactive         │ │   │
│  │  │  Direct Draw    │    │    DVUI Widgets         │ │   │
│  │  │ (cached layout) │    │ (focus, input, IME)     │ │   │
│  │  └────────┬────────┘    └────────────┬────────────┘ │   │
│  └───────────┼──────────────────────────┼──────────────┘   │
└──────────────┼──────────────────────────┼──────────────────┘
               │                          │
               ▼                          ▼
        dvui.renderTriangles      DVUI Widget System
        dvui.renderText                  │
               │                          │
               └──────────┬───────────────┘
                          ▼
                        GPU
```

**The 80/20**:
1. **Profile first** to confirm hot spots
2. **Cache layout** and direct-draw for non-interactive containers
3. **Keep DVUI widgets** for interactive elements (preserves focus/input/IME)
4. **Separate transforms from layout** so animations are O(1)

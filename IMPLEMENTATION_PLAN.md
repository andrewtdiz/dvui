# Implementation Plan: Achieving the Architecture Goal

This document outlines the concrete steps needed to fully realize the architecture described in `ARCHITECTURE_GOAL.md`.

---

## Current State Summary

| Component | Status | Notes |
|-----------|--------|-------|
| **NodeStore / SolidNode** | ✅ Implemented | `src/solid/core/types.zig` - includes version tracking, dirty flags |
| **Layout Engine** | ✅ Implemented | `src/solid/layout/` - flexbox, measurement, incremental updates |
| **Paint Cache** | ✅ Implemented | `src/solid/render/cache.zig` - DirtyRegionTracker, geometry caching |
| **Direct Rendering** | ✅ Implemented | `src/solid/render/direct.zig` - triangles, text |
| **Tailwind Parser** | ✅ Implemented | `src/solid/style/tailwind.zig` |
| **JS Bridge (Bun/Solid)** | 🟡 Partial | `solid-host.tsx` sends mutations; Zig receives via `applyOps` |
| **flushFrame() Protocol** | 🟡 Partial | JS calls `host.flush()` + `renderer.present()` - not batched as single flushFrame FFI |
| **Event Dispatch (Zig→JS)** | ✅ Implemented | `jsc.zig` dispatchEvent sends to JS callback |
| **EventLoop Integration** | 🟡 Partial | Zig renders; JS schedules via frame-scheduler.ts |

---

## Gap Analysis vs. ARCHITECTURE_GOAL.md

### 1. FFI Mutation Protocol
**Goal:** Small mutation ops (`createNode`, `updateNode`, `moveNode`, `removeNode`), batched, then `flushFrame()`.

**Current:**
- JS emits JSON mutation ops via `native.applyOps(payload)` 
- Zig parses JSON in `jsruntime/` and updates `NodeStore`
- Missing: Clean `flushFrame()` signal that triggers full pipeline (layout → paint cache → render)

**Gap:** `flushFrame()` is implicit (happens on `renderer.present()`). Should be an explicit FFI call.

---

### 2. Incremental Layout
**Goal:** Only dirty nodes recompute layout.

**Current:** ✅ Implemented in `layout/mod.zig`:
- `needsLayoutUpdate()` checks version against `subtree_version`
- Screen resize invalidates entire tree
- Subtree propagation via `markNodeChanged()`

**Gap:** None significant.

---

### 3. Incremental Paint / Dirty Regions
**Goal:** Nodes cache geometry; only `paintDirty` nodes regenerate buffers; track rectangular dirty regions.

**Current:** ✅ Implemented:
- `PaintCache` stores vertices/indices
- `DirtyRegionTracker` collects changed rectangles
- `renderCachedOrDirectBackground()` reuses cached geometry

**Gap:** Dirty region clipping not enforced (all intersecting nodes still draw even outside dirty rect). Low priority.

---

### 4. Event Flow (Input → JS → Mutations → Render)
**Goal:** Zig receives native input, dispatches to JS, JS reacts with mutations, Zig redraws.

**Current:**
- Button clicks dispatch via `jsc_bridge.dispatchEvent()`
- Input text changes dispatch `input` event
- JS receives via `native.onEvent()` callback

**Gap:** 
- Mouse/keyboard events not fully wired (only button/input)
- No hover state pushed to JS yet

---

### 5. Idle Efficiency / Event-Driven Rendering
**Goal:** No continuous JS render loop; only render when dirty.

**Current:**
- JS uses `createFrameScheduler()` which polls at ~60fps
- Zig re-renders every frame regardless of changes

**Gap:** 
- Should skip render when `!root.hasDirtySubtree()`
- JS scheduler should wait for events or dirty signals instead of polling

---

## Implementation Tasks

### Phase 1: Solidify Core Loop (Priority: High)

| Task | File(s) | Description |
|------|---------|-------------|
| **1.1** Add explicit `flushFrame` FFI | `frontend/solid/native-renderer.ts`, `src/jsruntime/runtime.zig` | Single call that processes queued ops → layout → paint → render |
| **1.2** Skip render when clean | `src/solid/render/mod.zig` | Early return if `!root.hasDirtySubtree()` and no dirty regions |
| **1.3** Remove polling in JS | `frontend/solid/frame-scheduler.ts` | Replace with event-driven loop (await input events or dirty signal) |

### Phase 2: Complete Event Pipeline (Priority: High)

| Task | File(s) | Description |
|------|---------|-------------|
| **2.1** Wire hover/focus events | `src/solid/render/mod.zig`, `bridge/jsc.zig` | Dispatch `mouseenter`, `mouseleave`, `focus`, `blur` |
| **2.2** Add keyboard events | `src/solid/bridge/jsc.zig` | Dispatch `keydown`, `keyup` to focused node |
| **2.3** Add listener type to mutations | `frontend/solid/solid-host.tsx` | Include listener names in `create` op so Zig knows which events to dispatch |

### Phase 3: Optimize Paint Pipeline (Priority: Medium)

| Task | File(s) | Description |
|------|---------|-------------|
| **3.1** Clip rendering to dirty regions | `src/solid/render/mod.zig` | Skip nodes entirely outside dirty rects |
| **3.2** Pool vertex buffers | `src/solid/render/cache.zig` | Reuse allocations across frames instead of alloc/free each paint |
| **3.3** Text glyph caching | `src/solid/render/direct.zig` | Cache shaped glyphs per text hash |

### Phase 4: Extended Widget Support (Priority: Medium)

| Task | File(s) | Description |
|------|---------|-------------|
| **4.1** Scroll containers | `src/solid/render/mod.zig`, `layout/` | Handle `overflow-y-auto` class, virtual content rect |
| **4.2** Select/dropdown | `src/solid/render/widgets.zig` (new) | Render `<select>` tags via DVUI menus |
| **4.3** Checkbox/radio | `src/solid/render/widgets.zig` | Render `<input type="checkbox">` |

### Phase 5: Developer Experience (Priority: Low)

| Task | File(s) | Description |
|------|---------|-------------|
| **5.1** Hot reload signal | `frontend/`, `src/jsruntime/hotreload.zig` | Invalidate entire tree on HMR |
| **5.2** Debug overlay | `src/solid/render/mod.zig` | Optional bounding-box visualization |
| **5.3** Performance metrics | `src/solid/render/mod.zig` | Time layout/paint/render per frame, expose to JS |

---

## Detailed Task Breakdown

### 1.1 Add Explicit `flushFrame` FFI

**frontend/solid/native-renderer.ts:**
```ts
flushFrame(): void {
  if (!this.ops.length && !this.dirtySnapshot) return;
  // Send queued ops
  if (this.ops.length) {
    const payload = encoder.encode(JSON.stringify({ ops: this.ops }));
    this.native.applyOps(payload);
    this.ops = [];
  }
  // Signal Zig to process
  this.native.flushFrame();
}
```

**src/jsruntime/runtime.zig:**
```zig
pub fn flushFrame(store: *NodeStore) void {
    layout.updateLayouts(store);
    var tracker = DirtyRegionTracker.init(allocator);
    defer tracker.deinit();
    paint_cache.updatePaintCache(store, &tracker);
    render_mod.render(null, store);
}
```

---

### 1.2 Skip Render When Clean

**src/solid/render/mod.zig:**
```zig
pub fn render(runtime: ?*jsruntime.JSRuntime, store: *types.NodeStore) bool {
    const root = store.node(0) orelse return false;
    
    // Early exit if nothing changed
    if (!root.hasDirtySubtree()) {
        return false;
    }
    
    // ... existing render logic
}
```

---

### 2.3 Include Listeners in Mutations

**frontend/solid/solid-host.tsx (in enqueueCreateOrMove):**
```ts
const createOp: MutationOp = {
  op: "create",
  id: node.id,
  parent: parentId,
  tag: node.tag,
  listeners: Array.from(node.listeners.keys()), // NEW
};
```

**src/solid/core/types.zig (in NodeStore op parsing):**
```zig
if (op.listeners) |names| {
  for (names) |name| {
    try node.addListener(name);
  }
}
```

---

## Success Criteria

1. **Frame time under 2ms** for typical UI updates (10-50 node changes)
2. **Zero allocations** in steady-state rendering (geometry buffers pooled)
3. **Events round-trip < 1ms** from native input to JS handler execution
4. **No render work** when UI is idle (dirty check early-exits)
5. **Clean FFI boundary**: JS never sees Zig internals; Zig never parses component logic

---

## Dependencies

- Bun FFI working (✅ confirmed)
- dvui triangle/text rendering (✅ confirmed)
- QuickJS removed; now using Bun JSC callbacks (✅ done)

---

## Risks

| Risk | Mitigation |
|------|------------|
| Bun FFI overhead | Profile; batch ops more aggressively |
| Layout complexity (CSS grid) | Defer grid; flexbox covers 90% of UIs |
| Focus management across FFI | Keep focus state in Zig; notify JS on change |

---

## Timeline Estimate

| Phase | Effort |
|-------|--------|
| Phase 1 (Core Loop) | 2-3 days |
| Phase 2 (Events) | 2-3 days |
| Phase 3 (Paint Optimization) | 3-5 days |
| Phase 4 (Widgets) | 5-7 days |
| Phase 5 (DX) | 2-3 days |

**Total: ~2-3 weeks** for full implementation with testing.

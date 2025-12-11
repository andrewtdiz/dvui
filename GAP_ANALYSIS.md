# Gap Analysis: Current Solid Implementation vs. Architecture Goal

This document identifies what's **missing** in the current `src/solid/` implementation compared to the reference implementation in `src/jsruntime_reference/` and the goals outlined in `ARCHITECTURE_GOAL.md`.

---

## Summary of Gaps

| Gap | Severity | Description |
|-----|----------|-------------|
| **1. No QuickJS integration** | 🔴 Critical | Reference has full QuickJS JS engine; current has stub bridge |
| **2. No `syncOps` / `flushOps` loop** | 🔴 Critical | Reference pulls ops from JS; current relies on external JSON push |
| **3. No signal state sync** | 🟡 Medium | Reference can read/write Solid signals; current cannot |
| **4. No in-process JS runtime** | 🔴 Critical | Reference runs JS inside Zig process; current delegates to Bun externally |
| **5. Limited op types** | 🟡 Medium | Reference has `set`, `listen`; current has partial coverage |
| **6. No gizmo/rect primitive ops** | 🟢 Low | Reference supports gizmoRect, rectPrimitive; current doesn't |

---

## Detailed Gap Analysis

### 1. QuickJS Integration (CRITICAL)

**Reference Implementation (`jsruntime_reference/solid/quickjs.zig`):**
- Full QuickJS bindings for calling JS functions
- `lookupHost()` / `lookupHostFunction()` to access `SolidHost` global
- `js_app_execute_jobs()` to drain JS microtask queue
- Direct JS→Zig value conversion (strings, ints, floats)

**Current Implementation (`solid/bridge/jsc.zig`):**
```zig
pub fn syncOps(_: *jsruntime.JSRuntime, _: *types.NodeStore) !bool {
    return false;  // ← STUB - does nothing
}
```
- All QuickJS functions are **empty stubs**
- No ability to call JS functions from Zig
- No microtask queue execution

**Impact:** Cannot achieve the incremental diff architecture where Zig **pulls** ops from JS.

---

### 2. Pull-Based `syncOps` / `flushOps` Loop (CRITICAL)

**Reference Implementation:**
```zig
pub fn syncOps(runtime: *jsruntime.JSRuntime, store: *types.NodeStore) !bool {
    // 1. Get JS context
    const ctx = try runtime.acquireContext();
    // 2. Lookup SolidHost.flushOps()
    const host = try lookupHost(ctx, global_const);
    const flush = try lookupHostFunction(ctx, host.const_value, "flushOps");
    // 3. Call JS to get pending ops array
    const ops_value = quickjs.JS_Call(ctx, flush.const_value, host.const_value, 0, null);
    // 4. Parse and apply each op
    for ops { applyOp(ctx, scratch, entry_const, store); }
    return true;
}
```

**Current Implementation:**
- JSON ops are pushed via FFI (`applySolidOps` in `native_renderer.zig`)
- `jsc.zig` stub returns `false`
- Polling-based: JS calls `renderer.present()` which triggers render

**Gap:** The architecture goal specifies:
> "Solid emits mutation ops as the UI changes. Solid calls `flushFrame()` to apply them."

Current implementation has this inverted: Zig waits for external FFI calls rather than pulling from embedded JS.

---

### 3. Solid Signal State Sync (MEDIUM)

**Reference Implementation:**
```zig
pub fn updateSolidStateI32(runtime: *jsruntime.JSRuntime, key: []const u8, value: i32) !void {
    try updateSolidState(runtime, key, .{ .integer = value });
}

pub fn readSolidStateI32(runtime: *jsruntime.JSRuntime, key: []const u8) !i32 {
    // Calls SolidHost.getSignalValue(key) in JS
    return read_value;
}
```

**Current Implementation:**
```zig
pub fn updateSolidStateI32(_: *jsruntime.JSRuntime, _: []const u8, _: i32) !void {
    return;  // ← NO-OP
}

pub fn readSolidStateI32(_: *jsruntime.JSRuntime, _: []const u8) !i32 {
    return error.SignalMissing;  // ← Always fails
}
```

**Gap:** Cannot synchronize state between Zig and JS, which is essential for:
- Zig pushing values to reactive signals (e.g., mouse position)
- Reading signal state for debugging/sync validation

---

### 4. In-Process JS Runtime (CRITICAL)

**Reference Implementation (`jsruntime_reference/runtime.zig`):**
- Embeds QuickJS inside Zig process
- `JSRuntime.init()` loads JavaScript modules
- `installNativeBindings()` exposes Zig functions to JS
- `runFrame()` executes JS hooks each frame

**Current Implementation (`jsruntime/runtime.zig`):**
```zig
pub const JSRuntime = struct {
    allocator: std.mem.Allocator,
    event_cb: ?EventCallback = null,
    event_ctx: ?*anyopaque = null,
    // ← No QuickJS handle, no JS context
};
```

**Gap:** Current runtime is a **callback registry**, not an embedded JS engine. It relies on:
- External Bun process running `frontend/index.ts`
- FFI calls via native C bindings
- JSON serialization for all communication

---

### 5. Op Type Coverage (MEDIUM)

**Reference ops supported:**
| Op | Reference | Current |
|----|-----------|---------|
| `create` | ✅ | ✅ |
| `slot` | ✅ (dedicated) | ✅ (via tag) |
| `text` | ✅ | ✅ |
| `insert` | ✅ | ✅ |
| `remove` | ✅ | ✅ |
| `listen` | ✅ | ❌ Missing |
| `set` | ✅ (class, src, value, gizmoRect, x/y/w/h, cornerRadius, variant, role, points) | 🟡 Partial (set_class, set_text, set_transform, set_visual) |

**Missing ops:**
- `listen` - add event listener to node
- Generic `set` with property routing (reference uses `set` + `name` field)

---

### 6. Extended Node Types (LOW)

**Reference types.zig:**
```zig
pub const RectPrimitive = struct {
    variant: RectPrimitiveVariant = .box,
    role: RectPrimitiveRole = .visual,
    rect: GizmoRect,
    corner_radius: f32 = 0,
    points: [3]RectPoint,
    point_count: u8 = 0,
};
```

**Current types.zig:**
- Has `Transform` and `VisualProps` ✅
- Has `PaintCache` with vertex buffers ✅
- Missing `RectPrimitive` and `gizmo_runtime_rect`

---

## What Needs to Change

### Option A: Embed QuickJS (Match Reference)

1. **Add QuickJS dependency** to `build.zig`
2. **Port `jsruntime_reference/solid/quickjs.zig`** to `solid/bridge/quickjs.zig`
3. **Rewrite `jsc.zig`** to call actual QuickJS functions
4. **Add JS files** from `jsruntime_reference/js/` to runtime
5. **Create `SolidHost` JS module** with `flushOps()`, `dispatchEvent()`, `updateState()`, `getSignalValue()`

**Pros:** Full control, single process, matches reference exactly  
**Cons:** Duplicate JS runtime (Bun + QuickJS), complex build

### Option B: Deep Bun Integration (Current Path)

1. **Implement proper FFI bridge** in TypeScript:
   - `SolidHost.flushOps()` returns pending ops array over FFI
   - Zig calls new FFI export that fetches ops
2. **Add listener sync** - include event listener names in `create` ops
3. **Add set op** - generic property setter with routing
4. **Signal sync via FFI** - export `getSignalValue`/`updateState` to Zig

**Pros:** Uses modern Bun, cleaner architecture  
**Cons:** FFI overhead, requires JS-side changes

### Option C: Hybrid - QuickJS for Logic, Bun for Tooling

1. Use Bun for **development/bundling only**
2. Embed QuickJS for **runtime execution**
3. Compile Solid app to QuickJS-compatible bundle
4. Load bundle into embedded runtime

**Pros:** Best of both worlds  
**Cons:** Complex tooling, potential compatibility issues

---

## Recommended Path: Option B (Deep Bun Integration)

Given the current architecture already uses Bun successfully, the most pragmatic path is:

1. **Keep Bun as external JS runtime**
2. **Enhance FFI protocol** to support:
   - Pull-based ops via new `flushOps()` export
   - Listener registration in `create` ops
   - Signal read/write via FFI
3. **Delete stubs** in `jsc.zig`, implement real FFI calls
4. **Add `listen` op** to JS renderer

This achieves the architecture goal **without embedding a second JS engine**.

---

## Immediate Actionable Changes

### 1. In `frontend/solid/solid-host.tsx`:
```ts
// Add to MutationOp type
listeners?: string[];

// In enqueueCreateOrMove:
if (node.listeners.size > 0) {
  createOp.listeners = Array.from(node.listeners.keys());
}
```

### 2. In `src/native_renderer.zig`:
```zig
// Add to SolidOp struct
listeners: ?[]const []const u8 = null,

// In applySolidOp "create" branch:
if (op.listeners) |names| {
    for (names) |name| {
        try store.addListener(op.id, name);
    }
}
```

### 3. In `src/solid/bridge/jsc.zig`:
```zig
// Implement dispatchEvent properly (already done!)
// Delete no-op functions, add error.NotImplemented
```

---

## Verification Criteria

The implementation is complete when:

1. ✅ Buttons receive click events from DVUI → dispatched to JS → signal update → mutation op → visible change
2. ✅ Text inputs sync bidirectionally (DVUI edit → JS state → render)
3. ⚠️ Signals can be read from Zig (`readSolidStateI32`)
4. ⚠️ Listeners are registered via `create` ops
5. ⚠️ Dirty tracking skips unchanged subtrees (already working)
6. ⚠️ Paint cache reuses geometry (already working)

Items with ⚠️ are gaps that need resolution.

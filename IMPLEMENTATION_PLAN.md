# Implementation Plan: Fix SolidJS Rendering

## Recommended Approach: Quick Fix First, Then Refactor

Given the current state, I recommend a **two-phase approach**:

1. **Phase 1 (Now):** Remove the dirty-tracking early-exit to fix the immediate bug
2. **Phase 2 (Later):** Migrate to command-buffer-only architecture

This gets the UI working immediately while allowing time for the larger refactor.

---

## Phase 1: Remove Dirty-Tracking Early-Exit

### File: `src/solid_renderer.zig`

#### Change 1: Remove Early-Exit in `renderElement()`

**Location:** Lines 90-108

**Current code to remove:**
```zig
if (!node.hasDirtySubtree() and node.total_interactive == 0) {
    node.markRendered();
    return;
}
const class_spec = node.prepareClassSpec();
if (canCacheNode(node, &class_spec)) {
    var cache = dvui.cache(
        @src(),
        .{ .invalidate = node.hasDirtySubtree() },
        .{ .id_extra = nodeCacheKey(node.id), .expand = .both },
    );
    defer cache.deinit();
    if (!cache.uncached()) {
        node.markRendered();
        return;
    }
    renderElementBody(runtime, store, node_id, node, allocator, class_spec);
    return;
}
renderElementBody(runtime, store, node_id, node, allocator, class_spec);
```

**Replace with:**
```zig
const class_spec = node.prepareClassSpec();
renderElementBody(runtime, store, node_id, node, allocator, class_spec);
```

#### Change 2: Remove `markRendered()` Calls (Optional Cleanup)

These calls are now no-ops but can be removed for clarity:

| Line | Context |
|------|---------|
| 70 | In `renderNode` for `.root` |
| 76 | In `renderNode` for `.slot` |
| 122 | In `renderElementBody` for `div` |
| 127 | In `renderElementBody` for `button` |
| 132 | In `renderElementBody` for `input` |
| 137 | In `renderElementBody` for `image` |
| 142 | In `renderElementBody` for `gizmo` |
| 147 | In `renderElementBody` for `p` |
| 152 | In `renderElementBody` for `h1` |
| 157 | In `renderElementBody` for `h2` |
| 162 | In `renderElementBody` for `h3` |
| 166 | In `renderElementBody` for generic |
| 329 | In `renderText` |

#### Change 3: Remove Unused Functions (Optional)

These functions are no longer needed:
- `canCacheNode()` (lines 169-175)
- `nodeCacheKey()` (lines 502-505)

---

## Verification Steps

After making the changes:

1. **Build the project:**
   ```bash
   zig build
   ```

2. **Run the application:**
   ```bash
   bun start
   ```
   (or whatever your start command is)

3. **Verify:**
   - [ ] UI persists beyond the first frame
   - [ ] No black screen after initial render
   - [ ] Text and layout render correctly
   - [ ] FPS counter is visible
   - [ ] Buttons respond to clicks
   - [ ] Input fields work

---

## Phase 2: Command-Buffer Migration (Future)

Once Phase 1 is verified working, consider the larger refactor:

### Step 1: Extend Command Opcodes

**File:** `src/native_renderer.zig`

Add new opcodes to the command system:
- `Opcode.Button = 3`
- `Opcode.Input = 4`
- `Opcode.FlexStart = 5`
- `Opcode.FlexEnd = 6`
- `Opcode.Image = 7`

### Step 2: Extend `renderCommandsDvui()`

Add handlers for each new opcode in the switch statement (around line 552).

### Step 3: Extend TypeScript CommandEncoder

**File:** `frontend/solid/command-encoder.ts` (or similar)

Add methods:
- `pushButton(id, parentId, frame, label)`
- `pushInput(id, parentId, frame, value, placeholder)`
- `pushFlexStart(id, parentId, direction, gap)`
- `pushFlexEnd(id)`
- `pushImage(id, parentId, frame, src)`

### Step 4: Update SolidJS Host Flush

**File:** `frontend/solid/solid-host.tsx`

Change `flush()` to emit commands for all node types:
```typescript
function emitNode(node: HostNode, parentId: number) {
  switch (node.tag) {
    case 'div':
      if (isFlex(node.className)) {
        encoder.pushFlexStart(node.id, parentId, ...);
        for (const child of node.children) emitNode(child, node.id);
        encoder.pushFlexEnd(node.id);
      } else {
        encoder.pushBox(node.id, parentId, ...);
        for (const child of node.children) emitNode(child, node.id);
      }
      break;
    case 'button':
      encoder.pushButton(node.id, parentId, ...);
      break;
    // ... etc
  }
}
```

### Step 5: Add Stateful Widget Registry

**File:** `src/native_renderer.zig` (new section)

```zig
const StatefulWidget = union(enum) {
    input: InputWidgetState,
};

var stateful_registry: std.AutoHashMap(u32, StatefulWidget) = undefined;

fn initStatefulRegistry(allocator: std.mem.Allocator) void {
    stateful_registry = std.AutoHashMap(u32, StatefulWidget).init(allocator);
}
```

### Step 6: Remove NodeStore Path

Once commands handle all widgets:
1. Remove `solid_store` from `Renderer` struct
2. Remove `solid_store_ready` flag
3. Remove `rebuildSolidStoreFromJson()` and `applySolidOps()`
4. Remove `solid_renderer.render()` call in `renderFrame()`
5. Delete `src/solid_renderer.zig`
6. Delete `src/jsruntime/solid/types.zig`

### Step 7: Remove TypeScript NodeStore Sync

1. Remove `setSolidTree()` FFI calls
2. Remove `applyRendererSolidOps()` FFI calls
3. Keep only `commit()` for command buffer

---

## Summary

| Phase | Action | Effort | Risk |
|-------|--------|--------|------|
| **1** | Remove dirty-tracking early-exit | ~10 lines | Low |
| **2** | Extend command opcodes | Medium | Low |
| **2** | Update TypeScript encoder | Medium | Low |
| **2** | Add stateful widget registry | Small | Medium |
| **2** | Remove NodeStore code | Large | Medium |

**Start with Phase 1** — it fixes the bug immediately with minimal changes.

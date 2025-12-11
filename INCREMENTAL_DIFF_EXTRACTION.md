# Extracting Incremental Diff from Reference to Shared-Memory Architecture

This document maps what can be extracted from `jsruntime_reference/` to implement incremental diffing in the shared-memory + polling architecture described in `BUN_FFI_ZIG.md`.

---

## Key Architectural Difference

| Aspect | Reference (QuickJS) | Target (Shared-Memory) |
|--------|---------------------|------------------------|
| **Who drives** | Zig calls `SolidHost.flushOps()` | JS calls `lib.frame(statePtr)` |
| **Op transport** | QuickJS JS objects → Zig parsing | Shared buffer (TypedArray) |
| **Event dispatch** | Zig calls `SolidHost.dispatchEvent()` | Zig writes to event ring buffer |
| **Data encoding** | JS object properties | Binary-packed structs |

---

## What Can Be Extracted Directly

### 1. **NodeStore & SolidNode** ✅ Already Ported
**Source:** `jsruntime_reference/solid/types.zig`  
**Current:** `src/solid/core/types.zig`

The entire retained scene graph is reusable:
- `NodeKind` enum (root, element, text, slot)
- `SolidNode` struct with version tracking
- `NodeStore` with `upsertElement`, `insert`, `remove`, `setClassName`, etc.
- Dirty propagation via `markNodeChanged` → parent chain update

**Status:** ✅ Already in place, no changes needed.

---

### 2. **Mutation Op Types (Schema)** ✅ Extractable
**Source:** `jsruntime_reference/solid/quickjs.zig` lines 412-449

The op types are transport-agnostic:
```
create   → { id, tag, parent?, before?, className? }
slot     → { id }  
text     → { id, text }
insert   → { id, parent, before? }
remove   → { id }
listen   → { id, type }           ← MISSING in current
set      → { id, name, value }    ← PARTIALLY MISSING
```

**Action:** Port `listen` and generic `set` op handlers to `native_renderer.zig`.

---

### 3. **Op Application Logic** ✅ Already Ported
**Source:** `jsruntime_reference/solid/quickjs.zig` lines 452-610  
**Current:** `native_renderer.zig` lines 325-387

The `applyOp` switch logic is identical conceptually:
```zig
// Reference
if (std.mem.eql(u8, name, "create")) try applyCreate(...);

// Current (already working)
if (std.mem.eql(u8, op.op, "create")) { ... }
```

**Status:** ✅ Working, just needs `listen` and `set` additions.

---

### 4. **Listener Registration** ⚠️ Missing
**Source:** `jsruntime_reference/solid/quickjs.zig` lines 496-505
```zig
fn applyListen(...) !void {
    const id = try readIntProperty(ctx, obj, "id");
    const event = try readStringProperty(ctx, allocator, obj, "type");
    try store.addListener(@intCast(id), event);
}
```

**Current:** No `listen` op handler.

**Action:** Add to `applySolidOp`:
```zig
if (std.mem.eql(u8, op.op, "listen")) {
    if (op.id == 0) return error.MissingId;
    const event_type = op.eventType orelse return error.MissingTag;
    try store.addListener(op.id, event_type);
    return;
}
```

---

### 5. **Generic `set` Op Routing** ⚠️ Partially Missing
**Source:** `jsruntime_reference/solid/quickjs.zig` lines 507-610

Reference routes `set` by property name:
```zig
if (std.mem.eql(u8, name, "class")) { store.setClassName(id, value); }
if (std.mem.eql(u8, name, "src")) { store.setImageSource(id, value); }
if (std.mem.eql(u8, name, "value")) { store.setInputValue(id, value); }
if (std.mem.eql(u8, name, "gizmoRect")) { store.setGizmoRect(id, rect); }
// ... x, y, w, h, cornerRadius, variant, role, points
```

**Current:** Has `set_class`, `set_text`, `set_transform`, `set_visual` - but not unified routing.

**Action:** Consider adding unified `set` op or keep current split approach.

---

## What Needs Adaptation for Shared-Memory

### 6. **Binary Op Buffer (NEW)**
**Reference:** Uses QuickJS JS objects  
**Target:** Shared TypedArray buffer

Instead of JSON parsing, define a binary op format:
```zig
const BinaryOp = packed struct {
    opcode: u8,      // 0=create, 1=remove, 2=insert, 3=set_text, ...
    flags: u8,       // reserved
    id: u32,         // node id
    parent_id: u32,  // for create/insert
    before_id: u32,  // for insert ordering
    payload_offset: u32,  // offset into string table
    payload_len: u16,     // bytes
};
```

**JS Side:**
```ts
const opBuffer = new DataView(lib.symbols.get_op_buffer());
let offset = 0;

function writeCreateOp(id: number, tag: string, parentId: number) {
    opBuffer.setUint8(offset, 0);      // opcode = create
    opBuffer.setUint32(offset + 2, id, true);
    opBuffer.setUint32(offset + 6, parentId, true);
    // ... write tag to string table
    offset += OP_SIZE;
}
```

**Zig Side:**
```zig
pub fn consumeOpBuffer(store: *NodeStore, buffer: []const u8) void {
    var cursor: usize = 0;
    while (cursor + @sizeOf(BinaryOp) <= buffer.len) {
        const op = std.mem.bytesToValue(BinaryOp, buffer[cursor..]);
        applyBinaryOp(store, op);
        cursor += @sizeOf(BinaryOp);
    }
}
```

---

### 7. **Event Ring Buffer (NEW)**
**Reference:** Zig calls `SolidHost.dispatchEvent(id, type, detail)`  
**Target:** Zig writes events to shared buffer, JS polls

```zig
const EventEntry = packed struct {
    event_type: u8,   // 0=click, 1=input, 2=focus, ...
    node_id: u32,
    detail_offset: u32,
    detail_len: u16,
};

pub fn enqueueEvent(ring: *EventRing, entry: EventEntry) void {
    const idx = ring.write_head % ring.capacity;
    ring.buffer[idx] = entry;
    ring.write_head += 1;
}
```

**JS Side:**
```ts
function pollEvents() {
    const readHead = eventRing.getUint32(0, true);
    const writeHead = eventRing.getUint32(4, true);
    
    while (readHead < writeHead) {
        const entry = readEventAt(readHead % CAPACITY);
        dispatchToSolid(entry.nodeId, entry.eventType);
        readHead++;
    }
    eventRing.setUint32(0, readHead, true);
}
```

---

### 8. **Dirty Region Output (NEW)**
**Reference:** DVUI redraws full frame  
**Target:** Zig outputs dirty rects to shared buffer, JS uploads only those

```zig
const DirtyRect = packed struct {
    x: u16,
    y: u16,
    w: u16,
    h: u16,
};

pub fn writeDirtyRegions(tracker: *DirtyRegionTracker, output: []DirtyRect) usize {
    var count: usize = 0;
    for (tracker.regions.items) |region| {
        if (count >= output.len) break;
        output[count] = .{
            .x = @intFromFloat(region.x),
            .y = @intFromFloat(region.y),
            .w = @intFromFloat(region.w),
            .h = @intFromFloat(region.h),
        };
        count += 1;
    }
    return count;
}
```

---

## Summary: Extraction Plan

| Component | Reference Source | Status | Adaptation Needed |
|-----------|------------------|--------|-------------------|
| NodeStore | `types.zig` | ✅ Ported | None |
| SolidNode | `types.zig` | ✅ Ported | None |
| Version/dirty tracking | `types.zig` | ✅ Ported | None |
| Op types schema | `quickjs.zig` | ✅ Ported | Add `listen`, `set` |
| `applyCreate` | `quickjs.zig` | ✅ Ported | None |
| `applyRemove` | `quickjs.zig` | ✅ Ported | None |
| `applyInsert` | `quickjs.zig` | ✅ Ported | None |
| `applyListen` | `quickjs.zig` | ❌ Missing | Add handler |
| `applySet` (routing) | `quickjs.zig` | 🟡 Partial | Add `src`, `value` |
| Op transport | QuickJS objects | ❌ N/A | Binary buffer |
| Event dispatch | QuickJS call | ❌ N/A | Ring buffer |
| Dirty output | N/A | NEW | Implement |

---

## Immediate Extraction Steps

### Step 1: Add `listen` op (5 min)
```zig
// In SolidOp struct
eventType: ?[]const u8 = null,

// In applySolidOp
if (std.mem.eql(u8, op.op, "listen")) {
    if (op.id == 0) return error.MissingId;
    const t = op.eventType orelse return error.MissingTag;
    try store.addListener(op.id, t);
    return;
}
```

### Step 2: Add `set` routing for `src` and `value` (10 min)
```zig
if (std.mem.eql(u8, op.op, "set")) {
    const name = op.propName orelse return error.MissingTag;
    const value = op.propValue orelse return error.MissingTag;
    if (std.mem.eql(u8, name, "src")) {
        try store.setImageSource(op.id, value);
    } else if (std.mem.eql(u8, name, "value")) {
        try store.setInputValue(op.id, value);
    }
    return;
}
```

### Step 3: Define binary op struct (future)
This enables the shared-memory architecture without JSON parsing overhead.

### Step 4: Define event ring buffer (future)
Eliminates the need for Zig→JS callbacks entirely.

---

## Conclusion

**80% of the reference logic is already ported** - the NodeStore, dirty tracking, and op application are in place. 

The remaining 20% consists of:
1. **Missing ops:** `listen`, fuller `set` routing (easy, ~30 min)
2. **Transport layer:** Replace JSON with binary buffers (medium, ~2-4 hrs)
3. **Event output:** Ring buffer instead of callbacks (medium, ~2-4 hrs)

The shared-memory architecture adds complexity but enables the "single FFI call per frame" goal from `BUN_FFI_ZIG.md`.

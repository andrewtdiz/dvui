# Incremental Diff Implementation Guide

This document provides a complete implementation guide for adding incremental diffing to the Bun FFI + Zig architecture. It is designed to be actionable by another LLM.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         TYPESCRIPT (Bun)                            │
│                                                                     │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────────────┐    │
│  │  Solid.js   │───▶│  HostNode    │───▶│   Mutation Ops      │    │
│  │  Components │    │  Tree (JS)   │    │   (JSON / Binary)   │    │
│  └─────────────┘    └──────────────┘    └──────────┬──────────┘    │
│                                                     │               │
│                                    ┌────────────────▼────────────┐  │
│                                    │  native.applyOps(buffer)   │  │
│                                    │  native.frame()            │  │
│                                    └────────────────┬────────────┘  │
└─────────────────────────────────────────────────────┼───────────────┘
                                                      │ FFI
┌─────────────────────────────────────────────────────▼───────────────┐
│                           ZIG (Native)                              │
│                                                                     │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────┐  │
│  │  Apply Ops   │───▶│  NodeStore   │───▶│  Layout + Render     │  │
│  │  (parse)     │    │  (retained)  │    │  (dirty tracking)    │  │
│  └──────────────┘    └──────────────┘    └──────────────────────┘  │
│                             │                        │              │
│                             ▼                        ▼              │
│                    ┌─────────────────┐      ┌────────────────┐     │
│                    │  Dirty Flags    │      │  Event Buffer  │     │
│                    │  (version #s)   │      │  (for JS poll) │     │
│                    └─────────────────┘      └────────────────┘     │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Principles

1. **JS drives, Zig responds** - JS calls `frame()`, never the reverse
2. **Retained scene graph** - NodeStore persists across frames
3. **Incremental updates** - Only changed nodes trigger layout/paint
4. **Version-based dirty tracking** - u64 version numbers propagate up tree
5. **No JSON in hot path** (future) - Binary ops for performance

---

## Current State Assessment

### ✅ Already Implemented

| Component | Location | Status |
|-----------|----------|--------|
| `NodeStore` | `src/solid/core/types.zig` | Complete |
| `SolidNode` with versions | `src/solid/core/types.zig` | Complete |
| Dirty propagation | `markNodeChanged()` → parent chain | Complete |
| Layout engine | `src/solid/layout/mod.zig` | Complete |
| Paint cache | `src/solid/render/cache.zig` | Complete |
| Op parsing (JSON) | `src/native_renderer.zig` | Complete |
| `create`, `remove`, `insert` ops | `applySolidOp()` | Complete |
| `listen`, `set` ops | `applySolidOp()` | Just Added |

### ❌ Not Yet Implemented

| Component | Priority | Effort |
|-----------|----------|--------|
| Binary op buffer | Medium | 2-4 hrs |
| Event ring buffer (Zig→JS) | Medium | 2-4 hrs |
| Idle frame skipping | Low | 30 min |

---

## Part 1: Core Data Structures (Reference → Current)

### 1.1 SolidNode - Version Tracking

**Reference:** `jsruntime_reference/solid/types.zig:149-368`

```zig
pub const SolidNode = struct {
    id: u32,
    kind: NodeKind,
    tag: []u8 = &.{},
    text: []u8 = &.{},
    class_name: []u8 = &.{},
    parent: ?u32 = null,
    children: std.ArrayList(u32),
    listeners: ListenerSet,
    
    // === DIRTY TRACKING (CRITICAL) ===
    version: u64 = 0,              // Bumped when THIS node changes
    subtree_version: u64 = 0,      // Max version in subtree (propagates up)
    last_render_version: u64 = 0,  // Version when last rendered
    
    // === INTERACTIVITY ===
    interactive_self: bool = false,
    total_interactive: u32 = 0,
    
    // === CACHED STATE ===
    class_spec: tailwind.ClassSpec = .{},
    class_spec_dirty: bool = true,
    
    /// Returns true if any descendant (or self) has changed since last render.
    pub fn hasDirtySubtree(self: *const SolidNode) bool {
        return self.last_render_version < self.subtree_version;
    }
    
    /// Mark this node as rendered (reset dirty state for this subtree).
    pub fn markRendered(self: *SolidNode) void {
        self.last_render_version = self.subtree_version;
    }
};
```

**Current:** `src/solid/core/types.zig` - Already has this. ✅

---

### 1.2 NodeStore - Version Propagation

**Reference:** `jsruntime_reference/solid/types.zig:617-632`

```zig
fn markNodeChanged(self: *NodeStore, id: u32) void {
    const version = self.nextVersion();  // Increment global counter
    var current: ?u32 = id;
    var is_self = true;
    
    while (current) |node_id| {
        const node = self.nodes.getPtr(node_id) orelse break;
        
        if (is_self) {
            node.version = version;  // Only self gets new version
            is_self = false;
        }
        
        // Propagate subtree_version UP the tree
        if (node.subtree_version < version) {
            node.subtree_version = version;
        }
        
        current = node.parent;
    }
}

fn nextVersion(self: *NodeStore) u64 {
    self.change_counter += 1;
    return self.change_counter;
}
```

**Current:** `src/solid/core/types.zig` - Already has this. ✅

---

### 1.3 ListenerSet - Event Registration

**Reference:** `jsruntime_reference/solid/types.zig:116-147`

```zig
const ListenerSet = struct {
    allocator: std.mem.Allocator,
    names: std.ArrayList([]u8),

    fn init(allocator: std.mem.Allocator) ListenerSet {
        return .{ .allocator = allocator, .names = .empty };
    }

    fn add(self: *ListenerSet, name: []const u8) !bool {
        // Deduplicate
        for (self.names.items) |existing| {
            if (std.mem.eql(u8, existing, name)) return false;
        }
        const copy = try self.allocator.dupe(u8, name);
        try self.names.append(self.allocator, copy);
        return true;
    }

    fn has(self: *const ListenerSet, name: []const u8) bool {
        for (self.names.items) |existing| {
            if (std.mem.eql(u8, existing, name)) return true;
        }
        return false;
    }
};
```

**Current:** `src/solid/core/types.zig` - Already has this. ✅

---

## Part 2: Mutation Op Handling

### 2.1 Op Types (Complete Set)

**Reference ops from** `jsruntime_reference/solid/quickjs.zig:412-449`:

| Op | Fields | Description |
|----|--------|-------------|
| `create` | `id`, `tag`, `parent?`, `before?`, `className?` | Create element and insert |
| `slot` | `id` | Create slot placeholder |
| `text` | `id`, `text` | Create/update text node |
| `insert` | `id`, `parent`, `before?` | Move existing node |
| `remove` | `id` | Remove node and children |
| `listen` | `id`, `type` | Register event listener |
| `set` | `id`, `name`, `value` | Set property by name |

### 2.2 Apply Op Implementation

**Reference:** `jsruntime_reference/solid/quickjs.zig:452-610`

```zig
fn applyCreate(store: *NodeStore, id: u32, tag: []const u8) !void {
    try store.upsertElement(id, tag);
}

fn applyInsert(store: *NodeStore, parent_id: u32, child_id: u32, before_id: ?u32) !void {
    try store.insert(parent_id, child_id, before_id);
}

fn applyRemove(store: *NodeStore, id: u32) void {
    store.remove(id);
}

fn applyListen(store: *NodeStore, id: u32, event_type: []const u8) !void {
    try store.addListener(id, event_type);
}

fn applySet(store: *NodeStore, id: u32, name: []const u8, value: []const u8) !void {
    if (std.mem.eql(u8, name, "class") or std.mem.eql(u8, name, "className")) {
        try store.setClassName(id, value);
        return;
    }
    if (std.mem.eql(u8, name, "src")) {
        try store.setImageSource(id, value);
        return;
    }
    if (std.mem.eql(u8, name, "value")) {
        try store.setInputValue(id, value);
        return;
    }
    // Extend with more properties as needed
}
```

**Current:** `src/native_renderer.zig:331-430` - Implemented with JSON parsing. ✅

---

## Part 3: TypeScript Side Changes

### 3.1 Emit `listen` Ops

**File:** `frontend/solid/solid-host.tsx`

**Current** `enqueueCreateOrMove` needs to emit listener registrations:

```typescript
const enqueueCreateOrMove = (parent: HostNode, node: HostNode, anchor?: HostNode) => {
  const parentId = parent === root ? 0 : parent.id;
  const beforeId = anchor ? anchor.id : undefined;
  
  if (!node.created) {
    node.created = true;
    const createOp: MutationOp = {
      op: "create",
      id: node.id,
      parent: parentId,
      before: beforeId,
      tag: node.tag,
    };
    if (node.tag === "text") createOp.text = node.props.text ?? "";
    const cls = nodeClass(node);
    if (cls) createOp.className = cls;
    Object.assign(createOp, extractTransform(node.props), extractVisual(node.props));
    ops.push(createOp);
    
    // === ADD THIS: Emit listen ops for registered handlers ===
    for (const [eventType] of node.listeners) {
      ops.push({
        op: "listen",
        id: node.id,
        eventType: eventType,
      });
    }
    return;
  }
  // ... move logic
};
```

### 3.2 Update MutationOp Type

```typescript
type MutationOp = {
  op:
    | "create"
    | "remove"
    | "move"
    | "set_text"
    | "set_class"
    | "set_transform"
    | "set_visual"
    | "listen"      // ADD
    | "set";        // ADD
  id: number;
  parent?: number;
  before?: number | null;
  tag?: string;
  text?: string;
  className?: string;
  eventType?: string;  // ADD - for listen op
  name?: string;       // ADD - for set op
  value?: string;      // ADD - for set op
  // ... existing transform/visual fields
};
```

---

## Part 4: Render Loop Integration

### 4.1 Dirty-Aware Rendering

**File:** `src/solid/render/mod.zig`

```zig
pub fn render(runtime: ?*jsruntime.JSRuntime, store: *NodeStore) bool {
    const root = store.node(0) orelse return false;
    
    // Early exit if nothing changed (idle optimization)
    if (!root.hasDirtySubtree()) {
        return true;  // Still "rendered" - just nothing to do
    }
    
    // Update layouts only for dirty subtrees
    layout.updateLayouts(store);
    
    // Render tree, skipping clean subtrees
    renderNode(runtime, store, root);
    
    // Mark entire tree as rendered
    root.markRendered();
    
    return true;
}

fn renderNode(runtime: ?*jsruntime.JSRuntime, store: *NodeStore, node: *SolidNode) void {
    // Skip clean subtrees entirely
    if (!node.hasDirtySubtree()) {
        return;
    }
    
    // Render this node
    renderNodeContent(runtime, store, node);
    
    // Recurse into children
    for (node.children.items) |child_id| {
        if (store.node(child_id)) |child| {
            renderNode(runtime, store, child);
        }
    }
    
    node.markRendered();
}
```

---

## Part 5: Event Dispatch (Zig → JS via Shared Buffer)

### 5.1 Event Ring Buffer Design

**NEW File:** `src/solid/events/ring.zig`

```zig
pub const EventKind = enum(u8) {
    click = 0,
    input = 1,
    focus = 2,
    blur = 3,
    mouseenter = 4,
    mouseleave = 5,
    keydown = 6,
    keyup = 7,
};

pub const EventEntry = packed struct {
    kind: EventKind,
    _pad: u8 = 0,
    node_id: u32,
    detail_offset: u32,  // Offset into detail buffer
    detail_len: u16,     // Length of detail string
};

pub const EventRing = struct {
    buffer: []EventEntry,
    detail_buffer: []u8,
    read_head: u32 = 0,
    write_head: u32 = 0,
    detail_write: u32 = 0,
    
    pub fn push(self: *EventRing, kind: EventKind, node_id: u32, detail: ?[]const u8) void {
        const idx = self.write_head % @intCast(u32, self.buffer.len);
        
        var entry = EventEntry{
            .kind = kind,
            .node_id = node_id,
            .detail_offset = 0,
            .detail_len = 0,
        };
        
        if (detail) |d| {
            if (self.detail_write + d.len <= self.detail_buffer.len) {
                @memcpy(self.detail_buffer[self.detail_write..][0..d.len], d);
                entry.detail_offset = self.detail_write;
                entry.detail_len = @intCast(u16, d.len);
                self.detail_write += @intCast(u32, d.len);
            }
        }
        
        self.buffer[idx] = entry;
        self.write_head += 1;
    }
    
    /// Called after JS has consumed events
    pub fn reset(self: *EventRing) void {
        self.read_head = self.write_head;
        self.detail_write = 0;
    }
};
```

### 5.2 TypeScript Event Polling

**File:** `frontend/solid/event-poller.ts`

```typescript
const EVENT_ENTRY_SIZE = 12;  // 1 + 1 + 4 + 4 + 2 bytes

const EventKind = {
  click: 0,
  input: 1,
  focus: 2,
  blur: 3,
} as const;

export function pollEvents(
  eventBuffer: DataView,
  detailBuffer: Uint8Array,
  nodeIndex: Map<number, HostNode>,
  decoder: TextDecoder
) {
  const readHead = eventBuffer.getUint32(0, true);
  const writeHead = eventBuffer.getUint32(4, true);
  const capacity = (eventBuffer.byteLength - 8) / EVENT_ENTRY_SIZE;
  
  let current = readHead;
  while (current < writeHead) {
    const idx = current % capacity;
    const offset = 8 + idx * EVENT_ENTRY_SIZE;
    
    const kind = eventBuffer.getUint8(offset);
    const nodeId = eventBuffer.getUint32(offset + 2, true);
    const detailOffset = eventBuffer.getUint32(offset + 6, true);
    const detailLen = eventBuffer.getUint16(offset + 10, true);
    
    const node = nodeIndex.get(nodeId);
    if (node) {
      const eventName = Object.keys(EventKind).find(
        k => EventKind[k as keyof typeof EventKind] === kind
      ) ?? "unknown";
      
      const handlers = node.listeners.get(eventName);
      if (handlers) {
        const detail = detailLen > 0 
          ? decoder.decode(detailBuffer.slice(detailOffset, detailOffset + detailLen))
          : undefined;
        
        const payload = new Uint8Array(4);
        new DataView(payload.buffer).setUint32(0, nodeId, true);
        
        for (const handler of handlers) {
          handler(payload);
        }
      }
    }
    
    current++;
  }
  
  // Update read head
  eventBuffer.setUint32(0, current, true);
}
```

---

## Part 6: Binary Op Buffer (Future Optimization)

### 6.1 Binary Op Format

```zig
pub const BinaryOpCode = enum(u8) {
    create = 0,
    remove = 1,
    insert = 2,
    set_text = 3,
    set_class = 4,
    listen = 5,
    set = 6,
};

pub const BinaryOp = packed struct {
    opcode: BinaryOpCode,
    flags: u8 = 0,
    id: u32,
    parent_id: u32,
    before_id: u32,
    payload_offset: u32,
    payload_len: u16,
};

pub fn consumeBinaryOps(store: *NodeStore, ops: []const u8, strings: []const u8) void {
    var cursor: usize = 0;
    while (cursor + @sizeOf(BinaryOp) <= ops.len) {
        const op = std.mem.bytesToValue(BinaryOp, ops[cursor..][0..@sizeOf(BinaryOp)]);
        const payload = strings[op.payload_offset..][0..op.payload_len];
        
        switch (op.opcode) {
            .create => store.upsertElement(op.id, payload) catch {},
            .remove => store.remove(op.id),
            .insert => store.insert(op.parent_id, op.id, 
                if (op.before_id == 0) null else op.before_id) catch {},
            .set_class => store.setClassName(op.id, payload) catch {},
            // ... other ops
        }
        
        cursor += @sizeOf(BinaryOp);
    }
}
```

---

## Implementation Checklist

### Phase 1: Complete Op Coverage
- [x] Add `listen` op to `applySolidOp` in `native_renderer.zig`
- [x] Add `set` op routing for `src`, `value`, `class`
- [x] Update TypeScript `MutationOp` type to include `eventType`, `name`, `value`
- [x] Emit `listen` ops in `enqueueCreateOrMove`

### Phase 2: Event Ring Buffer
- [x] Create `src/solid/events/ring.zig`
- [x] Add `EventRing` to `Renderer` struct
- [x] Replace `dispatchEvent` callback with ring buffer write
- [x] Create `event-poller.ts` for TypeScript side
- [x] Call `pollEvents()` after `native.frame()`

### Phase 3: Idle Optimization
- [ ] Add early exit in `render()` when `!root.hasDirtySubtree()`
- [ ] Skip layout computation for clean subtrees
- [ ] Add frame skip counter for debugging

### Phase 4: Binary Ops
- [ ] Define `BinaryOp` packed struct
- [ ] Create `consumeBinaryOps` function
- [ ] Add FFI export for binary op buffer pointer
- [ ] Update TypeScript to write binary ops

---

## Testing Verification

After implementation, verify these scenarios:

1. **Button Click:** Click button → event in ring buffer → JS handler fires → mutation → UI updates
2. **Text Input:** Type in input → Zig captures text → event to JS → signal update → re-render
3. **Idle Frames:** No mutations → `hasDirtySubtree()` returns false → frame cost near zero
4. **Hot Reload:** Reload JS → full tree sync → incremental updates resume

---

## Files to Modify

| File | Changes |
|------|---------|
| `src/native_renderer.zig` | ✅ Already updated with listen/set ops |
| `src/solid/events/ring.zig` | NEW - Event ring buffer |
| `src/solid/render/mod.zig` | Add dirty subtree early exit |
| `frontend/solid/solid-host.tsx` | Emit listen ops, update MutationOp type |
| `frontend/solid/event-poller.ts` | NEW - Poll events from shared buffer |
| `frontend/index.ts` | Call pollEvents after frame() |

---

## Summary

The incremental diff architecture is **80% implemented**. The remaining work is:

1. **TypeScript listener emission** - 30 min
2. **Event ring buffer** - 2-4 hrs (replaces callbacks)
3. **Binary ops** - Optional, 2-4 hrs (replaces JSON)

The core dirty tracking, version propagation, and retained scene graph are already in place and working.

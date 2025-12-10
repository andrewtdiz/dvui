# Solid → DVUI Architecture Overview

## High-Level Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              BUN RUNTIME (JS)                               │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐    ┌─────────────────────┐                         │
│  │   SolidJS Runtime   │───▶│  Solid Host         │                         │
│  │  (Reactive System)  │    │  (solid-host.tsx)   │                         │
│  └─────────────────────┘    └──────────┬──────────┘                         │
│                                        │                                    │
│                             ┌──────────▼──────────┐                         │
│                             │    HostNode Tree    │ ◀── JS-side DOM mirror  │
│                             │  (in-memory nodes)  │                         │
│                             └──────────┬──────────┘                         │
│                                        │                                    │
│                 ┌──────────────────────┼──────────────────────┐             │
│                 │                      │                      │             │
│        ┌────────▼────────┐   ┌────────▼────────┐   ┌────────▼────────┐     │
│        │   Snapshots     │   │   Mutations     │   │  Draw Commands  │     │
│        │  (Full Tree)    │   │   (Ops Batch)   │   │   (Fallback)    │     │
│        └────────┬────────┘   └────────┬────────┘   └────────┬────────┘     │
└─────────────────┼─────────────────────┼─────────────────────┼───────────────┘
                  │                     │                     │
┌─────────────────┼─────────────────────┼─────────────────────┼───────────────┐
│                 │        FFI BRIDGE (Bun:ffi)               │               │
│        ┌────────▼────────┐   ┌────────▼────────┐   ┌────────▼────────┐     │
│        │setSolidTree()   │   │applyOps()       │   │commitCommands() │     │
│        │  JSON payload   │   │  JSON payload   │   │ Binary headers  │     │
│        └────────┬────────┘   └────────┬────────┘   └────────┬────────┘     │
└─────────────────┼─────────────────────┼─────────────────────┼───────────────┘
                  │                     │                     │
┌─────────────────▼─────────────────────▼─────────────────────▼───────────────┐
│                           ZIG NATIVE RUNTIME                                │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    native_renderer.zig                              │   │
│  │  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐  │   │
│  │  │ rebuildSolid-   │    │ applySolidOps() │    │updateCommands() │  │   │
│  │  │ StoreFromJson() │    │                 │    │                 │  │   │
│  │  └────────┬────────┘    └────────┬────────┘    └────────┬────────┘  │   │
│  └───────────┼──────────────────────┼──────────────────────┼───────────┘   │
│              │                      │                      │               │
│              └──────────┬───────────┘                      │               │
│                         ▼                                  │               │
│              ┌─────────────────────┐                       │               │
│              │     NodeStore       │◀──Retained Zig tree   │               │
│              │   (types.zig)       │                       │               │
│              └──────────┬──────────┘                       │               │
│                         │                                  │               │
│                         ▼                                  ▼               │
│              ┌─────────────────────┐        ┌─────────────────────┐       │
│              │  solid_renderer.zig │        │ renderCommandsDvui()│       │
│              │  (Tag → Widget Map) │        │  (Binary fallback)  │       │
│              └──────────┬──────────┘        └──────────┬──────────┘       │
│                         │                              │                  │
│                         └──────────────┬───────────────┘                  │
│                                        ▼                                  │
│                         ┌─────────────────────────────┐                   │
│                         │        DVUI Widgets         │                   │
│                         │  (Immediate-Mode Rendering) │                   │
│                         └──────────────┬──────────────┘                   │
│                                        ▼                                  │
│                         ┌─────────────────────────────┐                   │
│                         │     Raylib Backend          │                   │
│                         │    (GPU / Window)           │                   │
│                         └─────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Components

### JavaScript Layer (Bun Runtim

| Component | File | Purpose |
|-----------|------|---------|
| **Solid Host** | `solid-host.tsx` | Creates Solid renderer, manages `HostNode` tree, schedules flushes |
| **HostNode** | `solid-host.tsx` | JS-side node class (id, tag, props, children, listeners) |
| **Native Renderer** | `native-renderer.ts` | FFI wrapper class, command encoder, native library bindings |
| **FFI Bindings** | `native.ts` | `dlopen` symbols, callback wrappers |
| **Frame Loop** | `index.ts` | Game loop: `flush()` → `present()` at target FPS |

### Native Layer (Zig)

| Component | File | Purpose |
|-----------|------|---------|
| **Renderer State** | `native_renderer.zig` | Holds window, backend, NodeStore, command buffers |
| **NodeStore** | `types.zig` | Retained tree of `SolidNode` (HashMap by id) |
| **SolidNode** | `types.zig` | Node struct: kind, tag, text, className, children, listeners |
| **Solid Renderer** | `solid_renderer.zig` | Walks NodeStore, maps tags to DVUI widgets |
| **Tailwind Adapter** | `dvui_tailwind.zig` | Parses Tailwind classes → `dvui.Options` |

## Memory Management

### JS Side
- **HostNode Tree**: Allocated per-session in JS heap; garbage collected when nodes are removed.
- **nodeIndex Map**: `Map<number, HostNode>` for O(1) lookup; entries removed recursively on `removeNode`.
- **Encoders**: Reused `CommandEncoder` with fixed-size `ArrayBuffer` headers (40 bytes × 256 max) and 16KB payload buffer. Reset each flush.

### Zig Side
- **GeneralPurposeAllocator**: Main allocator for long-lived data (NodeStore nodes, strings).
- **Frame Arena**: Per-frame scratch allocator, reset every `presentRenderer()` call—zero per-frame heap fragmentation.
- **NodeStore**: `std.AutoHashMap(u32, SolidNode)`. Nodes own their string slices (tag, text, className) via allocator dupes.
- **Deferred Destroy**: Callbacks tracked via `callback_depth`; renderer destruction deferred until depth returns to zero.

## Runtime Performance

### Synchronization Model
1. **Snapshot Once + Mutations**: Default mode. Full JSON snapshot on first flush, incremental mutation ops thereafter.
2. **Periodic Resync**: Every 300 frames, a full snapshot is sent to correct drift.
3. **Sequence Numbers**: Ops batches include `seq` to detect/reject stale or out-of-order messages.

### Data Transfer
| Channel | Format | Size | Frequency |
|---------|--------|------|-----------|
| `setSolidTree` | JSON `{ nodes: [...] }` | Variable (~KB) | First frame + every 300 frames |
| `applyOps` | JSON `{ seq, ops: [...] }` | Small (~bytes) | Every flush with changes |
| `commitCommands` | Binary headers + payload | Fixed 40B/cmd | Every flush (fallback path) |

### Rendering Path
```
presentRenderer() called by JS frame loop
    │
    ├─ if NodeStore ready → solid_renderer.render()
    │       │
    │       └─ Walk tree, call dvui.flexbox / dvui.box / dvui.button / dvui.label per tag
    │
    └─ else → renderCommandsDvui() (binary quad/text commands)
```

- **Immediate Mode**: DVUI widgets are recreated every frame. No widget caching—simplifies state but requires full traversal.
- **Dirty Tracking (disabled)**: Version-based dirty flags exist in `SolidNode` but are bypassed to avoid black-screen bugs.

## DOM Tree Synchronization

### JS → Zig Flow
```
SolidJS reactive update
    ↓
Solid Host renderer callbacks (insertNode, removeNode, setProperty, replaceText)
    ↓
HostNode tree mutation + enqueue MutationOp
    ↓
queueMicrotask(flush)
    ↓
flush(): serialize tree → setSolidTree() OR batch ops → applyOps()
    ↓
FFI call to Zig
    ↓
Zig parses JSON, updates NodeStore
```

### Mutation Operations
| Op | Fields | Action in Zig |
|----|--------|---------------|
| `create` | id, parent, before?, tag, text?, className? | `upsertElement` or `setTextNode`, then `insert` |
| `remove` | id | `removeRecursive` |
| `move` | id, parent, before? | Detach from old parent, `insert` under new |
| `set_text` | id, text | `setTextNode` |
| `set_class` | id, className | `setClassName` |

### Event Flow (Zig → JS)
```
DVUI widget interaction (button press, text input change)
    ↓
solid_renderer detects interaction, calls jsc_bridge.dispatchEvent()
    ↓
Native event callback → FFI → JS eventCallback
    ↓
HostNode.listeners.get(eventName) → invoke handlers
    ↓
SolidJS reactive update propagates
```

## Key Design Decisions

1. **Dual-Path Rendering**: NodeStore path for structured UI; binary command path for raw draw calls. Enables fallback and debugging.
2. **JSON for Tree Sync**: Simple, debuggable, adequate bandwidth for typical UI sizes. Binary could optimize but adds complexity.
3. **Immediate-Mode Widgets**: Matches DVUI's architecture. No retained widget layer—state lives in NodeStore.
4. **Tailwind Subset**: CSS-like styling via class strings parsed to `dvui.Options`. Limited but familiar.
5. **Single-Threaded**: All rendering on main thread. JS schedules frames; Zig blocks during `presentRenderer`.

## Performance Characteristics

| Metric | Value | Notes |
|--------|-------|-------|
| Frame budget | ~16ms @ 60fps | JS flush + FFI + Zig render + GPU swap |
| Tree sync latency | <1ms | JSON parse + HashMap updates |
| Max nodes | Practical ~1000s | HashMap + arena allocator scale well |
| Memory per node | ~200-400 bytes | SolidNode + owned strings |
| FFI overhead | ~μs per call | Minimal; bulk transfers preferred |

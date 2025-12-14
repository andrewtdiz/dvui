# Solid Logic & DOM Incremental Rendering Architecture

## Current Structure

The Solid integration lives under `src/integrations/` with two main modules:

```
src/integrations/
├── solid/                    # Solid DOM tree + rendering
│   ├── mod.zig               # Public API: render, updateLayouts, NodeStore
│   ├── core/
│   │   └── types.zig         # SolidNode, NodeStore, Rect, VisualProps, Transform
│   ├── layout/
│   │   ├── mod.zig           # updateLayouts entry point
│   │   ├── flex.zig          # Flex child positioning
│   │   └── measure.zig       # Intrinsic size measurement
│   ├── style/
│   │   ├── tailwind.zig      # Class parsing
│   │   ├── colors.zig        # Palette
│   │   └── apply.zig         # Map specs → dvui.Options / VisualProps
│   ├── render/
│   │   ├── mod.zig           # Render dispatch + dirty-region orchestration
│   │   ├── direct.zig        # Direct triangle/text draws (non-interactive)
│   │   ├── widgets.zig       # DVUI widget entry point (interactive only)
│   │   ├── cache.zig         # Paint cache + DirtyRegionTracker
│   │   └── image_loader.zig  # Image file loading and caching
│   └── events/
│       └── mod.zig           # EventRing buffer for Zig→JS event dispatch
│
└── native_renderer/          # FFI layer for JS↔Zig
    ├── mod.zig               # Re-exports + comptime force-export block
    ├── types.zig             # Renderer, CommandHeader, EventFn, LogFn
    ├── exports.zig           # All FFI export functions
    ├── lifecycle.zig         # Renderer creation, destruction, logging
    ├── window.zig            # Window lifecycle and frame rendering
    ├── commands.zig          # Command buffer handling
    ├── events.zig            # Event ring buffer helpers
    └── solid_sync.zig        # Solid tree sync (snapshot & ops)
```

Additional core types live in:
```
src/core/
├── mod.zig           # Re-exports all core types
├── point.zig         # Point type
├── size.zig          # Size type
├── rect.zig          # Rect + RectScale types
├── color.zig         # Color + HSLuv
├── vertex.zig        # Vertex for triangles
├── options.zig       # Options for widget styling
├── enums.zig         # Shared enumerations
├── data.zig          # Persistent data storage
└── ffi.zig           # FFI utilities
```

## Build System Module Wiring

The `build.zig` creates and wires four key modules:

```zig
// From build.zig (lines 69-106)
const native_module = b.createModule(.{
    .root_source_file = b.path("src/integrations/native_renderer/mod.zig"),
    ...
});
native_module.addImport("dvui", dvui_mod);
native_module.addImport("raylib-backend", raylib_mod);

const solid_mod = b.createModule(.{
    .root_source_file = b.path("src/integrations/solid/mod.zig"),
    ...
});
solid_mod.addImport("dvui", dvui_mod);

const jsruntime_mod = b.createModule(.{
    .root_source_file = b.path("src/integrations/jsruntime/mod.zig"),
    ...
});

// Cross-module imports
solid_mod.addImport("jsruntime", jsruntime_mod);
jsruntime_mod.addImport("solid", solid_mod);
jsruntime_mod.addImport("dvui", dvui_mod);
native_module.addImport("solid", solid_mod);
native_module.addImport("jsruntime", jsruntime_mod);
```

The result is a dynamic library `native_renderer.dll` (Windows) / `libnative_renderer.so` (Linux) / `libnative_renderer.dylib` (macOS).

## FFI Interface (Complete)

### All Exported Functions

From `src/integrations/native_renderer/exports.zig`:

| Export | Signature | Purpose |
|--------|-----------|---------|
| `createRenderer` | `(log_cb, event_cb) -> *Renderer` | Create renderer with callbacks |
| `destroyRenderer` | `(*Renderer) -> void` | Clean up renderer |
| `resizeRenderer` | `(*Renderer, width, height) -> void` | Resize window |
| `presentRenderer` | `(*Renderer) -> void` | Render frame to screen |
| `commitCommands` | `(*Renderer, headers, payload, count) -> void` | Submit draw commands |
| `setRendererText` | `(*Renderer, text_ptr, text_len) -> void` | Set debug text |
| `setRendererSolidTree` | `(*Renderer, json_ptr, json_len) -> void` | Full tree snapshot |
| `applyRendererSolidOps` | `(*Renderer, json_ptr, json_len) -> bool` | Apply incremental ops |
| `getEventRingHeader` | `(*Renderer, out_ptr, out_len) -> usize` | Get ring buffer header |
| `getEventRingBuffer` | `(*Renderer) -> *EventEntry` | Get event buffer pointer |
| `getEventRingDetail` | `(*Renderer) -> *u8` | Get detail string buffer |
| `acknowledgeEvents` | `(*Renderer, new_read_head) -> void` | Mark events as consumed |

### FFI Flow

```
frontend/index.ts
    → NativeRenderer (solid/native/adapter.ts)
        → lib.symbols.* (solid/native/ffi.ts loads native_renderer.dll)
            → exports.zig (Zig FFI exports)
                → lifecycle.zig, window.zig, solid_sync.zig, events.zig
                    → solid/mod.zig → render, layout, events
```

### TypeScript FFI Bindings

From `frontend/solid/native/ffi.ts`:

```typescript
const nativeSymbols = {
  createRenderer: { args: ["ptr", "ptr"], returns: "ptr" },
  destroyRenderer: { args: ["ptr"], returns: "void" },
  resizeRenderer: { args: ["ptr", "u32", "u32"], returns: "void" },
  commitCommands: { args: ["ptr", "ptr", "usize", "ptr", "usize", "u32"], returns: "void" },
  presentRenderer: { args: ["ptr"], returns: "void" },
  setRendererText: { args: ["ptr", "ptr", "usize"], returns: "void" },
  setRendererSolidTree: { args: ["ptr", "ptr", "usize"], returns: "void" },
  applyRendererSolidOps: { args: ["ptr", "ptr", "usize"], returns: "bool" },
  getEventRingHeader: { args: ["ptr", "ptr", "usize"], returns: "usize" },
  getEventRingBuffer: { args: ["ptr"], returns: "ptr" },
  getEventRingDetail: { args: ["ptr"], returns: "ptr" },
  acknowledgeEvents: { args: ["ptr", "u32"], returns: "void" },
};
```

## Render Pipeline

```
JS DOM mutations → NodeStore (core)
                → updateLayouts (layout)
                → updatePaintCache (render/cache, hydrates visual.bg from class when missing)
                → render (render/mod)
                    ├─ direct.zig for all non-interactive nodes (background + children)
                    └─ DVUI widgets for interactive nodes only
```

Dirty region tracking flows through `render/cache.zig` and reuses paint geometry when possible.

## JS Event Flow (Zig → JS)

The event system enables native DVUI widgets to dispatch events to SolidJS handlers:

```
DVUI button clicked
    → renderButton checks node.hasListener("click")
    → EventRing.pushClick(node_id)
    → JS pollEvents() reads EventRing via FFI
    → Lookup HostNode by node_id in nodeIndex
    → Dispatch to registered handlers via node.listeners.get("click")
```

### Event Ring Buffer

Located at `src/integrations/solid/events/ring.zig`:

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
    change = 8,
    submit = 9,
};

pub const EventEntry = extern struct {
    kind: EventKind,
    _pad: u8 = 0,
    node_id: u32,
    detail_offset: u32,
    detail_len: u16,
    _pad2: u16 = 0,
};
```

### Key Components

1. **EventRing** (`src/integrations/solid/events/ring.zig`): Lock-free ring buffer shared between Zig and JS
2. **pollEvents** (`frontend/solid/native/adapter.ts`): Called each frame after `present()` to read pending events
3. **HostNode.listeners** (`frontend/solid/host/node.ts`): Map of event names to handler sets

## SolidJS Universal Renderer Integration

### Babel Configuration

The Solid JSX transform MUST use `generate: "universal"` mode:

```typescript
// scripts/solid-plugin.ts
[solid, {
  generate: "universal",  // NOT "dom"!
  moduleName: "#solid-runtime",
}]
```

**Why this matters**: DOM mode compiles `onClick` to `node.$$click = handler` with event delegation that bypasses custom renderers. Universal mode uses `setProperty(node, "onClick", handler)` which we can intercept.

### Runtime Exports Required

Universal mode expects these exports from the runtime module (`frontend/solid/runtime/index.ts`):

```typescript
export const createElement = (tag: string) => ...
export const createTextNode = (value: string) => ...
export const insertNode = (parent, node, anchor?) => ...
export const removeNode = (parent, node) => ...
export const setProperty = (node, name, value, prev?) => ...  // Events go here!
export const getParentNode = (node) => ...
export const getFirstChild = (node) => ...
export const getNextSibling = (node) => ...
```

### Event Handler Detection in setProperty

```typescript
export const setProperty = (node, name, value, prev) => {
  // Handle onClick, onInput, on:click, etc.
  if (name.startsWith("on") && name.length > 2 && name[2] === name[2].toUpperCase()) {
    const eventName = name.slice(2, 3).toLowerCase() + name.slice(3); // onClick -> click
    if (prev) node.off(eventName, prev);
    if (value) node.on(eventName, value);
    return;
  }
  // ... handle other props
};
```

### Runtime Bridge Pattern

Nodes created by `runtime/index.ts` must be registered in the host's `nodeIndex`:

```typescript
// frontend/solid/runtime/bridge.ts
export const registerRuntimeBridge = (scheduleFlush, registerNode, hostOps?) => { ... };
export const registerRuntimeNode = (node) => bridge.registerNode?.(node);

// frontend/solid/runtime/index.ts
export const createElement = (tag) => {
  const node = new HostNode(tag);
  registerRuntimeNode(node);  // Critical! Otherwise node won't be tracked
  return node;
};
```

## Principles

- Integration modules live under `src/integrations/`, core types under `src/core/`.
- Separation of concerns: core data, layout math, style parsing, rendering, JS bridge.
- Explicit init/deinit and allocator ownership on all structs (see `core/types.zig`).
- Non-interactive elements are always drawn directly; DVUI is reserved for interactive paths so backgrounds are never skipped.
- Class-derived backgrounds are copied into `visual.background` before caching/drawing, ensuring consistent fills even when the DVUI path does not set one.
- Event ring buffer is available for Zig→JS input dispatch; mutation op path covers create/remove/move/set/listen.

## Key Lessons Learned

### 1. DVUI Widget ID Uniqueness

**Problem**: Multiple buttons rendered through the same `dvui.button(@src(), ...)` call get identical widget IDs because `@src()` returns the same source location.

**Solution**: Use `ButtonWidget` directly with unique `id_extra` derived from `node_id`:
```zig
var bw = dvui.ButtonWidget.init(@src(), .{}, .{ .id_extra = nodeIdExtra(node_id) });
```

### 2. SolidJS Compiler Mode Matters

**Problem**: With `generate: "dom"`, SolidJS uses `$$eventName` properties and `delegateEvents()` - a DOM-specific pattern that completely bypasses custom renderers.

**Solution**: Use `generate: "universal"` mode which routes all properties (including events) through `setProperty`.

### 3. Node Registration Across Modules

**Problem**: runtime.ts creates HostNodes that solid-host.tsx's flush loop never sees because they're not in `nodeIndex`.

**Solution**: Share node registration via a bridge module:
- runtime.ts calls `registerRuntimeNode(node)` 
- solid-host.tsx provides the actual `registerNode` implementation

### 4. Listener Emission Timing

**Problem**: The condition `node.created && node.listenersDirty` fails when properties (including event handlers) are set before nodes are inserted.

**Solution**: Remove the `node.created` requirement - emit listeners whenever `listenersDirty` is true or `sentListeners.size < listeners.size`.

### 5. FFI BigInt vs Number

**Problem**: Bun FFI returns `usize` as BigInt (`16n`), but JavaScript's strict equality `16n !== 16` is true.

**Solution**: Always convert FFI return values to Number before comparison: `Number(copied) !== headerBuffer.length`.


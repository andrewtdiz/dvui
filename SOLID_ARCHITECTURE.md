# Solid Logic & DOM Incremental Rendering Architecture

## Current Structure (Unified)

```
src/solid/
├── mod.zig              # Public API: init/render + NodeStore accessors
│
├── core/                # Data + lifecycle
│   ├── types.zig        # SolidNode, NodeStore, Rect, VisualProps, Transform
│   └── dirty.zig        # Version tracking
│
├── layout/              # Geometry only
│   ├── mod.zig          # updateLayouts entry point
│   ├── flex.zig         # Flex child positioning
│   └── measure.zig      # Intrinsic size measurement
│
├── style/               # Tailwind/CSS-ish interpretation
│   ├── tailwind.zig     # Class parsing
│   ├── colors.zig       # Palette
│   └── apply.zig        # Map specs → dvui.Options / VisualProps
│
├── render/              # Drawing subsystem
│   ├── mod.zig          # Render dispatch + dirty-region orchestration
│   ├── direct.zig       # Direct triangle/text draws (non-interactive)
│   ├── widgets.zig      # DVUI widget entry point (interactive only)
│   └── cache.zig        # Paint cache + DirtyRegionTracker
│
├── events/              # Zig→JS event dispatch
│   ├── mod.zig          # Re-exports
│   └── ring.zig         # EventRing buffer for click/input/focus events
│
└── bridge/              # JS runtime integration
    └── jsc.zig          # QuickJS/Bun bridge stub
```

Other touchpoints:
- `src/jsruntime/solid/mod.zig` now delegates to `solid/mod.zig`.
- Legacy wrappers (`src/solid_renderer.zig`, `src/solid_layout.zig`) and the old `src/jsruntime/solid/*` files are removed.

## Render Pipeline

```
JS DOM mutations → NodeStore (core)
                → updateLayouts (layout)
                → updatePaintCache (render/cache, hydrates visual.bg from class when missing)
                → render (render/mod)
                    ├─ direct.zig for all non-interactive nodes (background + children)
                    └─ DVUI widgets for interactive nodes only
```

Dirty region tracking flows through `render/cache.zig` and reused paint geometry when possible.

## JS Event Flow (Zig → JS)

The event system enables native DVUI widgets to dispatch events to SolidJS handlers:

```
DVUI button clicked
    → renderButton checks node.hasListener("click")
    → EventRing.pushClick(node_id)
    → JS pollEvents() reads EventRing
    → Lookup HostNode by node_id in nodeIndex
    → Dispatch to registered handlers via node.listeners.get("click")
```

### Key Components

1. **EventRing** (`src/solid/events/ring.zig`): Lock-free ring buffer shared between Zig and JS
2. **pollEvents** (`frontend/solid/native/adapter.ts`): Called each frame after `present()` to read pending events
3. **HostNode.listeners** (`frontend/solid/host/node.ts`): Map of event names to handler sets

### FFI Exports for Event Polling
- `getEventRingHeader` - Returns read/write heads and capacity
- `getEventRingBuffer` - Returns pointer to event entries
- `getEventRingDetail` - Returns pointer to detail string buffer
- `acknowledgeEvents` - Updates read head after JS consumes events

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

Universal mode expects these exports from the runtime module:

```typescript
// frontend/solid/runtime.ts (or runtime/index.ts)
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

Nodes created by `runtime.ts` must be registered in the host's `nodeIndex`:

```typescript
// frontend/solid/runtime-bridge.ts
export const registerRuntimeBridge = (scheduleFlush, registerNode) => { ... };
export const registerRuntimeNode = (node) => bridge.registerNode?.(node);

// frontend/solid/runtime.ts
export const createElement = (tag) => {
  const node = new HostNode(tag);
  registerRuntimeNode(node);  // Critical! Otherwise node won't be tracked
  return node;
};
```

## Principles

- Single source of truth under `src/solid/`.
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


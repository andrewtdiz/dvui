# JSX to Zig Render Path

This document traces how a JSX component in `frontend/solid/App.tsx` becomes pixels on screen via the Zig/DVUI rendering engine.

---

## Example Component

```tsx
// frontend/solid/App.tsx
export const App = () => {
  const [count, setCount] = createSignal(0);

  return (
    <div class="flex justify-center items-center w-full h-full bg-gray-500">
      <div class="flex flex-col gap-3 items-start bg-red-500 w-64 h-64 p-3 rounded-md">
        <p class="bg-blue-400 text-gray-100 rounded-sm px-2 py-1">
          Centered Text
        </p>
        <button class="bg-blue-400 text-gray-100 px-4 py-2 rounded"
          onClick={(payload) => setCount(c => c + 1)}>
          Increment
        </button>
        <p class="bg-purple-500 text-white rounded-sm">
          Right {count()}
        </p>
      </div>
    </div>
  );
};
```

---

## Phase 1: Build-Time Transform

### 1.1 Babel/SolidJS Compilation

**File:** `frontend/scripts/solid-plugin.ts`

The JSX is transformed using `babel-preset-solid` with `generate: "universal"` mode:

```typescript
[solid, {
  generate: "universal",  // Critical: NOT "dom"
  moduleName: "#solid-runtime",
}]
```

**Output:** Compiled JS that calls runtime functions instead of DOM APIs:

```javascript
// Simplified compiled output
import { createElement, setProperty, insert } from "#solid-runtime";

const App = () => {
  const div1 = createElement("div");
  setProperty(div1, "class", "flex justify-center...");
  
  const div2 = createElement("div");
  setProperty(div2, "class", "flex flex-col...");
  insert(div1, div2);
  
  const button = createElement("button");
  setProperty(button, "onClick", (payload) => setCount(c => c + 1));
  insert(div2, button);
  
  return div1;
};
```

---

## Phase 2: JavaScript Runtime

### 2.1 Runtime Functions Create HostNodes (via bridge)

**Files:** `frontend/solid/runtime/index.ts`, `frontend/solid/runtime/bridge.ts`, `frontend/solid/host/index.ts`

- `createSolidHost` builds the mutation queue + flush controller and registers its host ops (create/insert/remove/set) with the runtime bridge.
- `runtime/index.ts` delegates `createElement`/`createTextNode`/`insert`/`setProperty` to the bridged host ops, so nodes are registered and ops are enqueued automatically.
- Event props (`onClick`, `on:input`, etc.) register listeners on `HostNode` and mark them dirty so `listen` ops are emitted.

### 2.2 HostNode Structure

**File:** `frontend/solid/host/node.ts`

```typescript
class HostNode {
  id: number;           // Unique node ID
  tag: string;          // "div", "button", "p", "text"
  props: NodeProps;     // className, text, etc.
  children: HostNode[];
  parent?: HostNode;
  listeners: Map<string, Set<EventHandler>>;  // "click" → handlers
  created: boolean;     // Has been sent to native
}
```

### 2.3 Tree Built in Memory

After `App()` executes:

```
HostNode(root)
└── HostNode(div, id=1, class="flex justify-center …")
    └── HostNode(div, id=2, class="flex flex-col …")
        ├── HostNode(p, id=3) -> HostNode(text, id=4, text="Centered Text")
        ├── HostNode(p, id=5) -> HostNode(text, id=6, text="Does render on the UI")
        ├── HostNode(p, id=7) -> HostNode(text, id=8, text="Doesnt render on the UI")
        ├── HostNode(button, id=9, listeners: {click}) -> HostNode(text, id=10, text="Increment")
        └── HostNode(p, id=11) -> HostNode(text, id=12, text="Right 0")
```

---

## Phase 3: Flush to Native

### 3.1 Flush Triggered

**File:** `frontend/index.ts`

```typescript
const loop = () => {
  host.flush();                    // Emit commands + ops
  renderer.present();              // Render frame
  renderer.pollEvents(nodeIndex);  // Read events from Zig
};
```

### 3.2 Tree Serialization

**File:** `frontend/solid/host/flush.ts`

```typescript
const flush = () => {
  encoder.reset();
  for (const child of root.children) {
    emitNode(child, encoder, 0);   // Build command buffers
  }

  // Emit listener registrations
  for (const node of nodeIndex.values()) {
    if (node.listenersDirty || node.sentListeners.size < node.listeners.size) {
      emitPendingListeners(node, ops);
    }
  }

  // Prefer incremental ops once a snapshot has synced
  if (native.applyOps && ops.length > 0 && syncedOnce) {
    native.applyOps(treeEncoder.encode(JSON.stringify({ seq: ++seq, ops })));
    ops.length = 0;
  }

  // Full snapshot only on first sync or when mutations aren’t supported/failed
  const shouldSnapshot = !syncedOnce || needFullSync || (!mutationsSupported && native.setSolidTree != null);
  if (native.setSolidTree && shouldSnapshot) {
    const nodes = serializeTree(root.children);
    native.setSolidTree(treeEncoder.encode(JSON.stringify({ nodes })));
    markCreated(root);
    syncedOnce = true;
    needFullSync = false;
    ops.length = 0; // force re-emit listeners next flush
  }

  native.commit(encoder); // Send command buffers
};
```

### 3.3 Serialized Payload

```json
{
  "nodes": [
    { "id": 1, "tag": "div", "parent": 0, "className": "flex justify-center..." },
    { "id": 2, "tag": "div", "parent": 1, "className": "flex flex-col..." },
    { "id": 3, "tag": "p", "parent": 2, "className": "bg-blue-400..." },
    { "id": 4, "tag": "text", "parent": 3, "text": "Centered Text" },
    { "id": 5, "tag": "button", "parent": 2, "className": "bg-blue-400..." },
    { "id": 6, "tag": "text", "parent": 5, "text": "Increment" },
    { "id": 7, "tag": "p", "parent": 2, "className": "bg-purple-500..." },
    { "id": 8, "tag": "text", "parent": 7, "text": "Right 0" }
  ]
}

// Incremental ops example
{
  "seq": 11,
  "ops": [
    { "op": "set_text", "id": 12, "text": "Right 1" },
    { "op": "listen", "id": 9, "eventType": "click" }
  ]
}
```

---

## Phase 4: FFI Bridge

### 4.1 FFI Call

**File:** `frontend/solid/native/ffi.ts`

```typescript
const nativeSymbols = {
  setRendererSolidTree: { args: ["ptr", "ptr", "usize"], returns: "void" },
  applyRendererSolidOps: { args: ["ptr", "ptr", "usize"], returns: "bool" },
  presentRenderer: { args: ["ptr"], returns: "void" },
};
```

### 4.2 Zig FFI Export

**File:** `src/integrations/native_renderer/exports.zig`

```zig
pub export fn setRendererSolidTree(
    renderer: ?*Renderer,
    json_ptr: [*]const u8,
    json_len: usize,
) callconv(.c) void {
    const data = json_ptr[0..json_len];
    solid_sync.rebuildSolidStoreFromJson(renderer, data, logMessage);
}
```

---

## Phase 5: Zig NodeStore

### 5.1 JSON Parsing

**File:** `src/integrations/native_renderer/solid_sync.zig`

```zig
pub fn rebuildSolidStoreFromJson(renderer: *Renderer, json_bytes: []const u8, logMessage: anytype) void {
    var parsed = std.json.parseFromSlice(Payload, ...);
    
    // First pass: create nodes
    for (payload.nodes) |node| {
        if (std.mem.eql(u8, node.tag, "text")) {
            store.setTextNode(node.id, node.text);
        } else {
            store.upsertElement(node.id, node.tag);
        }
        if (node.className) |cls| {
            store.setClassName(node.id, cls);
        }
        // Transform/visual fields (opacity, radius, colors) are applied here too.
    }
    
    // Second pass: wire parent/child
    for (payload.nodes) |node| {
        store.insert(parent_id, node.id, null);
    }
}
```

### 5.2 SolidNode Structure

**File:** `src/integrations/solid/core/types.zig`

```zig
pub const SolidNode = struct {
    id: u32,
    kind: enum { root, element, text, slot },
    tag: []const u8,
    class_name: []const u8,
    text: []const u8,
    children: std.ArrayList(u32),
    parent: ?u32,
    
    layout: struct {
        rect: ?Rect,
    },
    visual: struct {
        background: ?PackedColor,
        text_color: ?PackedColor,
        opacity: f32,
        corner_radius: f32,
    },
    transform: struct {
        rotation: f32,
        scale: [2]f32,
        translation: [2]f32,
    },
    
    listeners: std.StringHashMap(void),  // "click" → registered
};
```

---

## Phase 6: Rendering

### 6.1 Present Frame

**File:** `src/integrations/native_renderer/window.zig`

```zig
pub fn renderFrame(renderer: *Renderer) void {
    ray.beginDrawing();
    ray.clearBackground(ray.Color.black);
    
    // Render Solid tree
    if (renderer.solid_store_ready) {
        if (types.solidStore(renderer)) |store| {
            _ = solid.render(runtime, store);
        }
    }
    
    ray.endDrawing();
}
```

### 6.2 Render Dispatch

**File:** `src/integrations/solid/render/mod.zig`

```zig
pub fn render(runtime: ?*JSRuntime, store: *NodeStore) bool {
    const root = store.node(0) orelse return false;
    
    layout.updateLayouts(store);           // Compute flex layout
    syncVisualsFromClasses(store, root);   // Parse Tailwind → visual props
    updatePaintCache(store, &dirty_tracker);
    
    for (root.children.items) |child_id| {
        renderNode(runtime, store, child_id, allocator, tracker);
    }
}
```

### 6.3 Tag-Based Routing

```zig
fn renderElementBody(...) void {
    if (std.mem.eql(u8, node.tag, "div")) {
        renderContainer(...);    // → dvui.flexbox or dvui.box
    }
    if (std.mem.eql(u8, node.tag, "button")) {
        renderButton(...);       // → dvui.ButtonWidget
    }
    if (std.mem.eql(u8, node.tag, "p")) {
        renderParagraph(...);    // → direct draw text (no background required; transparent fill used when missing)
    }
}
```

### 6.4 Button Rendering

```zig
fn renderButton(runtime, store, node_id, node, ...) void {
    const text = buildText(store, node, allocator);  // "Increment"
    
    var options = dvui.Options{
        .id_extra = nodeIdExtra(node_id),  // Unique widget ID
    };
    style_apply.applyToOptions(&class_spec, &options);  // Tailwind → DVUI
    
    var bw = dvui.ButtonWidget.init(@src(), .{}, options);
    bw.install();
    bw.processEvents();
    bw.drawBackground();
    
    dvui.labelNoFmt(@src(), text, ...);  // Draw caption
    
    bw.drawFocus();
    const pressed = bw.clicked();
    bw.deinit();
    
    if (pressed and node.hasListener("click")) {
        // Push to event ring buffer
        ring.pushClick(node_id);
    }
}
```

### 6.5 Tailwind → DVUI Options

**File:** `src/integrations/solid/style/apply.zig`

```zig
pub fn applyToOptions(spec: *const ClassSpec, options: *dvui.Options) void {
    // Background
    if (spec.background) |color| {
        options.color_fill = color;
    }
    
    // Padding
    if (spec.padding) |p| {
        options.padding = dvui.Rect.all(p);
    }
    
    // Border radius
    if (spec.border_radius) |r| {
        options.corner_radius = r;
    }
    
    // Text color
    if (spec.text_color) |color| {
        options.color_text = color;
    }
}
```

---

## Phase 7: Event Loop

### 7.1 Event Ring Buffer

**File:** `src/integrations/solid/events/ring.zig`

```zig
pub const EventRing = struct {
    buffer: []EventEntry,
    read_head: u32,
    write_head: u32,
    
    pub fn pushClick(self: *EventRing, node_id: u32) bool {
        self.buffer[idx] = EventEntry{
            .kind = .click,
            .node_id = node_id,
        };
        self.write_head += 1;
    }
};
```

### 7.2 JS Polls Events

**File:** `frontend/solid/native/adapter.ts`

```typescript
pollEvents(nodeIndex: Map<number, HostNode>): number {
  // Read header from Zig
  lib.symbols.getEventRingHeader(handle, headerBuffer, 16);
  const readHead = headerView.getUint32(0, true);
  const writeHead = headerView.getUint32(4, true);
  
  // Read events
  while (current < writeHead) {
    const kind = bufferView.getUint8(offset);      // 0 = click
    const nodeId = bufferView.getUint32(offset + 4, true);
    
    const node = nodeIndex.get(nodeId);
    const handlers = node.listeners.get("click");
    for (const handler of handlers) {
      handler(payload);  // Execute onClick handler
    }
  }
  
  // Acknowledge consumed events
  lib.symbols.acknowledgeEvents(handle, current);
}
```

### 7.3 Handler Executes

```javascript
onClick={(payload) => {
  setCount(c => c + 1);  // Solid signal update
}}
```

### 7.4 Reactivity Triggers Re-render

Signal update causes Solid to re-run reactive computations:
1. `count()` returns new value
2. Text node content changes: `"Right 0"` → `"Right 1"`
3. `setProperty(textNode, "text", "Right 1")` called
4. `notifyRuntimePropChange()` schedules flush
5. Next `flush()` sends `set_text` op to Zig
6. Zig updates `SolidNode.text`
7. Next `renderFrame()` renders updated text

---

## Summary Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        BUILD TIME                                   │
├─────────────────────────────────────────────────────────────────────┤
│  App.tsx (JSX)                                                      │
│      │                                                              │
│      ▼ babel-preset-solid (universal mode)                          │
│  Compiled JS (createElement, setProperty, insert calls)             │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       JAVASCRIPT RUNTIME                            │
├─────────────────────────────────────────────────────────────────────┤
│  runtime/index.ts                                                   │
│      │ createElement("div") → new HostNode("div")                   │
│      │ setProperty(node, "onClick", fn) → node.on("click", fn)      │
│      ▼                                                              │
│  HostNode tree built in memory                                      │
│      │                                                              │
│      ▼ host.flush()                                                 │
│  host/flush.ts                                                      │
│      │ serializeTree() → JSON                                       │
│      │ native.setSolidTree(payload) ─────────────────────┐          │
│      │ native.applyOps([{op:"listen", id:5, event:"click"}])        │
└──────│──────────────────────────────────────────────────────────────┘
       │                                                    │
       │ FFI                                                │
       ▼                                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         ZIG NATIVE                                  │
├─────────────────────────────────────────────────────────────────────┤
│  native_renderer/exports.zig                                        │
│      │ setRendererSolidTree() → solid_sync.rebuildSolidStoreFromJson│
│      ▼                                                              │
│  solid_sync.zig                                                     │
│      │ JSON parse → store.upsertElement(), store.setClassName()     │
│      ▼                                                              │
│  solid/core/types.zig::NodeStore                                    │
│      │ SolidNode tree with layout, visual, transform props          │
│      ▼                                                              │
│  window.renderFrame()                                               │
│      │ solid.render(runtime, store)                                 │
│      ▼                                                              │
│  solid/render/mod.zig                                               │
│      │ updateLayouts() → compute flex positions                     │
│      │ syncVisualsFromClasses() → parse Tailwind                    │
│      │ renderNode() → tag dispatch                                  │
│      ▼                                                              │
│  renderButton() / renderContainer() / renderParagraph()             │
│      │ dvui.ButtonWidget / dvui.flexbox / dvui.labelNoFmt           │
│      │                                                              │
│      │ on click: ring.pushClick(node_id)                            │
└──────│──────────────────────────────────────────────────────────────┘
       │                              ▲
       │ EventRing                    │ renderer.pollEvents()
       ▼                              │
┌─────────────────────────────────────────────────────────────────────┐
│                      EVENT DISPATCH                                 │
├─────────────────────────────────────────────────────────────────────┤
│  adapter.ts::pollEvents()                                           │
│      │ getEventRingHeader() → read/write heads                      │
│      │ Read EventEntry from buffer                                  │
│      │ nodeIndex.get(nodeId).listeners.get("click")                 │
│      │ handler(payload) → setCount(c => c+1)                        │
│      ▼                                                              │
│  Signal update → re-render → flush() → next frame                   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Key Files Reference

| Layer | File | Purpose |
|-------|------|---------|
| JSX Transform | `scripts/solid-plugin.ts` | Babel config with `universal` mode |
| Runtime | `solid/runtime/index.ts` | `createElement`, `setProperty`, `insert` |
| Node | `solid/host/node.ts` | `HostNode` class with props and listeners |
| Flush | `solid/host/flush.ts` | Serialize tree, emit ops, FFI calls |
| FFI | `solid/native/ffi.ts` | Symbol definitions |
| FFI | `solid/native/adapter.ts` | `NativeRenderer.pollEvents()` |
| Zig FFI | `native_renderer/exports.zig` | Export functions |
| Zig Sync | `native_renderer/solid_sync.zig` | JSON → NodeStore |
| Zig Store | `solid/core/types.zig` | `SolidNode`, `NodeStore` |
| Zig Render | `solid/render/mod.zig` | Render dispatch |
| Zig Style | `solid/style/tailwind.zig` | Class parsing |
| Zig Style | `solid/style/apply.zig` | Tailwind → DVUI options |
| Zig Events | `solid/events/ring.zig` | `EventRing`, `EventKind` |

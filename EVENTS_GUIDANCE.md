## Adding New Event Types

To add a new event like `mouseenter`, `mouseleave`, `input`, `focus`, etc., follow these steps:

### Step 1: Add to Zig EventKind Enum

**File**: `src/solid/events/ring.zig`

```zig
pub const EventKind = enum(u8) {
    click = 0,
    input = 1,
    focus = 2,
    blur = 3,
    mouseenter = 4,   // Already exists
    mouseleave = 5,   // Already exists
    keydown = 6,
    keyup = 7,
    change = 8,
    submit = 9,
    // Add new event here:
    hover = 10,
};
```

### Step 2: Add Convenience Push Method (Optional)

**File**: `src/solid/events/ring.zig`

```zig
pub fn pushHover(self: *EventRing, node_id: u32) bool {
    return self.push(.hover, node_id, null);
}
```

### Step 3: Emit Event from Render Code

**File**: `src/solid/render/mod.zig`

For widgets that should emit the event, add event dispatch logic:

```zig
fn renderButton(rt: *RenderContext, node: *SolidNode, node_id: u32) !void {
    // ... button widget code ...
    
    // Check for hover state
    if (bw.hovered() and node.hasListener("mouseenter")) {
        _ = rt.event_ring.pushMouseEnter(node_id);
    }
}
```

### Step 4: Add to JS Event Kind Mapping

**File**: `frontend/solid/native/adapter.ts`

In `pollEvents`, update the `eventKindToName` mapping:

```typescript
const eventKindToName: Record<number, string> = {
  0: "click",
  1: "input",
  2: "focus",
  3: "blur",
  4: "mouseenter",
  5: "mouseleave",
  6: "keydown",
  7: "keyup",
  8: "change",
  9: "submit",
  // Add new event here:
  10: "hover",
};
```

### Step 5: Use in JSX

**File**: Your SolidJS component (e.g., `solid-entry.tsx`)

```tsx
<button
  onClick={(payload) => console.log("clicked", payload)}
  onMouseEnter={(payload) => console.log("mouse entered", payload)}
  onMouseLeave={(payload) => console.log("mouse left", payload)}
>
  Hover me
</button>
```

The universal renderer's `setProperty` function automatically converts camelCase event props (like `onMouseEnter`) to lowercase event names (like `mouseenter`) for the listener registration.

### Step 6: Register Listener in Zig (Automatic)

When the JS host emits a `listen` op with the event type, it's handled automatically by `applySolidOp` in `src/native_renderer/solid_sync.zig`:

```zig
// In applySolidOp function:
if (std.mem.eql(u8, op.op, "listen")) {
    try store.addListener(op.id, event_type);
}
```

The `hasListener` check in render code will then return `true` for nodes with that event registered.

### Event Payload

All events receive a `Uint8Array` payload with at least the node ID:

```typescript
const handler = (payload: Uint8Array) => {
  const view = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
  const nodeId = view.getUint32(0, true);
  // Additional data can be packed after the node ID
};
```

For events that need additional data (like input value or key code), use the `detail` field in `EventRing.push()` which writes to the detail buffer.

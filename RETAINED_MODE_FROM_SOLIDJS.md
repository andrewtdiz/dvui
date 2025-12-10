# Retained-Mode Rendering State From SolidJS

## The Question

Can SolidJS hold the retained-mode state and send draw commands to Zig every frame, rather than Zig maintaining a `NodeStore` that mirrors the SolidJS tree?

**Short Answer:** Yes, and this may be a cleaner architecture. Below is the analysis.

---

## Current Architecture (Zig-Side Retained State)

```
┌─────────────────────────────────────────────────────────────────┐
│                         TypeScript                              │
├─────────────────────────────────────────────────────────────────┤
│  SolidJS Virtual DOM (HostNode tree)                            │
│       ↓                                                         │
│  flush() → serialize nodes to JSON                              │
│       ↓                                                         │
│  FFI: setSolidTree() / applyRendererSolidOps()                  │
└────────────────────────────┬────────────────────────────────────┘
                             │ JSON bytes
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                           Zig                                   │
├─────────────────────────────────────────────────────────────────┤
│  NodeStore (retained tree)  ←── rebuilt from JSON               │
│       ↓                                                         │
│  solid_renderer.render()  ←── walks tree, creates DVUI widgets  │
│       ↓                                                         │
│  DVUI → Raylib → Screen                                         │
└─────────────────────────────────────────────────────────────────┘
```

**Problems:**
1. **Double bookkeeping** — Same tree structure in JS and Zig
2. **Dirty-tracking mismatch** — Zig's optimization is incompatible with DVUI
3. **Serialization overhead** — JSON parsing every mutation batch
4. **Synchronization risk** — Mutation ops can get out of sync

---

## Proposed Architecture (SolidJS-Side Retained State)

```
┌─────────────────────────────────────────────────────────────────┐
│                         TypeScript                              │
├─────────────────────────────────────────────────────────────────┤
│  SolidJS Virtual DOM (HostNode tree) ← SOURCE OF TRUTH          │
│       ↓                                                         │
│  flush() → generate draw commands (binary buffer)               │
│       ↓                                                         │
│  FFI: commit(headers, payload)  ← EVERY FRAME                   │
└────────────────────────────┬────────────────────────────────────┘
                             │ Binary command buffer
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                           Zig                                   │
├─────────────────────────────────────────────────────────────────┤
│  renderCommandsDvui()  ← executes commands directly             │
│       ↓                                                         │
│  DVUI → Raylib → Screen                                         │
│                                                                 │
│  (No NodeStore, no tree traversal)                              │
└─────────────────────────────────────────────────────────────────┘
```

**Benefits:**
1. **Single source of truth** — SolidJS owns all state
2. **No synchronization issues** — No mutation ops to track
3. **Binary format** — Faster than JSON parsing
4. **Simpler Zig code** — Just execute commands, no tree logic
5. **Natural immediate-mode fit** — Commands = immediate-mode calls

---

## How It Would Work

### 1. SolidJS Generates Commands Each Frame

```typescript
// frontend/solid/solid-host.tsx
function flush() {
  const encoder = new CommandEncoder();
  
  // Walk the SolidJS tree and emit draw commands
  function emitNode(node: HostNode, parentId: number) {
    const id = node.id;
    
    if (node.tag === 'div') {
      encoder.pushBox(id, parentId, node.frame, node.backgroundColor);
    } else if (node.tag === 'p' || node.tag === 'h1') {
      encoder.pushText(id, parentId, node.frame, node.textContent, node.color);
    } else if (node.tag === 'button') {
      encoder.pushButton(id, parentId, node.frame, node.label);
    }
    // ... etc
    
    for (const child of node.children) {
      emitNode(child, id);
    }
  }
  
  emitNode(rootNode, 0);
  
  // Send binary buffer to Zig
  renderer.commit(encoder.headerBuffer, encoder.payloadBuffer);
}
```

### 2. Zig Executes Commands Directly

```zig
// src/native_renderer.zig
fn renderFrame(renderer: *Renderer) void {
    // ... setup ...
    
    // No NodeStore needed — just render the command buffer
    for (renderer.headers.items) |cmd| {
        switch (cmd.opcode) {
            Opcode.Box => renderBox(cmd, renderer.payload.items),
            Opcode.Text => renderText(cmd, renderer.payload.items),
            Opcode.Button => renderButton(cmd, renderer.payload.items),
            // ... etc
        }
    }
}
```

### 3. Layout Computation

**Option A: Layout in TypeScript**
- Use a JS layout library (Yoga, Taffy via WASM)
- Commands include absolute positions
- Zig just draws at specified coordinates

**Option B: Layout in Zig**
- Commands specify constraints (flex, percentage, etc.)
- Zig uses DVUI's layout system
- More complex command format, but leverages existing DVUI code

---

## Handling Stateful Widgets

The main challenge is widgets that have internal state:

| Widget | State Needed |
|--------|--------------|
| `<input>` | Cursor position, selection, text buffer |
| `<button>` | Hover/pressed state (handled by DVUI) |
| Scroll views | Scroll offset |
| Focus | Which element has keyboard focus |

### Solution: Stateful Widget Registry

Keep a minimal registry in Zig for stateful widgets only:

```zig
const StatefulWidget = union(enum) {
    input: InputState,
    scroll: ScrollState,
};

var stateful_widgets: std.AutoHashMap(u32, StatefulWidget) = ...;

fn renderInput(cmd: CommandHeader, payload: []const u8) void {
    const state = stateful_widgets.getPtr(cmd.node_id) orelse {
        // Create new state if first time seeing this ID
        stateful_widgets.put(cmd.node_id, .{ .input = InputState.init() });
        return stateful_widgets.getPtr(cmd.node_id).?;
    };
    
    // Use DVUI's textEntry with the persisted state
    var entry = dvui.textEntry(@src(), .{ .buffer = state.input.buffer }, options);
    // ...
}
```

Commands include a flag indicating if the node is stateful:
```typescript
encoder.pushInput(id, parentId, frame, { stateful: true, value: props.value });
```

---

## Event Flow (Input Back to SolidJS)

When a stateful widget changes (e.g., button click, text input):

```
┌─────────────────────────────────────────────────────────────────┐
│  Zig: DVUI detects button press                                 │
│       ↓                                                         │
│  sendEvent("click", { nodeId: 5 })                              │
└────────────────────────────┬────────────────────────────────────┘
                             │ FFI callback
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  TypeScript: event callback fires                               │
│       ↓                                                         │
│  Find SolidJS node by ID → call onClick handler                 │
│       ↓                                                         │
│  SolidJS reactivity triggers re-render                          │
│       ↓                                                         │
│  Next frame: new commands sent to Zig                           │
└─────────────────────────────────────────────────────────────────┘
```

This is already how the current architecture works — it just becomes the **only** path.

---

## Command Buffer Format

The existing `CommandHeader` format works well:

```zig
const CommandHeader = extern struct {
    opcode: u8,        // Box, Text, Button, Input, Image, etc.
    flags: u8,         // Stateful, absolute positioning, etc.
    reserved: u16,
    node_id: u32,      // For event routing
    parent_id: u32,    // For layout hierarchy
    x: f32, y: f32,    // Position (absolute or relative)
    width: f32, height: f32,
    payload_offset: u32,
    payload_size: u32,
    extra: u32,        // Color, font style, etc.
};
```

Extend with more opcodes:
```zig
const Opcode = enum(u8) {
    Box = 1,
    Text = 2,
    Button = 3,
    Input = 4,
    Image = 5,
    FlexStart = 6,   // Begin flex container
    FlexEnd = 7,     // End flex container
    // ...
};
```

---

## Migration Path

### Phase 1: Parallel Paths
- Keep `NodeStore` for now
- Add command-buffer rendering as alternative
- Toggle via config flag

### Phase 2: Validate Command Path
- Ensure all widgets work via commands
- Profile performance (command vs. NodeStore)
- Fix edge cases for stateful widgets

### Phase 3: Remove NodeStore
- Delete `solid_renderer.zig` tree walker
- Delete `NodeStore` and related types
- Simplify Zig codebase significantly

---

## Pros and Cons

### ✅ Pros of SolidJS-Owned State

| Benefit | Explanation |
|---------|-------------|
| **Single source of truth** | No synchronization bugs |
| **Simpler Zig code** | No tree traversal, no dirty tracking |
| **Natural SolidJS integration** | Reactivity model stays in JS |
| **Binary efficiency** | Faster than JSON mutations |
| **Immediate-mode compatible** | Commands map directly to DVUI calls |

### ⚠️ Cons / Challenges

| Challenge | Mitigation |
|-----------|------------|
| **Stateful widgets** | Keep minimal Zig registry for inputs/scrolls |
| **Layout computation** | Either compute in JS or use DVUI's layout |
| **Latency** | Every frame crosses FFI boundary (already happening) |
| **Command buffer size** | For large UIs, optimize with dirty regions |

---

## Recommendation

**Yes, move retained state to SolidJS.** The current architecture has the complexity of two synchronized trees without the benefit. The command-buffer approach:

1. Eliminates the dirty-tracking bug entirely
2. Simplifies the Zig codebase
3. Keeps SolidJS as the natural state owner
4. Matches the existing `commit()` / `renderCommandsDvui()` fallback path

The existing `renderCommandsDvui()` function (lines 432-599 in `native_renderer.zig`) is already a working prototype of this approach.

---

## Summary

| Question | Answer |
|----------|--------|
| Can SolidJS hold retained state? | **Yes** |
| Is it simpler? | **Yes** — single source of truth |
| Does it fix the rendering bug? | **Yes** — no dirty tracking to conflict |
| Is it performant? | **Yes** — binary commands, no JSON parsing |
| What's the tradeoff? | Stateful widgets need a Zig-side registry |

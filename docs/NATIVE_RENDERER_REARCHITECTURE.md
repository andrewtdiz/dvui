# Native Renderer Zig Re-Architecture

## Current State: 1275-line Monolith

`src/native_renderer.zig` contains **6 distinct concerns** mixed together:

| Lines | Concern |
|-------|---------|
| 1-103 | Core types (`Renderer`, `CommandHeader`, `RuntimeHandle`) |
| 104-557 | Solid tree sync (`SolidOp`, `applySolidOp`, `rebuildSolidStoreFromJson`) |
| 559-660 | Window/backend lifecycle (`ensureWindow`, `teardownWindow`) |
| 662-938 | Command rendering (`updateCommands`, `renderCommandsDvui`, `renderFrame`) |
| 940-1074 | Renderer lifecycle (`createRenderer`, `destroyRenderer`, `deinitRenderer`) |
| 1077-1275 | FFI exports (`resizeRenderer`, `presentRenderer`, event ring FFI) |

---

## Proposed Split

Using Zig's `comptime` export pattern to keep exports DLL-visible:

```
src/native_renderer/
├── mod.zig              # Re-exports + comptime force-export block
├── types.zig            # Renderer struct, CommandHeader, RuntimeHandle
├── solid_sync.zig       # SolidOp, applySolidOp, rebuildSolidStoreFromJson, applySolidOps
├── window.zig           # ensureWindow, teardownWindow, renderFrame
├── commands.zig         # updateCommands, renderCommandsDvui
├── lifecycle.zig        # createRenderer, destroyRenderer, deinitRenderer, tryFinalize
├── exports.zig          # All `pub export fn` FFI functions
└── events.zig           # Event ring FFI helpers (pushEvent, etc.)
```

---

## File Responsibilities

### `types.zig` (~100 lines)
```zig
// Core data structures only - no logic

pub const LogFn = fn (...) callconv(.c) void;
pub const EventFn = fn (...) callconv(.c) void;

pub const CommandHeader = extern struct { ... };

pub const Renderer = struct {
    gpa_instance: ...,
    allocator: ...,
    backend: ?RaylibBackend.RaylibBackend,
    window: ?dvui.Window,
    // ... all fields
};

pub const RuntimeHandle = struct {
    raw: ?*anyopaque,
    pub fn get(self: ...) ...
    pub fn set(self: ...) ...
    pub fn deinit(self: ...) ...
};

// Helper functions
pub fn asOpaquePtr(comptime T: type, raw: ?*anyopaque) ?*T { ... }
pub fn solidStore(renderer: *Renderer) ?*solid.NodeStore { ... }
pub fn eventRing(renderer: *Renderer) ?*solid.EventRing { ... }
```

### `solid_sync.zig` (~400 lines)
```zig
// All Solid tree synchronization logic

const types = @import("types.zig");
const Renderer = types.Renderer;

pub const SolidOp = struct { ... };
pub const SolidOpBatch = struct { ... };
pub const OpError = error { ... };

pub fn applyTransformFields(store: ..., id: u32, op: SolidOp) OpError!void { ... }
pub fn applyVisualFields(store: ..., id: u32, op: SolidOp) OpError!void { ... }
pub fn ensureSolidStore(renderer: *Renderer) !*solid.NodeStore { ... }
pub fn rebuildSolidStoreFromJson(renderer: *Renderer, json: []const u8) void { ... }
pub fn applySolidOp(store: *solid.NodeStore, op: SolidOp) OpError!void { ... }
pub fn applySolidOps(renderer: *Renderer, json: []const u8) bool { ... }
```

### `window.zig` (~150 lines)
```zig
// Window lifecycle and frame rendering

const types = @import("types.zig");

pub fn ensureWindow(renderer: *types.Renderer) !void { ... }
pub fn teardownWindow(renderer: *types.Renderer) void { ... }
pub fn renderFrame(renderer: *types.Renderer) void { ... }
```

### `commands.zig` (~200 lines)
```zig
// Command buffer handling and DVUI rendering

const types = @import("types.zig");

pub fn updateCommands(renderer: *types.Renderer, ...) void { ... }
pub fn renderCommandsDvui(renderer: *types.Renderer, win: *dvui.Window) void { ... }
```

### `lifecycle.zig` (~150 lines)
```zig
// Renderer creation/destruction

const types = @import("types.zig");

pub fn deinitRenderer(renderer: *types.Renderer) void { ... }
pub fn finalizeDestroy(renderer: *types.Renderer) void { ... }
pub fn forwardEvent(ctx: ?*anyopaque, name: []const u8, payload: []const u8) void { ... }
pub fn tryFinalize(renderer: *types.Renderer) void { ... }
pub fn logMessage(renderer: *types.Renderer, level: u8, comptime fmt: []const u8, args: anytype) void { ... }
pub fn sendFrameEvent(renderer: *types.Renderer) void { ... }
pub fn sendWindowClosedEvent(renderer: *types.Renderer) void { ... }
```

### `exports.zig` (~200 lines)
```zig
// ALL FFI export functions - the DLL surface

const types = @import("types.zig");
const solid_sync = @import("solid_sync.zig");
const window = @import("window.zig");
const commands = @import("commands.zig");
const lifecycle = @import("lifecycle.zig");

const Renderer = types.Renderer;

pub export fn createRenderer(log_cb: ?*const types.LogFn, event_cb: ?*const types.EventFn) callconv(.c) ?*Renderer {
    // Delegate to lifecycle.createRendererImpl or inline here
}

pub export fn destroyRenderer(renderer: ?*Renderer) callconv(.c) void { ... }
pub export fn resizeRenderer(renderer: ?*Renderer, width: u32, height: u32) callconv(.c) void { ... }
pub export fn presentRenderer(renderer: ?*Renderer) callconv(.c) void { ... }
pub export fn commitCommands(renderer: ?*Renderer, ...) callconv(.c) void { ... }
pub export fn setRendererText(renderer: ?*Renderer, ...) callconv(.c) void { ... }
pub export fn setRendererSolidTree(renderer: ?*Renderer, ...) callconv(.c) void { ... }
pub export fn applyRendererSolidOps(renderer: ?*Renderer, ...) callconv(.c) bool { ... }

// Event ring FFI
pub export fn getEventRingHeader(renderer: ?*Renderer, ...) callconv(.c) usize { ... }
pub export fn getEventRingBuffer(renderer: ?*Renderer) callconv(.c) ?[*]... { ... }
pub export fn getEventRingDetail(renderer: ?*Renderer) callconv(.c) ?[*]u8 { ... }
pub export fn acknowledgeEvents(renderer: ?*Renderer, new_read_head: u32) callconv(.c) void { ... }
```

### `events.zig` (~50 lines)
```zig
// Internal event helpers (non-exported)

const types = @import("types.zig");
const solid = @import("../solid/mod.zig");

pub fn pushEvent(renderer: *types.Renderer, kind: solid.EventKind, node_id: u32, detail: ?[]const u8) bool { ... }
```

### `mod.zig` (~30 lines)
```zig
// Main entry point - re-exports public API and forces exports

pub const types = @import("types.zig");
pub const Renderer = types.Renderer;

// Re-export frequently used functions
pub const ensureSolidStore = @import("solid_sync.zig").ensureSolidStore;
pub const renderFrame = @import("window.zig").renderFrame;
pub const pushEvent = @import("events.zig").pushEvent;

// Force DLL exports to be included
const exports = @import("exports.zig");
comptime {
    _ = exports.createRenderer;
    _ = exports.destroyRenderer;
    _ = exports.resizeRenderer;
    _ = exports.presentRenderer;
    _ = exports.commitCommands;
    _ = exports.setRendererText;
    _ = exports.setRendererSolidTree;
    _ = exports.applyRendererSolidOps;
    _ = exports.getEventRingHeader;
    _ = exports.getEventRingBuffer;
    _ = exports.getEventRingDetail;
    _ = exports.acknowledgeEvents;
}
```

---

## Migration Steps

### Phase 1: Create Directory Structure
```bash
mkdir -p src/native_renderer
```

### Phase 2: Extract in Order (Least → Most Dependencies)

1. **`types.zig`** - Pure data, no dependencies on other native_renderer files
2. **`events.zig`** - Only depends on types + solid
3. **`lifecycle.zig`** - Core helpers (logMessage, tryFinalize)
4. **`solid_sync.zig`** - Depends on types, lifecycle
5. **`commands.zig`** - Depends on types, lifecycle
6. **`window.zig`** - Depends on types, lifecycle, commands
7. **`exports.zig`** - Depends on all above
8. **`mod.zig`** - Ties it together

### Phase 3: Update build.zig

Change from:
```zig
exe.root_module.addAnonymousImport("native_renderer", .{ .file = "src/native_renderer.zig" });
```

To:
```zig
exe.root_module.addAnonymousImport("native_renderer", .{ .file = "src/native_renderer/mod.zig" });
```

### Phase 4: Verify DLL Exports
```powershell
dumpbin /exports zig-out/bin/native_renderer.dll
```

---

## Benefits

| Metric | Before | After |
|--------|--------|-------|
| Main file lines | 1275 | ~30 (mod.zig) |
| Largest file | 1275 | ~400 (solid_sync.zig) |
| Concern isolation | Mixed | Each file = one concern |
| Agent context | Load all 1275 lines | Load only relevant ~100-200 lines |

### When Working On...

| Task | Files to Load |
|------|---------------|
| Fix Solid tree sync bug | `types.zig` + `solid_sync.zig` |
| Add new FFI export | `exports.zig` |
| Change window behavior | `types.zig` + `window.zig` |
| Debug event dispatch | `types.zig` + `events.zig` |

---

## Alternative: Facade Pattern (Less Disruptive)

If full extraction is too risky, keep `native_renderer.zig` but split logic into helpers:

```zig
// src/native_renderer.zig (facade)
const solid_sync = @import("native_renderer/solid_sync.zig");
const window = @import("native_renderer/window.zig");
const commands = @import("native_renderer/commands.zig");

// FFI exports stay here, delegate to helpers
pub export fn setRendererSolidTree(...) callconv(.c) void {
    solid_sync.rebuildFromJson(renderer, json);
}
```

This keeps the export declarations in the original file while moving implementation details into focused modules.

# Retained Events (`events/`)

## Responsibility
Defines the retained event transport (`EventRing`) and the retained-mode interaction state machines (focus navigation and drag/drop). This module is the bridge between per-frame interaction and “events you can poll/dispatch”.

## Public Surface
- `EventKind` and `EventRing` (`src/retained/events/mod.zig`).
- `focus.beginFrame(...)` / `focus.endFrame(...)` (called by `src/retained/render/mod.zig`).
- Drag/drop entrypoints used by the renderer to maintain drag state and emit events.

## High-Level Architecture
- `mod.zig` defines `EventKind` plus `EventRing`, a fixed-capacity ring buffer for events and their variable-length detail bytes.
- `focus.zig` manages focus registration and keyboard navigation across retained nodes; the render loop calls `focus.beginFrame(...)` and `focus.endFrame(...)` each frame.
- `drag_drop.zig` tracks drag lifecycle and dispatches drag-related events based on pointer movement and hit testing.

## Core Data Model
- `EventKind`: compact `enum(u8)` used across retained and Lua (`src/native_renderer/luau_ui.zig` re-exports values).
- `EventEntry` (`extern struct`): `{ kind, node_id, detail_offset, detail_len }` indexing into `EventRing.detail_buffer`.
- `EventRing`: `buffer: []EventEntry` plus `detail_buffer: []u8`, `read_head`/`write_head` and `detail_write`, and drop counters for backpressure visibility (`dropped_events`, `dropped_details`).

## Critical Assumptions
- Producer/consumer: callers must advance consumption via `setReadHead(...)` or `reset()`; when fully drained, the detail buffer is reclaimed by resetting `detail_write` to 0.
- Detail bytes are opaque to the ring. Some events store UTF-8 strings, others store packed payload structs (for example `PointerPayload` via `std.mem.asBytes(&payload)`).
- `EventKind` values must remain `< 64` to fit `SolidNode.listener_mask` (enforced in `src/retained/core/node_store.zig`).

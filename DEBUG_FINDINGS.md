# Debug Findings

- Event ring header is returned by value in `src/native_renderer.zig:getEventRingHeader` but JS treats it as a pointer (`frontend/solid/native-renderer.ts:269-283`), so polling dereferences an integer and never reads real counters (events can stall or crash).
- Event entry size mismatch: Zig’s `EventEntry` is 16 bytes with padding (`src/solid/events/ring.zig:18-25`), while both JS pollers assume 12 bytes (`frontend/solid/native-renderer.ts:291` and `frontend/solid/event-poller.ts:31-33`), causing misaligned reads and detail buffer corruption.
- Input buffer length is clobbered: `renderInput` sets `state.text_len` to the buffer capacity (`src/solid/render/mod.zig:559-588`), so consumers of `currentText()` will read uninitialized data and may emit oversized event payloads.
- Listener mutations after creation never reach Zig: `setProperty` for `on:*` only mutates the local map (`frontend/solid/solid-host.tsx:643-651`) and never emits a `listen` op, so native never registers handlers added at runtime.
- No dirty-frame short-circuit: `solid/render/mod.zig` always runs layout, paint-cache updates, and forces full-window dirty regions even when nothing changed (missing `root.hasDirtySubtree()` early exit and subtree skips), keeping frame cost proportional to tree size.
